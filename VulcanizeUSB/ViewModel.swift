//
//  ViewModel.swift
//  VulcanizeUSB
//
//  Created by Nathan Barta on 3/21/24.
//

import Foundation
import Combine
import IOKit
import IOKit.usb
import IOKit.usb.IOUSBLib

// req >=10.14
public typealias USBDeviceInterfaceStruct = IOUSBDeviceInterface942
public typealias USBInterfaceInterfaceStruct = IOUSBInterfaceInterface942

final public class ViewModel: ObservableObject {
  var notificationPort: IONotificationPortRef
  var runLoop: CFRunLoopSource
  
  init() {
    self.notificationPort = IONotificationPortCreate(kIOMainPortDefault)
    self.runLoop = IONotificationPortGetRunLoopSource(self.notificationPort).takeRetainedValue()
    
    CFRunLoopAddSource(CFRunLoopGetMain(), self.runLoop, CFRunLoopMode.defaultMode)
    
    var ioInterfaceIterator: io_iterator_t = io_iterator_t()
    
    let d: CFDictionary = IOServiceMatching("IOUSBInterface")
    print(d)
    
    let selfPointer = Unmanaged.passUnretained(self).toOpaque()
    let bridge: IOServiceMatchingCallback = { p, iterator in
      let this = Unmanaged<ViewModel>.fromOpaque(p!).takeUnretainedValue()
      this.usbMatchingNotification(iterator)
    }
    
    let error: kern_return_t = IOServiceAddMatchingNotification(self.notificationPort, kIOMatchedNotification, d, bridge, selfPointer, &ioInterfaceIterator)
    if error != kIOReturnSuccess {
      fatalError(String(describing: error))
    }
    
    self.usbMatchingNotification(ioInterfaceIterator)
    RunLoop.current.run()
  }
  
  private func usbMatchingNotification(_ iterator: io_iterator_t) {
    guard (IOIteratorIsValid(iterator) != 0) else { return }

    while case let interface = IOIteratorNext(iterator), interface != 0 {
      // Credit: https://stackoverflow.com/questions/31814292/swift2-correct-way-to-initialise-unsafemutablepointerunmanagedcfmutabledictio
      var properties: Unmanaged<CFMutableDictionary>?
      if IORegistryEntryCreateCFProperties(interface, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS {
        if let properties = properties {
          let d = properties.takeRetainedValue() as NSDictionary
          print(d)
          
          if d.value(forKey: "bInterfaceProtocol") as? Int ?? .zero == 0x1 { // shitty for now
            seizeKeyboard(interface, properties: properties)
          }
          IOObjectRelease(interface)
        }
      }
    }
  }
  
  // bInterfaceClass/baseclass: 0x3 (HID)
  // bInterfaceSubClass/descriptor: 0x7 (Keyboard), 0x1 (Pointer, Boot interface subclass?)
  //      pointer seems to be my keyboard... it is! 0x2 is for a mouse...
  // bInterfaceProtocol: 0x1 (Keyboard?, only has meaning if bInterfaceSubClass is 0x1)
  
  private func isIdentifyingAsKeyboard(_ baseClass: Int, _ descriptor: Int) -> Bool {
    // Keyboards: 0x3, 0x7
    // USB Hubs: 0x9, 0x0
    // USB Drives: 0x0, 0x0
//    if baseClass == 0x9 && descriptor == 0x0 {
//      return true
//    }
//    return false
    
    return baseClass != 0x9 // we will skip ID for now bc the id might be at the interface level
  }
  
  // take out? Figure out what to use?
  public let kIOUSBDeviceInterfaceID100 = CFUUIDGetConstantUUIDWithBytes(nil, 0x5c, 0x81, 0x87, 0xd0, 0x9e, 0xf3, 0x11, 0xD4, 0x8b, 0x45, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)
  
  public let kIOUSBDeviceInterfaceID942 = CFUUIDGetConstantUUIDWithBytes(nil, 0x56, 0xAD, 0x08, 0x9D, 0x87, 0x8D, 0x4B, 0xEA, 0xA1, 0xF5, 0x2C, 0x8D, 0xC4, 0x3E, 0x8A, 0x98)
  
  public let kIOUSBInterfaceInterfaceID942 = CFUUIDGetConstantUUIDWithBytes(nil, 0x87, 0x52, 0x66, 0x3B, 0xC0, 0x7B, 0x4B, 0xAE, 0x95, 0x84, 0x22, 0x03, 0x2F, 0xAB, 0x9C, 0x5A)
  
  private func seizeKeyboard(_ interface: io_service_t, properties: Unmanaged<CFMutableDictionary>) {
    print("Seize!")
    
    var error: Int32 = 0
    var score: Int32 = 0
    
    var usbInterfaceInterfacePointerPointer: UnsafeMutablePointer<UnsafeMutablePointer<USBInterfaceInterfaceStruct>?>?
    var plugInInterfacePointerPointer: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
    
    error = IOCreatePlugInInterfaceForService(interface, kIOUSBInterfaceUserClientTypeID, kIOCFPlugInInterfaceID, &plugInInterfacePointerPointer, &score)
    if error != kIOReturnSuccess {
      fatalError(String(describing: error))
    }
    
    IOObjectRelease(interface)
    
    guard let plugInInterface = plugInInterfacePointerPointer?.pointee?.pointee else { fatalError("Unable to get Plug-In Interface") }
    
    error = withUnsafeMutablePointer(to: &usbInterfaceInterfacePointerPointer) {
      $0.withMemoryRebound(to: Optional<LPVOID>.self, capacity: 1) {
        plugInInterface.QueryInterface(
          plugInInterfacePointerPointer,
          CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID942),
          $0)
      }
    }
            
    if error != kIOReturnSuccess {
      fatalError(String(describing: error))
    }
    
    guard let interfaceInterface = usbInterfaceInterfacePointerPointer?.pointee?.pointee else { fatalError("Unable to get Device Interface") }
    
    error = interfaceInterface.USBInterfaceOpenSeize(usbInterfaceInterfacePointerPointer)
    
    if (error != kIOReturnSuccess && error != kIOReturnExclusiveAccess) {
        print("Could not open device (error: \(error))")
    }
    
    
    
    
  }
}

//{
//    "Device Speed" = 2;
//    IOCFPlugInTypes =     {
//        "9dc7b780-9ec0-11d4-a54f-000a27052861" = "IOUSBHostFamily.kext/Contents/PlugIns/IOUSBLib.bundle";
//    };
//    IOGeneralInterest = "IOCommand is not serializable";
//    IOPowerManagement =     {
//        CapabilityFlags = 32768;
//        ChildrenPowerState = 2;
//        CurrentPowerState = 2;
//        DevicePowerState = 2;
//        DriverPowerState = 0;
//        MaxPowerState = 2;
//        PowerOverrideOn = 1;
//    };
//    IOServiceDEXTEntitlements =     (
//                (
//            "com.apple.developer.driverkit.transport.usb"
//        )
//    );
//    "USB Address" = 2;
//    "USB Product Name" = "Flash Drive FIT";
//    "USB Serial Number" = 0353819060010281;
//    "USB Vendor Name" = Samsung;
//    USBPortType = 0;
//    USBSpeed = 3;
//    UsbDeviceSignature = {length = 28, bytes = 0x0c090010 00113033 35333831 39303630 ... 38310000 00080650 };
//    bDeviceClass = 0;
//    bDeviceProtocol = 0;
//    bDeviceSubClass = 0;
//    bMaxPacketSize0 = 64;
//    bNumConfigurations = 1;
//    bcdDevice = 4352;
//    bcdUSB = 528;
//    iManufacturer = 1;
//    iProduct = 2;
//    iSerialNumber = 3;
//    idProduct = 4096;
//    idVendor = 2316;
//    kUSBAddress = 2;
//    kUSBCurrentConfiguration = 1;
//    kUSBProductString = "Flash Drive FIT";
//    kUSBSerialNumberString = 0353819060010281;
//    kUSBVendorString = Samsung;
//    locationID = 17891328;
//    sessionID = 746208127863;
//}

//{
//    "Device Speed" = 2;
//    IOCFPlugInTypes =     {
//        "9dc7b780-9ec0-11d4-a54f-000a27052861" = "IOUSBHostFamily.kext/Contents/PlugIns/IOUSBLib.bundle";
//    };
//    IOGeneralInterest = "IOCommand is not serializable";
//    IOPowerManagement =     {
//        CapabilityFlags = 32768;
//        ChildrenPowerState = 2;
//        CurrentPowerState = 2;
//        DevicePowerState = 2;
//        DriverPowerState = 0;
//        MaxPowerState = 2;
//        PowerOverrideOn = 1;
//    };
//    IOServiceDEXTEntitlements =     (
//                (
//            "com.apple.developer.driverkit.transport.usb"
//        )
//    );
//    "USB Address" = 1;
//    "USB Product Name" = "USB2.0 Hub";
//    USBPortType = 0;
//    USBSpeed = 3;
//    UsbDeviceSignature = {length = 12, bytes = 0xe30508069060090001090000};
//    UsbExclusiveOwner = AppleUSB20Hub;
//    bDeviceClass = 9;
//    bDeviceProtocol = 1;
//    bDeviceSubClass = 0;
//    bMaxPacketSize0 = 64;
//    bNumConfigurations = 1;
//    bcdDevice = 24720;
//    bcdUSB = 512;
//    iManufacturer = 0;
//    iProduct = 1;
//    iSerialNumber = 0;
//    idProduct = 1544;
//    idVendor = 1507;
//    kUSBAddress = 1;
//    kUSBContainerID = "4bc3ab43-57d0-4872-9981-65db5329965f";
//    kUSBCurrentConfiguration = 1;
//    kUSBProductString = "USB2.0 Hub";
//    locationID = 17825792;
//    sessionID = 746121956903;
//}

//{
//    "Device Speed" = 0;
//    IOCFPlugInTypes =     {
//        "9dc7b780-9ec0-11d4-a54f-000a27052861" = "IOUSBHostFamily.kext/Contents/PlugIns/IOUSBLib.bundle";
//    };
//    IOGeneralInterest = "IOCommand is not serializable";
//    IOPowerManagement =     {
//        CapabilityFlags = 32768;
//        ChildrenPowerState = 2;
//        CurrentPowerState = 2;
//        DevicePowerState = 2;
//        DriverPowerState = 0;
//        MaxPowerState = 2;
//        PowerOverrideOn = 1;
//    };
//    IOServiceDEXTEntitlements =     (
//                (
//            "com.apple.developer.driverkit.transport.usb"
//        )
//    );
//    "USB Address" = 2;
//    "USB Product Name" = "USB Keyboard";
//    "USB Vendor Name" = Logitech;
//    USBPortType = 0;
//    USBSpeed = 2;
//    UsbDeviceSignature = {length = 15, bytes = 0x6d041cc32049000000030101030000};
//    bDeviceClass = 0;
//    bDeviceProtocol = 0;
//    bDeviceSubClass = 0;
//    bMaxPacketSize0 = 8;
//    bNumConfigurations = 1;
//    bcdDevice = 18720;
//    bcdUSB = 272;
//    iManufacturer = 1;
//    iProduct = 2;
//    iSerialNumber = 0;
//    idProduct = 49948;
//    idVendor = 1133;
//    kUSBAddress = 2;
//    kUSBCurrentConfiguration = 1;
//    kUSBProductString = "USB Keyboard";
//    kUSBVendorString = Logitech;
//    locationID = 17891328;
//    sessionID = 964807959500;
//}
