//
//  NXPayload.swift
//  SwiftUSB
//
//  Created by Brandon on 2019-07-27.
//  Copyright © 2019 XIO. All rights reserved.
//

import Foundation

func loadIntermezzo() -> [UInt8] {
	let intermezzo_path = Bundle.main.path(forResource: "intermezzo", ofType: "bin") ?? ""
	
	if !intermezzo_path.isEmpty, let url = URL(string: intermezzo_path) {
		if let data = try? Data(contentsOf: url) {
			return [UInt8](data)
		}
		return []
	}
	
	return intermezzo;
}

func loadPayload() -> [UInt8] {
	let payload_path = Bundle.main.path(forResource: "payload", ofType: "bin") ?? ""
	
	if !payload_path.isEmpty, let url = URL(string: payload_path) {
		if let data = try? Data(contentsOf: url) {
			return [UInt8](data)
		}
		return []
	}
	
	return fusee;
}

func createPayload(intermezzo: [UInt8], payload: [UInt8]) -> [UInt8] {
	let RCM_PAYLOAD_ADDRESS = 0x40010000
	let INTERMEZZO_LOCATION = 0x4001F000
	let PAYLOAD_LOAD_BLOCK = 0x40020000
	
	let MAX_PAYLOAD_LENGTH = 0x30298;
	let HEADER_SIZE = 0x2A8;
	
	let RCM_PAYLOAD_SIZE: UInt32 = { () -> UInt32 in
		let size = (HEADER_SIZE + (INTERMEZZO_LOCATION - RCM_PAYLOAD_ADDRESS) + 0x1000 + fusee.count)
		return UInt32(ceil(Double(size / 0x1000))) * 0x1000
	}()
	
	var buffer = [UInt8](repeating: 0, count: Int(RCM_PAYLOAD_SIZE + 0x1000))
	var rcmPayload = UnsafeMutablePointer<UInt8>(mutating: &buffer)
	
	rcmPayload.withMemoryRebound(to: UInt32.self, capacity: 1) {
		$0.pointee = UInt32(MAX_PAYLOAD_LENGTH)
	}
	
	rcmPayload = rcmPayload.advanced(by: HEADER_SIZE)
	
	for _ in stride(from: RCM_PAYLOAD_ADDRESS, to: INTERMEZZO_LOCATION, by: MemoryLayout<UInt32>.size)  {
		rcmPayload.withMemoryRebound(to: UInt32.self, capacity: 1) {
			$0.pointee = UInt32(INTERMEZZO_LOCATION)
		}
		rcmPayload = rcmPayload.advanced(by: MemoryLayout<UInt32>.size)
	}
	
	var intermezzo = intermezzo
	memcpy(rcmPayload, &intermezzo, intermezzo.count)
	memcpy(rcmPayload + (PAYLOAD_LOAD_BLOCK - INTERMEZZO_LOCATION), &fusee, fusee.count)
	return buffer
}
