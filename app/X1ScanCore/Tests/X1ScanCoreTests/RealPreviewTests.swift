// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import X1ScanCore
import X1Transport

/// Plays the real X1 for the tests: the guard of `IOKitTransport(capturedSequence:)`
/// in front of the simulator, with open and close recorded.
actor GuardedSimulatedConnection: ScannerConnection {
    let sequence: CapturedSequenceGuard
    private let simulator: SimulatedX1
    private let openError: (any Error)?
    /// If set, bytes 19-24 of the first page 0x20 read (an X1 not just switched on).
    private let channelValues: [Int]?
    /// If set, added to the measured position of the page 0x20 read with this
    /// number (1 = the first read).
    private let positionShift: (read: Int, by: Int)?
    private var statusReads = 0
    private(set) var opened = false
    private(set) var closed = false
    private(set) var sent: [SCSICommand] = []

    init(sequence: CapturedSequenceGuard, scanner: VirtualScanner, openError: (any Error)? = nil,
         channelValues: [Int]? = nil, warm: Bool = false, positionShift: (read: Int, by: Int)? = nil) {
        self.channelValues = channelValues
        self.positionShift = positionShift
        self.sequence = sequence
        // An X1 just switched on replays the cold capture (without its page 0x28
        // read, which is no longer sent); one used before, the warm capture.
        simulator = warm ? SimulatedX1(fixture: scanner.fixture, profile: scanner.profile)
            : SimulatedX1(fixture: scanner.coldFixture, profile: scanner.profile, skipping: [SimulatedX1.page28Read])
        self.openError = openError
    }

    func open() throws {
        if let openError { throw openError }
        opened = true
    }

    func close() { closed = true }

    func execute(_ command: SCSICommand) async throws -> SCSIResult {
        guard opened, !closed else { throw TransportError.notOpen }
        try sequence.check(command)  // as IOKitTransport does, before the device
        sent.append(command)
        let result = try await simulator.execute(command)
        guard command.cdb.prefix(3) == [0x5A, 0x00, 0x20] else { return result }
        statusReads += 1
        if let positionShift, statusReads == positionShift.read {
            var data = result.data
            let position = Int(data[27]) | Int(data[28]) << 8 + positionShift.by
            data[27] = UInt8(position & 0xFF)
            data[28] = UInt8(position >> 8)
            return SCSIResult(status: result.status, data: data)
        }
        guard statusReads == 1, let channelValues else { return result }
        var data = result.data
        for (channel, value) in channelValues.enumerated() {
            data[19 + 2 * channel] = UInt8(value & 0xFF)
            data[20 + 2 * channel] = UInt8(value >> 8)
        }
        return SCSIResult(status: result.status, data: data)
    }
}

@MainActor
final class RealPreviewTests {
    private var suites: [String] = []
    private let folder = FileManager.default.temporaryDirectory.appending(path: "X1ScanCoreTests-\(UUID().uuidString)")
    private var connections: [GuardedSimulatedConnection] = []

    deinit {
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        try? FileManager.default.removeItem(at: folder)
    }

    private func model(enabled: Bool, openError: (any Error)? = nil, channelValues: [Int]? = nil,
                       warm: Bool = false, positionShift: (read: Int, by: Int)? = nil,
                       interruptedBefore: Bool = false) throws -> AppModel {
        let suite = "X1ScanCoreTests-\(UUID().uuidString)"
        suites.append(suite)
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(interruptedBefore, forKey: "RealPreviewInterrupted")
        defaults.set(enabled, forKey: "EnableRealPreview")
        let scanner = try TestFixtures.scanner()
        let box = ConnectionBox()
        let model = AppModel(virtualScanner: { scanner }, inspector: ScannerInspector {
            FakeConnection(responses: [:], openError: TransportError.deviceBusy)
        }, defaults: defaults, realConnection: { sequence in
            let connection = GuardedSimulatedConnection(sequence: sequence, scanner: scanner, openError: openError,
                                                        channelValues: channelValues, warm: warm,
                                                        positionShift: positionShift)
            box.set(connection)
            return connection
        }, captureFolder: folder)
        self.box = box
        return model
    }

    private var box: ConnectionBox?
    private let all = RealPreviewConfirmation(scannerOn: true, holderInPlace: true, flexColorClosed: true,
                                              powerCycledSinceLastRealPreview: true)

    @Test func offByDefault() throws {
        let model = try model(enabled: false)
        model.source = .real
        #expect(!model.realPreviewEnabled)
        #expect(model.toolbar.previewBlock == .realScannerReadOnly && !model.toolbar.previewNeedsConfirmation)
        #expect(model.startRealPreview(all) == .failure(.notAllowed))
        model.startPreview()
        #expect(model.session.state == .idle, "startPreview never reaches the real X1")
        #expect(box?.connection == nil, "no connection made")
    }

    @Test func needsTheRealSourceAndEveryCheck() throws {
        let model = try model(enabled: true)
        #expect(model.startRealPreview(all) == .failure(.notAllowed), "virtual source")
        model.source = .real
        #expect(model.toolbar.previewBlock == nil && model.toolbar.previewNeedsConfirmation)
        for missing in [RealPreviewConfirmation(scannerOn: false, holderInPlace: true, flexColorClosed: true,
                                                powerCycledSinceLastRealPreview: true),
                        RealPreviewConfirmation(scannerOn: true, holderInPlace: false, flexColorClosed: true,
                                                powerCycledSinceLastRealPreview: true),
                        RealPreviewConfirmation(scannerOn: true, holderInPlace: true, flexColorClosed: false,
                                                powerCycledSinceLastRealPreview: true)] {
            #expect(model.startRealPreview(missing) == .failure(.notAllowed))
        }
        model.startPreview()
        #expect(model.session.state == .idle && box?.connection == nil)
    }

    @Test(arguments: [false, true])
    func runsTheCapturedSequenceChosenByTheScannerAndLogsIt(warm: Bool) async throws {
        let model = try model(enabled: true, warm: warm)
        model.source = .real
        let log = try model.startRealPreview(all).get()
        #expect(model.lastPreviewLog == log)
        await model.readRealScanner()
        #expect(model.realStatus == .notRead, "no identity read while the preview runs")
        await model.session.waitUntilIdle()
        #expect(model.session.state == .finished)
        let connection = try #require(box?.connection)
        let opened = await connection.opened, closed = await connection.closed
        #expect(opened && closed, "opened, then always closed")
        #expect(connection.sequence.isComplete)
        #expect(connection.sequence.expected == PreviewSession.realScannerPlan.steps(for: warm ? .warm : .cold).map(\.command))
        let text = try String(contentsOf: log, encoding: .utf8)
        #expect(text.contains("# sequence chosen by the first page 0x20 read: \(warm ? "warm" : "cold")"))
        #expect(!model.realPreviewNeedsPowerCycle, "a complete run asks for no power cycle")
        #expect(text.hasPrefix("# X1 Scan: FlexColor 4.8.13's captured preview replayed on the real X1"))
        #expect(text.contains("0001 CDB 12 00 00 00 60 00"))
        #expect(text.hasSuffix("# preview complete\n"))
        #expect(FileManager.default.fileExists(atPath: log.deletingPathExtension().appendingPathExtension("raw").path))
        #expect(log.path.hasPrefix(folder.path), "outside the repository, in the capture folder")
    }

    /// Neither the power-on values nor values left by earlier use: the
    /// preview stops at the first page 0x20 read, before anything moves, and
    /// the next one asks for the X1 to be switched off and on.
    @Test func stopsOnAnUnrecognisedStartState() async throws {
        let model = try model(enabled: true, channelValues: [2048, 2048, 2047])
        model.source = .real
        let log = try model.startRealPreview(all).get()
        await model.session.waitUntilIdle()
        guard case .failed(let failure) = model.session.state else {
            Issue.record("expected a failure, got \(model.session.state)")
            return
        }
        #expect(failure.emergencyStop == nil)
        if case .anomaly(.unrecognisedStartState([2048, 2048, 2047])) = failure.cause {} else {
            Issue.record("unrecognisedStartState expected, got \(failure.cause)")
        }
        let connection = try #require(box?.connection)
        let sent = await connection.sent
        #expect(sent.last?.cdb.prefix(3) == [0x5A, 0x00, 0x20], "nothing after the check")
        #expect(!sent.contains { [0x24, 0xF0, 0xE4, 0x1B, 0x28].contains($0.opcode) }, "nothing that moves")
        #expect(await connection.closed)
        #expect(try String(contentsOf: log, encoding: .utf8).contains("neither the power-on values"))
        #expect(model.realPreviewNeedsPowerCycle)
        let withoutPowerCycle = RealPreviewConfirmation(scannerOn: true, holderInPlace: true, flexColorClosed: true)
        #expect(model.startRealPreview(withoutPowerCycle) == .failure(.notAllowed), "the fourth box is now asked")
        _ = try model.startRealPreview(all).get()
        await model.session.waitUntilIdle()
    }

    /// Option A: the warm sequence's second page 0x20 read at 24 523 (as in
    /// the 2 000 ppi run) stops before the window with target 25 000; like any
    /// other stop, the next preview asks for the power cycle.
    @Test(arguments: [false, true])
    func unexpectedCarriagePositionAsksForThePowerCycle(interruptedBefore: Bool) async throws {
        let model = try model(enabled: true, warm: true, positionShift: (read: 2, by: 24523 - 25867),
                              interruptedBefore: interruptedBefore)
        model.source = .real
        _ = try model.startRealPreview(all).get()
        await model.session.waitUntilIdle()
        guard case .failed(let failure) = model.session.state,
              case .anomaly(.unexpectedCarriagePosition(25867, 24523, 256)) = failure.cause else {
            Issue.record("unexpectedCarriagePosition expected, got \(model.session.state)")
            return
        }
        let sent = await try #require(box?.connection).sent
        #expect(!sent.contains { $0.opcode == 0x24 && $0.dataOut[50...51] == [0xA8, 0x61] }, "no window with target 25 000")
        #expect(model.realPreviewNeedsPowerCycle)
        let text = try String(contentsOf: try #require(model.lastPreviewLog), encoding: .utf8)
        #expect(text.contains("# position: captured 25867, measured 24523, difference -1344"))
    }

    /// The scanner could not be opened: nothing sent, the flag stays as it was.
    @Test func couldNotOpenKeepsAnEarlierInterruption() async throws {
        let model = try model(enabled: true, openError: TransportError.deviceBusy, interruptedBefore: true)
        model.source = .real
        _ = try model.startRealPreview(all).get()
        await model.session.waitUntilIdle()
        #expect(model.realPreviewNeedsPowerCycle)
    }

    /// Stop during a real preview: the next one asks for the power cycle.
    @Test func stopLeavesTheFlagSet() async throws {
        let model = try model(enabled: true)
        model.source = .real
        let three = RealPreviewConfirmation(scannerOn: true, holderInPlace: true, flexColorClosed: true)
        _ = try model.startRealPreview(three).get()
        model.stop()
        await model.session.waitUntilIdle()
        if case .stopped = model.session.state {} else { Issue.record("stopped expected, got \(model.session.state)") }
        #expect(model.realPreviewNeedsPowerCycle)
    }

    /// Before any interrupted run, the first three boxes are enough.
    @Test func noPowerCycleAskedBeforeAnInterruptedRun() async throws {
        let model = try model(enabled: true)
        model.source = .real
        #expect(!model.realPreviewNeedsPowerCycle)
        let three = RealPreviewConfirmation(scannerOn: true, holderInPlace: true, flexColorClosed: true)
        _ = try model.startRealPreview(three).get()
        await model.session.waitUntilIdle()
        #expect(model.session.state == .finished)
    }

    @Test func openFailureSendsNothing() async throws {
        let model = try model(enabled: true, openError: TransportError.deviceBusy)
        model.source = .real
        let log = try model.startRealPreview(all).get()
        await model.session.waitUntilIdle()
        guard case .failed(let failure) = model.session.state else {
            Issue.record("expected a failure, got \(model.session.state)")
            return
        }
        #expect(failure.emergencyStop == nil)
        if case .anomaly(.couldNotOpen) = failure.cause {} else { Issue.record("couldNotOpen expected, got \(failure.cause)") }
        let connection = try #require(box?.connection)
        #expect(await connection.sent.isEmpty)
        #expect(try String(contentsOf: log, encoding: .utf8).contains("# could not open the scanner"))
    }

    @Test func switchingSourceStopsAPreview() async throws {
        let model = try model(enabled: true)
        model.source = .real
        _ = try model.startRealPreview(all).get()
        model.source = .virtual
        await model.session.waitUntilIdle()
        #expect(model.session.state == .stopped(nil) || model.session.state == .stopped(.stoppedAndReady),
                "stopped by the change of source, with the stop rules")
        #expect(model.lastPreviewWasReal, "still known as a real preview, for the alert")
        model.startPreview()
        #expect(!model.lastPreviewWasReal, "a virtual preview resets it")
    }
}

/// Keeps the connection the model made, for the assertions.
final class ConnectionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: GuardedSimulatedConnection?
    func set(_ connection: GuardedSimulatedConnection) { lock.withLock { stored = connection } }
    var connection: GuardedSimulatedConnection? { lock.withLock { stored } }
}
