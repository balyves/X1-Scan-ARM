// SPDX-License-Identifier: MIT
import Foundation
@testable import X1ScanCore
import X1Preview
import X1Transport

/// tests/fixtures at the repository root, read in place.
enum TestFixtures {
    static let directory: URL = URL(filePath: #filePath)
        .deletingLastPathComponent()  // X1ScanCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // X1ScanCore
        .deletingLastPathComponent()  // app
        .deletingLastPathComponent()  // repository root
        .appending(path: "tests/fixtures")

    static func scanner(pacing: Pacing = .none) throws -> VirtualScanner {
        try VirtualScanner.load(fixturesDirectory: directory, pacing: pacing)
    }

    /// The virtual X1, paused before its `index`-th non-poll command until
    /// `gate.release()`: stop tests do not depend on timing.
    static func scanner(pausedAt index: Int, gate: PreviewGate) throws -> VirtualScanner {
        var scanner = try VirtualScanner.load(fixturesDirectory: directory, pacing: .none)
        scanner.transportWrapper = { GatedTransport(inner: $0, gate: gate, pauseAt: index) }
        return scanner
    }

    /// Index of SCAN among the non-poll commands of the preview.
    static let scanIndex = PreviewScript.flexColor4813.firstIndex { $0.kind == .scan }!
}

/// Waits on the main actor until `condition` holds, or fails after `timeout`.
@MainActor
func waitUntil(timeout: Duration = .seconds(20), _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { throw TimeoutError() }
        try await Task.sleep(for: .milliseconds(1))
    }
}

struct TimeoutError: Error {}

/// A throwaway UserDefaults suite, removed when `body` returns.
func withTemporaryDefaults<T>(_ body: (UserDefaults) throws -> T) rethrows -> T {
    let suite = "X1ScanCoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    return try body(defaults)
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "X1ScanCoreTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A scanner connection that answers from fixed responses and records everything.
actor FakeConnection: ScannerConnection {
    var responses: [[UInt8]: SCSIResult]
    var openError: (any Error)?
    private(set) var sent: [SCSICommand] = []
    private(set) var opened = false
    private(set) var closed = false

    init(responses: [[UInt8]: SCSIResult], openError: (any Error)? = nil) {
        self.responses = responses
        self.openError = openError
    }

    func open() throws {
        if let openError { throw openError }
        opened = true
    }

    func close() { closed = true }

    func execute(_ command: SCSICommand) throws -> SCSIResult {
        sent.append(command)
        guard let result = responses[command.cdb] else { throw TransportError.notOpen }
        return result
    }
}

/// Holds the virtual X1 before a chosen command until the test releases it.
actor PreviewGate {
    private var paused = false
    private var released = false
    private var pauseContinuation: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Called by the transport before the command to pause at.
    func pause() async {
        paused = true
        for waiter in waiters { waiter.resume() }
        waiters = []
        guard !released else { return }
        await withCheckedContinuation { pauseContinuation = $0 }
    }

    /// Returns once the virtual X1 is paused.
    func waitUntilPaused() async {
        guard !paused else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        released = true
        pauseContinuation?.resume()
        pauseContinuation = nil
    }
}

/// Pauses on the gate before the `pauseAt`-th non-poll command.
actor GatedTransport: SCSITransport {
    private let inner: any SCSITransport
    private let gate: PreviewGate
    private let pauseAt: Int
    private var nonPollCount = 0

    init(inner: any SCSITransport, gate: PreviewGate, pauseAt: Int) {
        self.inner = inner
        self.gate = gate
        self.pauseAt = pauseAt
    }

    func execute(_ command: SCSICommand) async throws -> SCSIResult {
        if !SimulatedX1.pollingOpcodes.contains(command.opcode) {
            let index = nonPollCount
            nonPollCount += 1
            if index == pauseAt { await gate.pause() }
        }
        return try await inner.execute(command)
    }
}
