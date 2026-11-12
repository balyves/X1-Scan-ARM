// SPDX-License-Identifier: MIT
import Testing
import X1TestSupport
import X1Transport

struct SimulatedX1Tests {
    @Test func fixtureHasTheDocumentedShape() throws {
        let fixture = try Fixtures.sequence()
        #expect(fixture.exchanges.count == 766)
        #expect(fixture.exchanges.map(\.seq) == Array(1...766))
        let profile = try Fixtures.calibrationProfile()
        #expect(profile.width == 2004)
        #expect(profile.white.count == 2004 && profile.dark.count == 2004)
    }

    @Test func repliesWithTheRecordedResponse() async throws {
        let simulator = try Fixtures.simulator()
        let first = try #require(try Fixtures.sequence().exchanges.first)
        let result = try await simulator.execute(.read(first.cdbBytes, length: first.length))
        #expect(result.isGood)
        #expect(result.data == first.responseBytes)
    }

    @Test func rejectsACommandOutOfOrder() async throws {
        let simulator = try Fixtures.simulator()
        // The capture starts with INQUIRY, not with page 0x26.
        await #expect(throws: SimulatedX1.SimulatorError.self) {
            try await simulator.execute(.read([UInt8](hex: "5a 00 26 01 00 00 00 00 38 00")!, length: 56))
        }
    }

    @Test func replaysPolledStatesInOrderThenRepeatsTheLast() async throws {
        let simulator = try Fixtures.simulator()
        let exchanges = try Fixtures.nonPollingExchanges()
        // Play the capture up to F0 at seq 245, after which FlexColor saw 08 01 ×3, 08 40, 00 00.
        for exchange in exchanges where exchange.seq <= 245 {
            let command = SCSICommand(cdb: exchange.cdbBytes, direction: exchange.commandDirection!,
                                      transferLength: exchange.length, dataOut: exchange.dataOutBytes ?? [])
            _ = try await simulator.execute(command)
        }
        let state = SCSICommand.read([UInt8](hex: "df 00 00 00 02 00")!, length: 2)
        var seen: [[UInt8]] = []
        for _ in 0..<7 { seen.append(try await simulator.execute(state).data) }
        #expect(seen == [[8, 1], [8, 1], [8, 1], [8, 0x40], [0, 0], [0, 0], [0, 0]])
    }
}

struct SimulatedStopTests {
    @Test func earlyStopIsRefusedBeforeScan() async throws {
        let simulator = try Fixtures.simulator()
        await #expect(throws: SimulatedX1.SimulatorError.self) {
            try await simulator.execute(SCSICommand(cdb: [0xDB, 0, 0, 0, 0, 0], direction: .none, transferLength: 0))
        }
    }
}

struct SimulatedEarlyStopTests {
    /// Replays the capture up to and including SCAN (polling skipped).
    private func simulatorAfterScan() async throws -> SimulatedX1 {
        let simulator = try Fixtures.simulator()
        for exchange in try Fixtures.nonPollingExchanges() {
            let direction = try #require(exchange.commandDirection)
            let command = SCSICommand(cdb: exchange.cdbBytes, direction: direction, transferLength: exchange.length,
                                      dataOut: direction == .toDevice ? (exchange.dataOutBytes ?? []) : [])
            _ = try await simulator.execute(command)
            if exchange.cdbBytes.first == 0x1B { break }
        }
        return simulator
    }

    private let stop = SCSICommand(cdb: [0xDB, 0, 0, 0, 0, 0], direction: .none, transferLength: 0)
    private let state = SCSICommand.read([UInt8](hex: "df 00 00 00 02 00")!, length: 2)

    @Test func earlyStopAfterScanReplaysTheCapturedStopStates() async throws {
        let simulator = try await simulatorAfterScan()
        #expect(try await simulator.execute(stop).isGood)
        var states: [[UInt8]] = []
        repeat {
            states.append(try await simulator.execute(state).data)
        } while states.last != [0, 0] && states.count < 100
        #expect(states.last == [0, 0])
        #expect(states.dropLast().allSatisfy { $0 == [8, 1] || $0 == [8, 0x40] })
    }

    @Test func afterAnEarlyStopOnlyTheSessionEndIsAccepted() async throws {
        let simulator = try await simulatorAfterScan()
        _ = try await simulator.execute(stop)
        await #expect(throws: SimulatedX1.SimulatorError.self) { try await simulator.execute(stop) }
        let simulator2 = try await simulatorAfterScan()
        _ = try await simulator2.execute(stop)
        // The next captured image read (20 lines × 12 024 bytes) is skipped.
        let read = SCSICommand.read([0x28, 0, 1, 0, 0x14, 0, 0x03, 0xAB, 0x60, 0], length: 240_480)
        await #expect(throws: SimulatedX1.SimulatorError.self) { try await simulator2.execute(read) }

        // The end of session that follows the captured stop is accepted.
        let simulator3 = try await simulatorAfterScan()
        _ = try await simulator3.execute(stop)
        let sessionEnd = SCSICommand(cdb: [0xCF, 0x00, 0x02, 0x80, 0x00, 0x00], direction: .none, transferLength: 0)
        #expect(try await simulator3.execute(sessionEnd).isGood)
    }
}
