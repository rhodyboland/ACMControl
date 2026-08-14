//
//  ACMControlTests.swift
//  ACMControlTests
//
//  Created by Rhody Boland on 26/9/2024.
//

import Foundation
import XCTest
@testable import ACMControl

final class ACMControlTests: XCTestCase {
    
    func testFirmwareMetadataParsesOTACapableTelemetrySection() {
        let metadata = ACMFirmwareMetadata.parseFWSection("1.0.0-ota,2,1,ACM-0001")
        
        XCTAssertEqual(metadata?.firmwareVersion, "1.0.0-ota")
        XCTAssertEqual(metadata?.hardwareRevision, "2")
        XCTAssertEqual(metadata?.serialNumber, "ACM-0001")
        XCTAssertEqual(metadata?.isOTACapable, true)
    }
    
    func testFirmwareMetadataTrimsWhitespaceAndAcceptsTextualOTAFlag() {
        let metadata = ACMFirmwareMetadata.parseFWSection(" 1.0.1 , 3 , true , ACM-0002 \n")
        
        XCTAssertEqual(metadata?.firmwareVersion, "1.0.1")
        XCTAssertEqual(metadata?.hardwareRevision, "3")
        XCTAssertEqual(metadata?.serialNumber, "ACM-0002")
        XCTAssertEqual(metadata?.isOTACapable, true)
    }
    
    func testFirmwareMetadataFallsBackToOTASuffix() {
        let metadata = ACMFirmwareMetadata.parseFWSection("1.0.0-ota,2,0,ACM-0001")
        
        XCTAssertEqual(metadata?.isOTACapable, true)
    }
    
    func testFirmwareMetadataRejectsIncompleteSection() {
        XCTAssertNil(ACMFirmwareMetadata.parseFWSection("1.0.0-ota,2"))
    }
    
    func testOTAReadyStatusCanPopulateFirmwareMetadata() {
        let metadata = ACMFirmwareMetadata.parseOTAReadyStatus("OTA:READY,FW=1.0.0-ota,HW=2,MTU=185,MAX_CHUNK=72")
        
        XCTAssertEqual(metadata?.firmwareVersion, "1.0.0-ota")
        XCTAssertEqual(metadata?.hardwareRevision, "2")
        XCTAssertEqual(metadata?.isOTACapable, true)
        XCTAssertNil(metadata?.serialNumber)
    }
    
    func testOTAProtocolHexEncodesFirmwareChunks() {
        let data = Data([0x00, 0x01, 0x0f, 0x10, 0xab, 0xff])
        
        XCTAssertEqual(ACMOTAProtocol.hexEncodedString(for: data), "00010f10abff")
    }
    
    func testOTAProtocolParsesAckOffset() {
        XCTAssertEqual(ACMOTAProtocol.ackOffset(from: "OTA:ACK,OFFSET=144"), 144)
        XCTAssertNil(ACMOTAProtocol.ackOffset(from: "OTA:READY,FW=1.0.0-ota"))
    }
    
    func testOTAProtocolClassifiesStatusMessages() {
        XCTAssertTrue(ACMOTAProtocol.isBeginOK("OTA:BEGIN_OK,SIZE=1024,MAX_CHUNK=72"))
        XCTAssertTrue(ACMOTAProtocol.isComplete("OTA:COMPLETE,REBOOTING"))
        XCTAssertTrue(ACMOTAProtocol.isError("OTA:ERROR,BAD_CHUNK"))
        XCTAssertTrue(ACMOTAProtocol.isAborted("OTA:ABORTED"))
    }
}
