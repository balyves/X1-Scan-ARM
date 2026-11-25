// SPDX-License-Identifier: MIT
import Foundation
import Observation

/// The installation check's window (assistant, lot 2): the four lines, read
/// again every `interval` while the window is open, so that plugging in the
/// adapter or switching the X1 on shows at once. Each reading is a snapshot
/// of the I/O Registry, read only (`InstallationRegistry`): nothing is
/// opened, nothing is sent; the reading runs off the main actor.
@MainActor
@Observable
public final class InstallationMonitor {
    public private(set) var lines: [InstallationCheck.Line] = []
    /// The last snapshot read (the macOS version shown on its line).
    public private(set) var snapshot: InstallationSnapshot?
    public private(set) var lastChecked: Date?

    @ObservationIgnored private let read: @Sendable () -> InstallationSnapshot
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored private var reading = false

    /// Every 2 s while the window is open: a registry search is cheap, and
    /// the line follows a cable plugged in or an X1 switched on.
    public nonisolated static let defaultInterval: Duration = .seconds(2)

    public init(interval: Duration = defaultInterval,
                read: @escaping @Sendable () -> InstallationSnapshot = { InstallationRegistry.snapshot() }) {
        self.interval = interval
        self.read = read
    }

    /// One reading now (Check Again, and each tick of the watch).
    public func refresh(now: Date = Date()) async {
        guard !reading else { return }
        reading = true
        defer { reading = false }
        let read = read
        let snapshot = await Task.detached(priority: .userInitiated) { read() }.value
        self.snapshot = snapshot
        lines = InstallationCheck.evaluate(snapshot)
        lastChecked = now
    }

    /// While the window is open.
    public func startWatching() {
        guard watch == nil else { return }
        let interval = interval
        watch = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stopWatching() {
        watch?.cancel()
        watch = nil
    }

    public var isWatching: Bool { watch != nil }
}
