//
//  USB.swift
//  SwiftUSB
//
//  Created by Brandon on 2019-07-26.
//  Copyright © 2019 XIO. All rights reserved.
//

import Foundation
import IOKit
import IOKit.usb
import IOKit.usb.USB

import os

private func log(_ message: String) {
	//os_log(.error, log: .default, "%@", message)
	print(message)
}

struct Endpoint: OptionSet {
	let rawValue: UInt8

	//Endpoint Direction
	static let `in` = Endpoint(rawValue: UInt8((kUSBIn & kUSBRqDirnMask) << kUSBRqDirnShift))
	static let out = Endpoint(rawValue: UInt8((kUSBOut & kUSBRqDirnMask) << kUSBRqDirnShift))
	static let none = Endpoint(rawValue: UInt8((kUSBNone & kUSBRqDirnMask) << kUSBRqDirnShift))
	static let `any` = Endpoint(rawValue: UInt8((kUSBAnyDirn & kUSBRqDirnMask) << kUSBRqDirnShift))
	
	//Device Request Type
	static let standard = Endpoint(rawValue: UInt8((kUSBStandard & kUSBRqTypeMask) << kUSBRqTypeShift))
	static let `class` = Endpoint(rawValue: UInt8((kUSBClass & kUSBRqTypeMask) << kUSBRqTypeShift))
	static let vendor = Endpoint(rawValue: UInt8((kUSBVendor & kUSBRqTypeMask) << kUSBRqTypeShift))
	
	//Device Request Recipient
	static let device = Endpoint(rawValue: UInt8(kUSBDevice & kUSBRqRecipientMask))
	static let interface = Endpoint(rawValue: UInt8(kUSBInterface & kUSBRqRecipientMask))
	static let endpoint = Endpoint(rawValue: UInt8(kUSBRqRecipientMask & kUSBRqRecipientMask))
	static let other = Endpoint(rawValue: UInt8(kUSBOther & kUSBRqRecipientMask))
}

enum USBDeviceSpeed: Int {
	case unknown = -1
	case low = 0
	case full = 1
	case high = 2
	case `super` = 3
	case superPlus = 4
}

public class RuntimeError: NSError {
	private let message: String
	
	public init(_ message: String, code: Int = -1) {
		self.message = message
		
		if #available(iOS 11.0, *) {
			super.init(domain: "RuntimeError", code: code, userInfo: [
				NSLocalizedDescriptionKey: message,
				NSLocalizedFailureErrorKey: message
			])
		}
		else {
			super.init(domain: "RuntimeError", code: code, userInfo: [
				NSLocalizedDescriptionKey: message
			])
		}
	}
	
	required init?(coder aDecoder: NSCoder) {
		fatalError()
	}
}

class USBDevice {
	private var isOpen = false
	private var deviceName: String
	private var descriptor = IOUSBDeviceDescriptor()
	private var deviceInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface320>?>!
	private var interfaces = [USBInterface](repeating: USBInterface(), count: kUSBMaxInterfaces)
	
	private var currentConfiguration: UInt8 = 0
	private var defaultConfiguration: UInt8 = 0
	private var locationId: UInt32 = 0
	private var busNumber: UInt8 = 0
	private var deviceAddress: USBDeviceAddress = 0
	private var deviceSpeed: UInt8 = 0
	
	public init(_ service: io_service_t) throws {
		var name = [Int8](repeating: 0, count: 256)
		let kr = IORegistryEntryGetName(service, &name)
		
		if kr != kIOReturnSuccess {
			log(human_error_string(kr))
		}
		
		self.deviceName = String(cString: &name)
		deviceInterface = try getDeviceIterator(service)
		
		_ = getDeviceSpeed()
		_ = getDeviceLocation()
		_ = getDeviceAddress()
		
		try getDeviceDescriptor(descriptor: &descriptor)
		_ = try getDefaultConfiguration()
		
		if descriptor.bNumConfigurations == 0 {
			throw RuntimeError("Invalid number of configurations")
		}
	}
	
	deinit {
		_ = close()
	}
	
	public func getDescriptor() -> IOUSBDeviceDescriptor {
		return descriptor
	}
	
	public func open() -> Bool {
		if isOpen {
			return true
		}
		
		isOpen = deviceInterface.pointee?.pointee.USBDeviceOpenSeize(deviceInterface) == kIOReturnSuccess
		return isOpen
	}
	
	public func close() -> Bool {
		if !isOpen {
			return true
		}
		
		for interface in interfaces {
			if interface.claimed {
				_ = interface.interface?.pointee?.pointee.USBInterfaceClose(interface.interface)
				_ = interface.interface?.pointee?.pointee.Release(interface.interface)
				
				interface.claimed = false
			}
		}
		
		interfaces = [USBInterface](repeating: USBInterface(), count: kUSBMaxInterfaces)
		_ = deviceInterface.pointee?.pointee.USBDeviceClose(deviceInterface)
		isOpen = false
		return true
	}
	
	public func set_configuration(_ configuration: UInt8) -> Bool {
		do {
			try setConfiguration(configuration)
			return true
		} catch {
			log("\(error.localizedDescription)")
		}
		return false
	}
	
	public func claim_interface(_ interface: UInt8) -> Bool {
		do {
			try claimInterface(interface)
			return true
		} catch {
			log("\(error.localizedDescription)")
		}
		return false
	}
	
	public func read(_ endpoint: Endpoint, into buffer: UnsafeMutableRawPointer, size: UInt32) -> Bool {
		var pipe: UInt8 = 0
		guard let usbInterface = self.getEndpointInfo(endpoint, pipe: &pipe) else {
			return false
		}
		
		var direction: UInt8 = 0
		var number: UInt8 = 0
		var transferType: UInt8 = 0
		var maxPacketSize: UInt16 = 0
		var interval: UInt8 = 0
		
		var kr = usbInterface.pointee!.pointee.GetPipeProperties(usbInterface, pipe, &direction, &number, &transferType, &maxPacketSize, &interval)
		
		if kr != kIOReturnSuccess {
			log(human_error_string(kr))
		}
		
		var size = size
		kr = usbInterface.pointee!.pointee.ReadPipeTO(usbInterface, pipe, buffer, &size, 30, 60)
		
		if kr != kIOReturnSuccess {
			log(human_error_string(kr))
			return false
		}
		
		return true
	}
	
	func write(_ endpoint: Endpoint, buffer: UnsafeMutableRawPointer, size: UInt32) -> Bool {
		var pipe: UInt8 = 0
		guard let usbInterface = self.getEndpointInfo(endpoint, pipe: &pipe) else {
			return false
		}
		
		var direction: UInt8 = 0
		var number: UInt8 = 0
		var transferType: UInt8 = 0
		var maxPacketSize: UInt16 = 0
		var interval: UInt8 = 0
		
		var kr = usbInterface.pointee!.pointee.GetPipeProperties(usbInterface, pipe, &direction, &number, &transferType, &maxPacketSize, &interval)
		
		if kr != kIOReturnSuccess {
			log(human_error_string(kr))
		}
		
		kr = usbInterface.pointee!.pointee.WritePipeTO(usbInterface, pipe, buffer, size, 30, 60)
		if kr != kIOReturnSuccess {
			log(human_error_string(kr))
			return false
		}
		
		return true
	}
	
	func deviceRequest(_ endpoint: Endpoint, bmRequestType: UInt8, bRequest: UInt8, wValue: UInt16, wIndex: UInt16, buffer: UnsafeMutableRawPointer, wLength: UInt16, bytesReceived: UnsafeMutablePointer<UInt32>? = nil) -> Bool {

		var request = IOUSBDevRequestTO(bmRequestType: bmRequestType,
										bRequest: bRequest,
										wValue: CFSwapInt16LittleToHost(wValue),
										wIndex: CFSwapInt16LittleToHost(wIndex),
										wLength: CFSwapInt16LittleToHost(wLength),
										pData: buffer,
										wLenDone: 0,
										noDataTimeout: 30,
										completionTimeout: 60)

		var pipe: UInt8 = 0
		guard let usbInterface = getEndpointInfo(endpoint, pipe: &pipe) else {
			return false
		}
		
		let kr = usbInterface.pointee!.pointee.ControlRequestTO(usbInterface, pipe, &request)
		if kr != kIOReturnSuccess {
			log(human_error_string(kr))
			return false
		}
		
		bytesReceived?.pointee = request.wLenDone
		return true
	}
	
	func controlRequest(_ bmRequestType: Endpoint, bRequest: UInt8, wValue: UInt16, wIndex: UInt16, buffer: UnsafeMutableRawPointer, wLength: UInt16, bytesReceived: UnsafeMutablePointer<UInt32>? = nil) -> Bool {

		var request = IOUSBDevRequestTO(bmRequestType: bmRequestType.rawValue,
										bRequest: bRequest,
										wValue: CFSwapInt16LittleToHost(wValue),
										wIndex: CFSwapInt16LittleToHost(wIndex),
										wLength: CFSwapInt16LittleToHost(wLength),
										pData: buffer,
										wLenDone: 0,
										noDataTimeout: 30,
										completionTimeout: 60)
		
		//Same as a `ControlRequest` on pipe 0..
		let kr = deviceInterface.pointee!.pointee.DeviceRequestTO(deviceInterface, &request)
		if kr != kIOReturnSuccess {
			log(human_error_string(kr))
			return false
		}
		
		bytesReceived?.pointee = request.wLenDone
		return true
	}
}

extension USBDevice {
	func get_device_name() -> String {
		return deviceName
	}
	
	func get_manufacturer() -> String {
		return getStringDescriptor(index: descriptor.iManufacturer)
	}
	
	func get_product_name() -> String {
		return getStringDescriptor(index: descriptor.iProduct)
	}
	
	func get_serial_number() -> String {
		return getStringDescriptor(index: descriptor.iSerialNumber)
	}
	
	func get_vendor_id() -> UInt16 {
		return descriptor.idVendor
	}
	
	func get_product_id() -> UInt16 {
		return descriptor.idProduct
	}
	
	/// USB Properties
	func get_descriptor_length() -> UInt8 {
		return descriptor.bLength
	}
	
	func get_descriptor_type() -> UInt8 {
		return descriptor.bDescriptorType
	}
	
	func get_specification_number() -> UInt16 {
		return descriptor.bcdUSB
	}
	
	func get_device_release_number() -> UInt16 {
		return descriptor.bcdDevice
	}
	
	func get_max_packet_size() -> UInt8 {
		return descriptor.bMaxPacketSize0
	}
	
	func get_number_of_configurations() -> UInt8 {
		return descriptor.bNumConfigurations
	}
	
	func get_device_speed() -> USBDeviceSpeed {
		switch Int(deviceSpeed) {
		case kUSBDeviceSpeedLow:
			return .low
			
		case kUSBDeviceSpeedFull:
			return .full
			
		case kUSBDeviceSpeedHigh:
			return .high
			
		case kUSBDeviceSpeedSuper:
			return .super
			
		case kUSBDeviceSpeedSuperPlus:
			return .superPlus
			
		default:
			return .unknown
		}
	}
	
	func get_bus_number() -> UInt8 {
		return busNumber
	}
}

extension USBDevice {
	@available(swift, obsoleted: 1.0, renamed: "get_serial_number")
	func get_serial_string() -> String {
		var index: UInt8 = 0
		let kr = deviceInterface.pointee!.pointee.USBGetSerialNumberStringIndex(deviceInterface, &index)
		if kr != kIOReturnSuccess {
			log(human_error_string(kr))
			return ""
		}
		
		return getStringDescriptor(index: index)
	}
	
	@available(swift, obsoleted: 1.0, renamed: "get_manufacturer")
	func get_manufacturer_string() -> String {
		var index: UInt8 = 0
		let kr = deviceInterface.pointee!.pointee.USBGetManufacturerStringIndex(deviceInterface, &index)
		if kr != kIOReturnSuccess {
			log(human_error_string(kr))
			return ""
		}
		
		return getStringDescriptor(index: index)
	}
	
	@available(swift, obsoleted: 1.0, renamed: "get_produce_name")
	private func get_product_string() -> String {
		var index: UInt8 = 0
		let kr = deviceInterface.pointee!.pointee.USBGetProductStringIndex(deviceInterface, &index)
		if kr != kIOReturnSuccess {
			log(human_error_string(kr))
			return ""
		}
		
		return getStringDescriptor(index: index)
	}
}

extension USBDevice {
	class func getDevices() throws -> [USBDevice] {
		var devices = [USBDevice]()
		let matches = IOServiceMatching("IOUSBHostDevice") //Before ElCapitan: IOUSBDevice -- kIOUSBDeviceClassName
		
		if matches == nil {
			throw RuntimeError(human_error_string(kIOReturnError))
		}
		
		var deviceIterator: io_iterator_t = IO_OBJECT_NULL
		let kr = IOServiceGetMatchingServices(kIOMasterPortDefault, matches, &deviceIterator)
		if kr != kIOReturnSuccess {
			throw RuntimeError(human_error_string(kr))
		}
		
		while case let service = IOIteratorNext(deviceIterator), service != IO_OBJECT_NULL {
			do {
				
				/*let name = CFStringCreateWithCString(kCFAllocatorDefault, kIOBSDNameKey, CFStringBuiltInEncodings.UTF8.rawValue)
				
				let deviceBSDName = IORegistryEntrySearchCFProperty(service, kIOServicePlane, name, kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively))
				
				log(deviceBSDName)*/
				
				
				let device = try USBDevice(service)
				devices.append(device)
			} catch {
				log(error.localizedDescription)
			}
			
			IOObjectRelease(service)
		}
		IOObjectRelease(deviceIterator)
		return devices
	}
}

extension USBDevice {
	private func setConfiguration(_ configuration: UInt8) throws {
		let kr = deviceInterface.pointee!.pointee.SetConfiguration(deviceInterface, configuration)
		if kr != kIOReturnSuccess {
			throw RuntimeError(human_error_string(kr))
		}
	}
	
	private func claimInterface(_ interface: UInt8) throws {
		//If the interface is already claimed..
		if interfaces[Int(interface)].claimed {
			throw RuntimeError("Interface already claimed")
		}
		
		var usbInterface: io_service_t = IO_OBJECT_NULL
		try getUSBDeviceInterface(usbInterface: &usbInterface, interface: interface)
		
		if usbInterface == IO_OBJECT_NULL {
			try setConfiguration(defaultConfiguration)
			try getUSBDeviceInterface(usbInterface: &usbInterface, interface: interface)
		}
		
		if usbInterface == IO_OBJECT_NULL {
			throw RuntimeError("Cannot get interface")
		}
		
		// Claim..
		var score: Int32 = 0
		var plugInInterfacePtr: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
		var kr = IOCreatePlugInInterfaceForService(usbInterface, kIOUSBInterfaceUserClientTypeID, kIOCFPlugInInterfaceID, &plugInInterfacePtr, &score)
		
		guard kr == kIOReturnSuccess, let pluginInterface = plugInInterfacePtr?.pointee?.pointee else {
			IOObjectRelease(usbInterface)
			throw RuntimeError(human_error_string(kr))
		}
		
		IOObjectRelease(usbInterface)
		
		var claimedInterfacePtr: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBInterfaceInterface300>?>?
		let res = withUnsafeMutablePointer(to: &claimedInterfacePtr) {
			$0.withMemoryRebound(to: Optional<LPVOID>.self, capacity: 1) {
				pluginInterface.QueryInterface(plugInInterfacePtr, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID), $0)
			}
		}
		
		guard kr == kIOReturnSuccess, let claimedInterface = claimedInterfacePtr?.pointee?.pointee else {
			throw RuntimeError(human_error_string(kr))
		}
		
		kr = claimedInterface.USBInterfaceOpen(claimedInterfacePtr)
		if kr != kIOReturnSuccess {
			_ = claimedInterface.Release(claimedInterfacePtr)
			throw RuntimeError(human_error_string(kr))
		}
		
		let claim = interfaces[Int(interface)]
		claim.id = interface
		claim.claimed = true
		claim.interface = claimedInterfacePtr!
		
		// Endpoints..
		do {
			try getEndpoints(interface: interface)
		} catch {
			defer {
				var kr = claimedInterface.USBInterfaceClose(claimedInterfacePtr)
				if kr != kIOReturnSuccess {
					log(human_error_string(kr))
				}
				
				kr = IOReturn(claimedInterface.Release(claimedInterfacePtr))
				if kr != kIOReturnSuccess {
					log(human_error_string(kr))
				}
				
				interfaces[Int(interface)] = USBInterface()
			}
			
			throw error
		}
	}
	
	private func getDeviceIterator(_ service: io_service_t) throws -> UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface320>?> {
		var score: Int32 = 0
		var plugInInterfacePtr: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
		
		let kr = IOCreatePlugInInterfaceForService(service, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugInInterfacePtr, &score)
		
		guard kr == kIOReturnSuccess, let pluginInterface = plugInInterfacePtr?.pointee?.pointee else {
			throw RuntimeError(human_error_string(kr))
		}
		
		var deviceInterfacePtr: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface320>?>?
		let res = withUnsafeMutablePointer(to: &deviceInterfacePtr) {
			$0.withMemoryRebound(to: Optional<LPVOID>.self, capacity: 1) {
				pluginInterface.QueryInterface(plugInInterfacePtr, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID320), $0)
			}
		}
		
		_ = pluginInterface.Release(plugInInterfacePtr)
		
		guard res == S_OK, let deviceInterface = deviceInterfacePtr, deviceInterface.pointee != nil else {
			throw RuntimeError(human_error_string(res))
		}
		
		return deviceInterface
	}
	
	private func getDeviceDescriptor(descriptor: UnsafeMutablePointer<IOUSBDeviceDescriptor>) throws {
		memset(descriptor, 0, MemoryLayout<IOUSBDeviceDescriptor>.size)
		
		let isOpen = deviceInterface.pointee!.pointee.USBDeviceOpenSeize(deviceInterface) == kIOReturnSuccess
		defer {
			if isOpen {
				let kr = deviceInterface.pointee!.pointee.USBDeviceClose(deviceInterface)
				if kr != kIOReturnSuccess {
					log(human_error_string(kr))
				}
			}
		}

		var retry = false
		repeat {
			var request = IOUSBDevRequestTO(bmRequestType: Endpoint([.in, .standard, .device]).rawValue,
											bRequest: UInt8(kUSBRqGetDescriptor),
											wValue: UInt16(kUSBDeviceDesc << 8),
											wIndex: 0,
											wLength: UInt16(MemoryLayout<IOUSBDeviceDescriptor>.size),
											pData: descriptor,
											wLenDone: 0,
											noDataTimeout: 30,
											completionTimeout: 60)
			
			var kr = deviceInterface.pointee!.pointee.DeviceRequestTO(deviceInterface, &request)
			if kr != kIOReturnSuccess && kr == kIOReturnOverrun {
				kr = kIOReturnSuccess
			}
			
			let kPrdRootHubApple = 0x8005
			let kPrdRootHubAppleE = 0x8006
			if (descriptor.pointee.idVendor == kAppleVendorID ||
				descriptor.pointee.idVendor == kIOUSBVendorIDAppleComputer ||
				descriptor.pointee.idVendor == kIOUSBVendorIDApple)
				&&
				(descriptor.pointee.idProduct == kPrdRootHubApple ||
					descriptor.pointee.idProduct == kPrdRootHubAppleE) {
				return
			}
			
			if !retry && kr == kIOReturnSuccess && descriptor.pointee.bNumConfigurations == 0 {
				retry = true
				kr = deviceInterface.pointee!.pointee.SetConfiguration(deviceInterface, 1)
				continue
			}
			
			if kr != kIOReturnSuccess {
				memset(descriptor, 0, MemoryLayout<IOUSBDeviceDescriptor>.size)
				throw RuntimeError(human_error_string(kr))
			}
			else {
				break
			}
		} while(!retry)
	}
	
	private func getUSBDeviceInterface(usbInterface: UnsafeMutablePointer<io_service_t>, interface: UInt8) throws {
		let getProperty = { (service: io_service_t, propertyName: String, value: UnsafeMutablePointer<UInt8>) -> Bool in
			let name = CFStringCreateWithCString(kCFAllocatorDefault, propertyName, CFStringBuiltInEncodings.UTF8.rawValue)
			if name == nil {
				return false
			}
			
			let number = IORegistryEntryCreateCFProperty(service, name, kCFAllocatorDefault, 0)?.takeUnretainedValue()
			
			if let number = number {
				if CFGetTypeID(number) == CFNumberGetTypeID() {
					if CFNumberGetValue((number as! CFNumber), .sInt8Type, value) {
						return true
					}
				}
			}
			return false
		}
		
		usbInterface.pointee = IO_OBJECT_NULL
		var interfaceRequest = IOUSBFindInterfaceRequest(bInterfaceClass: UInt16(kIOUSBFindInterfaceDontCare),
														 bInterfaceSubClass: UInt16(kIOUSBFindInterfaceDontCare),
														 bInterfaceProtocol: UInt16(kIOUSBFindInterfaceDontCare),
														 bAlternateSetting: UInt16(kIOUSBFindInterfaceDontCare))
		
		var iterator: io_iterator_t = IO_OBJECT_NULL
		let kr = deviceInterface.pointee!.pointee.CreateInterfaceIterator(deviceInterface, &interfaceRequest, &iterator)
		if kr != kIOReturnSuccess {
			throw RuntimeError(human_error_string(kr))
		}
		
		while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
			var bInterfaceNumber: UInt8 = 0
			if getProperty(service, "bInterfaceNumber", &bInterfaceNumber) {
				if bInterfaceNumber == interface {
					usbInterface.pointee = service
					break
				}
			}
			
			IOObjectRelease(service)
		}
		
		IOObjectRelease(iterator)
	}
	
	private func getDefaultConfiguration() throws -> Bool {
		let kPrdRootHubApple = 0x8005
		let kPrdRootHubAppleE = 0x8006
		
		if descriptor.bNumConfigurations == 0 {
			throw RuntimeError("Invalid Number of Configurations")
		}
		
		if (descriptor.idVendor == kAppleVendorID ||
				descriptor.idVendor == kIOUSBVendorIDAppleComputer ||
				descriptor.idVendor == kIOUSBVendorIDApple)
				&&
				(descriptor.idProduct == kPrdRootHubApple ||
					descriptor.idProduct == kPrdRootHubAppleE) {
			return true
		}
		
		//Get the configuration..
		var config: IOUSBConfigurationDescriptorPtr?
		var kr = deviceInterface.pointee!.pointee.GetConfigurationDescriptorPtr(deviceInterface, 0, &config)
		if config != nil && kr == kIOReturnSuccess {
			defaultConfiguration = config!.pointee.bConfigurationValue
			currentConfiguration = config!.pointee.bConfigurationValue
		}
		else {
			log(human_error_string(kr))
		}

		var interfaceRequest = IOUSBFindInterfaceRequest(bInterfaceClass: UInt16(kIOUSBFindInterfaceDontCare),
														 bInterfaceSubClass: UInt16(kIOUSBFindInterfaceDontCare),
														 bInterfaceProtocol: UInt16(kIOUSBFindInterfaceDontCare),
														 bAlternateSetting: UInt16(kIOUSBFindInterfaceDontCare))

		var iterator: io_iterator_t = IO_OBJECT_NULL
		kr = deviceInterface.pointee!.pointee.CreateInterfaceIterator(deviceInterface, &interfaceRequest, &iterator)
		if kr != kIOReturnSuccess {
			throw RuntimeError(human_error_string(kr))
		}
		
		IOObjectRelease(iterator)
		if case let interface = IOIteratorNext(iterator), interface != IO_OBJECT_NULL {
			IOObjectRelease(interface)
			if descriptor.bNumConfigurations == 1 {
				currentConfiguration = defaultConfiguration
			}
			else {
				kr = deviceInterface.pointee!.pointee.GetConfiguration(deviceInterface, &currentConfiguration)
				if kr != kIOReturnSuccess {
					log(human_error_string(kr))
				}
			}
		}
		return true
	}
	
	private func getEndpoints(interface: UInt8) throws {
		let usbInterface = interfaces[Int(interface)]
		guard let interface = usbInterface.interface else {
			throw RuntimeError("Invalid Interface")
		}
		
		let kr = interface.pointee!.pointee.GetNumEndpoints(interface, &usbInterface.numberOfEndpoints)
		if kr != kIOReturnSuccess {
			throw RuntimeError(human_error_string(kr))
		}
		
		//0 = kUSBControl
		for i in 1...usbInterface.numberOfEndpoints {
			var direction: UInt8 = 0
			var number: UInt8 = 0
			var transferType: UInt8 = 0
			var maxPacketSize: UInt16 = 0
			var interval: UInt8 = 0
			
			let kr = interface.pointee!.pointee.GetPipeProperties(interface, i, &direction, &number, &transferType, &maxPacketSize, &interval)
			if kr != kIOReturnSuccess {
				throw RuntimeError(human_error_string(kr))
			}
			
			//bEndpointAddress
			//https://www.beyondlogic.org/usbnutshell/usb5.shtml#EndpointDescriptors
			//Bits 0:3 are the endpoint number. Bits 4:6 are reserved. Bit 7 indicates direction
			//kUSBEndpointDirectionIn
			usbInterface.endpoints[Int(i) - 1] = UInt8(((Int32(direction) & Int32(kUSBRqDirnMask)) << Int32(kUSBRqDirnShift)) | (Int32(number) & 0x0F))
			
			/*if transferType == kUSBBulk {
				if direction == kUSBIn || direction == kUSBOut {
					let kr = interface.pointee!.pointee.ClearPipeStallBothEnds(interface, i)
					if kr != kIOReturnSuccess {
						log(human_error_string(kr))
					}
				}
			}*/
		}
	}
	
	private func getEndpointInfo(_ endpoint: Endpoint, pipe: inout UInt8) -> UnsafeMutablePointer<UnsafeMutablePointer<IOUSBInterfaceInterface300>?>? {
		for iface in 0..<kUSBMaxInterfaces {
			let interface = self.interfaces[iface]
			if interface.claimed {
				for i in 0..<interface.numberOfEndpoints {
					
					//Same as a `DeviceRequest`..
					/*if endpoint == 0 {
						pipe = i
						usbInterface = interface.interface
						return true
					}*/
					
					if interface.endpoints[Int(i)] == endpoint.rawValue {
						pipe = i + 1
						return interface.interface
					}
				}
			}
		}
		return nil
	}
	
	private func getDeviceAddress() -> Bool {
		let kr = deviceInterface.pointee!.pointee.GetDeviceAddress(deviceInterface, &deviceAddress)
		if kr != kIOReturnSuccess {
			log(human_error_string(kr))
			return false
		}
		return true
	}
	
	private func getDeviceSpeed() -> Bool {
		let kr = deviceInterface.pointee!.pointee.GetDeviceSpeed(deviceInterface, &deviceSpeed)
		if kr != kIOReturnSuccess {
			log(human_error_string(kr))
			return false
		}
		return true
	}
	
	private func getDeviceLocation() -> Bool {
		let kr = deviceInterface.pointee!.pointee.GetLocationID(deviceInterface, &locationId)
		if kr != kIOReturnSuccess {
			log(human_error_string(kr))
			return false
		}
		
		busNumber = UInt8(locationId >> 24)
		return true
	}
	
	private func getStringDescriptor(index: UInt8) -> String {
		if index == 0 {
			return ""
		}
		
		var count: UInt32 = 0
		var buffer = [UInt8](repeating: 0x0, count: 256)
		//var buffer = [UInt16](repeating: 0x0, count: 128)
		_ = controlRequest([.in, .standard, .device],
						   bRequest: UInt8(kUSBRqGetDescriptor),
						   wValue: UInt16(Int16(kUSBStringDesc << 8) | Int16(index)),
						   wIndex: 0x409, //English
			buffer: &buffer,
			wLength: UInt16(buffer.count),
			bytesReceived: &count)
		
		let utf16String = CFStringCreateWithBytes(kCFAllocatorDefault, UnsafePointer<UInt8>(buffer).advanced(by: MemoryLayout<Int16>.size), CFIndex(count), CFStringBuiltInEncodings.UTF16LE.rawValue, false)
		return utf16String as String? ?? ""
		
		
		/*_ = controlRequest([.in, .standard, .device],
						   bRequest: UInt8(kUSBRqGetDescriptor),
						   wValue: UInt16(Int16(kUSBStringDesc << 8) | Int16(index)),
						   wIndex: 0x409, //English
						   buffer: &buffer,
						   wLength: UInt16(buffer.count),
						   bytesReceived: &count)
		
		var result = ""
		for i in 0..<Int((count - 1) / 2) {
			if let scalar = UnicodeScalar(buffer[i + 1]) {
				result.append(Character(scalar))
			}
		}
		
		return result*/
	}
	
	private class USBInterface {
		var id: UInt8 = 0
		var claimed: Bool = false
		var interface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBInterfaceInterface300>?>? = nil
		var numberOfEndpoints: UInt8 = 0
		var endpoints = [UInt8](repeating: 0, count: kUSBMaxPipes)
	}
}
