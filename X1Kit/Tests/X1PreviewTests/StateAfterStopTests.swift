// SPDX-License-Identifier: MIT
import Testing
import X1Preview
import X1Protocol
import X1TestSupport
import X1Transport

/// 0xDF `08 00` after a DB (real X1, 2026-11-18, docs/protocol.md §7): busy
/// while waiting after the final DB of a sequence (or the emergency DB), an
/// unexpected state anywhere else.
struct StateAfterStopTests {
    private static let state0800 = ScannerState(rawValue: 0x0800)

    @Test func busyAfterAStopOnly() {
        #expect(Self.state0800.isBusyAfterStop)
        #expect(!Self.state0800.isBusy)
        for state in ScannerState.observedBusyStates { #expect(state.isBusyAfterStop) }
        for raw: UInt16 in [0x0805, 0x0808, 0x0001, 0x0006, 0xFFFF] {
            #expect(!ScannerState(rawValue: raw).isBusyAfterStop)
        }
    }

    /// The case of 2026-11-18: cold sequence chosen, image complete, then
    /// `08 00` right after the final DB. The preview now completes.
    @Test func theColdPreviewCompletesWith0800AfterItsFinalStop() async throws {
        let plan = PreviewScript.plan
        let steps = plan.steps(for: .cold)
        let stop = try #require(steps.lastIndex { $0.command == X1Command.stop() })
        let sequence = try Fixtures.previewGuard()
        let faulty = FaultInjectingTransport(inner: try Fixtures.coldSimulator(),
                                             faultAtNonPollingCommand: stop, fault: .stateAfter(Self.state0800))
        let capture = try await PreviewRunner(transport: GuardedTransport(inner: faulty, sequence: sequence),
                                              configuration: .simulator, plan: plan).run()
        #expect(capture.choice == .cold)
        #expect(capture.image.count == 41)
        #expect(sequence.isComplete)
        #expect(await faulty.faultLogIndex != nil, "the fault was injected")
        let after = await faulty.commandsAfterFault
        #expect(after.first == X1Command.scannerState())
        #expect(!after.contains(X1Command.stop()), "no second DB")
    }

    /// After the final DB, several `08 00` in a row are accepted, read first
    /// included (unlike in other waits, `TransientStateTests.twoInARowStop`).
    @Test func afterTheFinalStopSeveral0800AreAccepted() async throws {
        let plan = PreviewScript.plan
        let steps = plan.steps(for: .cold)
        let stop = try #require(steps.lastIndex { $0.command == X1Command.stop() })
        let transport = AnswerStates(inner: try Fixtures.coldSimulator(), afterNonPolling: stop,
                                     states: [Self.state0800, Self.state0800, ScannerState(rawValue: 0x0801)])
        let capture = try await PreviewRunner(transport: transport, configuration: .simulator, plan: plan).run()
        #expect(capture.choice == .cold)
        #expect(await transport.answered == 3)
    }

    /// The scan's final DB: same rule.
    @Test func theScanCompletesWith0800AfterItsFinalStop() async throws {
        let script = ScanRunTests.script
        let stop = try #require(script.lastIndex { $0.command == X1Command.stop() })
        let sequence = try ScanRunTests.scanGuard()
        let faulty = FaultInjectingTransport(inner: try ScanRunTests.simulator(),
                                             faultAtNonPollingCommand: stop, fault: .stateAfter(Self.state0800))
        let capture = try await ScanRunTests.runner(GuardedTransport(inner: faulty, sequence: sequence)).run()
        #expect(await faulty.faultLogIndex != nil, "the fault was injected")
        #expect(await faulty.commandsAfterFault.first == X1Command.scannerState())
        #expect(sequence.isComplete)
        #expect(capture.focusLines.count == 400)
        #expect(capture.image.reduce(0) { $0 + $1.count } == 1023 * ScanScript.pixelsPerLine * 6)
    }

    /// After the scan's middle DB (end of the 400-line step), `08 00` stops the
    /// scan: the captures show `00 00` right away there.
    @Test func theScansMiddleStopStillStops() async throws {
        let script = ScanRunTests.script
        let stop = try #require(script.firstIndex { $0.command == X1Command.stop() })
        #expect(stop != script.lastIndex { $0.command == X1Command.stop() })
        let faulty = FaultInjectingTransport(inner: try ScanRunTests.simulator(),
                                             faultAtNonPollingCommand: stop, fault: .stateAfter(Self.state0800))
        do {
            _ = try await ScanRunTests.runner(faulty).run()
            Issue.record("the scan should have stopped")
        } catch {
            #expect(error.anomaly == .unexpectedState(Self.state0800, waitingFor: .ready))
            #expect(error.stepIndex == stop)
            #expect(error.emergencyStop == .stoppedAndReady)
        }
    }

    /// The emergency DB: `08 00` in the wait after it is busy too. The scan
    /// stops on `08 00` after its middle DB; the first 0xDF after the
    /// emergency DB answers `08 00` again.
    @Test func theEmergencyStopAccepts0800() async throws {
        let script = ScanRunTests.script
        let stop = try #require(script.firstIndex { $0.command == X1Command.stop() })
        let faulty = FaultInjectingTransport(inner: try ScanRunTests.simulator(),
                                             faultAtNonPollingCommand: stop, fault: .stateAfter(Self.state0800))
        let transport = StateAfterSecondStop(inner: faulty, state: Self.state0800)
        do {
            _ = try await ScanRunTests.runner(transport).run()
            Issue.record("the scan should have stopped")
        } catch {
            #expect(error.anomaly == .unexpectedState(Self.state0800, waitingFor: .ready))
            #expect(error.emergencyStop == .stoppedAndReady)
        }
        #expect(await transport.answered, "08 00 was answered after the emergency DB")
    }

    /// Anywhere else (here after F0 and after SCAN), `08 00` still stops.
    @Test(arguments: [0xF0, 0x1B])
    func elsewhere0800StillStops(opcode: Int) async throws {
        let script = PreviewScript.flexColor4813Cold
        let index = try #require(script.firstIndex { $0.command.opcode == opcode && $0.waitUntil != nil })
        let transport = FaultInjectingTransport(inner: try Fixtures.coldSimulator(),
                                                faultAtNonPollingCommand: index, fault: .stateAfter(Self.state0800))
        do {
            _ = try await PreviewRunner(transport: transport, configuration: .simulator, script: script).run()
            Issue.record("the preview should have stopped")
        } catch {
            let target = try #require(script[index].waitUntil)
            #expect(error.anomaly == .unexpectedState(Self.state0800, waitingFor: target))
            #expect(error.stepIndex == index)
        }
    }
}

/// Answers `state` to the first 0xDF read after the second DB it forwards.
private actor StateAfterSecondStop: SCSITransport {
    private let inner: any SCSITransport
    private let state: ScannerState
    private var stops = 0
    private(set) var answered = false

    init(inner: any SCSITransport, state: ScannerState) {
        self.inner = inner
        self.state = state
    }

    func execute(_ command: SCSICommand) async throws -> SCSIResult {
        if command == X1Command.stop() { stops += 1 }
        if stops == 2, !answered, command == X1Command.scannerState() {
            answered = true
            return SCSIResult(data: [UInt8(state.rawValue >> 8), UInt8(state.rawValue & 0xFF)])
        }
        return try await inner.execute(command)
    }
}

/// Answers `states` to the first 0xDF reads after non-polling command
/// `afterNonPolling` (0-based), then forwards everything to `inner`.
private actor AnswerStates: SCSITransport {
    private let inner: any SCSITransport
    private let index: Int
    private var pending: [ScannerState]
    private var nonPolling = 0
    private(set) var answered = 0

    init(inner: any SCSITransport, afterNonPolling index: Int, states: [ScannerState]) {
        self.inner = inner
        self.index = index
        self.pending = states
    }

    func execute(_ command: SCSICommand) async throws -> SCSIResult {
        if ![0xDF, 0xEE, 0xD3].contains(command.opcode) { nonPolling += 1 }
        if nonPolling == index + 1, command == X1Command.scannerState(), !pending.isEmpty {
            let state = pending.removeFirst()
            answered += 1
            return SCSIResult(data: [UInt8(state.rawValue >> 8), UInt8(state.rawValue & 0xFF)])
        }
        return try await inner.execute(command)
    }
}
