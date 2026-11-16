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
    private(set) var opened = false
    private(set) var closed = false
    private(set) var sent: [SCSICommand] = []

    init(sequence: CapturedSequenceGuard, scanner: VirtualScanner, openError: (any Error)? = nil) {
        self.sequence = sequence
        simulator = scanner.makeTransport().simulator
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
        return try await simulator.execute(command)
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

    private func model(enabled: Bool, openError: (any Error)? = nil) throws -> AppModel {
        let suite = "X1ScanCoreTests-\(UUID().uuidString)"
        suites.append(suite)
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(enabled, forKey: "EnableRealPreview")
        let scanner = try TestFixtures.scanner()
        let box = ConnectionBox()
        let model = AppModel(virtualScanner: { scanner }, inspector: ScannerInspector {
            FakeConnection(responses: [:], openError: TransportError.deviceBusy)
        }, defaults: defaults, realConnection: { sequence in
            let connection = GuardedSimulatedConnection(sequence: sequence, scanner: scanner, openError: openError)
            box.set(connection)
            return connection
        }, captureFolder: folder)
        self.box = box
        return model
    }

    private var box: ConnectionBox?
    private let all = RealPreviewConfirmation(scannerOn: true, holderInPlace: true, flexColorClosed: true)

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
        for missing in [RealPreviewConfirmation(scannerOn: false, holderInPlace: true, flexColorClosed: true),
                        RealPreviewConfirmation(scannerOn: true, holderInPlace: false, flexColorClosed: true),
                        RealPreviewConfirmation(scannerOn: true, holderInPlace: true, flexColorClosed: false)] {
            #expect(model.startRealPreview(missing) == .failure(.notAllowed))
        }
        model.startPreview()
        #expect(model.session.state == .idle && box?.connection == nil)
    }

    @Test func runsTheCapturedSequenceAndLogsIt() async throws {
        let model = try model(enabled: true)
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
        let text = try String(contentsOf: log, encoding: .utf8)
        #expect(text.hasPrefix("# X1 Scan: FlexColor 4.8.13's captured preview replayed on the real X1"))
        #expect(text.contains("0001 CDB 12 00 00 00 60 00"))
        #expect(text.hasSuffix("# preview complete\n"))
        #expect(FileManager.default.fileExists(atPath: log.deletingPathExtension().appendingPathExtension("raw").path))
        #expect(log.path.hasPrefix(folder.path), "outside the repository, in the capture folder")
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
