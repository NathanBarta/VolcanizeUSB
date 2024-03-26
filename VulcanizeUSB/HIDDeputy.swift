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
  
  private var seizedDevices: [IOHIDDevice] = .init()
  
  init() {
    self.notificationPort = IONotificationPortCreate(kIOMainPortDefault)
    self.runLoop = IONotificationPortGetRunLoopSource(self.notificationPort).takeRetainedValue()
    
    CFRunLoopAddSource(CFRunLoopGetMain(), self.runLoop, CFRunLoopMode.defaultMode)
 
    // Create matching dictionary
    var matchingDictionary = IOServiceMatching(kIOHIDDeviceKey) as NSDictionary as! [String: AnyObject]
    
    // Look for USB Keyboards
    matchingDictionary[kIOHIDTransportKey] = kIOHIDTransportUSBValue as AnyObject
    matchingDictionary[kIOHIDPrimaryUsageKey] = 0x6 as AnyObject
    matchingDictionary[kIOHIDPrimaryUsagePageKey] = 0x1 as AnyObject
    
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
    self.releaseSeizedDevices()
  }
  
  private func captureDevices(_ devices: io_iterator_t) {
    guard (IOIteratorIsValid(devices) != 0) else { return }
    
    // Will need to figure out a stable identity since re-enumeration happens sometimes...
    
    while case let device = IOIteratorNext(devices), device != 0 {
      if let deviceReference = IOHIDDeviceCreate(kCFAllocatorDefault, device) {
        let error = IOHIDDeviceOpen(deviceReference, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        
        if error == kIOReturnSuccess {
          os_log("Seized device")
          self.seizedDevices.append(deviceReference)
          
          let manufactor = IOHIDDeviceGetProperty(deviceReference, kIOHIDManufacturerKey as CFString)
        } else {
          os_log("Failed to seize device")
        }
      }
      
      IOObjectRelease(device)
    }
  }
  
  private func releaseSeizedDevices() {
    for seizedDevice in seizedDevices {
      IOHIDDeviceClose(seizedDevice, IOOptionBits(kIOHIDOptionsTypeNone))
    }
  }
}
