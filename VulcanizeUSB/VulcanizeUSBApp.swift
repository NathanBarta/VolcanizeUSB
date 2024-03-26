//
//  VulcanizeUSBApp.swift
//  VulcanizeUSB
//
//  Created by Nathan Barta on 3/7/24.
//

import SwiftUI

// The attack I am trying to prevent in general is "BadUSB"

// https://developer.apple.com/documentation/security/disabling_and_enabling_system_integrity_protection
// https://developer.apple.com/documentation/driverkit/debugging_and_testing_system_extensions

// https://usb.org/sites/default/files/hut1_5.pdf
// https://www.usb.org/sites/default/files/hid1_11.pdf
// Base class: 0x3h (HID)
// Descriptor: 0x07 (Keyboard / KeyPad)

// https://deskthority.net/wiki/USB
// > "USB allows a peripheral device to expose multiple logical interfaces, to perform multiple roles.
//    For instance, a peripheral could be both a keyboard and a mouse, or a keyboard and a storage device, 
//    each on a separate logic interface."

// https://deskthority.net/wiki/Rollover,_blocking_and_ghosting
// > "The USB Human Interface Device (HID) protocol fully supports N-key rollover. However, the compatibility
//    version of HID that all present systems implement limits USB keyboards to reporting a mere six regular
//    keys together with four modifiers. Additional keys pressed beyond the limit will generally cause some
//    of the other keys to be dropped.
//    Many USB keyboards implement workarounds to bypass this limit; the most common trick is to simulate
//    multiple endpoints, e.g. the keyboard pretends to be a USB hub with several keyboards attached. When
//    more than six keys are pressed simultaneously, the keyboard controller simulates up to six keys coming
//    from one of its virtual keyboards, and the rest coming from its other virtual keyboards."

// https://deskthority.net/wiki/NKRO-over-USB_issues
// Introduces a keyboard problem on OSX
// Cites an opensource keyboard driver for a fix: https://github.com/thefloweringash/iousbhiddriver-descriptor-override

// https://www.beyondlogic.org/usbnutshell/usb1.shtml
// A USB programming bible, thank fucking god

// https://developer.apple.com/documentation/driverkit/creating_a_driver_using_the_driverkit_sdk
// https://developer.apple.com/documentation/iousbhost/iousbhostdevice
// USB kernel extensions can be interface services or device services
// Interface service: "...reads and writes data, processes that data, and does something useful with it. 
//                     For example, a HID interface service processes input reports from a HID device and
//                     dispatches events to the system."
// Device service: "...support custom devices or to configure devices so that the system can use them"
//
// It looks like IOUSBHostDevice is what I need because it allows reading/writing from ANY USB device. Also,
// for as long as we maintain an instance, nobody else can change the state of the device. Although, I don't
// know if that is ideal, since I don't want to have to proxy every given USB interaction - I'd rather just
// be an initial gate keeper.
//
// https://developer.apple.com/documentation/hiddriverkit/iouserhideventdriver
// IOUserHIDEventDriver also looks pretty attractive. It seems to be a template for regular HID devices and
// can do pattern matching to find keyboards?
// Well, well, well, they have some sample code:
// https://developer.apple.com/documentation/hiddriverkit/handling_keyboard_events_from_a_human_interface_device

// https://objective-see.org/blog/blog_0x1A.html
// > "Adding a kernel extension (kext) into RansomWhere? just to perform process monitoring seemed like overkill,
//    so I decided to re-examine various user-mode options. Turns out, a method I had previously discounted
//    (as I couldn't get it working consistently) - process monitoring via OpenBSM, provides an adequate means to
//    track process creation from user-mode!
// Maybe creating a daemon would work better? What APIs are available to me?

// Code analysis of https://github.com/objective-see/DoNotDisturb/
//   Uses NSXPCConnection, which is a bidirectional XPC. XPC is Mach's IPC framework.
//   Listens to USB devices using https://developer.apple.com/documentation/iokit/iousblib_h
//   which is a user-space framework
// Doccumentation:
// According to https://stackoverflow.com/questions/24040765/communicate-with-another-app-using-xpc
// NSXPCConnection can connect to 3 things:
// 1) "An XPCService. You can connect to an XPCService strictly through a name"
// 2) "A Mach Service. You can also connect to a Mach Service strictly through a name"
// 3) "An NSXPCEndpoint. ...two application processes."
// Additional details: https://developer.apple.com/forums/thread/715338

// https://www.quora.com/What-is-the-difference-between-the-following-terms-Darwin-OS-XNU-Mach-FreeBSD-BSD
// > "Darwin OS is the kernel develop by Apple that powers theirs latest computers and mobile devices.
//    BSD is a unix system developed at Berkeley University. It is a very know Unix System.
//    FreeBSD is an open source descendant of BSD unix.
//    Mach is a micro kernel specification. Gnu have implemented Mach arquiteture and used it on its own Hurd kernel,
//    for example. The ideia is to have a minimalistic block of code running on kernel space and the rest running as
//    servers on user space.
//    XNU is an implementation of mach as micro kernel using the BSD kernel on user space as servers.
//    In a simple way, they took the BSD kernel, split it, and used as user space servers on top of a mach micro kernel.
//    Now, you have probably asked that to understand DarwinOS right?
//    DarwinOS is the XNU implementation from Apple. They took the FreeBSD kernel and used it as user space servers on
//    top of a mach micro kernel.
//    XNU was developed by Next which has been bought by Apple latter. Both companies had been founded by Steve Jobs.
//    This is a very simplified answer, but I think that will help.

// https://developer.apple.com/library/archive/documentation/DeviceDrivers/Conceptual/USBBook/USBIntro/USBIntro.html#//apple_ref/doc/uid/TP40002643-TPXREF101
// > "IOUSBDeviceInterface for communicating with the device itself; IOUSBInterfaceInterface for communicating with an interface in the device"
// > "Communicating with the device itself is usually only necessary when you need to set or change its configuration. For example, vendor-specific
//    devices are often not configured because there are no default drivers that set a particular configuration. In this case, your application must
//    use the device interface for the device to set the configuration it needs so the interfaces become available."
// > "If, for example, your application needs to communicate with the scanning function of a device that does scanning, faxing, and printing, you need
//    to build a dictionary to match on only the scanning interface (an IOUSBInterface object), not the device as a whole (an IOUSBDevice object). In
//    this situation, you would use the keys defined for interface matching (those shown in Table 1-3), not the keys for device matching."
//        bInterfaceClass: Base Class of USB-IF
//        bInterfaceSubClass: Descriptor of USB-IF


// Code for USBDeviceInterfaces: https://developer.apple.com/library/archive/documentation/DeviceDrivers/Conceptual/USBBook/USBDeviceInterfaces/USBDevInterfaces.html#//apple_ref/doc/uid/TP40002645-TPXREF101
// Swift version (kinda): https://github.com/Arti3DPlayer/USBDeviceSwift/blob/master/Sources/USBDeviceMonitor.swift
// Obj-C version (kinda): https://github.com/objective-see/DoNotDisturb/blob/master/launchDaemon/launchDaemon/monitor/USBMonitor.m

// Bluetooth keyboard vuln:
// https://github.com/skysafe/reblog/tree/main/cve-2023-45866
// https://github.com/marcnewlin/hi_my_name_is_keyboard/blob/main/keystroke-injection-macos.py
// https://www.securityweek.com/apple-patches-keystroke-injection-vulnerability-in-magic-keyboard/

// https://developer.apple.com/documentation/kernel
// https://developer.apple.com/documentation/hiddriverkit

// https://developer.apple.com/documentation/hiddriverkit/iouserhideventservice
// > "Subclass IOUserHIDEventService when you want to process incoming data from a HID device before dispatching it to the system"

// https://developer.apple.com/documentation/hiddriverkit/iohideventservice/3338745-dispatchkeyboardevent
// > "Call this method from your event service to dispatch a keyboard event to the system. Typically, you call this method when
//    handling a report from the device, after you determine that the report contains a keyboard-related event."

// https://developer.apple.com/documentation/iokit
// https://developer.apple.com/library/archive/documentation/DeviceDrivers/Conceptual/IOKitFundamentals/Introduction/Introduction.html#//apple_ref/doc/uid/TP0000011
// About IOKit, first site says that DeviceDrivers are now mandatory for macOS 11+?

// https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html
// Daemons
// Looks like "Login items" type daemons are what I'd use
// Looks like loginwindow "Configures the mouse, keyboard, and system sound using the user’s preferences." It's unclear where daemons would
// start, which is no-bueno if keyboard gets configured. launchd supposdly starts daemons before the loginwindow though...
// Login items are managed via the Service Management framework (or a shared file list, which makes it accessable via System Preferences like KnockKnock)

// https://ieftimov.com/posts/create-manage-macos-launchd-agents-golang/

// NEXT STEPS
// - Probably go back to reviewing Objective-See code, see if I can run it locally
// - I think DND and KnockKnock are probably two good places to start

// IOUSBLib Device
// +++ IOUSBDeviceStruct100
// - USBDeviceOpen: Opens for exclusive access... if I can get to it first [MAYBE NEXT STEPS IS JUST BUILDING AN OBSERVER & SEEING IF I CAN LOCK DOWN EA]
// - GetDeviceSubClass...: All of the getters are here
// - GetLocationID: Seems to uniquely ID a USB device unless topogology changes (hubs? could this be exploited?)
// - CreateInterfaceIterator: Could be necessary to find keyboards on devices
// +++ IOUSBDeviceStruct182
// - USBDeviceOpenSeize: Tries to seize EA
// - USBDeviceSuspend: Seems like a good way to turn things off?
// +++ IOUSBDeviceStruct187
// - USBDeviceReEnumerate: Simulates unplugging and plugging back in.
// +++ IOUSBDeviceStruct197
// - GetIOUSBLibVersion: Returns IOUSBLib version of the IOUSBFamily
// +++ IOUSBDeviceStruct320
// - GetUSBDeviceInformation: Info such as if the USB device is captive/suspended
// +++ IOUSBDeviceStruct650
// - RegisterForNotification: Callback for when certain events happen in the kernel. suspending/resuming
// - AcknowledgeNotification: If suspending, tells kernel that user is ready to suspend.

// IOUSBLib Interface
// - USBInterfaceOpen: Tries to open with exclusive access.
// - USBInterfaceOpenSeize: yup
// - RegisterForNotification: yup
// - RegisterDriver: Very interesting, tells kernel to find the associated driver for this. SetConfigurationV2 can be used to turn off the register system & this can be used to selectively turn ones back on!

// IOKitLib: "IOKitLib implements non-kernel task access to common IOKit object types - IORegistryEntry, IOService, IOIterator etc. These functions are generic - families may provide API that is more specific."
// - IONotificationPortCreate: For recieving notifications (new devices, state changes)
// - IONotificationPortSetImportanceReceiver: Up the importance
// - IONotificationPortGetRunLoopSource: The runloop
// - IOIteratorNext, IOIteratorReset, IOIteratorIsValid
// - IOServiceGetMatchingService for currently registered, IORegistryEntryCreateIterator for not yet registered
// - IOServiceOpen: "A non kernel client may request a connection be opened via the IOServiceOpen() library function, which will call IOService::newUserClient in the kernel. The rules & capabilities of user level clients are family dependent, the default IOService implementation returns kIOReturnUnsupported."

// hid/
// - IOHIDDevice:
// -- IOHIDDeviceOpen: Has exclusive access option
// -- IOHIDDeviceConformsTo: Could be interesting
// -- IOHIDDeviceScheduleWithRunLoop: Needed for asynch APIs
// - IOHIDManager:
// -- IOHIDManagerCreate: Global system for communicating with HID devices.
// -- IOHIDManagerOpen: Open the manager, you can ask for exclusive access.
// -- IOHIDManagerScheduleWithRunLoop
// -- IOHIDManagerSetDeviceMatching, IOHIDManagerSetDeviceMatchingMultiple: <- Have to check if the keys can define an anon keyboard, I think Interface is already handled bc we're a HID device... There are Usage Tables to specify keyboard

// hidsystem/
// - IOHIDGetStateForSelector: Don't know
// - IOHIDCheckAccess
// - IOHIDRequestAccess
// - IOHIDUserDeviceCreateWithProperties: Create a virtual device, needs permissions.
// - IOHIDUserDeviceRegisterGetReportBlock: Registers for reports, must be present before connected

// `open /Library/Preferences/com.apple.keyboardtype.plist`
// To see keyboard settings. Format: "productid-idvendor-?

// https://developer.apple.com/library/archive/documentation/DeviceDrivers/Conceptual/AccessingHardware/AH_Intro/AH_Intro.html
// Might contain doccumentation on IOPluggin stuff

// https://chrispaynter.medium.com/what-to-do-when-your-macos-daemon-gets-blocked-by-tcc-dialogues-d3a1b991151f

@main
struct VulcanizeUSBApp: App {
  @StateObject var deputy = HIDDeputy()

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}
