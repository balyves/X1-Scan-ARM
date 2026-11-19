// SPDX-License-Identifier: MIT
import Foundation
import X1Image
import X1Preview
import X1Protocol
import X1ScanCore

/// User-facing text for the typed states of X1ScanCore. The core never
/// produces interface text; every translatable string lives in this target's
/// String Catalog (Localizable.xcstrings, English and French).
enum Strings {
    /// Texts of a compact slider row: label and unit as given, the reset
    /// action, and a tooltip with the default value and its unit.
    static func sliderRow(label: String, unit: String, format: CompactValueFormat) -> CompactSliderRow.Texts {
        let defaultValue = format.text(for: format.defaultValue, locale: .current)
        // No-break space: the value and its unit stay on one line.
        let defaultText = unit.isEmpty ? defaultValue : "\(defaultValue)\u{00A0}\(unit)"
        return CompactSliderRow.Texts(
            label: label,
            unit: unit,
            resetAction: String(localized: "Reset to Default", comment: "VoiceOver action of a panel slider row"),
            resetHelp: String(localized: "Double-click to reset to \(defaultText)",
                              comment: "Tooltip of a panel slider row label; the default value with its unit"))
    }

    /// VoiceOver values of a foldable panel title.
    static var foldTexts: CompactFoldTexts {
        CompactFoldTexts(expanded: String(localized: "Expanded", comment: "Palette state"),
                         collapsed: String(localized: "Collapsed", comment: "Palette state"))
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
        case .focus: String(localized: "Focusing", comment: "Scan phase: the 400-line step before the image")
        // Not shown today: sessionStatus shows "Preview: n of m lines" for this phase.
        case .scanning: String(localized: "Reading the image", comment: "Preview phase: image lines are read")
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

    /// Under the panel's buttons and in their tooltip.
    static func previewBlockShort(_ block: ToolbarState.PreviewBlock) -> String {
        switch block {
        case .realScannerReadOnly:
            String(localized: "Preview on the real X1 is not available yet: choose the virtual X1 in Settings.",
                   comment: "Why Preview is disabled, under the panel's buttons")
        case .virtualScannerUnavailable, .busy:
            previewBlock(block)
        }
    }

    /// Status line of the window.
    @MainActor
    static func sessionStatus(_ session: PreviewSession, scanSave: Result<URL, ExportError>? = nil) -> String {
        if session.kind == .scan { return scanStatus(session, save: scanSave) }
        switch session.state {
        case .idle:
            return String(localized: "Ready", comment: "Status")
        case .running:
            guard let phase = session.progress.phase else { return String(localized: "Starting", comment: "Status") }
            if phase == .scanning {
                // A scan has its own texts (scanStatus).
                return String(localized: "Preview: \(session.progress.linesReceived) of \(session.progress.linesExpected) lines",
                              comment: "Status while the preview reads the image lines")
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

    /// Status line of the window during and after a scan.
    @MainActor
    static func scanStatus(_ session: PreviewSession, save: Result<URL, ExportError>?) -> String {
        let progress = session.progress
        switch session.state {
        case .idle:
            return String(localized: "Ready", comment: "Status")
        case .running:
            switch progress.phase {
            case nil:
                return String(localized: "Starting", comment: "Status")
            case .focus?:
                return String(localized: "Focusing: \(progress.focusLinesReceived) of \(progress.focusLinesExpected) lines",
                              comment: "Status while the scan reads the 400-line step")
            case .references?:
                return String(localized: "White and black references", comment: "Status while the scan reads its white and black reference lines")
            case .scanning?, .finishing?:
                return String(localized: "Image: \(progress.linesReceived) of \(progress.linesExpected) lines",
                              comment: "Status while the scan reads the image lines")
            case let phase?:
                return Self.phase(phase)
            }
        case .stopping:
            return String(localized: "Stopping…", comment: "Status while the stop sequence runs")
        case .finished:
            switch save {
            case .success(let url)?:
                return String(localized: "Scan complete: \(url.lastPathComponent)", comment: "Status, with the file saved")
            case .failure?:
                return String(localized: "Scan complete, not saved", comment: "Status: the TIFF could not be written")
            case nil:
                return String(localized: "Scan complete", comment: "Status")
            }
        case .stopped(let outcome):
            guard let outcome else { return String(localized: "Scan stopped", comment: "Status, stopped before SCAN") }
            return emergencyStop(outcome)
        case .failed:
            return String(localized: "Scan stopped after an anomaly", comment: "Status")
        }
    }

    /// Why Scan is disabled (tooltip).
    static func scanBlock(_ block: ToolbarState.ScanBlock) -> String {
        switch block {
        case .busy:
            String(localized: "A preview or scan is in progress.", comment: "Why Scan is disabled")
        case .noScanCapture:
            String(localized: "The captured scan could not be loaded.", comment: "Why Scan is disabled")
        case .noExportFolder:
            String(localized: "Choose an export folder first: the scan is saved there.", comment: "Why Scan is disabled")
        case .realScanDisabled:
            String(localized: "Scanning on the real X1 is not enabled.", comment: "Why Scan is disabled")
        case .needsCompletePreview:
            String(localized: "Run a complete real preview first.", comment: "Why Scan is disabled")
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
    static func statusLine(_ line: ScannerStatusLine, session: PreviewSession,
                           scanSave: Result<URL, ExportError>? = nil) -> String {
        "\(source(line.source)) · \(statusDetail(line, session: session, scanSave: scanSave))"
    }

    /// The state alone: "Ready", "Identity read"…
    @MainActor
    static func statusDetail(_ line: ScannerStatusLine, session: PreviewSession,
                             scanSave: Result<URL, ExportError>? = nil) -> String {
        switch line.detail {
        case .session: sessionStatus(session, scanSave: scanSave)
        case .unavailable: String(localized: "Unavailable", comment: "Status: virtual X1 fixtures missing")
        case .notRead: String(localized: "Not read", comment: "Scanner state")
        case .reading: String(localized: "Reading…", comment: "Status: reading the real X1")
        case .read: String(localized: "Identity read", comment: "Status: the real X1 was read")
        case .failed: String(localized: "Reading failed", comment: "Status: reading the real X1 failed")
        }
    }

    /// "6×7", or "Mounted slides 35 mm". Default formats use the decimal
    /// separator of the user's number format ("6×4,5" in French); custom names stay as typed.
    static func holderName(_ holder: Holder) -> String {
        let format = holder.isCustom ? holder.format : Holder.localizedDecimals(holder.format)
        return holder.mountedSlides
            ? String(localized: "Mounted slides \(format)", comment: "Holder for mounted slides; %@ is the slide size")
            : format
    }

    /// Panel menu: "6×7 (50200403)".
    static func holderMenuTitle(_ holder: Holder) -> String {
        guard let reference = holder.reference else { return holderName(holder) }
        return "\(holderName(holder)) (\(reference))"
    }

    /// "57 × 70 mm (2¼ × 2.76″)", "57 × 57 / 57 × 42.5 mm (2¼ × 2¼ / 2¼ × 1⅔″)",
    /// or "—"; decimals in the locale's separator.
    static func holderApertures(_ holder: Holder) -> String {
        guard !holder.apertures.isEmpty else { return "—" }
        let sizes = holder.apertures.map {
            "\($0.width.formatted(.number.grouping(.never))) × \($0.height.formatted(.number.grouping(.never)))"
        }
        let inches = holder.inches.map { Holder.localizedDecimals("\($0.width) × \($0.height)") }
        return sizes.joined(separator: " / ") + " mm (" + inches.joined(separator: " / ") + "″)"
    }

    /// VoiceOver: "57 × 70 millimetres, 2¼ × 2.76 inches" (the ″ symbol is not
    /// read as inches).
    static func holderAperturesAccessibility(_ holder: Holder) -> String {
        guard !holder.apertures.isEmpty else { return holderApertures(holder) }
        let millimetres = holder.apertures.map {
            "\($0.width.formatted(.number.grouping(.never))) × \($0.height.formatted(.number.grouping(.never)))"
        }.joined(separator: " / ")
        let inches = holder.inches.map { Holder.localizedDecimals("\($0.width) × \($0.height)") }.joined(separator: " / ")
        return holderSizeAccessibility(millimetres: millimetres, inches: inches)
    }

    /// The inch equivalent of an opening typed in millimetres: "2.24 × 2.76″".
    static func holderInches(width: Double, height: Double) -> String {
        Holder.localizedDecimals("\(Holder.inches(width)) × \(Holder.inches(height))″")
    }

    /// VoiceOver label of `holderInches`.
    static func holderInchesAccessibility(width: Double, height: Double) -> String {
        let inches = Holder.localizedDecimals("\(Holder.inches(width)) × \(Holder.inches(height))")
        return String(localized: "\(inches) inches", comment: "VoiceOver: an opening in inches, e.g. “2.24 × 2.76 inches”")
    }

    private static func holderSizeAccessibility(millimetres: String, inches: String) -> String {
        String(localized: "\(millimetres) millimetres, \(inches) inches",
               comment: "VoiceOver: a holder opening, e.g. “57 × 70 millimetres, 2¼ × 2.76 inches”")
    }

    static func holderSeries(_ series: Holder.Series) -> String {
        switch series {
        case .standard: String(localized: "Supplied with the X1 and X5", comment: "Holder list section")
        case .common: String(localized: "Common series", comment: "Holder list section")
        case .custom: String(localized: "Custom", comment: "Holder list section")
        }
    }

    static func panelSection(_ section: PanelSection) -> String {
        switch section {
        case .original: String(localized: "Original", comment: "Panel section: the film")
        case .scan: String(localized: "panel.section.scan", defaultValue: "Scan",
                           comment: "Panel section: resolution, scale, sizes")
        case .exposure: String(localized: "Exposure", comment: "Panel section: share of the CCD range the preview uses")
        case .histogram: String(localized: "Histogram", comment: "Palette title")
        case .output: String(localized: "Output", comment: "Panel section: export")
        }
    }

    // MARK: Orientation (lot 1)

    static var rotateCounterclockwise: String {
        String(localized: "Rotate 90° Counterclockwise", comment: "Menu item and tooltip: orientation of the image")
    }
    static var rotateClockwise: String {
        String(localized: "Rotate 90° Clockwise", comment: "Menu item and tooltip: orientation of the image")
    }
    static var mirrorHorizontally: String {
        String(localized: "Flip Horizontal", comment: "Menu item and tooltip: mirror the image left to right")
    }

    // MARK: Exposure (lot 1)

    private static func percent(_ fraction: Double, digits: Int) -> String {
        fraction.formatted(.percent.precision(.fractionLength(digits)).grouping(.never))
    }

    /// The share of clipped pixels the text rounds to 0.1 % (below: "< 0.1 %").
    static let clippedShownFrom = 0.0005

    private static func clippedText(_ fraction: Double) -> String {
        guard fraction > 0, fraction < clippedShownFrom else { return percent(fraction, digits: 1) }
        return "< " + percent(0.001, digits: 1)
    }

    /// "83 % · 0.4 % clipped": the folded section and VoiceOver.
    static func exposureSummary(_ reading: ExposureReading) -> String {
        let clipped = clippedText(reading.clippedFraction)
        return String(localized: "\(percent(reading.usedRange, digits: 0)) · \(clipped) clipped",
                      comment: "Folded Exposure section: CCD range used, then share of clipped pixels")
    }

    /// "CCD range used 83 % · 0.4 % clipped", under the gauge.
    static func exposureLine(_ reading: ExposureReading) -> String {
        let clipped = clippedText(reading.clippedFraction)
        return String(localized: "CCD range used \(percent(reading.usedRange, digits: 0)) · \(clipped) clipped",
                      comment: "Exposure section, under the gauge")
    }

    static var exposureGaugeLabel: String {
        String(localized: "CCD range used", comment: "VoiceOver label of the exposure gauge")
    }

    static var exposureEmpty: String {
        String(localized: "Measured after each preview.", comment: "Exposure section before the first preview")
    }

    static var exposureHelp: String {
        String(localized: "Measured on the preview's raw CCD values, before any correction. Left: the noise floor; right: clipping. Provisional thresholds, to be measured on the X1.",
               comment: "Tooltip of the exposure gauge")
    }

    static var exposureZonesToggle: String {
        String(localized: "Show clipped and noise zones", comment: "Exposure section checkbox")
    }

    static var exposureZonesHelp: String {
        String(localized: "On the preview: clipped pixels in red, pixels near the noise floor in blue. Display only.",
               comment: "Tooltip of the exposure zones checkbox")
    }

    /// Advice under the gauge; hidden in lot 1 (it will point to quality modes).
    static func exposureAdvice(_ reading: ExposureReading) -> String? { nil }

    // MARK: Grid (lot 1)

    static var gridTool: String { String(localized: "Grid", comment: "Tool column button: grid over the image") }
    static var gridHidden: String {
        String(localized: "grid.hidden", defaultValue: "Hidden", comment: "VoiceOver value of the grid button (the grid, feminine in French)")
    }
    static var showGrid: String { String(localized: "Show Grid", comment: "Menu item (Image menu)") }
    static var hideGrid: String { String(localized: "Hide Grid", comment: "Menu item (Image menu)") }
    static var fineGridSpacing: String {
        String(localized: "Fine Grid Squares", comment: "Image menu > Grid: submenu, number of squares across the image")
    }

    static func gridKind(_ kind: GridKind) -> String {
        switch kind {
        case .thirds: String(localized: "Thirds", comment: "Grid kind")
        case .fine: String(localized: "Fine Grid", comment: "Grid kind")
        case .centre: String(localized: "Centre Cross", comment: "Grid kind")
        }
    }

    /// A tooltip with its shortcut: "Rotate 90° Clockwise (⌘])".
    static func withShortcut(_ title: String, _ shortcut: String) -> String {
        String(localized: "\(title) (\(shortcut))", comment: "Tooltip: an action and its keyboard shortcut")
    }

    /// VoiceOver description of the orientation, e.g. "Turned 90° clockwise, mirrored".
    static func orientationDescription(_ orientation: Orientation) -> String {
        let turn = switch orientation.quarterTurns {
        case 1: String(localized: "Turned 90° clockwise", comment: "VoiceOver: orientation of the image")
        case 2: String(localized: "Turned 180°", comment: "VoiceOver: orientation of the image")
        case 3: String(localized: "Turned 90° counterclockwise", comment: "VoiceOver: orientation of the image")
        default: String(localized: "Not turned", comment: "VoiceOver: orientation of the image")
        }
        guard orientation.mirrored else { return turn }
        return String(localized: "\(turn), mirrored", comment: "VoiceOver: orientation of the image; %@ is the turn")
    }

    /// The values a folded section shows next to its title; empty: none.
    @MainActor
    static func panelSummary(_ section: PanelSection, model: AppModel) -> String {
        let settings = model.scanSettings
        switch section {
        case .original:
            let film = filmType(settings.filmType)
            guard let holder = model.selectedHolder else { return film }
            return "\(film) · \(holderName(holder))"
        case .scan:
            let ppi = String(localized: "ppi", comment: "Unit: pixels per inch")
            let scale = (Double(settings.scalePercent) / 100).formatted(.percent.grouping(.never))
            return "\(settings.resolution.formatted(.number.grouping(.never))) \(ppi) · \(scale)"
        case .exposure:
            return model.exposure.map(exposureSummary) ?? ""
        case .histogram:
            return ""
        case .output:
            return exportFormat(model.exportSettings.format)
        }
    }

    static func filmType(_ film: FilmType) -> String {
        switch film {
        case .positive: String(localized: "Positive", comment: "Film type")
        case .colorNegative: String(localized: "Colour negative", comment: "Film type")
        case .blackAndWhiteNegative: String(localized: "B&W negative", comment: "Film type")
        }
    }

    static func exportFormat(_ format: TIFFFormat) -> String {
        switch format {
        case .rgb16: String(localized: "RGB 16-bit linear", comment: "Export format (short: shown whole in the panel menu)")
        case .rgb8: String(localized: "RGB 8-bit sRGB", comment: "Export format (short: shown whole in the panel menu)")
        case .gray16: String(localized: "Grey 16-bit linear", comment: "Export format (short: shown whole in the panel menu)")
        case .gray8: String(localized: "Grey 8-bit sRGB", comment: "Export format (short: shown whole in the panel menu)")
        }
    }

    /// Tooltip and VoiceOver help of the export format menu.
    static var exportFormatHelp: String {
        String(localized: "RGB 16-bit: the scanner's linear values after the white and dark references, without profile. Grey 16-bit: linear luminance (provisional weights). 8-bit: sRGB curve and profile (provisional).",
               comment: "Tooltip of the export format menu of the settings panel")
    }

    static func compression(_ compression: TIFFCompression) -> String {
        switch compression {
        case .none: String(localized: "compression.none", defaultValue: "None", comment: "TIFF compression: none (feminine in French)")
        case .lzw: String(localized: "LZW", comment: "TIFF compression")
        case .deflate: String(localized: "ZIP", comment: "TIFF compression (Deflate)")
        }
    }

    static func estimatedSize(_ bytes: Int) -> String {
        let size = Int64(bytes).formatted(.byteCount(style: .file))
        return String(localized: "≈ \(size) before compression", comment: "Bottom bar: estimated export size")
    }

    /// Channel letter of the bottom bar: R G B in English, R V B in French.
    static func channelLetter(_ channel: Int) -> String {
        switch channel {
        case 0: String(localized: "channel.red", defaultValue: "R", comment: "Bottom bar: red channel letter")
        case 1: String(localized: "channel.green", defaultValue: "G", comment: "Bottom bar: green channel letter")
        default: String(localized: "channel.blue", defaultValue: "B", comment: "Bottom bar: blue channel letter")
        }
    }

    /// VoiceOver label of one channel of the bottom bar: "Red 149".
    static func channelSpoken(_ channel: Int, value: String) -> String {
        switch channel {
        case 0: String(localized: "channel.red.spoken", defaultValue: "Red \(value)", comment: "VoiceOver: red value under the pointer")
        case 1: String(localized: "channel.green.spoken", defaultValue: "Green \(value)", comment: "VoiceOver: green value under the pointer")
        default: String(localized: "channel.blue.spoken", defaultValue: "Blue \(value)", comment: "VoiceOver: blue value under the pointer")
        }
    }

    /// VoiceOver label of the bottom bar without a pixel under the pointer.
    static var noPixelSpoken: String {
        String(localized: "channel.none.spoken", defaultValue: "No pixel under the pointer", comment: "VoiceOver: bottom bar without a pixel under the pointer")
    }

    /// Bottom bar without a pixel under the pointer.
    static var noPixelReading: String {
        String(localized: "channel.none", defaultValue: "R – G – B –", comment: "Bottom bar: no pixel under the pointer")
    }

    static func rgbValue(_ sample: UInt16, unit: RGBUnit) -> String {
        let value = unit.value(sample)
        return switch unit {
        case .eightBit, .sixteenBit: Int(value).formatted(.number.grouping(.never))
        case .percent: (value / 100).formatted(.percent.precision(.fractionLength(1)))
        }
    }

    static func rgbUnit(_ unit: RGBUnit) -> String {
        switch unit {
        case .eightBit: String(localized: "0–255", comment: "RGB unit")
        case .percent: String(localized: "Percent", comment: "RGB unit")
        case .sixteenBit: String(localized: "16-bit (0–65535)", comment: "RGB unit")
        }
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
        case .custom: String(localized: "Custom…", comment: "Background around the image: chosen with the colour panel")
        }
    }

    static func startupZoom(_ zoom: StartupZoom) -> String {
        switch zoom {
        case .fit: String(localized: "Zoom to Fit", comment: "Menu item")
        case .actualSize: String(localized: "Actual Size (100 %)", comment: "Setting: zoom at launch")
        }
    }

    /// Label of a file name token button; the template stores the English placeholder.
    static func exportToken(_ token: ExportToken) -> String {
        switch token {
        case .roll: String(localized: "Roll", comment: "File name token button: roll name")
        case .frame: String(localized: "Frame", comment: "File name token button: frame number")
        case .date: String(localized: "Date", comment: "File name token button")
        case .time: String(localized: "Time", comment: "File name token button")
        case .counter: String(localized: "Number", comment: "File name token button: counter {n}")
        }
    }

    static func startupSource(_ startup: StartupSource) -> String {
        switch startup {
        case .virtual: source(.virtual)
        case .real: source(.real)
        case .last: String(localized: "Last chosen", comment: "Setting: scanner source at launch, the last source chosen in the interface")
        }
    }
}
