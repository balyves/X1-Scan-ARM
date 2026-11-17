// SPDX-License-Identifier: MIT
import Foundation
import Testing
import X1TestSupport
import X1Transport

struct SecondWarmFixtureTests {
    /// The warm capture of 2026-11-17 (FlexColor restarted, X1 warm) has the same
    /// commands outside polling as the warm fixture of 2026-11-12 (protocol.md §11).
    @Test func sameCommandsAsTheFirstWarmCapture() throws {
        let second = try CaptureFixture.load(from: Fixtures.secondWarmSequenceURL)
        let first = try Fixtures.sequence()
        func commands(_ fixture: CaptureFixture) -> [String] {
            fixture.exchanges
                .filter { !SimulatedX1.pollingOpcodes.contains($0.cdbBytes.first ?? 0) }
                .map { "\($0.cdb)|\($0.dataOut ?? "")|\($0.length)" }
        }
        #expect(commands(second).count == 206)
        #expect(commands(second) == commands(first))
        #expect(second.exchanges.allSatisfy { ($0.status ?? 0) == 0 })
    }

    @Test func readOnlyReadsPassThePolicyAndNoSerialNumber() throws {
        let second = try CaptureFixture.load(from: Fixtures.secondWarmSequenceURL)
        for exchange in second.exchanges where CommandPolicy.readOnlyCommands[exchange.cdbBytes.first ?? 0] != nil {
            let command = SCSICommand(cdb: exchange.cdbBytes, direction: try #require(exchange.commandDirection),
                                      transferLength: exchange.length, dataOut: exchange.dataOutBytes ?? [])
            #expect(throws: Never.self, "seq \(exchange.seq)") { try CommandPolicy.readOnly.check(command) }
        }
        let text = try String(contentsOf: Fixtures.secondWarmSequenceURL, encoding: .utf8)
        #expect(text.range(of: #"FX1[0-9]"#, options: .regularExpression) == nil)
        #expect(text.range(of: #"46 58 31 3[0-9]"#, options: .regularExpression) == nil)
    }
}
