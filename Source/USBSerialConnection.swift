//
//  USBSerialConnection.swift
//  NovaSerialUSB
//

import Foundation
import IOKit

protocol USBSerialConnectionDelegate {
    func device(_ device: USBSerialConnection, dataRead: Data)
    func deviceConnected(_ device: USBSerialConnection)
    func deviceDisonnected(_ device: USBSerialConnection)
}

class USBSerialConnection {
    
    fileprivate static let CalloutDeviceKey = "IOCalloutDevice"
    
    fileprivate var serialFileHandle: FileHandle?
    var delegate: USBSerialConnectionDelegate?
    
    let vendorId: UInt16
    let productId: UInt16
    let vendorName: String?
    let productName: String?
    
    init(vendorId: UInt16, productId: UInt16, vendorName: String? = nil, productName: String? = nil) {
        self.vendorId = vendorId
        self.productId = productId
        self.vendorName = vendorName
        self.productName = productName
    }
    
    private var isScanning: Bool = false
    private var matchedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    func startScan() {
        if isScanning {
            return
        }
        isScanning = true
        let matchingDict: NSMutableDictionary = IOServiceMatching("IOUSBHostDevice")
        matchingDict["idVendor"] = vendorId as NSNumber
        matchingDict["idProduct"] = productId as NSNumber
        
        let notifyPort = IONotificationPortCreate(kIOMasterPortDefault)
        let runLoop = RunLoop.current.getCFRunLoop()
        let runLoopSource = IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue()
        CFRunLoopAddSource(runLoop, runLoopSource, CFRunLoopMode.commonModes)
        
        let observer: UnsafeMutableRawPointer = bridge(self)
        IOServiceAddMatchingNotification(notifyPort, kIOFirstMatchNotification, matchingDict, DeviceMatched, observer, &matchedIterator)
        DeviceMatched(observer, iterator: matchedIterator)
        IOServiceAddMatchingNotification(notifyPort, kIOTerminatedNotification, matchingDict, DeviceRemoved, observer, &removedIterator)
        DeviceRemoved(observer, iterator: removedIterator)
    }
    
    func stopScan() {
        if matchedIterator != 0 {
            IOObjectRelease(matchedIterator)
            matchedIterator = 0
        }
        if removedIterator != 0 {
            IOObjectRelease(removedIterator)
            removedIterator = 0
        }
    }
    
    func disconnect() {
        serialFileHandle?.readabilityHandler = nil
        serialFileHandle?.closeFile()
        serialFileHandle = nil
    }
    
    var connected: Bool {
        return serialFileHandle != nil
    }
    
    deinit {
        disconnect()
    }
    
    fileprivate func deviceConnected(_ device: io_object_t) {
        // Callout key takes time to populate apparently. :-/
        DispatchQueue.global(qos: .background).asyncAfter(deadline: DispatchTime.now() + DispatchTimeInterval.seconds(1)) {
            if let calloutDevice = self.propertyForDevice(device, property: USBSerialConnection.CalloutDeviceKey) {
                self.openSerialFile(calloutDevice)
            }
            IOObjectRelease(device)
        }
    }
    
    fileprivate func openSerialFile(_ path: String) {
        if let fileHandle = FileHandle(forUpdatingAtPath: path) {
            self.serialFileHandle = fileHandle
            self.delegate?.deviceConnected(self)
            fileHandle.readabilityHandler = { [weak self] fileHandle in
                if let s = self {
                    s.delegate?.device(s, dataRead: fileHandle.availableData)
                }
            }
        }
    }
    
    fileprivate func deviceDisconnected(_ device: io_object_t) {
        if let _ = propertyForDevice(device, property: USBSerialConnection.CalloutDeviceKey) {
            serialFileHandle?.readabilityHandler = nil
            serialFileHandle?.closeFile()
            serialFileHandle = nil
            delegate?.deviceDisonnected(self)
        }
        IOObjectRelease(device)
    }
    
    fileprivate func propertyForDevice(_ device: io_object_t, property: String) -> String? {
        if let calloutKey = IORegistryEntrySearchCFProperty(device, kIOServicePlane, property as CFString, kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)) {
            return calloutKey as? String
        }
        return nil
    }
    
    func writeData(_ data: Data) {
        serialFileHandle?.write(data)
    }
    
}


private func DeviceMatched(_ uscPtr: UnsafeMutableRawPointer?, iterator: io_iterator_t) -> Void {
    guard let uscPtr = uscPtr else { return }
    let usc: USBSerialConnection = bridge(uscPtr)
    while case let device = IOIteratorNext(iterator), device != 0 {
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

private func DeviceRemoved(_ uscPtr: UnsafeMutableRawPointer?, iterator: io_iterator_t) -> Void {
    guard let uscPtr = uscPtr else { return }
    let usc: USBSerialConnection = bridge(uscPtr)
    while case let device = IOIteratorNext(iterator), device != 0 {
        usc.deviceDisconnected(device)
    }
}

private func bridge<T: AnyObject>(_ obj: T) -> UnsafeMutableRawPointer {
    return Unmanaged.passUnretained(obj).toOpaque()
}

private func bridge<T: AnyObject>(_ ptr: UnsafeMutableRawPointer) -> T {
    return Unmanaged.fromOpaque(ptr).takeUnretainedValue()
}

