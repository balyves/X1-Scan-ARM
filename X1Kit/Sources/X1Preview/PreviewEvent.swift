// SPDX-License-Identifier: MIT
import X1Protocol
import X1Transport

/// Broad stage of the preview sequence, for progress display. Derived from the
/// script itself (docs/protocol.md §11), never sent to the scanner.
public enum PreviewPhase: Sendable, Hashable, CaseIterable {
    /// Identity, vendor pages, usage log, before the session starts.
    case initialisation
    /// From session start (`CF 00 01 80`) to the first white reference read.
    case calibration
    /// White and dark references at preview width, up to SCAN.
    case references
    /// From SCAN to the stop command.
    case scanning
    /// Stop (`DB`) and end of session.
    case finishing

    /// The phase of every step of `script`, in order.
    public static func phases(for script: [PreviewStep]) -> [PreviewPhase] {
        let sessionStart = X1Command.session(.start)
        let stop = X1Command.stop()
        var phase = PreviewPhase.initialisation
        return script.map { step in
            switch (phase, step.kind) {
            case (.initialisation, _) where step.command == sessionStart:
                phase = .calibration
            case (.calibration, .read(.whiteReference)):
                phase = .references
            case (.references, .scan):
                phase = .scanning
            case (.scanning, _) where step.command == stop:
                phase = .finishing
            default:
                break
            }
            return phase
        }
    }
}

/// What the runner reports while it runs. Events are delivered synchronously,
/// on the runner's task, after the step has been checked; a slow handler slows
/// the preview down, so a handler should only hand the event over.
public enum PreviewEvent: Sendable {
    /// Step `index` of `count` is about to be sent.
    case step(index: Int, count: Int, phase: PreviewPhase)
    /// Page 0x20 read and accepted.
    case scanStatus(ScanStatusPage)
    /// READ data received and accepted.
    case data([UInt8], purpose: PreviewStep.ReadPurpose)
    /// An anomaly or a cancellation happened after SCAN: the stop sequence
    /// (`DB`, then wait for 0xDF = 00 00) is starting.
    case stopping
}

public typealias PreviewEventHandler = @Sendable (PreviewEvent) -> Void
