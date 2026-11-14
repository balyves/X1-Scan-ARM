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
    /// Scanning is a later stage.
    public let canScan = false

    public init(source: ScannerSourceKind, session: PreviewSession.State, virtualAvailable: Bool,
                hasImage: Bool, hasExportFolder: Bool) {
        let busy = session == .running || session == .stopping
        if busy {
            previewBlock = .busy
        } else if source == .real {
            previewBlock = .realScannerReadOnly
        } else if !virtualAvailable {
            previewBlock = .virtualScannerUnavailable
        } else {
            previewBlock = nil
        }
        canStop = session == .running
        isStopping = session == .stopping
        canExport = !busy && hasImage && hasExportFolder
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
