// SPDX-License-Identifier: MIT
import Foundation
import Testing
import X1Preview
import X1Protocol
import X1TestSupport
import X1Transport

struct PreviewConformanceTests {
    /// Our sequence, played against the simulator, sends the same commands as
    /// FlexColor in the same order: CDB, direction, transfer length and data_out,
    /// apart from the polling commands (0xEE, 0xD3, 0xDF).
    @Test func previewMatchesTheCaptureCommandForCommand() async throws {
        let simulator = try Fixtures.simulator()
        _ = try await PreviewRunner(transport: simulator, configuration: .simulator).run()

        let sent = await simulator.log.filter { !SimulatedX1.pollingOpcodes.contains($0.opcode) }
        let captured = try Fixtures.nonPollingExchanges()
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
    @Test func waitsOnScannerStateWhereFlexColorDid() async throws {
        let simulator = try Fixtures.simulator()
        _ = try await PreviewRunner(transport: simulator, configuration: .simulator).run()

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
        let flexColor = waitsAfterEachCommand(try Fixtures.sequence().exchanges.map { $0.cdbBytes[0] })
        let captured = try Fixtures.nonPollingExchanges()
        #expect(ours.count == flexColor.count)
        for (index, (mine, theirs)) in zip(ours, flexColor).enumerated() {
            #expect(mine == theirs, "after seq \(captured[index].seq) (\(captured[index].cdb))")
        }
    }

    @Test func onlyPollingCommandSentIsTheStateRead() async throws {
        let simulator = try Fixtures.simulator()
        _ = try await PreviewRunner(transport: simulator, configuration: .simulator).run()
        let polls = await simulator.log.filter { SimulatedX1.pollingOpcodes.contains($0.opcode) }
        #expect(!polls.isEmpty)
        #expect(polls.allSatisfy { $0 == X1Command.scannerState() })
    }

    @Test func captureContainsTheExpectedReads() async throws {
        let simulator = try Fixtures.simulator()
        let capture = try await PreviewRunner(transport: simulator, configuration: .simulator).run()
        #expect(capture.calibrationLines.count == 3)
        #expect(capture.whiteReference.count == 5)
        #expect(capture.darkReference.count == 18)
        #expect(capture.leadIn.count == 3)
        #expect(capture.image.count == 41)
        #expect(capture.image.reduce(0) { $0 + $1.count } == 819 * 2004 * 6)
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
        let (transport, result) = try await run(faultAt: Self.positioningIndex, .shiftMeasuredPosition(by: 101))
        guard case .failure(let error) = result else {
            Issue.record("the preview should have stopped")
            return
        }
        #expect(error.anomaly == .positionOutOfTolerance(captured: 8971, measured: 9072, tolerance: 100))
        #expect(error.emergencyStop == nil)
        #expect(await transport.commandsAfterFault.isEmpty)
    }

    @Test func positionWithinToleranceIsAccepted() async throws {
        // Two captures differed by 64 on the first measurement.
        let (_, result) = try await run(faultAt: Self.positioningIndex, .shiftMeasuredPosition(by: 64))
        if case .failure(let error) = result { Issue.record("unexpected stop: \(error)") }
    }
}

struct PreviewEventTests {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [PreviewEvent] = []
        func record(_ event: PreviewEvent) { lock.withLock { stored.append(event) } }
        var events: [PreviewEvent] { lock.withLock { stored } }
    }

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
            }
        }
        #expect(steps == Array(script.indices))
        #expect(phases == PreviewPhase.allCases)
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
