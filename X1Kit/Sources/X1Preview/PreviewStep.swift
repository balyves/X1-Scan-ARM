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
        /// The single lines FlexColor reads right after SCAN. Role unknown; not decoded.
        case leadIn
        /// Image lines.
        case image
    }

    public let command: SCSICommand
    public let kind: Kind
    /// If set, poll 0xDF after this step until the scanner reports this state,
    /// as FlexColor did at this point of the capture.
    public let waitUntil: ScannerState?

    public init(command: SCSICommand, kind: Kind = .command, waitUntil: ScannerState? = nil) {
        self.command = command
        self.kind = kind
        self.waitUntil = waitUntil
    }

    func waiting(for state: ScannerState) -> PreviewStep {
        PreviewStep(command: command, kind: kind, waitUntil: state)
    }
}

/// Everything the preview reads that matters for decoding.
public struct PreviewCapture: Sendable {
    public var calibrationLines: [[UInt8]] = []
    public var whiteReference: [[UInt8]] = []
    public var darkReference: [[UInt8]] = []
    public var leadIn: [[UInt8]] = []
    public var image: [[UInt8]] = []
    public var scanStatuses: [ScanStatusPage] = []

    public init() {}

    mutating func append(_ data: [UInt8], for purpose: PreviewStep.ReadPurpose) {
        switch purpose {
        case .calibrationLine: calibrationLines.append(data)
        case .whiteReference: whiteReference.append(data)
        case .darkReference: darkReference.append(data)
        case .leadIn: leadIn.append(data)
        case .image: image.append(data)
        }
    }
}
