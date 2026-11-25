// SPDX-License-Identifier: MIT

/// Which scanner the window works with.
public enum ScannerSourceKind: String, Sendable, Hashable, Codable, CaseIterable {
    /// Replay of tests/fixtures. Default.
    case virtual
    /// The X1 through IOKit, read-only.
    case real
}

/// What the window toolbar and menus allow, and why not.
public struct ToolbarState: Sendable, Hashable {
    public enum PreviewBlock: Sendable, Hashable {
        /// Real X1: only reads are allowed at this stage.
        case realScannerReadOnly
        /// The fixtures of the virtual X1 could not be loaded.
        case virtualScannerUnavailable
        /// A preview is running or stopping.
        case busy
    }

    public var canPreview: Bool { previewBlock == nil }
    public var previewBlock: PreviewBlock?
    public var canStop: Bool
    /// Stop is drawn red only while a preview runs.
    public var stopIsProminent: Bool { canStop }
    /// True while the stop sequence runs: Stop is shown, but pressing it again does nothing.
    public var isStopping: Bool
    public var canExport: Bool
    /// The image shown is incomplete (a preview stopped before its end; a
    /// stopped scan has no image): Export is disabled (user's decision of 2026-11-25).
    public let exportNeedsCompleteImage: Bool

    public enum ScanBlock: Sendable, Hashable {
        /// A preview or scan is running or stopping.
        case busy
        /// The scan capture is not available.
        case noScanCapture
        /// No export folder: the scan would not be saved.
        case noExportFolder
        /// Real X1 without the hidden setting `EnableRealScan`.
        case realScanDisabled
        /// Real X1: a real preview must have completed just before, with no
        /// real run since (each captured scan follows one preview).
        case needsCompletePreview
    }

    public var canScan: Bool { scanBlock == nil }
    public let scanBlock: ScanBlock?
    /// Real X1: Scan asks for a confirmation first.
    public let scanNeedsConfirmation: Bool

    /// Real X1 with the hidden setting on: Preview asks for a confirmation first (step 4).
    public let previewNeedsConfirmation: Bool

    /// `realPreviewEnabled`: the hidden setting `EnableRealPreview` (off by default).
    /// `realScanEnabled`: `EnableRealScan` (off by default); `realScanReady`: a
    /// real preview completed just before, with no real run since.
    public init(source: ScannerSourceKind, session: PreviewSession.State, virtualAvailable: Bool,
                hasImage: Bool, hasExportFolder: Bool, realPreviewEnabled: Bool = false,
                scanAvailable: Bool = false, scanHasExportFolder: Bool = true, realScanEnabled: Bool = false,
                realScanReady: Bool = false, imageIsComplete: Bool = true) {
        let busy = session == .running || session == .stopping
        previewNeedsConfirmation = source == .real && realPreviewEnabled
        if busy {
            previewBlock = .busy
        } else if source == .real && !realPreviewEnabled {
            previewBlock = .realScannerReadOnly
        } else if !virtualAvailable {  // the captured sequence comes with the virtual X1's fixtures
            previewBlock = .virtualScannerUnavailable
        } else {
            previewBlock = nil
        }
        canStop = session == .running
        isStopping = session == .stopping
        exportNeedsCompleteImage = !busy && hasImage && !imageIsComplete
        canExport = !busy && hasImage && imageIsComplete && hasExportFolder
        scanNeedsConfirmation = source == .real
        if busy {
            scanBlock = .busy
        } else if !scanAvailable {
            scanBlock = .noScanCapture
        } else if !scanHasExportFolder {
            scanBlock = .noExportFolder
        } else if source == .real && !realScanEnabled {
            scanBlock = .realScanDisabled
        } else if source == .real && !realScanReady {
            scanBlock = .needsCompletePreview
        } else {
            scanBlock = nil
        }
    }
}

/// The serial number is personal data (CLAUDE.md): masked unless the user asks.
public enum SerialMasking {
    public static let visiblePrefix = 3

    /// `FX1` followed by one bullet per hidden character.
    public static func masked(_ serial: String) -> String {
        String(serial.prefix(visiblePrefix)) + String(repeating: "•", count: max(serial.count - visiblePrefix, 0))
    }

    public static func display(_ serial: String, revealed: Bool) -> String {
        revealed ? serial : masked(serial)
    }
}
