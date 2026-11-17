// SPDX-License-Identifier: MIT
import Foundation
import Testing
import X1TestSupport
import X1Transport

/// The three scan captures of 2026-11-17 (protocol.md §12). Nothing replays
/// them yet: these tests check their anonymisation, their statuses and a few
/// values protocol.md gives as confirmed.
struct ScanFixtureTests {
    static let names = ["scan-sequence-1000ppi.json", "scan-sequence-2000ppi.json", "scan-sequence-3200ppi.json"]

    @Test(arguments: names) func noSerialNumberAndAllStatusesZero(name: String) throws {
        let url = Fixtures.directory.appending(path: name)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.range(of: #"FX1[0-9]"#, options: .regularExpression) == nil)
        #expect(text.range(of: #"46 58 31 3[0-9]"#, options: .regularExpression) == nil)
        let fixture = try CaptureFixture.load(from: url)
        // Asynchronous image reads have no captured status.
        #expect(fixture.exchanges.allSatisfy { $0.status == 0 || ($0.status == nil && $0.isAsync == true) })
        #expect(!fixture.exchanges.contains { $0.cdb.hasPrefix("5a 00 28") })
    }

    /// Every read of the captures passes `CommandPolicy.readOnly`, MODE SENSE
    /// page 0x24 (seen only in scans) included since 2026-11-17.
    @Test(arguments: names) func readsPassThePolicy(name: String) throws {
        let fixture = try CaptureFixture.load(from: Fixtures.directory.appending(path: name))
        var refused: Set<String> = []
        for exchange in fixture.exchanges where CommandPolicy.readOnlyCommands[exchange.cdbBytes.first ?? 0] != nil {
            let command = SCSICommand(cdb: exchange.cdbBytes, direction: try #require(exchange.commandDirection),
                                      transferLength: exchange.length, dataOut: exchange.dataOutBytes ?? [])
            if (try? CommandPolicy.readOnly.check(command)) == nil { refused.insert(exchange.cdb) }
        }
        #expect(refused.isEmpty)
    }

    /// SET WINDOW offset 10 = ppi × 50 000 / 3 in the image window, and
    /// offset 26 = lines read after the SCAN + 1 (protocol.md §9, §10).
    @Test(arguments: [("scan-sequence-1000ppi.json", 1000), ("scan-sequence-2000ppi.json", 2000),
                      ("scan-sequence-3200ppi.json", 3200)])
    func imageWindowResolutionAndLines(name: String, ppi: Int) throws {
        let exchanges = try CaptureFixture.load(from: Fixtures.directory.appending(path: name)).exchanges
        let scan = try #require(exchanges.lastIndex { $0.cdb == "1b 00 00 01 01 00" })
        let window = try #require(exchanges[..<scan].last { $0.cdbBytes.first == 0x24 }?.dataOutBytes)
        func le(_ offset: Int, _ size: Int) -> Int {
            (0..<size).reduce(0) { $0 | Int(window[offset + $1]) << (8 * $1) }
        }
        #expect(le(10, 4) == ppi * 50_000 / 3)
        let linesRead = exchanges[scan...].filter { $0.cdbBytes.first == 0x28 }.reduce(0) { $0 + Int($1.cdbBytes[4]) }
        #expect(le(26, 2) == linesRead + 1)
    }
}
