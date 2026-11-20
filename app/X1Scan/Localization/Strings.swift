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
    static func sliderRow(label: String, unit: String, format: CompactValueFormat,
                          help: String? = nil) -> CompactSliderRow.Texts {
        let defaultValue = format.text(for: format.defaultValue, locale: .current)
        // No-break space: the value and its unit stay on one line.
        let defaultText = unit.isEmpty ? defaultValue : "\(defaultValue)\u{00A0}\(unit)"
        return CompactSliderRow.Texts(
            label: label,
            unit: unit,
            resetAction: String(localized: "Reset to Default", comment: "VoiceOver action of a panel slider row"),
            resetHelp: String(localized: "Double-click to reset to \(defaultText)",
                              comment: "Tooltip of a panel slider row label; the default value with its unit"),
            help: help)
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
        case .straighten: String(localized: "tool.straighten", defaultValue: "Straightening Rule",
                                 comment: "Tool: draw a line along what should be horizontal or vertical")
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
        case .framing: String(localized: "panel.section.framing", defaultValue: "Framing",
                              comment: "Panel section: orientation, proportions, angle, straightening, grid")
        case .scan: String(localized: "panel.section.scan", defaultValue: "Scan",
                           comment: "Panel section: resolution, scale, sizes")
        case .exposure: String(localized: "Exposure", comment: "Panel section: share of the CCD range the preview uses")
        case .histogram: String(localized: "Histogram", comment: "Palette title")
        case .output: String(localized: "Output", comment: "Panel section: export")
        }
    }

    // MARK: Panel tabs (lot 1b)

    static func panelTab(_ tab: PanelTab) -> String {
        switch tab {
        case .prepare: String(localized: "panel.tab.prepare", defaultValue: "Prepare",
                              comment: "Settings panel tab: the film, orientation and framing")
        case .scan: String(localized: "panel.tab.scan", defaultValue: "Scan",
                           comment: "Settings panel tab: resolution, scale, sizes")
        case .develop: String(localized: "panel.tab.develop", defaultValue: "Develop",
                              comment: "Settings panel tab: corrections (a later version; not shown yet)")
        case .output: String(localized: "panel.tab.output", defaultValue: "Output",
                             comment: "Settings panel tab: export")
        }
    }

    /// Tooltip of a tab, without its shortcut (composed from the tab's place, as the menu's).
    static func panelTabHelp(_ tab: PanelTab) -> String {
        switch tab {
        case .prepare: String(localized: "Film, holder, orientation and framing",
                              comment: "Tooltip of the Prepare tab of the settings panel")
        case .scan: String(localized: "Resolution, scale and sizes of the scan",
                           comment: "Tooltip of the Scan tab of the settings panel")
        case .develop: String(localized: "Corrections of the image", comment: "Tooltip of the Develop tab (not shown yet)")
        case .output: String(localized: "Format, name and folder of the exported file",
                             comment: "Tooltip of the Output tab of the settings panel")
        }
    }

    /// Shortcut of a visible tab: ⌥⌘1, ⌥⌘2…, in the tab bar's order (the View menu's too).
    static func panelTabShortcut(_ tab: PanelTab) -> String? {
        PanelTab.visible.firstIndex(of: tab).map { "⌥⌘\($0 + 1)" }
    }

    /// View menu: "Prepare Tab".
    static func panelTabMenuItem(_ tab: PanelTab) -> String {
        switch tab {
        case .prepare: String(localized: "Prepare Tab", comment: "View menu item: show the Prepare tab of the settings panel")
        case .scan: String(localized: "Scan Tab", comment: "View menu item: show the Scan tab of the settings panel")
        case .develop: String(localized: "Develop Tab", comment: "View menu item (not shown yet)")
        case .output: String(localized: "Output Tab", comment: "View menu item: show the Output tab of the settings panel")
        }
    }

    /// Small title above Histogram and Exposure, shown in capitals.
    static var informationTitle: String {
        String(localized: "panel.information", defaultValue: "Information",
               comment: "Settings panel: small title of the area common to every tab (histogram, exposure); shown in capitals")
    }

    static var panelTabsLabel: String {
        String(localized: "Settings Panel Tabs", comment: "VoiceOver label of the tab bar at the top of the settings panel")
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

    /// The tool column's button for the exposure zones (VoiceOver label).
    static var exposureZonesTool: String {
        String(localized: "Exposure Zones", comment: "Tool column button: clipped and noise zones over the preview")
    }
    static var exposureZonesShown: String { String(localized: "zones.shown", defaultValue: "Shown", comment: "VoiceOver value of the exposure zones button (zones, feminine plural in French)") }
    static var exposureZonesHidden: String { String(localized: "zones.hidden", defaultValue: "Hidden", comment: "VoiceOver value of the exposure zones button (zones, feminine plural in French)") }

    static var exposureZonesHelp: String {
        String(localized: "On the preview: clipped pixels in red, pixels near the noise floor in violet. Display only.",
               comment: "Tooltip of the exposure zones checkbox of the Exposure section and of the tool column's button")
    }

    /// Advice under the gauge; hidden in lot 1 (it will point to quality modes).
    static func exposureAdvice(_ reading: ExposureReading) -> String? { nil }

    // MARK: Tooltips (lot 1b): one sentence for each control of the panel and each tool

    static var filmHelp: String {
        String(localized: "Type of film in the holder; saved, applied to the scanner with real scans later.",
               comment: "Tooltip of the Film menu of the settings panel")
    }
    static var holderHelp: String {
        String(localized: "Film holder in the scanner; saved, applied to the scanner with real scans later.",
               comment: "Tooltip of the Holder menu of the settings panel")
    }
    static var resolutionHelp: String {
        String(localized: "Scan resolution in pixels per inch; saved, the scan stays at 2 000 ppi for now.",
               comment: "Tooltip of the Resolution slider and field of the settings panel")
    }
    static var scaleHelp: String {
        String(localized: "Size of the output relative to the input, in percent; saved, applied in a later step.",
               comment: "Tooltip of the Scale slider and field of the settings panel")
    }
    static var angleHelp: String {
        String(localized: "Fine rotation of the image in degrees; ← → in crop mode, ⇧ by multiples of 5°.",
               comment: "Tooltip of the Angle slider and field of the Framing section")
    }
    static var orientationHelp: String {
        String(localized: "Quarter turns and mirror of the image, for the display and the export.",
               comment: "Tooltip of the Orientation label of the Framing section")
    }
    static var straightenRowHelp: String {
        String(localized: "Straighten the image with the rule (R); from the frame's edges in a later version.",
               comment: "Tooltip of the Straighten label of the Framing section")
    }
    static var gridTintHelp: String {
        String(localized: "Colour and opacity of the grid lines; display only.", comment: "Tooltip of the Tint label of the Framing section")
    }
    static var cropCustomWidthHelp: String {
        String(localized: "Width of the ratio (13 in 13 × 18)", comment: "Tooltip of the width field of the custom proportions")
    }
    static var cropCustomHeightHelp: String {
        String(localized: "Height of the ratio (18 in 13 × 18)", comment: "Tooltip of the height field of the custom proportions")
    }
    static var folderHelp: String {
        String(localized: "Folder where Export saves the files.", comment: "Tooltip of the Folder row of the settings panel")
    }
    static var compressionHelp: String {
        String(localized: "Lossless compression of the TIFF file.", comment: "Tooltip of the Compression menu of the settings panel")
    }
    static var nameTemplateHelp: String {
        String(localized: "Template of the file name; {roll}, {frame}… are replaced on export.",
               comment: "Tooltip of the Name menu of the settings panel; {roll} and {frame} are tokens, not translated")
    }
    static var chooseFolderHelp: String {
        String(localized: "Choose the folder where Export writes the files.", comment: "Tooltip of the Choose… button of the Folder row")
    }
    static var showInFinderHelp: String {
        String(localized: "Show the exported file in the Finder.", comment: "Tooltip of the Show in Finder link after an export")
    }
    static var histogramHelp: String {
        String(localized: "Levels of red, green and blue in the image shown, inside the crop frame if there is one.",
               comment: "Tooltip of the histogram")
    }
    static var logarithmicHelp: String {
        String(localized: "Logarithmic scale: shows small counts next to large peaks.", comment: "Tooltip of the histogram's Logarithmic checkbox")
    }
    static var gridButtonHelp: String {
        String(localized: "Click: show or hide (⌘') · Right click: kind, colour, opacity",
               comment: "Tooltip of the Grid button of the tool column")
    }

    /// Tooltip of a tool of the column, with its key.
    static func toolHelp(_ tool: Tool) -> String {
        switch tool {
        case .hand: String(localized: "Hand: move the image (H, or hold Space)", comment: "Tooltip of the Hand tool")
        case .zoom: String(localized: "Zoom: click to zoom in, ⌥-click to zoom out (Z)", comment: "Tooltip of the Zoom tool (magnifier)")
        case .crop: String(localized: "Crop: draw and adjust the frame, in Prepare › Framing (C)", comment: "Tooltip of the Crop tool")
        case .straighten: String(localized: "Straightening Rule: draw a line along what should be horizontal or vertical (R)",
                                 comment: "Tooltip of the Straightening Rule tool")
        }
    }

    // MARK: Framing: crop and straighten (lot 1, lot 1b)

    /// An angle in degrees with a true minus sign: whole degrees ("−1°"),
    /// or tenths when the straightening rule measured them ("−1.3°", lot 1b).
    static func angle(_ degrees: Double) -> String {
        let text = abs(degrees).formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
        return (degrees < -0.05 ? "\u{2212}" : "") + text + "°"
    }

    static var cropDone: String { String(localized: "Done", comment: "Button: leave the crop tool") }
    static var cropDoneHelp: String {
        String(localized: "Keep the changes and go back to the previous tool (↩); Esc cancels them",
               comment: "Help of the Done button of the crop options")
    }
    static var framingReset: String {
        String(localized: "Reset Framing", comment: "VoiceOver label of the Reset button (icon) of the Framing section: orientation, proportions, angle and frame back to the original")
    }
    /// Name of the action in Edit > Undo / Redo (a noun: "Undo Framing Reset").
    static var framingResetAction: String {
        String(localized: "Framing Reset", comment: "Undo action name, after Undo / Redo in the Edit menu (a noun)")
    }
    static var framingResetHelp: String {
        String(localized: "Reset the orientation, proportions, angle and frame to the original (⌘Z undoes it)",
               comment: "Tooltip of the Reset button of the Framing section")
    }
    static var cropProportions: String { String(localized: "Proportions", comment: "Crop options label: aspect ratio") }
    static var cropProportionsHelp: String {
        String(localized: "Proportions of the frame, width × height as named: 6×7 is 6 wide and 7 high; X exchanges them.",
               comment: "Tooltip of the crop proportions menu")
    }
    static var cropFree: String { String(localized: "Free", comment: "Crop proportions: any") }
    static var cropOriginal: String { String(localized: "crop.original", defaultValue: "Original", comment: "Crop proportions: those of the image") }
    static var cropCustom: String { String(localized: "Custom…", comment: "Crop proportions: type a ratio") }
    static var cropCustomTitle: String { String(localized: "Custom Proportions", comment: "Title of the custom ratio popover") }
    static var cropCustomWidth: String { String(localized: "Width", comment: "Custom ratio field") }
    static var cropCustomHeight: String { String(localized: "Height", comment: "Custom ratio field") }
    static var cropSwap: String { String(localized: "Swap Width and Height", comment: "Crop options button (key X)") }
    static var cropSwapped: String { String(localized: "Exchanged", comment: "VoiceOver value of the swap button: width and height exchanged") }
    static var cropAsNamed: String { String(localized: "As named", comment: "VoiceOver value of the swap button: width × height as named") }
    static var cropLock: String { String(localized: "Lock Proportions", comment: "Crop options toggle") }
    static var cropLockHelp: String {
        String(localized: "Lock the proportions: the frame keeps its shape while it is resized.", comment: "Tooltip of the crop lock")
    }
    static var cropAngle: String { String(localized: "Angle", comment: "Crop options label: fine rotation") }
    static var cropStraighten: String { String(localized: "Straighten", comment: "Crop options label") }
    static var cropRuleHelp: String {
        String(localized: "Draw a line along what should be horizontal or vertical", comment: "Tooltip of the Straightening Rule button")
    }
    static var cropRule: String { String(localized: "crop.rule", defaultValue: "Rule", comment: "Crop options button: the straightening rule (short)") }
    static var cropAutoEdges: String { String(localized: "Auto (Edges)", comment: "Crop options button, not available yet") }
    static var cropAutoEdgesHelp: String {
        String(localized: "Straighten from the frame's edges on the film: in a later version.", comment: "Tooltip of the disabled Auto (Edges) button")
    }
    static var cropGridNone: String { String(localized: "crop.grid.none", defaultValue: "None", comment: "Crop grid menu: no grid") }
    static var cropGridHelp: String {
        String(localized: "Grid shown inside the frame while cropping; display only.", comment: "Tooltip of the crop grid menu")
    }
    static var cropConstrain: String {
        String(localized: "Constrain to image", comment: "Crop options checkbox")
    }
    static var cropConstrainHelp: String {
        String(localized: "Keeps the frame entirely inside the turned image, with no empty corners.", comment: "Tooltip of the constrain checkbox")
    }
    static var exportHelp: String {
        String(localized: "Export the image shown, turned, straightened and cropped, with its recipe (⇧⌘E). A saved scan is never replaced: its versions are named _v1, _v2…",
               comment: "Tooltip of the panel's Export button")
    }
    static var ok: String { String(localized: "OK", comment: "Button") }
    static var cancel: String { String(localized: "Cancel", comment: "Button") }

    /// A film format or ratio as named: "6×4.5".
    static func ratio(_ width: Double, _ height: Double) -> String {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2)).grouping(.never)
        return "\(width.formatted(format))×\(height.formatted(format))"
    }

    /// Next to the rule: "−1.3° · horizontal".
    static func straightenLabel(angle degrees: Double, axis: Straighten.Axis) -> String {
        switch axis {
        case .horizontal:
            String(localized: "\(angle(degrees)) · horizontal", comment: "Label next to the straightening rule: angle applied")
        case .vertical:
            String(localized: "\(angle(degrees)) · vertical", comment: "Label next to the straightening rule: angle applied")
        }
    }

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

    static var gridTint: String { String(localized: "Tint", comment: "Framing section label: colour and opacity of the grid lines") }
    static var gridColorHelp: String {
        String(localized: "Colour of the grid lines, on the image and in the crop frame; display only.",
               comment: "Tooltip of the grid colour menu of the Framing section")
    }
    static var gridOpacityHelp: String {
        String(localized: "Opacity of the grid lines; display only.", comment: "Tooltip of the grid opacity menu of the Framing section")
    }
    static var gridColorMenu: String { String(localized: "Grid Colour", comment: "Image menu and grid button's context menu: submenu of line colours") }
    static var gridOpacityMenu: String { String(localized: "Grid Opacity", comment: "Image menu and grid button's context menu: submenu of line opacities") }

    static func gridColor(_ color: GridColor) -> String {
        switch color {
        case .green: String(localized: "grid.color.green", defaultValue: "Green", comment: "Grid line colour (Image menu and grid button's context menu)")
        case .pink: String(localized: "grid.color.pink", defaultValue: "Pink", comment: "Grid line colour (Image menu and grid button's context menu)")
        case .white: String(localized: "grid.color.white", defaultValue: "White", comment: "Grid line colour (Image menu and grid button's context menu)")
        case .black: String(localized: "grid.color.black", defaultValue: "Black", comment: "Grid line colour (Image menu and grid button's context menu)")
        }
    }

    /// "70 %", in the locale's style.
    static func gridOpacity(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)).grouping(.never))
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
        case .framing:
            return framingSummary(model.recipe)
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

    /// Framing folded: "6×7 · −1° · 90°", the proportions as named, then the
    /// fine angle and the quarter turns when there are any, and the mirror.
    static func framingSummary(_ recipe: Recipe) -> String {
        var parts: [String] = []
        switch recipe.crop.aspect {
        case .free: parts.append(cropFree)
        case .original: parts.append(cropOriginal)
        case .ratio(let width, let height): parts.append(ratio(width, height))
        }
        if recipe.crop.angle != 0 { parts.append(angle(recipe.crop.angle)) }
        let turns = recipe.orientation.quarterTurns
        if turns != 0 { parts.append("\(turns * 90)°") }
        if recipe.orientation.mirrored {
            parts.append(String(localized: "mirrored", comment: "Framing section summary: the image is mirrored"))
        }
        return parts.joined(separator: " · ")
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
