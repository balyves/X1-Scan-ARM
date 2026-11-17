// SPDX-License-Identifier: MIT
import X1Protocol
import X1Transport

/// Broad stage of a preview or scan sequence, for progress display. Derived
/// from the commands of the script themselves, not from a fixed order (in
/// FlexColor's scans the white/dark read comes before or after the 400-line
/// step depending on the resolution; docs/protocol.md §11, §12). Never sent
/// to the scanner.
public enum PreviewPhase: Sendable, Hashable, CaseIterable {
    /// Identity, vendor pages, usage log, before the session starts.
    case initialisation
    /// From session start (`CF 00 01 80`): windows, modes, exposure, positions.
    case calibration
    /// White and dark references (preview width, or full width in a scan).
    case references
    /// Scan only: from `1b 00 08 06 01 00` to its stop, the 400-line step
    /// (focus, [hypothesis]).
    case focus
    /// From the image SCAN (`1b 00 00 01 01 00`) to the stop command.
    case scanning
    /// Stop (`DB`) after the image, and end of session.
    case finishing

    /// The phase of every step of `script`, in order.
    public static func phases(for script: [PreviewStep]) -> [PreviewPhase] {
        let sessionStart = X1Command.session(.start)
        let sessionEnd = X1Command.session(.end)
        let stop = X1Command.stop()
        let focusSweep = X1Command.focusSweep()
        let imageScan = X1Command.scan()
        var phase = PreviewPhase.initialisation
        return script.map { step in
            let command = step.command
            switch phase {
            case .initialisation where command == sessionStart:
                phase = .calibration
            case .calibration, .references:
                if command == focusSweep { phase = .focus }
                else if command == imageScan { phase = .scanning }
                else if case .read(.whiteReference) = step.kind { phase = .references }
                else if case .read(.scanReference) = step.kind { phase = .references }
                else if phase == .references, command.opcode == 0xF0 || command.opcode == 0xE4,
                        !isReferenceMode(command) { phase = .calibration }
            case .focus where command == stop:
                phase = .calibration
            case .scanning where command == stop || command == sessionEnd:
                phase = .finishing
            default:
                break
            }
            return phase
        }
    }

    /// The modes around the white and dark reads (`F0 00 01 x 0 01`): they
    /// belong to the references phase.
    private static func isReferenceMode(_ command: SCSICommand) -> Bool {
        command.opcode == 0xF0 && command.cdb[2] == 0x01 && command.cdb[4] == 0x00
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
    /// The first page 0x20 read chose the cold or the warm sequence.
    case sequenceChosen(PreviewPlan.Choice)
    /// A page 0x20 read whose measured position differs from the expected one
    /// (sent before the tolerance check). `expected`: the captured position,
    /// or after a substituted window the position sent.
    /// `checked`: the tolerance applies to this read.
    case positionDifference(expected: Int, measured: Int, checked: Bool)
    /// READ data received and accepted.
    case data([UInt8], purpose: PreviewStep.ReadPurpose)
    /// An anomaly or a cancellation happened after SCAN: the stop sequence
    /// (`DB`, then wait for 0xDF = 00 00) is starting.
    case stopping
}

public typealias PreviewEventHandler = @Sendable (PreviewEvent) -> Void
