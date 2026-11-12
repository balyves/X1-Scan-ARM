// SPDX-License-Identifier: MIT
import Foundation
import Testing
import X1Protocol
@testable import X1ScanCore
import X1Transport

struct ScannerInspectorTests {
    /// Responses recorded in the capture, for the inspector's four commands.
    private static func recordedResponses() throws -> [[UInt8]: SCSIResult] {
        let fixture = try CaptureFixture.load(from: TestFixtures.directory.appending(path: "preview-sequence.json"))
        var responses: [[UInt8]: SCSIResult] = [:]
        for command in ScannerInspector.commands {
            let exchange = try #require(fixture.exchanges.first { $0.cdbBytes == command.cdb && $0.responseBytes != nil })
            responses[command.cdb] = SCSIResult(data: exchange.responseBytes!)
        }
        return responses
    }

    @Test func everyCommandIsAnAllowedRead() throws {
        for command in ScannerInspector.commands {
            try CommandPolicy.readOnly.check(command)
            #expect(command.direction == .fromDevice)
        }
    }

    @Test func readsIdentityCountersAndStateThenCloses() async throws {
        let connection = FakeConnection(responses: try Self.recordedResponses())
        let info = try await ScannerInspector { connection }.read()
        #expect(info.model == "Flextight X1" && info.firmware == "R185")
        #expect(info.counters.count == 7 && info.state == .ready)
        #expect(await connection.sent == ScannerInspector.commands)
        #expect(await connection.closed)
    }

    @Test func stopsAfterInquiryIfNotAnX1() async throws {
        var responses = try Self.recordedResponses()
        var inquiry = responses[X1Command.inquiry().cdb]!.data
        for (offset, byte) in Array("Other scanner   ".utf8).enumerated() { inquiry[16 + offset] = byte }
        responses[X1Command.inquiry().cdb] = SCSIResult(data: inquiry)
        let connection = FakeConnection(responses: responses)
        await #expect(throws: ScannerInspector.Failure.notAFlextightX1(vendor: "Imacon", product: "Other scanner")) {
            try await ScannerInspector { connection }.read()
        }
        #expect(await connection.sent == [X1Command.inquiry()])
        #expect(await connection.closed)
    }

    @Test func badStatusStopsAndCloses() async throws {
        var responses = try Self.recordedResponses()
        responses[X1Command.usageLog().cdb] = SCSIResult(status: SCSIResult.checkCondition)
        let connection = FakeConnection(responses: responses)
        await #expect(throws: ScannerInspector.Failure.self) { try await ScannerInspector { connection }.read() }
        #expect(await connection.sent.count == 3)
        #expect(await connection.closed)
    }

    @Test func busyDeviceIsReported() async throws {
        let connection = FakeConnection(responses: [:], openError: TransportError.deviceBusy)
        await #expect(throws: ScannerInspector.Failure.transport(.deviceBusy)) {
            try await ScannerInspector { connection }.read()
        }
        #expect(await connection.sent.isEmpty)
    }

    @Test func theRealScannerConnectionIsReadOnly() {
        // Built but not opened: nothing reaches IOKit.
        #expect(ScannerInspector.realConnection().policy == .readOnly)
    }
}
