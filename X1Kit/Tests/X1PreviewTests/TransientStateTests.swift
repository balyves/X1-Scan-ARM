// SPDX-License-Identifier: MIT
import Testing
import X1Preview
import X1Protocol
import X1TestSupport
import X1Transport

/// `08 00` right after an accepted `08 xx` in the same wait: busy in every
/// wait (real X1, 2026-11-18, cold preview step 81; docs/protocol.md §7).
struct TransientStateTests {
    private static func states(_ raw: [UInt16]) -> [ScannerState] { raw.map { ScannerState(rawValue: $0) } }
    private static let state0800 = ScannerState(rawValue: 0x0800)

    @Test func onlyAfterA08State() {
        #expect(Self.state0800.isTransientAfter(ScannerState(rawValue: 0x0801)))
        #expect(!Self.state0800.isTransientAfter(Self.state0800), "two in a row were never seen")
        #expect(!Self.state0800.isTransientAfter(nil))
        #expect(!Self.state0800.isTransientAfter(.ready))
        #expect(!ScannerState(rawValue: 0x0805).isTransientAfter(ScannerState(rawValue: 0x0801)))
        #expect(!ScannerState(rawValue: 0x0880).isTransientAfter(ScannerState(rawValue: 0x0801)))
    }

    /// The case of 2026-11-18 (x1scan log, step 81): cold preview, wait after
    /// the first `f0 00 01 01 01 01`. The preview now completes.
    @Test func theColdPreviewGoesThroughTheCaseOfStep81() async throws {
        let plan = PreviewScript.plan
        let steps = plan.steps(for: .cold)
        let index = try #require(steps.firstIndex { $0.command == X1Command.setMode(1, 1, 1, 1) })
        #expect(index == 81, "the step of the log")
        let transport = ScriptedStates(inner: try Fixtures.coldSimulator(), afterNonPolling: index,
                                       states: Self.states([0x0807, 0x0803] + Array(repeating: 0x0801, count: 6) + [0x0800]))
        let capture = try await PreviewRunner(transport: GuardedTransport(inner: transport, sequence: try Fixtures.previewGuard()),
                                              configuration: .simulator, plan: plan).run()
        #expect(capture.choice == .cold)
        #expect(capture.image.count == 41)
        #expect(await transport.answered == 9)
    }

    /// In the scan: after `f0 00 01 01 01 01`, after the SCAN of the image
    /// (target `00 01`), and after the middle DB (where `08 00` read first
    /// still stops, `StateAfterStopTests`).
    @Test(arguments: [(0, [0x0807, 0x0801, 0x0800, 0x0801, 0x0800, 0x0840]),
                      (1, [0x0806, 0x0800, 0x0802]),
                      (2, [0x0801, 0x0800])])
    func theScanAccepts0800AfterABusyState(place: Int, raw: [UInt16]) async throws {
        let script = ScanRunTests.script
        let index: Int
        switch place {
        case 0: index = try #require(script.firstIndex { $0.command == X1Command.setMode(1, 1, 1, 1) })
        case 1: index = try #require(script.lastIndex { $0.command == X1Command.scan() })
        default: index = try #require(script.firstIndex { $0.command == X1Command.stop() })
        }
        let transport = ScriptedStates(inner: try ScanRunTests.simulator(), afterNonPolling: index,
                                       states: Self.states(raw))
        let sequence = try ScanRunTests.scanGuard()
        let capture = try await ScanRunTests.runner(GuardedTransport(inner: transport, sequence: sequence)).run()
        #expect(sequence.isComplete)
        #expect(capture.focusLines.count == 400)
        #expect(await transport.answered == raw.count)
    }

    /// Warm preview: after `08 80`, accepted in that wait, `08 00` is too.
    @Test func theWarmPreviewAccepts0800After0880() async throws {
        let plan = PreviewScript.plan
        let steps = plan.steps(for: .warm)
        let index = try #require(steps.firstIndex { $0.command == X1Command.setMode(1, 1, 1, 1) })
        let transport = ScriptedStates(inner: try Fixtures.simulator(), afterNonPolling: index,
                                       states: Self.states([0x0801, 0x0880, 0x0800, 0x0840]))
        let capture = try await PreviewRunner(transport: transport, configuration: .simulator, plan: plan).run()
        #expect(capture.choice == .warm)
        #expect(capture.image.count == 41)
        #expect(await transport.answered == 4)
    }

    /// Two `08 00` in a row: the second stops the run.
    @Test func twoInARowStop() async throws {
        let script = ScanRunTests.script
        let index = try #require(script.firstIndex { $0.command == X1Command.setMode(1, 1, 1, 1) })
        let transport = ScriptedStates(inner: try ScanRunTests.simulator(), afterNonPolling: index,
                                       states: Self.states([0x0801, 0x0800, 0x0800]))
        do {
            _ = try await ScanRunTests.runner(transport).run()
            Issue.record("the scan should have stopped")
        } catch {
            #expect(error.anomaly == .unexpectedState(Self.state0800, waitingFor: .ready))
            #expect(error.stepIndex == index)
        }
        #expect(await transport.answered == 3)
    }

    /// `08 00` first in a wait stops the run. `08 80` (scan) and `08 04` are
    /// refused themselves, so a `08 00` after them is never read. Nothing but
    /// that first 0xDF read is sent after the fault (before SCAN).
    @Test(arguments: [[0x0800], [0x0880, 0x0800], [0x0804, 0x0800]])
    func otherwiseItStops(_ raw: [UInt16]) async throws {
        let script = ScanRunTests.script
        let index = try #require(script.firstIndex { $0.command == X1Command.setMode(1, 1, 1, 1) })
        let transport = ScriptedStates(inner: try ScanRunTests.simulator(), afterNonPolling: index,
                                       states: Self.states(raw))
        do {
            _ = try await ScanRunTests.runner(transport).run()
            Issue.record("the scan should have stopped")
        } catch {
            #expect(error.anomaly == .unexpectedState(ScannerState(rawValue: raw[0]), waitingFor: .ready))
            #expect(error.stepIndex == index)
            #expect(error.emergencyStop == nil)
        }
        #expect(await transport.answered == 1, "stopped on the first state")
        #expect(await transport.commandsAfter == [X1Command.scannerState()])
    }
}

/// Answers `states` to the first 0xDF reads after non-polling command
/// `afterNonPolling` (0-based), then forwards everything to `inner`.
private actor ScriptedStates: SCSITransport {
    private let inner: any SCSITransport
    private let index: Int
    private var pending: [ScannerState]
    private var nonPolling = 0
    private(set) var answered = 0
    private(set) var commandsAfter: [SCSICommand] = []

    init(inner: any SCSITransport, afterNonPolling index: Int, states: [ScannerState]) {
        self.inner = inner
        self.index = index
        self.pending = states
    }

    func execute(_ command: SCSICommand) async throws -> SCSIResult {
        let polling = [0xDF, 0xEE, 0xD3].contains(command.opcode)
        if nonPolling > index { commandsAfter.append(command) }
        if !polling { nonPolling += 1 }
        if nonPolling == index + 1, command == X1Command.scannerState(), !pending.isEmpty {
            let state = pending.removeFirst()
            answered += 1
            return SCSIResult(data: [UInt8(state.rawValue >> 8), UInt8(state.rawValue & 0xFF)])
        }
        return try await inner.execute(command)
    }
}
