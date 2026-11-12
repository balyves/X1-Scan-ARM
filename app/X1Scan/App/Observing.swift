// SPDX-License-Identifier: MIT
import Observation

/// Runs `apply` now and again every time an observable value it read changes.
/// For AppKit code that mirrors X1ScanCore models; SwiftUI views observe them directly.
@MainActor
final class Observing {
    private let apply: @MainActor () -> Void
    private var active = true

    init(_ apply: @escaping @MainActor () -> Void) {
        self.apply = apply
        track()
    }

    func cancel() { active = false }

    private func track() {
        guard active else { return }
        withObservationTracking {
            apply()
        } onChange: { [weak self] in
            Task { @MainActor in self?.track() }
        }
    }
}
