// SPDX-License-Identifier: MIT
import Foundation
import X1Preview
import X1Transport

/// The stable identifier of everything that can go wrong in front of the
/// user (lot A, step B; docs/decisions.md, "Lot A: error catalogue"). Each has its
/// texts in the String Catalog (`issue.<id>.title`, `.cause`, `.step1`…)
/// and an entry of the same name in docs/help/<language>/troubleshooting.md.
/// Only what is shown changes: the guards and the runner stop exactly as
/// before, and the log keeps every technical detail.
public enum IssueID: String, Sendable, Hashable, CaseIterable {
    // Access to the real X1.
    case noScanner = "no-scanner"
    case scannerBusy = "scanner-busy"
    case notAnX1 = "not-an-x1"
    case scannerReadFailed = "scanner-read-failed"
    case disconnected
    case scannerTimeout = "scanner-timeout"
    // Starting a run on the real X1.
    case captureMissing = "capture-missing"
    case logFailed = "log-failed"
    // Safety checks: stopped on purpose, to protect the scanner.
    case guardRefused = "guard-refused"
    case unexpectedState = "unexpected-state"
    case stateTimeout = "state-timeout"
    case positionOutOfTolerance = "position-out-of-tolerance"
    case positionOutOfRange = "position-out-of-range"
    case carriagePosition = "carriage-position"
    case startStateUnknown = "start-state-unknown"
    case scanNeedsPreview = "scan-needs-preview"
    case lineCounter = "line-counter"
    case unexpectedResponse = "unexpected-response"
    // Stop.
    case stoppedByUser = "stopped-by-user"
    case stopIncomplete = "stop-incomplete"
    // Image and files.
    case decodingFailed = "decoding-failed"
    case noExportFolder = "no-export-folder"
    case exportFolderMissing = "export-folder-missing"
    case writeFailed = "write-failed"
    /// Reserved: no capture shows how the X1 answers without a holder, so
    /// nothing leads here yet; nothing is guessed (docs/decisions.md, "Lot A: error catalogue").
    case holderMissing = "holder-missing"
    /// Anything not foreseen: a generic message, its details and Troubleshooting.
    case unknown

    /// A safety check stopped the scanner on purpose (the message says so).
    public var isSafetyStop: Bool {
        switch self {
        case .guardRefused, .unexpectedState, .stateTimeout, .positionOutOfTolerance, .positionOutOfRange,
             .carriagePosition, .startStateUnknown, .scanNeedsPreview, .lineCounter, .unexpectedResponse:
            true
        default:
            false
        }
    }

    /// The catalog step of this case that says to switch the X1 off and on,
    /// left out when the window gives its own (the one that fits where the
    /// run stopped), so that the message has one such step, first.
    public var powerCycleStep: Int? {
        switch self {
        case .scannerReadFailed: 1
        case .disconnected, .scannerTimeout: 2
        default: nil
        }
    }

    /// Steps a case has at most in the String Catalog (`.step1` to `.step3`).
    public static let maximumSteps = 3

    /// The Troubleshooting entry: `troubleshooting.md#<id>`.
    public var helpAnchor: String { rawValue }
    public static let helpPage = "troubleshooting"
}

/// What a message shows: the case, the extra steps the situation adds
/// (switch the X1 off and on…, chosen as before), and the technical text of
/// today for the folded Details part.
public struct UserIssue: Sendable, Hashable {
    public var id: IssueID
    /// A translated line above the title saying which operation it was
    /// (the title of the alert before: "The preview stopped after an anomaly").
    public var context: String?
    /// Translated steps put before the case's own: the advice the alerts gave
    /// before (switch the X1 off and on…), since the X1's state comes first.
    public var extraSteps: [String]
    /// The technical text: codes, commands, values, the log's path. Copyable.
    public var details: String

    public init(_ id: IssueID, context: String? = nil, extraSteps: [String] = [], details: String) {
        self.id = id
        self.context = context
        self.extraSteps = extraSteps
        self.details = details
    }
}

/// Which `IssueID` a failure is. Read-only: it looks at what the runner,
/// the guards, the transport and the export already decided, and decides
/// nothing itself.
public enum IssueClassifier {
    public static func id(for failure: PreviewFailure) -> IssueID {
        switch failure.cause {
        case .decoding: .decodingFailed
        case .anomaly(let anomaly): id(for: anomaly)
        }
    }

    public static func id(for anomaly: PreviewAnomaly) -> IssueID {
        switch anomaly {
        case .couldNotOpen(let detail):
            switch transportError(described: detail) {
            case .deviceNotFound?: .noScanner
            case .deviceBusy?: .scannerBusy
            default: .scannerReadFailed
            }
        case .transport(let detail):
            id(forTransportDuringRun: transportError(described: detail))
        case .unexpectedIdentity: .notAnX1
        case .unexpectedState: .unexpectedState
        case .stateTimeout: .stateTimeout
        case .positionOutOfTolerance: .positionOutOfTolerance
        case .positionOutOfRange: .positionOutOfRange
        case .unexpectedCarriagePosition: .carriagePosition
        case .unrecognisedStartState: .startStateUnknown
        case .startStateMismatch: .scanNeedsPreview
        case .lineCounterWentBack: .lineCounter
        // notJustSwitchedOn: a fixed cold script, never run by the application.
        case .badStatus, .wrongLength, .unexpectedScanResponse, .malformedResponse, .notJustSwitchedOn: .unexpectedResponse
        case .cancelled: .stoppedByUser
        }
    }

    /// A transport error in the middle of a preview or a scan.
    static func id(forTransportDuringRun error: TransportError?) -> IssueID {
        switch error {
        case .refusedByPolicy?: .guardRefused
        case .deviceNotFound?, .deliveryFailure(.deviceNotPresent)?, .deliveryFailure(.deviceNotResponding)?: .disconnected
        case .deliveryFailure(.taskTimeout)?, .deliveryFailure(.protocolTimeout)?: .scannerTimeout
        // Another IOKit error or service response: no message would be right but the generic one.
        case .deliveryFailure?, .ioKit?: .unknown
        case .deviceBusy?: .scannerBusy
        case .notOpen?, nil: .unknown
        }
    }

    /// A failure of Scanner Information's reads.
    public static func id(for failure: ScannerInspector.Failure) -> IssueID {
        switch failure {
        case .transport(.deviceNotFound): .noScanner
        case .transport(.deviceBusy): .scannerBusy
        case .transport(.refusedByPolicy): .guardRefused
        case .transport(.deliveryFailure(.deviceNotPresent)), .transport(.deliveryFailure(.deviceNotResponding)): .disconnected
        case .notAFlextightX1: .notAnX1
        case .transport, .badStatus, .wrongLength, .malformed, .missingResponse, .other: .scannerReadFailed
        }
    }

    /// Nil: not shown (`notAllowed` is refused silently, as before).
    public static func id(for error: RealPreviewError) -> IssueID? {
        switch error {
        case .notAllowed: nil
        case .noCapturedSequence: .captureMissing
        case .log: .logFailed
        }
    }

    public static func id(for error: ExportError) -> IssueID {
        switch error {
        case .noFolder: .noExportFolder
        case .folderMissing: .exportFolderMissing
        case .write: .writeFailed
        case .noImage: .unknown  // Export is disabled without an image
        }
    }

    /// The stop sequence after SCAN did not bring the scanner back to ready.
    public static func stopFailed(_ outcome: EmergencyStopOutcome?) -> Bool {
        guard let outcome else { return false }
        return outcome != .stoppedAndReady
    }

    /// The runner keeps transport errors as their text
    /// (`PreviewAnomaly.transport(String)`, `.couldNotOpen(String)`, made
    /// with `String(describing:)`); X1Kit is left unchanged (docs/decisions.md,
    /// "Lot A: error catalogue"). The text is compared with the descriptions of
    /// `TransportError` itself, so a changed wording fails the tests instead
    /// of misleading the user. The values returned only choose a message.
    static func transportError(described text: String) -> TransportError? {
        let fixed: [TransportError] = [
            .deviceNotFound, .deviceBusy, .notOpen,
            .deliveryFailure(.taskTimeout), .deliveryFailure(.protocolTimeout),
            .deliveryFailure(.deviceNotResponding), .deliveryFailure(.deviceNotPresent),
        ]
        if let match = fixed.first(where: { $0.description == text }) { return match }
        // Cases with a value in their text: one representative of each.
        // "command 0x00 refused by policy: <reason>": the words after the opcode.
        let policy = TransportError.refusedByPolicy(opcode: 0, reason: "").description
        let policyWords = String(policy.drop { $0 != " " }.dropFirst().drop { $0 != " " })  // " refused by policy: "
        let commandPrefix = String(policy.prefix { $0 != "0" })  // "command "
        if text.hasPrefix(commandPrefix), text.contains(policyWords) {
            return .refusedByPolicy(opcode: 0, reason: text)
        }
        let ioKitPrefix = String(TransportError.ioKit(code: 0, operation: "").description.prefix { $0 != "0" })
        if text.hasPrefix(ioKitPrefix) { return .ioKit(code: 0, operation: text) }
        let deliveryPrefix = String(TransportError.deliveryFailure(.other(0)).description.prefix { $0 != ":" })
        if text.hasPrefix(deliveryPrefix + ":") { return .deliveryFailure(.other(0)) }
        return nil
    }
}
