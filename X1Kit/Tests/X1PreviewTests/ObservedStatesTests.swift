// SPDX-License-Identifier: MIT
import Foundation
import Testing
import X1Preview
import X1Protocol
import X1TestSupport
import X1Transport

/// The warm previews, the cold preview and the 2 000 ppi scan session
/// captured: every 0xDF state is accepted in the wait where it appears, and
/// `08 80` only there. `08 04` (1 000 ppi scan) and the `08 80` of the
/// 3 200 ppi scan session stay refused: those sessions are not walked
/// (docs/protocol.md §7).
struct ObservedStatesTests {
    private static let pollingOpcodes: Set<UInt8> = [0xDF, 0xEE, 0xD3]
    private static let state0880 = ScannerState.busy0880

    /// The 0xDF states FlexColor read after each non-polling command of
    /// `fixture` from `seq`, in order: one entry per command.
    private static func waits(_ fixture: CaptureFixture, from seq: Int) -> [(cdb: [UInt8], seq: Int, states: [ScannerState])] {
        var result: [(cdb: [UInt8], seq: Int, states: [ScannerState])] = []
        for exchange in fixture.exchanges where exchange.seq >= seq {
            let cdb = exchange.cdbBytes
            guard let opcode = cdb.first else { continue }
            if opcode == 0xDF, let bytes = exchange.responseBytes, let state = try? ScannerState(bytes) {
                if !result.isEmpty { result[result.count - 1].states.append(state) }
            } else if !pollingOpcodes.contains(opcode) {
                result.append((cdb, exchange.seq, []))
            }
        }
        return result
    }

    /// Matches each command of the capture with the step that has the same
    /// CDB and the same rank among the steps with that CDB (FlexColor's order
    /// varies a little: the warm preview before the 2 000 ppi scan reads page
    /// 0x20 once more, seq 269), then checks that every state read in the
    /// wait is its target or accepted there. A command the script does not
    /// have may only show the observed busy states.
    private static func check(_ steps: [PreviewStep], against fixture: CaptureFixture, from seq: Int,
                              to end: Int = .max, _ name: String) {
        var stepsByCDB: [[UInt8]: [Int]] = [:]
        for (index, step) in steps.enumerated() { stepsByCDB[step.command.cdb, default: []].append(index) }
        let statusRead = X1Command.modeSense(page: ScanStatusPage.page, length: ScanStatusPage.length).cdb
        var rank: [[UInt8]: Int] = [:]
        var matched = 0
        for wait in waits(fixture, from: seq) where wait.seq < end {
            let r = rank[wait.cdb, default: 0]
            rank[wait.cdb] = r + 1
            guard let candidates = stepsByCDB[wait.cdb], r < candidates.count else {
                for state in wait.states where state != .ready && state != .afterScan {
                    #expect(state.isBusy, "\(name): \(state) after seq \(wait.seq), a command not in the script")
                }
                continue
            }
            matched += 1
            let index = candidates[r]
            let step = steps[index]
            guard let target = step.waitUntil else {
                // Page 0x20 reads are matched by rank, which the extra read of
                // the 2 000 ppi preview shifts: there, only the global list.
                guard wait.cdb != statusRead else {
                    for state in wait.states where state != .ready {
                        #expect(state.isBusy, "\(name): \(state) after seq \(wait.seq)")
                    }
                    continue
                }
                #expect(wait.states.isEmpty, "\(name): FlexColor waited after seq \(wait.seq), the script does not (step \(index))")
                continue
            }
            // The runner's rule (PreviewRunner.waitForState), without the after-DB case.
            // States read after the target in the same wait (FlexColor polled on)
            // are checked too, the transition rule starting again.
            var previous: ScannerState?
            for state in wait.states {
                if state == target { previous = nil; continue }
                let accepted = state.isBusy || step.alsoBusy.contains(state) || state.isTransientAfter(previous)
                #expect(accepted, "\(name): \(state) after seq \(wait.seq) (step \(index)) is refused")
                previous = state
            }
        }
        #expect(matched > steps.count * 9 / 10, "\(name): the capture does not follow the script")
    }

    private static func load(_ name: String) throws -> CaptureFixture {
        try CaptureFixture.load(from: Fixtures.directory.appending(path: "\(name).json"))
    }

    @Test func theScanCaptureStatesAreAccepted() throws {
        Self.check(ScanScript.flexColor4813Scan2000ppi, against: try Self.load("scan-sequence-2000ppi"),
                   from: ScanRunTests.sessionSeq, "2000 ppi scan")
    }

    /// The warm previews captured, including those before the three scans.
    /// (name, first seq of the scan session, where the preview ends)
    @Test(arguments: [("preview-sequence", Int.max), ("preview-sequence-warm-2", Int.max),
                      ("preview-sequence-warm-3", Int.max), ("preview-sequence-warm-4", Int.max),
                      ("preview-sequence-warm-5", Int.max),
                      ("scan-sequence-1000ppi", 778), ("scan-sequence-2000ppi", 834),
                      ("scan-sequence-3200ppi", 767)])
    func warmPreviewStatesAreAccepted(_ name: String, end: Int) throws {
        Self.check(PreviewScript.plan.steps(for: .warm), against: try Self.load(name), from: 0, to: end, name)
    }

    /// The warm previews of 2026-11-18 (FlexColor restarted before each)
    /// send exactly the warm capture's commands outside polling.
    @Test(arguments: ["preview-sequence-warm-3", "preview-sequence-warm-4", "preview-sequence-warm-5"])
    func laterWarmPreviewsSendTheSameCommands(_ name: String) throws {
        func commands(_ fixture: CaptureFixture) -> [String] {
            fixture.exchanges.filter { !Self.pollingOpcodes.contains($0.cdbBytes.first ?? 0) }
                .map { "\($0.cdb)|\($0.dataOut ?? "")|\($0.length)" }
        }
        #expect(commands(try Self.load(name)) == commands(try Self.load("preview-sequence")))
    }

    @Test func coldPreviewStatesAreAccepted() throws {
        Self.check(PreviewScript.plan.steps(for: .cold), against: try Fixtures.coldSequence(), from: 0,
                   "preview-sequence-cold")
    }

    /// `08 80` is accepted in one wait only: after the first
    /// `f0 00 01 01 01 01` of the warm preview. Not in the cold preview, not
    /// in the 2 000 ppi scan (only the 3 200 ppi capture shows it there).
    @Test func state0880OnlyWhereItWasSeen() {
        let mode1111 = X1Command.setMode(1, 1, 1, 1)
        let warm = PreviewScript.plan.steps(for: .warm)
        let cold = PreviewScript.plan.steps(for: .cold)
        let warmIndex = warm.firstIndex { $0.command == mode1111 }
        #expect(warm.indices.filter { warm[$0].alsoBusy.contains(Self.state0880) } == [warmIndex].compactMap { $0 })
        #expect(warmIndex.map { warm[$0].alsoBusy } == [Self.state0880], "08 80 and nothing else")
        #expect(warm.filter { !$0.alsoBusy.isEmpty }.count == 1)
        #expect(cold.allSatisfy { $0.alsoBusy.isEmpty }, "never seen in a cold preview")
        #expect(ScanScript.flexColor4813Scan2000ppi.allSatisfy { $0.alsoBusy.isEmpty })
        #expect(!Self.state0880.isBusy && !Self.state0880.isBusyAfterStop, "no global list")
        #expect(!ScannerState(rawValue: 0x0804).isBusy, "08 04: 1 000 ppi only, not in our scripts")
    }

    /// On the simulator: `08 80` in the scan's wait after `f0 00 01 01 01 01`
    /// stops the scan, before anything moves on.
    @Test func state0880StopsTheScan() async throws {
        let script = ScanRunTests.script
        let mode1111 = try #require(script.firstIndex { $0.command == X1Command.setMode(1, 1, 1, 1) })
        let refused = FaultInjectingTransport(inner: try ScanRunTests.simulator(),
                                              faultAtNonPollingCommand: mode1111, fault: .stateAfter(Self.state0880))
        do {
            _ = try await ScanRunTests.runner(refused).run()
            Issue.record("the scan should have stopped")
        } catch {
            #expect(error.anomaly == .unexpectedState(Self.state0880, waitingFor: .ready))
            #expect(error.stepIndex == mode1111)
            #expect(error.emergencyStop == nil, "before SCAN")
        }
        #expect(await refused.commandsAfterFault == [X1Command.scannerState()],
                "only the 0xDF read that returned 08 80; nothing after the refusal")
    }

    /// On the simulator: `08 80` in the warm preview's wait goes through; at
    /// the same step of the cold preview it stops.
    @Test(arguments: [false, true])
    func state0880InThePreview(cold: Bool) async throws {
        let plan = PreviewScript.plan
        let steps = plan.steps(for: cold ? .cold : .warm)
        let index = try #require(steps.firstIndex { $0.command == X1Command.setMode(1, 1, 1, 1) })
        let simulator = cold ? try Fixtures.coldSimulator() : try Fixtures.simulator()
        let transport = FaultInjectingTransport(inner: simulator, faultAtNonPollingCommand: index,
                                                fault: .stateAfter(Self.state0880))
        do {
            let capture = try await PreviewRunner(transport: transport, configuration: .simulator, plan: plan).run()
            #expect(!cold, "the cold preview should have stopped")
            #expect(capture.image.count == 41)
        } catch {
            #expect(cold, "the warm preview should have gone through: \(error)")
            #expect(error.anomaly == .unexpectedState(Self.state0880, waitingFor: .ready))
            #expect(error.stepIndex == index)
        }
        #expect(await transport.faultLogIndex != nil)
    }
}
