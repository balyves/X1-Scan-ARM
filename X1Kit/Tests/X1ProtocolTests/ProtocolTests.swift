// SPDX-License-Identifier: MIT
import Testing
import X1Protocol
import X1TestSupport
import X1Transport

struct ProtocolTests {
    private func exchange(_ seq: Int) throws -> CaptureExchange {
        try #require(try Fixtures.sequence().exchanges.first { $0.seq == seq })
    }

    private func response(_ seq: Int) throws -> [UInt8] {
        try #require(try exchange(seq).responseBytes)
    }

    @Test func buildersReproduceCapturedCDBs() throws {
        #expect(X1Command.inquiry().cdb == (try exchange(1).cdbBytes))
        #expect(X1Command.modeSense(page: 0x26, length: 56).cdb == (try exchange(2).cdbBytes))
        #expect(X1Command.startupD2().cdb == (try exchange(17).cdbBytes))
        #expect(X1Command.usageLog().cdb == (try exchange(107).cdbBytes))
        #expect(X1Command.session(.start).cdb == (try exchange(224).cdbBytes))
        #expect(X1Command.setMode(0, 0, 1, 1).cdb == (try exchange(245).cdbBytes))
        #expect(X1Command.exposure(Array(repeating: 0, count: 12)).cdb == (try exchange(255).cdbBytes))
        #expect(X1Command.readE1().cdb == (try exchange(297).cdbBytes))
        #expect(X1Command.scan().cdb == (try exchange(636).cdbBytes))
        #expect(X1Command.read(lines: 20, calibration: false, bytes: 240_480).cdb == (try exchange(648).cdbBytes))
        #expect(X1Command.read(lines: 10, calibration: true, bytes: 120_240).cdb == (try exchange(369).cdbBytes))
        #expect(X1Command.stop().cdb == (try exchange(729).cdbBytes))
        #expect(X1Command.session(.end).cdb == (try exchange(748).cdbBytes))
        #expect(X1Command.scannerState().cdb == [UInt8](hex: "df 00 00 00 02 00"))
        #expect(X1Command.readRegister(0x04).cdb == [UInt8](hex: "ee 00 00 00 01 04 00 00 01 00"))
    }

    @Test func readOnlyBuildersPassTheReadOnlyPolicy() throws {
        for command in [X1Command.inquiry(), X1Command.testUnitReady(), X1Command.requestSense(),
                        X1Command.modeSense(page: 0x26, length: 56), X1Command.usageLog(),
                        X1Command.readRegister(0x19), X1Command.sensors(), X1Command.scannerState()] {
            try CommandPolicy.readOnly.check(command)
        }
    }

    @Test func inquiry() throws {
        let inquiry = try InquiryResponse(try response(1))
        #expect(inquiry.peripheralDeviceType == 6)
        #expect(inquiry.vendor == "Imacon")
        #expect(inquiry.product == "Flextight X1")
        #expect(inquiry.revision == "R185")
        #expect(inquiry.isFlextightX1)
    }

    @Test func identityPageGivesTheAnonymisedSerialNumber() throws {
        let identity = try IdentityPage(try response(2))
        #expect(identity.serialNumber == "FX1xxxxxxx")
        #expect(identity.isFieldUnset)
    }

    @Test func scanStatusPage() throws {
        let positioning = try ScanStatusPage(try response(271))
        #expect(positioning.measuredPosition == 24_971)
        #expect(positioning.linesAcquired == 0)
        let lastImageBlock = try ScanStatusPage(try response(727))
        #expect(lastImageBlock.measuredPosition == 6_155)
        #expect(lastImageBlock.linesAcquired == 808)
        #expect(throws: ResponseError.self) { try ScanStatusPage(try response(2)) }  // page 0x26
    }

    @Test func usageLog() throws {
        let log = try UsageLog(try response(107))
        #expect(log.counters == [31_015, 0, 6_958, 0, 227, 67_598, 0])
    }

    @Test func everyCapturedScannerStateIsKnown() throws {
        let states = try Fixtures.sequence().exchanges
            .filter { $0.cdbBytes.first == 0xDF }
            .map { try ScannerState(try #require($0.responseBytes)) }
        #expect(Set(states) == [.ready, .busy, .busyOtherPhase, .afterScan])
    }
}
