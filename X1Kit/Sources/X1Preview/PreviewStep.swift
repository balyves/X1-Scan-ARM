// SPDX-License-Identifier: MIT
import X1Protocol
import X1Transport

/// One command of the preview sequence, with what the runner checks and does around it.
public struct PreviewStep: Sendable {
    public enum Kind: Sendable, Hashable {
        /// Sent as is; only status and length are checked.
        case command
        /// INQUIRY: the scanner must identify as `Imacon` / `Flextight X1`.
        case inquiry
        /// Page 0x20: the measured position must stay within the tolerance of the captured value.
        case scanStatus(capturedPosition: Int)
        /// Page 0x20 always checked, even before any window requests a position:
        /// the read before the warm sequence's window with target 25 000. In one
        /// capture (24 523 there) FlexColor did not send that window; beyond the
        /// tolerance the preview stops before it (docs/decisions.md, "Option A").
        case positionGate(capturedPosition: Int)
        /// Page 0x20 checked against a range of its own instead of the
        /// tolerance: the two reads after the cold calibration's
        /// `F0 00 00 01 01 01` (`PreviewScript.coldCalibrationPositions`;
        /// docs/decisions.md, "Real X1: cold calibration positions"). Only
        /// read and compared: nothing sent later carries that position.
        /// Always checked: to be used only after a window that requests a
        /// position (as `.scanStatus` is checked only then).
        case positionRange(capturedPosition: Int, allowed: ClosedRange<Int>)
        /// Page 0x20, first read of the session: chooses the rest of the
        /// sequence (`PreviewPlan`). Power-on values (2 048 × 3): the cold
        /// sequence; values left by earlier use: the warm one; anything else
        /// stops the preview. Before this read only reads, D2 and the session
        /// start have been sent.
        case sequenceChoice
        /// Page 0x20, first read of a session whose script fits only one state
        /// (a scan: no scan right after power-on was captured). Any other state
        /// stops before any window, mode, exposure or READ (only the session
        /// start and reads come before it).
        case startState(PreviewPlan.Choice)
        /// SET WINDOW whose target position (offset 50, LE16) is replaced by the
        /// position of the last page 0x20 read, as FlexColor did (the window of
        /// a scan's 400-line step, docs/protocol.md §9). The only substitution
        /// allowed: the position must be within `allowed` (positions FlexColor
        /// measured there ± the tolerance), or the run stops before sending the
        /// window (docs/decisions.md).
        case positionWindow(capturedPosition: Int, allowed: ClosedRange<Int>)
        /// READ: data kept for decoding.
        case read(ReadPurpose)
        /// 0x1B SCAN: must return `00 00`. From here on, an anomaly triggers the stop sequence.
        case scan
    }

    public enum ReadPurpose: Sendable, Hashable {
        /// One full-CCD line during calibration (not used for decoding yet).
        case calibrationLine
        /// White reference lines at preview width.
        case whiteReference
        /// Dark reference lines at preview width.
        case darkReference
        /// The single lines FlexColor reads right after SCAN. Not decoded in a
        /// preview; in a scan, the first lines of the image (priming lines).
        case leadIn
        /// Scan: the full-width white then dark lines (10 per read).
        case scanReference
        /// Scan: one line of the 400-line step (focus sweep, [hypothesis]).
        case focusLine
        /// Image lines.
        case image
    }

    public let command: SCSICommand
    public let kind: Kind
    /// If set, poll 0xDF after this step until the scanner reports this state,
    /// as FlexColor did at this point of the capture.
    public let waitUntil: ScannerState?
    /// Busy states accepted in this wait only, besides
    /// `ScannerState.observedBusyStates`: states not in that list that a
    /// capture shows at this step (docs/protocol.md §7).
    public let alsoBusy: Set<ScannerState>

    public init(command: SCSICommand, kind: Kind = .command, waitUntil: ScannerState? = nil,
                alsoBusy: Set<ScannerState> = []) {
        self.command = command
        self.kind = kind
        self.waitUntil = waitUntil
        self.alsoBusy = alsoBusy
    }

    func waiting(for state: ScannerState, alsoBusy: Set<ScannerState> = []) -> PreviewStep {
        PreviewStep(command: command, kind: kind, waitUntil: state, alsoBusy: alsoBusy)
    }
}

/// The two sequences FlexColor 4.8.13 uses for a preview, which are identical
/// up to and including the first page 0x20 read of the session
/// (docs/protocol.md §11): `common` ends with that read (`.sequenceChoice`),
/// then the runner goes on with `cold` or `warm`.
public struct PreviewPlan: Sendable {
    public enum Choice: Sendable, Hashable {
        /// Power-on values: right after the X1 was switched on.
        case cold
        /// Values left by earlier use.
        case warm
    }

    public let common: [PreviewStep]
    public let cold: [PreviewStep]
    public let warm: [PreviewStep]
    /// 0xDF state to wait for right after the choice, per branch, as FlexColor
    /// polled there (warm: until `00 00`; cold: no poll).
    public let waitAfterChoice: [Choice: ScannerState]

    public init(common: [PreviewStep], cold: [PreviewStep], warm: [PreviewStep],
                waitAfterChoice: [Choice: ScannerState] = [:]) {
        precondition(common.last?.kind == .sequenceChoice, "the common part ends with the choice read")
        self.common = common
        self.cold = cold
        self.warm = warm
        self.waitAfterChoice = waitAfterChoice
    }

    /// The whole sequence for one choice.
    public func steps(for choice: Choice) -> [PreviewStep] {
        var steps = common
        if let state = waitAfterChoice[choice] { steps[steps.count - 1] = steps[steps.count - 1].waiting(for: state) }
        return steps + (choice == .cold ? cold : warm)
    }
}

/// Everything the preview reads that matters for decoding.
public struct PreviewCapture: Sendable {
    public var calibrationLines: [[UInt8]] = []
    public var whiteReference: [[UInt8]] = []
    public var darkReference: [[UInt8]] = []
    public var leadIn: [[UInt8]] = []
    public var image: [[UInt8]] = []
    public var scanReference: [[UInt8]] = []
    public var focusLines: [[UInt8]] = []
    public var scanStatuses: [ScanStatusPage] = []
    /// The sequence chosen after the first page 0x20 read (nil for a fixed script).
    public var choice: PreviewPlan.Choice?

    public init() {}

    mutating func append(_ data: [UInt8], for purpose: PreviewStep.ReadPurpose) {
        switch purpose {
        case .calibrationLine: calibrationLines.append(data)
        case .whiteReference: whiteReference.append(data)
        case .darkReference: darkReference.append(data)
        case .leadIn: leadIn.append(data)
        case .image: image.append(data)
        case .scanReference: scanReference.append(data)
        case .focusLine: focusLines.append(data)
        }
    }
}
