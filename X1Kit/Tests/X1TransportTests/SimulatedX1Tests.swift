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
