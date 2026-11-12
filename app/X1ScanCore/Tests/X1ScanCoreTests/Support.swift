// SPDX-License-Identifier: MIT
import Foundation
@testable import X1ScanCore
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

    /// Slow enough to stop at a chosen phase, fast enough for a test.
    static let slow = Pacing(perCommand: .milliseconds(2), perImageRead: .milliseconds(15))
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
