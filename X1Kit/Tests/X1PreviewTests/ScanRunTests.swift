// SPDX-License-Identifier: MIT
import Foundation
import Testing
import X1Preview
import X1Protocol
import X1TestSupport
import X1Transport

/// FlexColor's 2 000 ppi scan session on the simulator (docs/decisions.md,
/// "Real X1: scan"; nothing is sent to a real scanner).
struct ScanRunTests {
    static let script = ScanScript.flexColor4813Scan2000ppi
    static let fixtureURL = Fixtures.directory.appending(path: "scan-sequence-2000ppi.json")
    /// First exchange of the scan session in the capture.
    static let sessionSeq = 834
    static let windowIndex = script.firstIndex { $0.kind == .positionWindow(capturedPosition: 16651) }!
    static let tolerance = PreviewConfiguration.defaultPositionTolerance

    static func fixture() throws -> CaptureFixture { try CaptureFixture.load(from: fixtureURL) }

    static func simulator() throws -> SimulatedX1 {
        SimulatedX1(fixture: try fixture(), profile: try Fixtures.calibrationProfile(), fromSeq: sessionSeq)
    }

    static func scanGuard() throws -> CapturedSequenceGuard {
        try CapturedSequenceGuard.scan(fixture: fixture(), positionTolerance: tolerance)
    }

    static func runner(_ transport: any SCSITransport) -> PreviewRunner {
        PreviewRunner(transport: transport, configuration: .simulator, script: script)
    }

    /// The script is the capture's scan session, command for command.
    @Test func theScriptIsTheCapturedScanSession() throws {
        let captured = try Self.fixture().exchanges.filter {
            $0.seq >= Self.sessionSeq && !SimulatedX1.pollingOpcodes.contains($0.cdbBytes.first ?? 0)
        }
        #expect(captured.count == Self.script.count)
        for (step, exchange) in zip(Self.script, captured) {
            #expect(step.command.cdb == exchange.cdbBytes, "seq \(exchange.seq)")
            #expect(step.command.transferLength == exchange.length, "seq \(exchange.seq)")
            #expect(step.command.dataOut == (exchange.dataOutBytes ?? []), "seq \(exchange.seq)")
        }
    }

    /// 0xDF is polled after exactly the commands FlexColor polled it after,
    /// until the state it last saw there.
    @Test func waitsAreThoseOfTheCapture() throws {
        var lastState: [Int: String] = [:]
        var index = -1
        for exchange in try Self.fixture().exchanges where exchange.seq >= Self.sessionSeq {
            let opcode = exchange.cdbBytes.first ?? 0
            if opcode == 0xDF, index >= 0 { lastState[index] = exchange.response }
            else if !SimulatedX1.pollingOpcodes.contains(opcode) { index += 1 }
        }
        for (index, step) in Self.script.enumerated() {
            #expect(step.waitUntil?.description == lastState[index], "step \(index)")
        }
        #expect(Self.script.filter { $0.waitUntil == .afterFocusSweep }.count == 1)
    }

    @Test func wholeScanGoesThroughTheGuard() async throws {
        let sequence = try Self.scanGuard()
        let capture = try await Self.runner(GuardedTransport(inner: try Self.simulator(), sequence: sequence)).run()
        #expect(sequence.isComplete)
        #expect(capture.choice == .warm)
        #expect(capture.focusLines.count == 400)
        #expect(capture.scanReference.count == 23)
        #expect(capture.leadIn.count == 41)
        #expect(capture.image.reduce(0) { $0 + $1.count } == 1023 * ScanScript.pixelsPerLine * 6)
    }

    /// Within the tolerance, the window of the 400-line step carries the
    /// position read just before; the guard lets that window through.
    @Test(arguments: [64, -192, 256])
    func theMeasuredPositionIsSubstituted(shift: Int) async throws {
        let sequence = try Self.scanGuard()
        let faulty = FaultInjectingTransport(inner: CapturedFocusWindow(inner: try Self.simulator()),
                                             faultAtNonPollingCommand: Self.windowIndex - 1,
                                             fault: .shiftMeasuredPosition(by: shift))
        let capture = try await Self.runner(GuardedTransport(inner: faulty, sequence: sequence)).run()
        #expect(capture.image.count == 52)
        let window = try #require(await faulty.log.first { $0.opcode == 0x24 && $0.dataOut[10] == 0xA9 })
        #expect(Int(window.dataOut[50]) | Int(window.dataOut[51]) << 8 == 16651 + shift)
        #expect(Array(window.dataOut[..<50]) == Array(Self.script[Self.windowIndex].command.dataOut[..<50]))
        #expect(Array(window.dataOut[52...]) == Array(Self.script[Self.windowIndex].command.dataOut[52...]))
    }

    /// After the substitution, later reads are compared with the position sent
    /// (the carriage must have reached it), not with the captured 16 651.
    @Test func laterReadsAreComparedWithThePositionSent() async throws {
        let windowRead = Self.statusReadsBeforeWindow  // the read just before the window
        // Sent 16 851 (+200); a later read at 16 551 is 300 from what was sent, 100 from the capture: stop.
        let shifted = StatusShifting(inner: CapturedFocusWindow(inner: try Self.simulator()),
                                     shifts: [windowRead: 200, windowRead + 1: -100])
        let stopping = Self.runner(GuardedTransport(inner: shifted, sequence: try Self.scanGuard()))
        do {
            _ = try await stopping.run()
            Issue.record("the scan should have stopped")
        } catch {
            #expect(error.anomaly == .positionOutOfTolerance(expected: 16851, measured: 16551, tolerance: 256))
            #expect(error.emergencyStop == .stoppedAndReady, "after SCAN: the stop command")
        }
        // Sent 16 851; a later read at 16 951 is 100 from it (300 from the capture): accepted.
        let accepted = StatusShifting(inner: CapturedFocusWindow(inner: try Self.simulator()),
                                      shifts: [windowRead: 200, windowRead + 1: 300])
        let capture = try await Self.runner(GuardedTransport(inner: accepted, sequence: try Self.scanGuard())).run()
        #expect(capture.image.count == 52)
    }

    /// Number (1-based) of the page 0x20 read right before the substituted window.
    static let statusReadsBeforeWindow = script[..<windowIndex].filter {
        $0.command.opcode == 0x5A && $0.command.cdb[2] == 0x20
    }.count

    /// Beyond it, the run stops before that window: nothing more is sent.
    @Test(arguments: [257, -300, 8000])
    func beyondTheToleranceNothingMoreIsSent(shift: Int) async throws {
        let faulty = FaultInjectingTransport(inner: try Self.simulator(), faultAtNonPollingCommand: Self.windowIndex - 1,
                                             fault: .shiftMeasuredPosition(by: shift))
        let runner = Self.runner(GuardedTransport(inner: faulty, sequence: try Self.scanGuard()))
        do {
            _ = try await runner.run()
            Issue.record("the scan should have stopped")
        } catch {
            #expect(error.anomaly == .positionOutOfTolerance(expected: 16651, measured: 16651 + shift, tolerance: 256))
            #expect(error.stepIndex == Self.windowIndex)
            #expect(error.emergencyStop == nil)
            #expect(await faulty.commandsAfterFault.allSatisfy { $0.opcode == 0xDF }, "only the wait after that read")
        }
    }

    /// The scan needs a scanner used before: power-on values stop it at the
    /// first page 0x20 read: only the session start and reads come before it.
    @Test func aScannerJustSwitchedOnIsRefused() async throws {
        let choice = Self.script.firstIndex { $0.kind == .startState(.warm) }!
        let faulty = FaultInjectingTransport(inner: try Self.simulator(), faultAtNonPollingCommand: choice,
                                             fault: .setChannelValues([2048, 2048, 2048]))
        do {
            _ = try await Self.runner(faulty).run()
            Issue.record("the scan should have stopped")
        } catch {
            #expect(error.anomaly == .startStateMismatch(required: .warm, channelValues: [2048, 2048, 2048]))
            #expect(await faulty.commandsAfterFault.isEmpty)
        }
        let before = Self.script[..<choice].map(\.command).filter { $0.direction != .fromDevice }
        #expect(before == [X1Command.session(.start)], "only the session start before that read")
    }

    /// Neither the power-on values nor values left by earlier use: stopped too.
    @Test func anUnrecognisedStateIsRefused() async throws {
        let choice = Self.script.firstIndex { $0.kind == .startState(.warm) }!
        let faulty = FaultInjectingTransport(inner: try Self.simulator(), faultAtNonPollingCommand: choice,
                                             fault: .setChannelValues([0, 0, 0]))
        do {
            _ = try await Self.runner(faulty).run()
            Issue.record("the scan should have stopped")
        } catch {
            #expect(error.anomaly == .startStateMismatch(required: .warm, channelValues: [0, 0, 0]))
            #expect(await faulty.commandsAfterFault.isEmpty)
        }
    }

    /// A negative tolerance cannot build a guard.
    @Test func negativeToleranceIsRefused() throws {
        #expect(throws: CapturedSequenceGuard.SetupError.self) {
            try CapturedSequenceGuard.scan(fixture: Self.fixture(), positionTolerance: -1)
        }
    }

    /// An anomaly during the 400-line step: the stop command, then 0xDF only.
    @Test func anomalyDuringTheFocusStepStops() async throws {
        let sweep = Self.script.firstIndex { $0.command == X1Command.focusSweep() }!
        let sequence = try Self.scanGuard()
        let faulty = FaultInjectingTransport(inner: try Self.simulator(), faultAtNonPollingCommand: sweep + 10,
                                             fault: .checkCondition)
        do {
            _ = try await Self.runner(GuardedTransport(inner: faulty, sequence: sequence)).run()
            Issue.record("the scan should have stopped")
        } catch {
            #expect(error.emergencyStop == .stoppedAndReady)
        }
        let after = await faulty.commandsAfterFault
        #expect(after.first == X1Command.stop())
        #expect(after.dropFirst().allSatisfy { $0 == X1Command.scannerState() })
    }

    /// Phases follow the commands: 400-line step, then (at 2 000 ppi) white
    /// and dark, then the image.
    @Test func phasesFollowTheCommands() {
        let phases = PreviewPhase.phases(for: Self.script)
        var order: [PreviewPhase] = []
        for phase in phases where order.last != phase { order.append(phase) }
        #expect(order == [.calibration, .focus, .calibration, .references, .scanning, .finishing])
        let sweep = Self.script.firstIndex { $0.command == X1Command.focusSweep() }!
        #expect(phases[sweep] == .focus && phases[sweep + 400] == .focus)
        // The other order (white/dark first, as at 1 000 and 3 200 ppi) is derived the same way.
        let reordered = Array(Self.script[0..<sweep - 4]) + Self.script[(sweep + 402)...].prefix(26)
            + Array(Self.script[(sweep - 4)...(sweep + 401)])
        var other: [PreviewPhase] = []
        for phase in PreviewPhase.phases(for: reordered) where other.last != phase { other.append(phase) }
        #expect(other == [.calibration, .references, .focus, .calibration])
    }

    /// `00 06` is a wait target of the scan script only, never a busy state.
    @Test func state0006OnlyInTheScan() {
        #expect(!ScannerState.afterFocusSweep.isBusy)
        let previews = PreviewScript.plan.steps(for: .cold) + PreviewScript.plan.steps(for: .warm)
        #expect(!previews.contains { $0.waitUntil == .afterFocusSweep })
    }
}

/// The scan guard's single substitution.
struct ScanGuardTests {
    private static let commands = ScanScript.flexColor4813Scan2000ppi.map(\.command)
    private static let window = ScanScript.flexColor4813Scan2000ppi.firstIndex {
        $0.kind == .positionWindow(capturedPosition: 16651)
    }!

    private static func withPosition(_ command: SCSICommand, _ position: Int) -> SCSICommand {
        var data = command.dataOut
        data[50] = UInt8(position & 0xFF)
        data[51] = UInt8(position >> 8)
        return X1Command.setWindow(data)
    }

    private func guardAtTheWindow() throws -> CapturedSequenceGuard {
        let sequence = try ScanRunTests.scanGuard()
        for command in Self.commands.prefix(Self.window) { try sequence.check(command) }
        return sequence
    }

    @Test(arguments: [16651 - 256, 16651, 16651 + 256])
    func thePositionWithinTheToleranceIsAccepted(position: Int) throws {
        try guardAtTheWindow().check(Self.withPosition(Self.commands[Self.window], position))
    }

    @Test(arguments: [16651 - 257, 16651 + 257, 0])
    func aPositionBeyondIsRefused(position: Int) throws {
        let sequence = try guardAtTheWindow()
        #expect(throws: TransportError.self) { try sequence.check(Self.withPosition(Self.commands[Self.window], position)) }
    }

    /// Any other byte of that window must be the captured one.
    @Test func anotherByteIsRefused() throws {
        var data = Self.commands[Self.window].dataOut
        data[54] ^= 1
        #expect(throws: TransportError.self) { try guardAtTheWindow().check(X1Command.setWindow(data)) }
    }

    /// Bytes 52-53 (the high half of the target field) stay 0.
    @Test func bytes52And53AreNotPartOfTheSubstitution() throws {
        var data = Self.commands[Self.window].dataOut
        data[52] = 1
        #expect(throws: TransportError.self) { try guardAtTheWindow().check(X1Command.setWindow(data)) }
    }

    /// No other window may carry another position (here the image window).
    @Test func noSubstitutionElsewhere() throws {
        let sequence = try ScanRunTests.scanGuard()
        let image = Self.commands.lastIndex { $0.opcode == 0x24 }!
        for command in Self.commands.prefix(image) { try sequence.check(command) }
        #expect(throws: TransportError.self) { try sequence.check(Self.withPosition(Self.commands[image], 100)) }
    }
}

/// Plays a scanner that measured another position: the window of the
/// 400-line step reaches the simulator with the captured target again.
actor CapturedFocusWindow: SCSITransport {
    let inner: SimulatedX1
    init(inner: SimulatedX1) { self.inner = inner }

    func execute(_ command: SCSICommand) async throws -> SCSIResult {
        guard command.opcode == 0x24, command.dataOut.count >= 54, command.dataOut[10] == 0xA9 else {
            return try await inner.execute(command)
        }
        var data = command.dataOut
        data[50] = 0x0B
        data[51] = 0x41  // 16 651
        return try await inner.execute(X1Command.setWindow(data))
    }
}

/// Adds a shift to the measured position of given page 0x20 reads (1-based).
actor StatusShifting: SCSITransport {
    let inner: any SCSITransport
    let shifts: [Int: Int]
    private var reads = 0
    init(inner: any SCSITransport, shifts: [Int: Int]) {
        self.inner = inner
        self.shifts = shifts
    }

    func execute(_ command: SCSICommand) async throws -> SCSIResult {
        let result = try await inner.execute(command)
        guard command.opcode == 0x5A, command.cdb[2] == 0x20 else { return result }
        reads += 1
        guard let shift = shifts[reads] else { return result }
        var data = result.data
        let position = Int(data[27]) | Int(data[28]) << 8 + shift
        data[27] = UInt8(position & 0xFF)
        data[28] = UInt8(position >> 8)
        return SCSIResult(status: result.status, data: data)
    }
}
