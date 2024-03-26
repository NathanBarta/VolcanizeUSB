//
//  HIDDeputy.swift
//  VulcanizeUSB
//
//  Created by Nathan Barta on 3/25/24.
//

import Foundation
import Combine
import IOKit.hid
import OSLog

final public class HIDDeputy: ObservableObject {
  
  private var notificationPort: IONotificationPortRef
  private var runLoop: CFRunLoopSource
  
//  private var seizedDevices: [IOHIDDevice] = .init()
  private var seizedDevice: IOHIDDevice?
  
  init() {
    self.notificationPort = IONotificationPortCreate(kIOMainPortDefault)
    self.runLoop = IONotificationPortGetRunLoopSource(self.notificationPort).takeRetainedValue()
    
    CFRunLoopAddSource(CFRunLoopGetMain(), self.runLoop, CFRunLoopMode.defaultMode)
 
    // Create matching dictionary
    var matchingDictionary = IOServiceMatching(kIOHIDDeviceKey) as NSDictionary as! [String: AnyObject]
    
    // Look for USB Keyboards
    matchingDictionary[kIOHIDTransportKey] = kIOHIDTransportUSBValue as AnyObject
    matchingDictionary[kIOHIDPrimaryUsageKey] = kHIDUsage_GD_Keyboard as AnyObject
    matchingDictionary[kIOHIDPrimaryUsagePageKey] = kHIDPage_GenericDesktop as AnyObject
    
    // Manufacturer, Product, ProductID, VendorID, kOSBundleDextUniqueIdentifier
    
    let cfMatchingDictionary = matchingDictionary as CFDictionary
        
    var existingDeviceIterator = io_iterator_t()
    let selfPointer = Unmanaged.passUnretained(self).toOpaque()
    let bridge: IOServiceMatchingCallback = { p, iterator in
      let this = Unmanaged<HIDDeputy>.fromOpaque(p!).takeUnretainedValue()
      this.captureDevices(iterator)
    }
    
    let error: kern_return_t = IOServiceAddMatchingNotification(self.notificationPort, kIOMatchedNotification, cfMatchingDictionary, bridge, selfPointer, &existingDeviceIterator)
    
    if error != kIOReturnSuccess {
      fatalError(String(describing: error))
    }
    
    self.captureDevices(existingDeviceIterator)
    //    RunLoop.current.run() // code appears to run without this?
  }
  
  deinit {
//    self.releaseSeizedDevices()
  }
  
  private func captureDevices(_ devices: io_iterator_t) {
    guard (IOIteratorIsValid(devices) != 0) else { return }
    
    // Will need to figure out a stable identity since re-enumeration happens sometimes...
    // Also, I don't handle removing seized devices when they get removed...
    
    while case let device = IOIteratorNext(devices), device != 0 {
      if let deviceReference = IOHIDDeviceCreate(kCFAllocatorDefault, device) {
        let error = IOHIDDeviceOpen(deviceReference, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        
        if error == kIOReturnSuccess {
          os_log("Seized device")
//          self.seizedDevices.append(deviceReference)
          self.seizedDevice = deviceReference
          
          let selfPointer = Unmanaged.passUnretained(self).toOpaque()
          let bridge: IOHIDValueCallback = { p, result, sender, value in
            let this = Unmanaged<HIDDeputy>.fromOpaque(p!).takeUnretainedValue()
            this.seizedKeyboardCallback(result: result, sender: sender, value: value)
          }

          IOHIDDeviceScheduleWithRunLoop(deviceReference, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
          IOHIDDeviceRegisterInputValueCallback(deviceReference, bridge, selfPointer)
          
          print("a/A key: \(kHIDUsage_KeyboardA)")
          
//          let manufactor = IOHIDDeviceGetProperty(deviceReference, kIOHIDManufacturerKey as CFString)
        } else {
          os_log("Failed to seize device")
        }
      }
      
      IOObjectRelease(device)
    }
  }
  
  // Adapted from: https://stackoverflow.com/questions/30380400/how-to-tap-hook-keyboard-events-in-osx-and-record-which-keyboard-fires-each-even
  private func seizedKeyboardCallback(result: IOReturn, sender: UnsafeMutableRawPointer?, value: IOHIDValue) {
    let element: IOHIDElement = IOHIDValueGetElement(value)
    let device = IOHIDElementGetDevice(element) // can't figure out how to cast sender as device, so this will suffice
    
    guard IOHIDElementGetUsagePage(element) == 0x7 else { return }
    
    let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString)
    
    let scancode: UInt32 = IOHIDElementGetUsage(element)
    if scancode < 4 || scancode > 231 {
      return
    }
    
    let pressed = IOHIDValueGetIntegerValue(value)
    
    print("scancode: \(scancode), pressed: \(pressed), keyboardId: \(String(describing: productID))")
  }
  
//  private func releaseSeizedDevices() {
//    for seizedDevice in seizedDevices {
//      IOHIDDeviceClose(seizedDevice, IOOptionBits(kIOHIDOptionsTypeNone))
//    }
//  }
}
