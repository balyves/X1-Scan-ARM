// SPDX-License-Identifier: MIT
import Foundation
import X1Preview
import X1Protocol
import X1ScanCore

/// User-facing text for the typed states of X1ScanCore. The core never
/// produces interface text; every translatable string lives in this target's
/// String Catalog (Localizable.xcstrings, English and French).
enum Strings {
    static func paletteTitle(_ id: PaletteID) -> String {
        switch id {
        case .histogram: String(localized: "Histogram", comment: "Palette title")
        case .info: String(localized: "Info", comment: "Palette title")
        case .export: String(localized: "Export", comment: "Palette title")
        default: id.rawValue
        }
    }

    static func toolName(_ tool: Tool) -> String {
        switch tool {
        case .hand: String(localized: "tool.hand", defaultValue: "Hand", comment: "Tool: move the image")
        case .zoom: String(localized: "tool.zoom", defaultValue: "Zoom", comment: "Tool: magnifier (not the window zoom)")
        case .crop: String(localized: "tool.crop", defaultValue: "Crop", comment: "Tool: framing rectangle")
        }
    }

    static func source(_ source: ScannerSourceKind) -> String {
        switch source {
        case .virtual: String(localized: "Virtual X1", comment: "Scanner source")
        case .real: String(localized: "Real X1", comment: "Scanner source")
        }
    }

    static func phase(_ phase: PreviewPhase) -> String {
        switch phase {
        case .initialisation: String(localized: "Initialising", comment: "Preview phase")
        case .calibration: String(localized: "Calibrating", comment: "Preview phase")
        case .references: String(localized: "Reading references", comment: "Preview phase: white and dark references")
        case .scanning: String(localized: "Scanning", comment: "Preview phase")
        case .finishing: String(localized: "Finishing", comment: "Preview phase")
        }
    }

    static func previewBlock(_ block: ToolbarState.PreviewBlock) -> String {
        switch block {
        case .realScannerReadOnly:
            String(localized: "Preview on the real X1 is not allowed yet: only reads (identity, state, counters) are.",
                   comment: "Why Preview is disabled")
        case .virtualScannerUnavailable:
            String(localized: "The virtual X1 could not be loaded.", comment: "Why Preview is disabled")
        case .busy:
            String(localized: "A preview is in progress.", comment: "Why Preview is disabled")
        }
    }

    /// Status line of the window.
    @MainActor
    static func sessionStatus(_ session: PreviewSession) -> String {
        switch session.state {
        case .idle:
            return String(localized: "Ready", comment: "Status")
        case .running:
            guard let phase = session.progress.phase else { return String(localized: "Starting", comment: "Status") }
            if phase == .scanning {
                return String(localized: "Scanning: \(session.progress.linesReceived) of \(session.progress.linesExpected) lines",
                              comment: "Status during the scan")
            }
            return Self.phase(phase)
        case .stopping:
            return String(localized: "Stopping…", comment: "Status while the stop sequence runs")
        case .finished:
            return String(localized: "Preview complete", comment: "Status")
        case .stopped(let outcome):
            guard let outcome else { return String(localized: "Preview stopped", comment: "Status, stopped before SCAN") }
            return emergencyStop(outcome)
        case .failed:
            return String(localized: "Preview stopped after an anomaly", comment: "Status")
        }
    }

    static func emergencyStop(_ outcome: EmergencyStopOutcome) -> String {
        switch outcome {
        case .stoppedAndReady:
            String(localized: "Preview stopped; scanner ready", comment: "Stop sequence succeeded")
        case .stopNotSent(let detail):
            String(localized: "The stop command could not be sent: \(detail)", comment: "Stop sequence failed")
        case .stopRefused(let status, _):
            String(localized: "The scanner refused the stop command (status \(String(format: "0x%02x", status)))",
                   comment: "Stop sequence failed")
        case .notReadyAfterStop(let detail):
            String(localized: "The scanner did not report ready after the stop: \(detail)", comment: "Stop sequence failed")
        }
    }

    static func scannerState(_ state: ScannerState?) -> String {
        guard let state else { return String(localized: "Unknown", comment: "Scanner state") }
        switch state {
        case .ready: return String(localized: "Ready", comment: "Status")
        case .busy, .busyOtherPhase: return String(localized: "Busy (\(state.description))", comment: "Scanner state, with 0xDF bytes")
        case .afterScan: return String(localized: "Scanning (\(state.description))", comment: "Scanner state, with 0xDF bytes")
        default: return String(localized: "Unknown state (\(state.description))", comment: "Scanner state, with 0xDF bytes")
        }
    }

    static func inspectorFailure(_ failure: ScannerInspector.Failure) -> String {
        switch failure {
        case .transport(.deviceNotFound):
            String(localized: "No X1 found. Check that it is on and connected.", comment: "Real scanner read failure")
        case .transport(.deviceBusy):
            String(localized: "The X1 is open in another program (probably FlexColor). Quit it and try again.",
                   comment: "Real scanner read failure")
        case .notAFlextightX1(let vendor, let product):
            String(localized: "This scanner is not a Flextight X1 (\(vendor) \(product)). Nothing more was sent.",
                   comment: "Real scanner read failure")
        default:
            String(localized: "Reading failed: \(failure.description)", comment: "Real scanner read failure")
        }
    }

    static func exportError(_ error: ExportError) -> String {
        switch error {
        case .noFolder: String(localized: "Choose an export folder first.", comment: "Export error")
        case .noImage: String(localized: "There is no image to export.", comment: "Export error")
        case .folderMissing(let path): String(localized: "Folder not found: \(path)", comment: "Export error")
        case .write(let detail): String(localized: "The file could not be written: \(detail)", comment: "Export error")
        }
    }

    /// "12,5 %", "8,33 %", "1600 %": three significant digits, as in the zoom steps.
    static func zoom(_ magnification: Double) -> String {
        magnification.formatted(.percent.precision(.significantDigits(1...3)).grouping(.never))
    }

    static func zoomMode(_ mode: ZoomMode) -> String {
        switch mode {
        case .fit: String(localized: "Zoom to Fit", comment: "Menu item")
        case .fill: String(localized: "Fill Window", comment: "Menu item")
        case .fixed: String(localized: "Actual Size", comment: "Menu item")
        }
    }

    /// Bottom bar: "Virtual X1 · Ready".
    @MainActor
    static func statusLine(_ line: ScannerStatusLine, session: PreviewSession) -> String {
        let detail: String = switch line.detail {
        case .session: sessionStatus(session)
        case .unavailable: String(localized: "Unavailable", comment: "Status: virtual X1 fixtures missing")
        case .notRead: String(localized: "Not read", comment: "Scanner state")
        case .reading: String(localized: "Reading…", comment: "Status: reading the real X1")
        case .read: String(localized: "Identity read", comment: "Status: the real X1 was read")
        case .failed: String(localized: "Reading failed", comment: "Status: reading the real X1 failed")
        }
        return "\(source(line.source)) · \(detail)"
    }

    static func language(_ language: InterfaceLanguage) -> String {
        switch language {
        case .system: String(localized: "System", comment: "Setting: follow the system")
        case .french: "Français"
        case .english: "English"
        }
    }

    static func appearance(_ appearance: AppearanceSetting) -> String {
        switch appearance {
        case .system: String(localized: "System", comment: "Setting: follow the system")
        case .light: String(localized: "Light", comment: "Appearance")
        case .dark: String(localized: "Dark", comment: "Appearance")
        }
    }

    static func canvasBackground(_ background: CanvasBackground) -> String {
        switch background {
        case .neutralGray: String(localized: "Neutral grey 18 %", comment: "Background around the image")
        case .black: String(localized: "Black", comment: "Background around the image")
        case .white: String(localized: "White", comment: "Background around the image")
        }
    }

    static func startupZoom(_ zoom: StartupZoom) -> String {
        switch zoom {
        case .fit: String(localized: "Zoom to Fit", comment: "Menu item")
        case .actualSize: String(localized: "Actual Size (100 %)", comment: "Setting: zoom at launch")
        }
    }

    static func startupSource(_ startup: StartupSource) -> String {
        switch startup {
        case .virtual: source(.virtual)
        case .real: source(.real)
        case .last: String(localized: "Last used", comment: "Setting: scanner source at launch")
        }
    }
}
