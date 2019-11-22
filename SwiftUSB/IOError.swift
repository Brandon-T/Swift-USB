//
//  IOError.swift
//  SwiftUSB
//
//  Created by Brandon on 2019-07-26.
//  Copyright © 2019 XIO. All rights reserved.
//

import Foundation
import IOKit
import IOKit.usb
import IOKit.usb.USB

private func err_system(_ x: IOReturn) -> Int32 {
	return Int32((UInt32(x) & 0x3f) << 26)
}

private func err_sub(_ x: IOReturn) -> Int32 {
	return (x & 0xfff) << 14
}

private func err_get_system(_ err: IOReturn) -> Int32 {
	return (err >> 26) & 0x3f
}

private func err_get_sub(_ err: IOReturn) -> Int32 {
	return (err >> 14) & 0xfff
}

private func err_get_code(_ err: IOReturn) -> Int32 {
	return err & 0x3fff
}

private func iokit_usb_err(_ ret: IOReturn) -> IOReturn {
	let sys_iokit = err_system(0x38)
	let sub_iokit_usb = err_sub(1)
	return IOReturn(sys_iokit | sub_iokit_usb | ret)
}

private enum IOUSBError: Int, CaseIterable {
	static func from(_ value: Int32) -> IOUSBError? {
		for errCode in IOUSBError.allCases {
			if Int32(bitPattern: UInt32(errCode.rawValue)) == value {
				return errCode
			}
		}
		
		return nil
	}
	
	static func from(_ value: Int) -> IOUSBError? {
		return IOUSBError(rawValue: value)
	}
	
	case unknownPipeErr = 0xE0004061
	case tooManyPipesErr = 0xE0004060
	case noAsyncPortErr = 0xE000405f
	case notEnoughPipesErr = 0xE000405E
	case notEnoughPowerErr = 0xE000405D
	case endpointNotFound = 0xE0004057
	case configNotFound = 0xE0004056
	case transactionTimeout = 0xE0004051
	case transactionReturned = 0xE0004050
	case pipeStalled = 0xE000404F
	case interfaceNotFound = 0xE000404E
	case lowLatencyBufferNotPreviouslyAllocated = 0xE000404D
	case lowLatencyFrameListNotPreviouslyAllocated = 0xE000404C
	case highSpeedSplitError = 0xE000404B
	case syncRequestOnWLThread = 0xE000404A
	case deviceTransferredToCompanion = 0xE0004049
	case clearPipeStallNotRecursive = 0xE0004048
	case devicePortWasNotSuspended = 0xE0004047
	case endpointCountExceeded = 0xE0004046
	case deviceCountExceeded = 0xE0004045
	case streamsNotSupported = 0xE0004044
	case invalidSSEndpoint = 0xE0004043
	case tooManyTransactionsPending = 0xE0004042
	
	case linkErr = 0xE0004010
	case notSent2Err = 0xE000400F
	case notSent1Err = 0xE000400E
	case bufferUnderrunErr = 0xE000400D
	case bufferOverrunErr = 0xE000400C
	case reserved2Err = 0xE000400B
	case reserved1Err = 0xE000400A
	case wrongPIDErr = 0xE0004007
	case pidCheckErr = 0xE0004006
	case dataToggleErr = 0xE0004003
	case bitstufErr = 0xE0004002
	case crcErr = 0xE0004001
}

private enum HRESULTError: Int, CaseIterable {
	static func from(_ value: Int32) -> HRESULTError? {
		for errCode in HRESULTError.allCases {
			if Int32(bitPattern: UInt32(errCode.rawValue)) == value {
				return errCode
			}
		}
		
		return nil
	}
	
	static func from(_ value: Int) -> HRESULTError? {
		return HRESULTError(rawValue: value)
	}
	
	case eUnexpected = 0x8000FFFF
	case eNotImpl = 0x80000001
	case eOutOfMemory = 0x80000002
	case eInvalidArg = 0x80000003
	case eNoInterface = 0x80000004
	case ePointer = 0x80000005
	case eHandle = 0x80000006
	case eAbort = 0x80000007
	case eFail = 0x80000008
	case eAccessDenied = 0x80000009
}

private func string_format(_ format: String, _ args: CVarArg...) -> String {
	return String(format: format, arguments: args)
}

/// Converts IOKit errors to human readable strings.
private func usb_human_error_string(_ errCode: IOReturn) -> String {
	guard let errorCode = IOUSBError.from(errCode) else {
		return string_format("Error Code (%08x)\n-- System: (%02X), SubSystem: (%02X), Code: (%02X) ", errCode, err_get_system(errCode), err_get_sub(errCode), err_get_code(errCode));
	}
	
	switch (errorCode) {
	case .unknownPipeErr:
		return string_format("Pipe Ref Not Recognized (%08x)", errCode);
		
	case .tooManyPipesErr:
		return string_format("Too Many Pipes (%08x)", errCode);
		
	case .noAsyncPortErr:
		return string_format("No Async Port (%08x)", errCode);
		
	case .notEnoughPipesErr:
		return string_format("Not Enough Pipes in Interface (%08x)", errCode);
		
	case .notEnoughPowerErr:
		return string_format("Not Enough Power for Selected Configuration (%08x)", errCode);
		
	case .endpointNotFound:
		return string_format("Endpoint Not Found (%08x)", errCode);
		
	case .configNotFound:
		return string_format("Configuration Not Found (%08x)", errCode);
		
	case .transactionTimeout:
		return string_format("Transaction Timed Out (%08x)", errCode);
		
	case .transactionReturned:
		return string_format("Transaction has been returned to the caller (%08x)", errCode);
		
	case .pipeStalled:
		return string_format("Pipe has stalled, Error needs to be cleared (%08x)", errCode);
		
	case .interfaceNotFound:
		return string_format("Interface Ref Not Recognized (%08x)", errCode);
		
	case .lowLatencyBufferNotPreviouslyAllocated:
		return string_format("Attempted to use user land low latency isoc calls w/out calling PrepareBuffer (on the data buffer) first (%08x)", errCode);
		
	case .lowLatencyFrameListNotPreviouslyAllocated:
		return string_format("Attempted to use user land low latency isoc calls w/out calling PrepareBuffer (on the frame list) first (%08x)", errCode);
		
	case .highSpeedSplitError:
		return string_format("Error to hub on high speed bus trying to do split transaction (%08x)", errCode);
		
	case .syncRequestOnWLThread:
		return string_format("A synchronous USB request was made on the workloop thread (from a callback?).  Only async requests are permitted in that case (%08x)", errCode);
		
	case .deviceTransferredToCompanion:
		return string_format("The device has been tranferred to another controller for enumeration (%08x)", errCode);
		
	case .clearPipeStallNotRecursive:
		return string_format("ClearPipeStall should not be called recursively (%08x)", errCode);
		
	case .devicePortWasNotSuspended:
		return string_format("Port was not suspended (%08x)", errCode);
		
	case .endpointCountExceeded:
		return string_format("The endpoint was not created because the controller cannot support more endpoints (%08x)", errCode);
		
	case .deviceCountExceeded:
		return string_format("The device cannot be enumerated because the controller cannot support more devices (%08x)", errCode);
		
	case .streamsNotSupported:
		return string_format("The request cannot be completed because the XHCI controller does not support streams (%08x)", errCode);
		
	case .invalidSSEndpoint:
		return string_format("An endpoint found in a SuperSpeed device is invalid (usually because there is no Endpoint Companion Descriptor) (%08x)", errCode);
		
	case .tooManyTransactionsPending:
		return string_format("The transaction cannot be submitted because it would exceed the allowed number of pending transactions (%08x)", errCode);
		
	default:
		return string_format("Error Code (%08x)\n-- System: (%02X), SubSystem: (%02X), Code: (%02X) ", errCode, err_get_system(errCode), err_get_sub(errCode), err_get_code(errCode));
	}
}

private func hresult_human_error_string(_ errCode: Int32) -> String? {
	guard let errorCode = HRESULTError.from(errCode) else {
		return nil
	}
	
	switch errorCode {
		case .eUnexpected:
			return string_format("Unexpected Error (%08x)", errCode);
	
		case .eNotImpl:
			return string_format("Not Implemented (%08x)", errCode);
	
		case .eOutOfMemory:
			return string_format("Out of Memory (%08x)", errCode);
	
		case .eInvalidArg:
			return string_format("Invalid Argument (%08x)", errCode);
	
		case .eNoInterface:
			return string_format("No Interface (%08x)", errCode);
	
		case .ePointer:
			return string_format("Null Pointer (%08x)", errCode);
	
		case .eHandle:
			return string_format("Invalid Handle (%08x)", errCode);
	
		case .eAbort:
			return string_format("Abort (%08x)", errCode);
	
		case .eFail:
			return string_format("Fail (%08x)", errCode);
	
		case .eAccessDenied:
			return string_format("Access Denied (%08x)", errCode);
	}
}

func human_error_string(_ errorCode: Int32) -> String {
	switch errorCode {
	// IOReturn
	case kIOReturnSuccess:
		return string_format("Success (%08x)", errorCode);
		
	case kIOReturnError:
		return string_format("General Error (%08x)", errorCode);
		
	case kIOReturnNoMemory:
		return string_format("Cannot Allocate Memory (%08x)", errorCode);
		
	case kIOReturnNoResources:
		return string_format("Resource Shortage (%08x)", errorCode);
		
	case kIOReturnIPCError:
		return string_format("IPC Error (%08x)", errorCode);
		
	case kIOReturnNoDevice:
		return string_format("No Such Device (%08x)", errorCode);
		
	case kIOReturnNotPrivileged:
		return string_format("Insufficient Privileges (%08x)", errorCode);
		
	case kIOReturnBadArgument:
		return string_format("Invalid Argument (%08x)", errorCode);
		
	case kIOReturnLockedRead:
		return string_format("Device Read Locked (%08x)", errorCode);
		
	case kIOReturnLockedWrite:
		return string_format("Device Write Locked (%08x)", errorCode);
		
	case kIOReturnExclusiveAccess:
		return string_format("Exclusive Access and Device already opened (%08x)", errorCode);
		
	case kIOReturnBadMessageID:
		return string_format("Sent/Received Messages had different MSG_ID (%08x)", errorCode);
		
	case kIOReturnUnsupported:
		return string_format("Unsupported Function (%08x)", errorCode);
		
	case kIOReturnVMError:
		return string_format("Misc. VM Failure (%08x)", errorCode);
		
	case kIOReturnInternalError:
		return string_format("Internal Error (%08x)", errorCode);
		
	case kIOReturnIOError:
		return string_format("General I/O Error (%08x)", errorCode);
		
	case kIOReturnCannotLock:
		return string_format("Can't Acquire Lock (%08x)", errorCode);
		
	case kIOReturnNotOpen:
		return string_format("Device Not Open (%08x)", errorCode);
		
	case kIOReturnNotReadable:
		return string_format("Read Not Supported (%08x)", errorCode);
		
	case kIOReturnNotWritable:
		return string_format("Write Not Supported (%08x)", errorCode);
		
	case kIOReturnNotAligned:
		return string_format("Alignment Error (%08x)", errorCode);
		
	case kIOReturnBadMedia:
		return string_format("Media Error (%08x)", errorCode);
		
	case kIOReturnStillOpen:
		return string_format("Device(s) Still Open (%08x)", errorCode);
		
	case kIOReturnRLDError:
		return string_format("RLD Failure (%08x)", errorCode);
		
	case kIOReturnDMAError:
		return string_format("DMA Failure (%08x)", errorCode);
		
	case kIOReturnBusy:
		return string_format("Device Busy (%08x)", errorCode);
		
	case kIOReturnTimeout:
		return string_format("I/O Timeout (%08x)", errorCode);
		
	case kIOReturnOffline:
		return string_format("Device Offline (%08x)", errorCode);
		
	case kIOReturnNotReady:
		return string_format("Not Ready (%08x)", errorCode);
		
	case kIOReturnNotAttached:
		return string_format("Device Not Attached (%08x)", errorCode);
		
	case kIOReturnNoChannels:
		return string_format("No DMA Channels Left (%08x)", errorCode);
		
	case kIOReturnNoSpace:
		return string_format("No Space For Data (%08x)", errorCode);
		
	case kIOReturnPortExists:
		return string_format("Port Already Exists (%08x)", errorCode);
		
	case kIOReturnCannotWire:
		return string_format("Can't Write Down (%08x)", errorCode);
		
	case kIOReturnNoInterrupt:
		return string_format("No Interrupt Attached (%08x)", errorCode);
		
	case kIOReturnNoFrames:
		return string_format("No DMA Frames Enqueued (%08x)", errorCode);
		
	case kIOReturnMessageTooLarge:
		return string_format("Oversized MSG Received On Interrupt Port (%08x)", errorCode);
		
	case kIOReturnNotPermitted:
		return string_format("Not Permitted (%08x)", errorCode);
		
	case kIOReturnNoPower:
		return string_format("No Power To Device (%08x)", errorCode);
		
	case kIOReturnNoMedia:
		return string_format("Media Not Present (%08x)", errorCode);
		
	case kIOReturnUnformattedMedia:
		return string_format("Media Not Formatted (%08x)", errorCode);
		
	case kIOReturnUnsupportedMode:
		return string_format("No Such Mode (%08x)", errorCode);
		
	case kIOReturnUnderrun:
		return string_format("Buffer Underflow (%08x)", errorCode);
		
	case kIOReturnOverrun:
		return string_format("Buffer Overflow (%08x)", errorCode);
		
	case kIOReturnDeviceError:
		return string_format("The Device Is Not Working Properly! (%08x)", errorCode);
		
	case kIOReturnNoCompletion:
		return string_format("A Completion Routine Is Required (%08x)", errorCode);
		
	case kIOReturnAborted:
		return string_format("Operation Aborted (%08x)", errorCode);
		
	case kIOReturnNoBandwidth:
		return string_format("Bus Bandwidth Would Be Exceeded (%08x)", errorCode);
		
	case kIOReturnNotResponding:
		return string_format("Device Not Responding (%08x)", errorCode);
		
	case kIOReturnIsoTooOld:
		return string_format("ISOChronous I/O request for distance past! (%08x)", errorCode);
		
	case kIOReturnIsoTooNew:
		return string_format("ISOChronous I/O request for distant future! (%08x)", errorCode);
		
	case kIOReturnNotFound:
		return string_format("Data Not Found (%08x)", errorCode);
		
	case kIOReturnInvalid:
		return string_format("Should Never Be Seen (%08x)", errorCode);
		
	default:
		if let error = hresult_human_error_string(errorCode) {
			return error
		}
		
		/// See here for more: https://developer.apple.com/library/content/qa/qa1075/_index.html
		/// See here for more: https://developer.apple.com/library/archive/documentation/DeviceDrivers/Conceptual/AccessingHardware/AH_Handling_Errors/AH_Handling_Errors.html
		return usb_human_error_string(errorCode);
	}
}
