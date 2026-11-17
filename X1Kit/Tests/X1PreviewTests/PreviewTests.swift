// SPDX-License-Identifier: MIT
import Foundation
import Testing
import X1Preview
import X1Protocol
import X1TestSupport
import X1Transport

/// The two captured sequences: warm (2026-11-12, after earlier previews) and
/// cold (2026-11-16, right after power-on).
enum Capture: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case warm, cold

    var script: [PreviewStep] { self == .cold ? PreviewScript.flexColor4813Cold : PreviewScript.flexColor4813 }
    func simulator() throws -> SimulatedX1 { self == .cold ? try Fixtures.coldSimulator() : try Fixtures.simulator() }
    func fixture() throws -> CaptureFixture { self == .cold ? try Fixtures.coldSequence() : try Fixtures.sequence() }
    /// The captured exchanges, without the cold capture's page 0x28 read (not sent by the scripts).
    func exchanges() throws -> [CaptureExchange] {
        try fixture().exchanges.filter { $0.cdbBytes != SimulatedX1.page28Read }
    }
    func nonPollingExchanges() throws -> [CaptureExchange] { try Fixtures.nonPollingExchanges(cold: self == .cold) }
    func run(on transport: any SCSITransport) async throws -> PreviewCapture {
        try await PreviewRunner(transport: transport, configuration: .simulator, script: script).run()
    }
    var testDescription: String { rawValue }
}

struct PreviewConformanceTests {
    /// Our sequence, played against the simulator, sends the same commands as
    /// FlexColor in the same order: CDB, direction, transfer length and data_out,
    /// apart from the polling commands (0xEE, 0xD3, 0xDF).
    @Test(arguments: Capture.allCases)
    func previewMatchesTheCaptureCommandForCommand(_ capture: Capture) async throws {
        let simulator = try capture.simulator()
        _ = try await capture.run(on: simulator)

        let sent = await simulator.log.filter { !SimulatedX1.pollingOpcodes.contains($0.opcode) }
        let captured = try capture.nonPollingExchanges()
        #expect(sent.count == captured.count)
        for (command, exchange) in zip(sent, captured) {
            #expect(command.cdb == exchange.cdbBytes, "seq \(exchange.seq): CDB")
            #expect(command.direction == exchange.commandDirection, "seq \(exchange.seq): direction")
            #expect(command.transferLength == exchange.length, "seq \(exchange.seq): transfer length")
            #expect(command.dataOut == (exchange.dataOutBytes ?? []), "seq \(exchange.seq): data_out")
        }
    }

    /// We poll 0xDF after exactly the commands after which FlexColor polled it
    /// (the number of polls may differ). Not waiting would mean sending the next
    /// command while the scanner is still moving.
    @Test(arguments: Capture.allCases)
    func waitsOnScannerStateWhereFlexColorDid(_ capture: Capture) async throws {
        let simulator = try capture.simulator()
        _ = try await capture.run(on: simulator)

        func waitsAfterEachCommand(_ opcodes: [UInt8]) -> [Bool] {
            var waits: [Bool] = []
            for opcode in opcodes {
                if opcode == 0xDF {
                    if !waits.isEmpty { waits[waits.count - 1] = true }
                } else if !SimulatedX1.pollingOpcodes.contains(opcode) {
                    waits.append(false)
                }
            }
            return waits
        }
        let ours = waitsAfterEachCommand(await simulator.log.map(\.opcode))
        let flexColor = waitsAfterEachCommand(try capture.exchanges().map { $0.cdbBytes[0] })
        let captured = try capture.nonPollingExchanges()
        #expect(ours.count == flexColor.count)
        for (index, (mine, theirs)) in zip(ours, flexColor).enumerated() {
            #expect(mine == theirs, "after seq \(captured[index].seq) (\(captured[index].cdb))")
        }
    }

    /// Every wait ends on the state FlexColor last saw there.
    @Test(arguments: Capture.allCases)
    func waitsEndOnTheStateFlexColorLastSaw(_ capture: Capture) throws {
        var lastState: [Int: String] = [:]
        var index = -1
        for exchange in try capture.exchanges() {
            let opcode = exchange.cdbBytes.first ?? 0
            if opcode == 0xDF, index >= 0 { lastState[index] = exchange.response }
            else if !SimulatedX1.pollingOpcodes.contains(opcode) { index += 1 }
        }
        for (index, step) in capture.script.enumerated() {
            #expect(step.waitUntil?.description == lastState[index], "step \(index)")
        }
    }

    @Test(arguments: Capture.allCases)
    func onlyPollingCommandSentIsTheStateRead(_ capture: Capture) async throws {
        let simulator = try capture.simulator()
        _ = try await capture.run(on: simulator)
        let polls = await simulator.log.filter { SimulatedX1.pollingOpcodes.contains($0.opcode) }
        #expect(!polls.isEmpty)
        #expect(polls.allSatisfy { $0 == X1Command.scannerState() })
    }

    @Test(arguments: Capture.allCases)
    func captureContainsTheExpectedReads(_ capture: Capture) async throws {
        let result = try await capture.run(on: try capture.simulator())
        #expect(result.calibrationLines.count == 3)
        #expect(result.whiteReference.count == 5)
        #expect(result.darkReference.count == 18)
        #expect(result.leadIn.count == 3)
        #expect(result.image.count == 41)
        #expect(result.image.reduce(0) { $0 + $1.count } == 819 * 2004 * 6)
    }
}

/// The cold sequence (2026-11-16): power-on check and busy states.
struct ColdSequenceTests {
    private static let script = PreviewScript.flexColor4813Cold
    private static let checkIndex = script.firstIndex { $0.kind == .sequenceChoice }!

    /// One power-on check, the first page 0x20 read, with nothing that moves
    /// the scanner before it: only reads, the startup D2 and the session start,
    /// as in both captures.
    @Test func thePowerOnCheckComesBeforeAnythingThatMoves() {
        #expect(Self.script.filter { $0.kind == .sequenceChoice }.count == 1)
        let firstStatusRead = Self.script.firstIndex { $0.command.cdb.prefix(3) == [0x5A, 0x00, 0x20] }
        #expect(firstStatusRead == Self.checkIndex)
        let before = Self.script[..<Self.checkIndex].map(\.command)
        let allowed: Set<[UInt8]> = [X1Command.startupD2().cdb, X1Command.session(.start).cdb]
        for command in before where command.direction != .fromDevice {
            #expect(allowed.contains(command.cdb), "\(command) before the power-on check")
        }
        #expect(!before.contains { [0x24, 0xF0, 0xE4, 0x1B, 0x28].contains($0.opcode) })
    }

    @Test(arguments: [[2048, 2048, 2047], [1928, 1843, 1882], [1936, 1846, 1891], [0, 0, 0]])
    func otherValuesStopBeforeAnythingMoves(_ values: [Int]) async throws {
        let transport = FaultInjectingTransport(inner: try Fixtures.coldSimulator(),
                                                faultAtNonPollingCommand: Self.checkIndex,
                                                fault: .setChannelValues(values))
        do {
            _ = try await PreviewRunner(transport: transport, configuration: .simulator, script: Self.script).run()
            Issue.record("the preview should have stopped")
        } catch {
            // The fixed cold script stops on warm values, and on values it does not recognise.
            let warm = ScanStatusPage.earlierUseChannelRanges.indices.allSatisfy {
                ScanStatusPage.earlierUseChannelRanges[$0].contains(values[$0])
            }
            #expect(error.anomaly == (warm ? .notJustSwitchedOn(channelValues: values)
                                           : .unrecognisedStartState(channelValues: values)))
            #expect(error.stepIndex == Self.checkIndex)
            #expect(error.emergencyStop == nil)
            #expect(await transport.commandsAfterFault.isEmpty, "nothing sent after the check")
        }
    }

    @Test func powerOnValuesAreAccepted() async throws {
        let result = try await Capture.cold.run(on: try Fixtures.coldSimulator())
        #expect(result.scanStatuses.first?.showsPowerOnValues == true)
        #expect(result.scanStatuses.first?.measuredPosition == 8203)
    }

    /// The cold capture's waits went through 08 07, 08 06, 08 02, 08 03.
    @Test func coldCaptureStatesAreTheObservedOnes() throws {
        let states = Set(try Fixtures.coldSequence().exchanges
            .filter { $0.cdbBytes.first == 0xDF }
            .compactMap { $0.response })
        #expect(states == ["00 00", "00 01", "08 01", "08 02", "08 03", "08 06", "08 07", "08 40"])
    }

    @Test(arguments: [0x0801, 0x0802, 0x0803, 0x0806, 0x0807, 0x0840])
    func observedBusyStates(_ raw: Int) {
        #expect(ScannerState(rawValue: UInt16(raw)).isBusy)
    }

    @Test(arguments: [0x0800, 0x0804, 0x0805, 0x0808, 0x0841, 0x0001, 0x0002, 0x0C01, 0xFFFF])
    func otherStatesAreNotBusy(_ raw: Int) {
        #expect(!ScannerState(rawValue: UInt16(raw)).isBusy)
    }

    /// A state never observed during a wait still stops the preview.
    @Test func anUnknownStateStillStops() async throws {
        let index = try #require(Self.script.firstIndex { $0.command.opcode == 0xF0 })
        let transport = FaultInjectingTransport(inner: try Fixtures.coldSimulator(),
                                                faultAtNonPollingCommand: index,
                                                fault: .stateAfter(ScannerState(rawValue: 0x0805)))
        do {
            _ = try await PreviewRunner(transport: transport, configuration: .simulator, script: Self.script).run()
            Issue.record("the preview should have stopped")
        } catch {
            #expect(error.anomaly == .unexpectedState(ScannerState(rawValue: 0x0805), waitingFor: .ready))
            #expect(error.emergencyStop == nil)
        }
    }

    /// The incomplete responses of the capture (INQUIRY 96 bytes, page 0x21
    /// 100 bytes: cap3.py prints 64) were completed from the warm fixture.
    @Test func longResponsesWereCompletedFromTheWarmFixture() throws {
        let warm = try Fixtures.sequence().exchanges
        for exchange in try Fixtures.coldSequence().exchanges
            where exchange.direction == "in" && exchange.length > 64 && exchange.cdbBytes[0] != 0x28 {
            let response = try #require(exchange.responseBytes, "seq \(exchange.seq)")
            #expect(response.count == exchange.length)
            #expect(warm.contains { $0.cdb == exchange.cdb && $0.responseBytes == response })
        }
    }
}

struct PreviewStopTests {
    private static let script = PreviewScript.flexColor4813
    private static let scanIndex = script.firstIndex { $0.kind == .scan }!

    private func run(faultAt index: Int, _ fault: FaultInjectingTransport.Fault)
        async throws -> (FaultInjectingTransport, Result<PreviewCapture, PreviewError>) {
        let transport = FaultInjectingTransport(inner: try Fixtures.simulator(),
                                                faultAtNonPollingCommand: index, fault: fault)
        let runner = PreviewRunner(transport: transport, configuration: .simulator)
        do {
            return (transport, .success(try await runner.run()))
        } catch {
            return (transport, .failure(error))
        }
    }

    @Test func anomalyAfterScanSendsOnlyStopThenWaitsForReady() async throws {
        let index = Self.scanIndex + 10  // an image read
        let (transport, result) = try await run(faultAt: index, .checkCondition)
        guard case .failure(let error) = result else {
            Issue.record("the preview should have stopped")
            return
        }
        #expect(error.stepIndex == index)
        #expect(error.anomaly == .badStatus(status: 0x02, senseKey: 0x04))
        #expect(error.emergencyStop == .stoppedAndReady)
        // DB, then 0xDF until 00 00 (08 01, 00 00), and nothing else.
        #expect(await transport.commandsAfterFault == [X1Command.stop(), X1Command.scannerState(), X1Command.scannerState()])
    }

    @Test func anomalyOnScanItselfAlsoStops() async throws {
        let (transport, result) = try await run(faultAt: Self.scanIndex, .checkCondition)
        guard case .failure(let error) = result else {
            Issue.record("the preview should have stopped")
            return
        }
        #expect(error.emergencyStop == .stoppedAndReady)
        #expect(await transport.commandsAfterFault.first == X1Command.stop())
    }

    @Test func anomalyBeforeScanSendsNothingMore() async throws {
        let index = Self.scanIndex - 3
        let (transport, result) = try await run(faultAt: index, .checkCondition)
        guard case .failure(let error) = result else {
            Issue.record("the preview should have stopped")
            return
        }
        #expect(error.stepIndex == index)
        #expect(error.emergencyStop == nil)
        #expect(await transport.commandsAfterFault.isEmpty)
    }

    private static let positioningIndex = script.firstIndex { $0.kind == .scanStatus(capturedPosition: 8971) }!

    @Test func positionBeyondToleranceStops() async throws {
        let (transport, result) = try await run(faultAt: Self.positioningIndex, .shiftMeasuredPosition(by: 257))
        guard case .failure(let error) = result else {
            Issue.record("the preview should have stopped")
            return
        }
        #expect(error.anomaly == .positionOutOfTolerance(expected: 8971, measured: 9228, tolerance: 256))
        #expect(error.emergencyStop == nil)
        #expect(await transport.commandsAfterFault.isEmpty)
    }

    /// Page 0x20 reads, as non-poll command indices, with whether a window
    /// requesting a position was sent before them.
    private static let statusReads: [(index: Int, checked: Bool)] = {
        var requested = false
        var reads: [(Int, Bool)] = []
        for (index, step) in script.enumerated() {
            if case .scanStatus = step.kind { reads.append((index, requested)) }
            if PreviewRunner.requestsPosition(step.command) { requested = true }
        }
        return reads
    }()

    /// Test of 2026-11-16 on the real X1: after power-on, the first page 0x20
    /// read gave 8203 where the capture (made after earlier previews) had 6155.
    @Test func readsBeforeAPositionRequestAreNotChecked() async throws {
        let unchecked = Self.statusReads.filter { !$0.checked }.map(\.index)
        #expect(unchecked.count == 1, "after session start (the read after the first calibration windows is a gate)")
        for index in unchecked {
            let (_, result) = try await run(faultAt: index, .shiftMeasuredPosition(by: 2048))
            if case .failure(let error) = result { Issue.record("unexpected stop at \(index): \(error)") }
        }
        let firstChecked = try #require(Self.statusReads.first { $0.checked }).index
        let (_, result) = try await run(faultAt: firstChecked, .shiftMeasuredPosition(by: 257))
        guard case .failure(let error) = result, case .positionOutOfTolerance = error.anomaly else {
            Issue.record("the first read after a position request must be checked")
            return
        }
    }

    @Test func onlyWindowsWithATargetRequestAPosition() {
        let windows = Self.script.map(\.command).filter { $0.opcode == 0x24 }
        let requesting = windows.filter(PreviewRunner.requestsPosition)
        // Targets 25 000, 9 000, 8 971, 6 250 twice.
        #expect(requesting.count == 5)
        #expect(Set(requesting.map { Int($0.dataOut[50]) | Int($0.dataOut[51]) << 8 }) == [25_000, 9_000, 8_971, 6_250])
    }

    /// An unchecked read is still parsed and recorded.
    @Test func uncheckedReadsAreStillRecorded() async throws {
        let index = try #require(Self.statusReads.first { !$0.checked }).index
        let (_, result) = try await run(faultAt: index, .shiftMeasuredPosition(by: 2048))
        let capture = try result.get()
        #expect(capture.scanStatuses.first?.measuredPosition == 6_155 + 2_048)
    }

    @Test func positionWithinToleranceIsAccepted() async throws {
        // Two captures differed by 64 on the first measurement.
        let (_, result) = try await run(faultAt: Self.positioningIndex, .shiftMeasuredPosition(by: 64))
        if case .failure(let error) = result { Issue.record("unexpected stop: \(error)") }
    }
}

struct PreviewEventTests {

    /// Events do not change what is sent: the conformance test runs without
    /// them, this one checks the same command log with them.
    @Test func eventsDoNotChangeTheCommandsSent() async throws {
        let plain = try Fixtures.simulator()
        _ = try await PreviewRunner(transport: plain, configuration: .simulator).run()
        let observed = try Fixtures.simulator()
        let recorder = Recorder()
        _ = try await PreviewRunner(transport: observed, configuration: .simulator).run { recorder.record($0) }
        #expect(await plain.log == observed.log)
    }

    @Test func eventsFollowTheScriptAndItsPhases() async throws {
        let recorder = Recorder()
        let capture = try await PreviewRunner(transport: try Fixtures.simulator(), configuration: .simulator)
            .run { recorder.record($0) }
        let script = PreviewScript.flexColor4813
        var steps: [Int] = []
        var phases: [PreviewPhase] = []
        var imageBlocks: [[UInt8]] = []
        var statuses = 0
        for event in recorder.events {
            switch event {
            case .step(let index, let count, let phase):
                #expect(count == script.count)
                steps.append(index)
                if phases.last != phase { phases.append(phase) }
            case .data(let bytes, .image): imageBlocks.append(bytes)
            case .data: break
            case .scanStatus: statuses += 1
            case .stopping: Issue.record("no stop expected")
            case .sequenceChosen: Issue.record("a fixed script chooses nothing")
            case .positionDifference: break
            }
        }
        #expect(steps == Array(script.indices))
        #expect(phases == [.initialisation, .calibration, .references, .scanning, .finishing], "no focus step in a preview")
        #expect(imageBlocks == capture.image)
        #expect(statuses == capture.scanStatuses.count)
    }

    @Test func phasesStartWhereTheProtocolSays() {
        let script = PreviewScript.flexColor4813
        let phases = PreviewPhase.phases(for: script)
        let firstOf = { (phase: PreviewPhase) in phases.firstIndex(of: phase)! }
        #expect(script[firstOf(.calibration)].command == X1Command.session(.start))
        #expect(script[firstOf(.references)].kind == .read(.whiteReference))
        #expect(script[firstOf(.scanning)].kind == .scan)
        #expect(script[firstOf(.finishing)].command == X1Command.stop())
    }

    /// Cancelling after SCAN reports `.stopping`, sends only DB and waits for 00 00.
    @Test func cancellingAfterScanRunsTheStopSequence() async throws {
        let simulatorTransport = try Fixtures.simulator()
        let transport = CancellingTransport(inner: simulatorTransport, cancelAfterImageReads: 5)
        let recorder = Recorder()
        let task = Task {
            try await PreviewRunner(transport: transport, configuration: .simulator).run { recorder.record($0) }
        }
        await transport.setTask(task)
        let result = await task.result
        guard case .failure(let error as PreviewError) = result else {
            Issue.record("the preview should have stopped")
            return
        }
        #expect(error.anomaly == .cancelled)
        #expect(error.emergencyStop == .stoppedAndReady)
        #expect(recorder.events.contains { if case .stopping = $0 { true } else { false } })
        let after = await transport.commandsAfterCancel
        #expect(after.first == X1Command.stop())
        #expect(after.dropFirst().allSatisfy { $0 == X1Command.scannerState() })
    }

    @Test func cancellingBeforeScanSendsNothingMore() async throws {
        let transport = CancellingTransport(inner: try Fixtures.simulator(), cancelAfterNonPolling: 30)
        let task = Task { try await PreviewRunner(transport: transport, configuration: .simulator).run() }
        await transport.setTask(task)
        guard case .failure(let error as PreviewError) = await task.result else {
            Issue.record("the preview should have stopped")
            return
        }
        #expect(error.anomaly == .cancelled)
        #expect(error.emergencyStop == nil)
        #expect(await transport.commandsAfterCancel.isEmpty)
    }
}

/// Cancels the running preview task from inside the transport, at a chosen
/// point, and records what is sent afterwards.
private actor CancellingTransport: SCSITransport {
    private let inner: any SCSITransport
    private let imageReadsBeforeCancel: Int?
    private let nonPollingBeforeCancel: Int?
    private var task: Task<PreviewCapture, any Error>?
    private var imageReads = 0
    private var nonPolling = 0
    private var cancelled = false
    private(set) var commandsAfterCancel: [SCSICommand] = []

    init(inner: any SCSITransport, cancelAfterImageReads count: Int) {
        self.inner = inner
        imageReadsBeforeCancel = count
        nonPollingBeforeCancel = nil
    }

    init(inner: any SCSITransport, cancelAfterNonPolling count: Int) {
        self.inner = inner
        imageReadsBeforeCancel = nil
        nonPollingBeforeCancel = count
    }

    func setTask(_ task: Task<PreviewCapture, any Error>) { self.task = task }

    func execute(_ command: SCSICommand) async throws -> SCSIResult {
        if cancelled { commandsAfterCancel.append(command) }
        let result = try await inner.execute(command)
        guard !cancelled else { return result }
        if command.opcode == 0x28 && command.cdb[5] == 0x00 { imageReads += 1 }
        if !SimulatedX1.pollingOpcodes.contains(command.opcode) { nonPolling += 1 }
        if imageReads == imageReadsBeforeCancel || nonPolling == nonPollingBeforeCancel {
            // Wait until the test has handed over the task, then cancel it.
            while task == nil { await Task.yield() }
            cancelled = true
            task?.cancel()
        }
        return result
    }
}

/// Cancels the task when 0xDF first reports a busy state, so that the
/// cancellation lands in the runner's wait (Task.sleep), as with a real scanner.
private actor CancelOnBusyTransport: SCSITransport {
    private let inner: any SCSITransport
    private var task: Task<PreviewCapture, any Error>?
    private var cancelled = false
    private(set) var commandsAfterCancel: [SCSICommand] = []

    init(inner: any SCSITransport) { self.inner = inner }

    func setTask(_ task: Task<PreviewCapture, any Error>) { self.task = task }

    func execute(_ command: SCSICommand) async throws -> SCSIResult {
        if cancelled { commandsAfterCancel.append(command) }
        let result = try await inner.execute(command)
        if !cancelled, command.opcode == 0xDF, result.data == [0x08, 0x01] || result.data == [0x08, 0x40] {
            while task == nil { await Task.yield() }
            cancelled = true
            task?.cancel()
        }
        return result
    }
}

struct PreviewCancelDuringWaitTests {
    /// With a non-zero poll interval (the real scanner's configuration), a
    /// cancellation during a 0xDF wait is reported as `.cancelled`, not as a
    /// transport error.
    @Test func cancellingDuringAStateWaitIsACancellation() async throws {
        let transport = CancelOnBusyTransport(inner: try Fixtures.simulator())
        let configuration = PreviewConfiguration(pollInterval: .milliseconds(20), stateTimeout: .seconds(5))
        let task = Task { try await PreviewRunner(transport: transport, configuration: configuration).run() }
        await transport.setTask(task)
        guard case .failure(let error as PreviewError) = await task.result else {
            Issue.record("the preview should have stopped")
            return
        }
        #expect(error.anomaly == .cancelled)
        #expect(error.emergencyStop == nil, "first busy state is before SCAN")
        #expect(await transport.commandsAfterCancel.isEmpty)
    }
}

/// The plan used on the real X1: the first page 0x20 read chooses the cold
/// or the warm sequence (docs/decisions.md, "Real X1: cold or warm sequence").
struct SequenceChoiceTests {
    private static let plan = PreviewScript.plan
    private static let choiceIndex = plan.common.count - 1

    @Test func bothSequencesShareTheCommonPartAndMatchTheCaptures() throws {
        #expect(Self.plan.steps(for: .cold).map(\.command) == PreviewScript.flexColor4813Cold.map(\.command))
        #expect(Self.plan.steps(for: .warm).map(\.command) == PreviewScript.flexColor4813.map(\.command))
        // Nothing that moves the scanner before the choice.
        let allowed: Set<[UInt8]> = [X1Command.startupD2().cdb, X1Command.session(.start).cdb]
        for step in Self.plan.common where step.command.direction != .fromDevice {
            #expect(allowed.contains(step.command.cdb), "\(step.command) before the choice")
        }
        // Waits as in each capture.
        #expect(Self.plan.steps(for: .warm)[Self.choiceIndex].waitUntil == .ready)
        #expect(Self.plan.steps(for: .cold)[Self.choiceIndex].waitUntil == nil)
    }

    @Test(arguments: [false, true])
    func theCaptureDecidesThroughTheGuard(cold: Bool) async throws {
        let sequence = try Fixtures.previewGuard()
        let simulator = cold ? try Fixtures.coldSimulator() : try Fixtures.simulator()
        let recorder = Recorder()
        let capture = try await PreviewRunner(transport: GuardedTransport(inner: simulator, sequence: sequence),
                                              configuration: .simulator, plan: Self.plan)
            .run { recorder.record($0) }
        let expected: PreviewPlan.Choice = cold ? .cold : .warm
        #expect(capture.choice == expected)
        #expect(capture.image.count == 41)
        #expect(sequence.isComplete)
        let chosen = recorder.events.compactMap { event -> PreviewPlan.Choice? in
            if case .sequenceChosen(let choice) = event { choice } else { nil }
        }
        #expect(chosen == [expected])
    }

    @Test(arguments: [[2048, 2048, 2047], [1700, 1845, 1883], [0, 0, 0]])
    func unrecognisedValuesStopBeforeAnythingMoves(_ values: [Int]) async throws {
        let transport = FaultInjectingTransport(inner: try Fixtures.simulator(),
                                                faultAtNonPollingCommand: Self.choiceIndex,
                                                fault: .setChannelValues(values))
        do {
            _ = try await PreviewRunner(transport: transport, configuration: .simulator, plan: Self.plan).run()
            Issue.record("the preview should have stopped")
        } catch {
            #expect(error.anomaly == .unrecognisedStartState(channelValues: values))
            #expect(error.stepIndex == Self.choiceIndex)
            #expect(error.emergencyStop == nil)
            #expect(await transport.commandsAfterFault.isEmpty, "nothing sent after the choice")
        }
    }

    /// Every page 0x20 read whose position differs from the capture is
    /// reported, checked or not, with both values.
    @Test func positionDifferencesAreReported() async throws {
        let script = Self.plan.steps(for: .warm)
        let firstStatus = try #require(script.firstIndex { if case .scanStatus = $0.kind { true } else { false } })
        let transport = FaultInjectingTransport(inner: try Fixtures.simulator(), faultAtNonPollingCommand: firstStatus,
                                                fault: .shiftMeasuredPosition(by: 128))
        let recorder = Recorder()
        _ = try await PreviewRunner(transport: transport, configuration: .simulator, plan: Self.plan)
            .run { recorder.record($0) }
        let differences = recorder.events.compactMap { event -> (Int, Int, Bool)? in
            if case .positionDifference(let expected, let measured, let checked) = event { (expected, measured, checked) } else { nil }
        }
        #expect(differences.count == 1)
        #expect(differences.first.map { $0.1 - $0.0 } == 128)
        #expect(differences.first?.2 == true, "after the window with target 25 000: checked")
    }
}

/// Collects runner events (they arrive on the runner's task).
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [PreviewEvent] = []
    func record(_ event: PreviewEvent) { lock.withLock { stored.append(event) } }
    var events: [PreviewEvent] { lock.withLock { stored } }
}

/// Option A (docs/decisions.md): the read before the warm sequence's window
/// with target 25 000 is always checked.
struct PositionGateTests {
    private static let plan = PreviewScript.plan
    private static let warm = plan.steps(for: .warm)
    private static let gate = warm.firstIndex { $0.kind == .positionGate(capturedPosition: 25867) }!

    @Test func theGateComesRightBeforeTheWindowWithTarget25000() {
        #expect(Self.warm.filter { if case .positionGate = $0.kind { true } else { false } }.count == 1)
        #expect(Self.warm[Self.gate + 1].command.dataOut[50...51] == [0xA8, 0x61])  // 25 000
        #expect(!Self.warm[..<Self.gate].contains { PreviewRunner.requestsPosition($0.command) },
                "no window had requested a position before it")
    }

    /// 24 523 (the 2 000 ppi run of 2026-11-17): stop, nothing more sent.
    @Test func farFromTheCaptureStopsBeforeTheWindow() async throws {
        let transport = FaultInjectingTransport(inner: try Fixtures.simulator(), faultAtNonPollingCommand: Self.gate,
                                                fault: .shiftMeasuredPosition(by: 24523 - 25867))
        do {
            _ = try await PreviewRunner(transport: transport, configuration: .simulator, plan: Self.plan).run()
            Issue.record("the preview should have stopped")
        } catch {
            #expect(error.anomaly == .unexpectedCarriagePosition(captured: 25867, measured: 24523, tolerance: 256))
            #expect(error.stepIndex == Self.gate)
            #expect(error.emergencyStop == nil)
            #expect(await transport.commandsAfterFault.isEmpty, "the window with target 25 000 is not sent")
        }
    }

    /// The differences seen in the captures that went on (64, 128) pass; 256 too.
    @Test(arguments: [-128, -64, 256]) func withinTheTolerancePasses(shift: Int) async throws {
        let transport = FaultInjectingTransport(inner: try Fixtures.simulator(), faultAtNonPollingCommand: Self.gate,
                                                fault: .shiftMeasuredPosition(by: shift))
        let capture = try await PreviewRunner(transport: transport, configuration: .simulator, plan: Self.plan).run()
        #expect(capture.image.count == 41)
    }
}
