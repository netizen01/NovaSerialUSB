//
//  USBSerialConnection.swift
//

import Foundation
import IOKit

protocol USBSerialConnectionDelegate {
    func device(device: USBSerialConnection, dataRead: NSData)
    func deviceConnected(device: USBSerialConnection)
    func deviceDisonnected(device: USBSerialConnection)
}

class USBSerialConnection {

    private static let CalloutDeviceKey = "IOCalloutDevice"
    
    private var serialFileHandle: NSFileHandle?
    var delegate: USBSerialConnectionDelegate?
    
    let vendorId: Int
    let productId: Int
    let vendorName: String?
    let productName: String?
    
    init(vendorId: Int, productId: Int, vendorName: String? = nil, productName: String? = nil) {
        self.vendorId = vendorId
        self.productId = productId
        self.vendorName = vendorName
        self.productName = productName
        
    }
    
func startScan() {
        let matchingDict = IOServiceMatching("IOUSBHostDevice")
        let vendorKey = "idVendor" as CFStringRef!
        CFDictionarySetValue(matchingDict, unsafeAddressOf(vendorKey), unsafeAddressOf(vendorId))
        let productKey = "idProduct" as CFStringRef!
        CFDictionarySetValue(matchingDict, unsafeAddressOf(productKey), unsafeAddressOf(productId))
        let notifyPort = IONotificationPortCreate(kIOMasterPortDefault)
        var portIterator: io_iterator_t = 0
        let runLoop = NSRunLoop.currentRunLoop().getCFRunLoop()
        let runLoopSource = IONotificationPortGetRunLoopSource(notifyPort)
        CFRunLoopAddSource(runLoop, runLoopSource.takeRetainedValue(), kCFRunLoopCommonModes)
        let observer: UnsafeMutablePointer<Void> = bridge(self)
        IOServiceAddMatchingNotification(notifyPort, kIOFirstMatchNotification, matchingDict, DeviceMatched, observer, &portIterator)
        DeviceMatched(observer, iterator: portIterator)
        IOServiceAddMatchingNotification(notifyPort, kIOTerminatedNotification, matchingDict, DeviceRemoved, observer, &portIterator)
        DeviceRemoved(observer, iterator: portIterator)
    }
    
    func stopScan() {
        // uhh.... how do I rereg those notifiers?
    }
    
    var connected: Bool {
        return serialFileHandle != nil
    }
    
    deinit {
        serialFileHandle?.readabilityHandler = nil
        serialFileHandle?.closeFile()
        serialFileHandle = nil
    }
    
    private func deviceConnected(device: io_object_t) {
        // Callout key takes time to populate apparently. :-/
        let delayTime = dispatch_time(DISPATCH_TIME_NOW, Int64(1 * Double(NSEC_PER_SEC)))
        dispatch_after(delayTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)) {
            if let calloutDevice = self.propertyForDevice(device, property: USBSerialConnection.CalloutDeviceKey) {
                self.openSerialFile(calloutDevice)
            }
            IOObjectRelease(device)
        }
    }
    
    private func openSerialFile(path: String) {
        if let fileHandle = NSFileHandle(forUpdatingAtPath: path) {
            serialFileHandle = fileHandle
            delegate?.deviceConnected(self)
            fileHandle.readabilityHandler = { [weak self] fileHandle in
                if let s = self {
                    s.delegate?.device(s, dataRead: fileHandle.availableData)
                }
            }
        }
    }
    
    private func deviceDisconnected(device: io_object_t) {
        if let _ = propertyForDevice(device, property: USBSerialConnection.CalloutDeviceKey) {
            serialFileHandle?.closeFile()
            serialFileHandle = nil
            delegate?.deviceDisonnected(self)
        }
        IOObjectRelease(device)
    }
    
    private func propertyForDevice(device: io_object_t, property: String) -> String? {
        if let calloutKey = IORegistryEntrySearchCFProperty(device, kIOServicePlane, property, kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)) {
            return calloutKey as? String
        }
        return nil
    }
    
    func writeData(data: NSData) {
        serialFileHandle?.writeData(data)
    }
    
}



private func DeviceMatched(uscPtr: UnsafeMutablePointer<Void>, iterator: io_iterator_t) -> Void {
    let usc: USBSerialConnection = bridge(uscPtr)
    while case let device = IOIteratorNext(iterator) where device != 0 {
        if let matchVendor = usc.vendorName {
            guard let vendor = usc.propertyForDevice(device, property: "USB Vendor Name") else { continue }
            if matchVendor != vendor {
                continue
            }
        }
        if let matchProduct = usc.productName {
            guard let product = usc.propertyForDevice(device, property: "USB Product Name") else { continue }
            if matchProduct != product {
                continue
            }
        }
        usc.deviceConnected(device)
    }
}

private func DeviceRemoved(uscPtr: UnsafeMutablePointer<Void>, iterator: io_iterator_t) -> Void {
    let usc: USBSerialConnection = bridge(uscPtr)
    while case let device = IOIteratorNext(iterator) where device != 0 {
        usc.deviceDisconnected(device)
    }
}

private func bridge<T: AnyObject>(obj: T) -> UnsafeMutablePointer<Void> {
    return UnsafeMutablePointer(Unmanaged.passUnretained(obj).toOpaque())
}

private func bridge<T: AnyObject>(ptr: UnsafeMutablePointer<Void>) -> T {
    return Unmanaged<T>.fromOpaque(COpaquePointer(ptr)).takeUnretainedValue()
}
