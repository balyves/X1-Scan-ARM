// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import X1Image
import X1ScanCore

/// The settings panel on the right (lot 1): Original, Scan, Histogram,
/// Output, and the Preview and Scan buttons. Small controls everywhere. All
/// sections follow the compact panel conventions
/// (.claude/skills/compact-settings-panel/SKILL.md); a folded section shows
/// a summary of its values next to its title.
struct SettingsPanelView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section(.original) { OriginalSection(model: model) }
                    section(.scan) { ScanSection(model: model) }
                    section(.histogram) { HistogramView(model: model) }
                    section(.output) {
                        OutputSection(model: model)
                    }
                }
                .padding(.bottom, 8)
            }
            Divider()
            VStack(spacing: 6) {
                ActionButtons(model: model)
                if let block = model.toolbar.previewBlock, block != .busy {
                    Text(Strings.previewBlockShort(block))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
        }
        .controlSize(.small)
        .font(.callout)
    }

    private func section(_ section: PanelSection, @ViewBuilder content: @escaping () -> some View) -> some View {
        CompactSection(Strings.panelSection(section), summary: Strings.panelSummary(section, model: model),
                       foldTexts: Strings.foldTexts, isExpanded: model.panel.expansion(of: section),
                       content: content)
    }
}

private struct OriginalSection: View {
    @Bindable var model: AppModel

    /// Tooltip of both rows: saved, but not sent to the scanner yet.
    private static var notYet: String {
        String(localized: "Saved; applied to the scanner with real scans (a later step).",
               comment: "Tooltip of the Film and Holder rows of the settings panel")
    }

    var body: some View {
        let film = String(localized: "Film", comment: "Panel label: film type")
        let holder = String(localized: "Holder", comment: "Panel label: film holder")
        CompactControlRow(film, help: Self.notYet) {
            CompactPopUp(film, help: Self.notYet, selection: $model.scanSettings.filmType,
                         items: FilmType.allCases.map { .init(Strings.filmType($0), $0) })
        }
        CompactControlRow(holder, help: Self.notYet) {
            HStack(spacing: CompactPanelMetrics.columnSpacing) {
                CompactPopUp(holder, help: Self.notYet,
                             selection: Binding { model.selectedHolder?.id } set: { model.scanSettings.holderID = $0 },
                             sections: [
                                [.init(String(localized: "Not specified", comment: "Holder placeholder"), nil)],
                                model.holders.ownedHolders.map { .init(Strings.holderMenuTitle($0), Optional($0.id)) },
                             ])
                Button {
                    NSApp.sendAction(#selector(AppDelegate.showHolderSettings(_:)), to: nil, from: nil)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.borderless)
                .help(Text("Choose the holders shown here (Settings > Holders)", comment: "Tooltip"))
                .accessibilityLabel(Text("Edit Holders", comment: "VoiceOver label of the … button next to the holder menu"))
            }
        }
    }
}

/// Scan section (lot 1): resolution, scale, input, output. The Main /
/// Advanced tabs of step 3 are gone; they will come back with corrections.
private struct ScanSection: View {
    @Bindable var model: AppModel

    private static let resolutionFormat = CompactValueFormat(
        integers: ScanSettings.resolutionRange, defaultValue: ScanSettings.defaultResolution,
        sliderScale: .logarithmic)
    private static let scaleFormat = CompactValueFormat(
        integers: ScanSettings.scaleRange, defaultValue: ScanSettings.defaultScalePercent)

    var body: some View {
        VStack(alignment: .leading, spacing: CompactPanelMetrics.rowSpacing) {
            CompactSliderRow(
                value: Binding(rounding: $model.scanSettings.resolution),
                format: Self.resolutionFormat,
                texts: Strings.sliderRow(label: String(localized: "Resolution", comment: "Panel label"),
                                         unit: String(localized: "ppi", comment: "Unit: pixels per inch"),
                                         format: Self.resolutionFormat))
            CompactSliderRow(
                value: Binding(rounding: $model.scanSettings.scalePercent),
                format: Self.scaleFormat,
                texts: Strings.sliderRow(label: String(localized: "Scale", comment: "Panel label"),
                                         unit: "%", format: Self.scaleFormat))
            CompactInfoRow(String(localized: "Input", comment: "Panel label: input size"),
                           value: pixels(model.inputPixelSize), help: Self.sizesNote)
            CompactInfoRow(String(localized: "Output", comment: "Panel label: output size"),
                           value: pixels(model.inputPixelSize.map {
                               let scale = Double(model.scanSettings.scalePercent) / 100
                               return (Int((Double($0.width) * scale).rounded()), Int((Double($0.height) * scale).rounded()))
                           }))
                .help(Self.sizesNote)  // tooltip only: VoiceOver gets the hint once, on Input
        }
    }

    /// Tooltip of the size rows.
    private static var sizesNote: String {
        String(localized: "Sizes in preview pixels; millimetres once the preview resolution is confirmed. Resolution, scale and crop apply to the scan (a later step): Export Preview writes the whole preview.",
               comment: "Tooltip and VoiceOver hint of the Input and Output size rows of the settings panel")
    }

    private func pixels(_ size: (width: Int, height: Int)?) -> String {
        guard let size else { return "—" }
        return String(localized: "\(size.width) × \(size.height) px", comment: "Image size in pixels")
    }
}

private struct OutputSection: View {
    @Bindable var model: AppModel

    var body: some View {
        let format = String(localized: "Format", comment: "Export palette label")
        let compression = String(localized: "Compression", comment: "Panel label")
        let name = String(localized: "Name", comment: "Panel label: file name template")
        CompactControlRow(format, help: Strings.exportFormatHelp) {
            CompactPopUp(format, help: Strings.exportFormatHelp, selection: $model.exportSettings.format,
                         items: TIFFFormat.allCases.map { .init(Strings.exportFormat($0), $0) })
        }
        if model.exportSettings.format.usesSRGBCurve {
            // A warning: stays visible, not in a tooltip.
            CompactDetailRow {
                Label(String(localized: "8 bits: sRGB curve and profile (provisional); fewer levels than 16-bit linear.",
                             comment: "Export warning for 8-bit formats"),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        CompactControlRow(compression) {
            CompactPopUp(compression, selection: $model.exportSettings.compression,
                         items: TIFFCompression.allCases.map { .init(Strings.compression($0), $0) })
        }
        CompactControlRow(name) {
            HStack(spacing: CompactPanelMetrics.columnSpacing) {
                CompactPopUp(name, selection: $model.exportSettings.nameTemplate,
                             items: templates.map { .init($0, $0) })
                // Same small button as the holder row: the menu keeps the room.
                Button {
                    NSApp.sendAction(#selector(AppDelegate.showExportSettings(_:)), to: nil, from: nil)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.borderless)
                .help(Text("Edit the name templates (Settings > Export)", comment: "Tooltip of the … button next to the name template menu"))
                .accessibilityLabel(Text("Edit Name Templates", comment: "VoiceOver label of the … button next to the name template menu"))
            }
        }
        // The name the template gives now: the immediate result of the row above.
        CompactDetailRow {
            Text(ExportNameHelp.next(model))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(ExportNameHelp.next(model))  // whole name when truncated
        }
        let folderLabel = String(localized: "Folder", comment: "Export palette label")
        let folderName = model.exportSettings.folder.map {
            FileManager.default.displayName(atPath: $0.path(percentEncoded: false))  // localized ("Bureau")
        } ?? String(localized: "None", comment: "No export folder chosen")
        CompactControlRow(folderLabel) {
            HStack(spacing: CompactPanelMetrics.columnSpacing) {
                Text(folderName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(model.exportSettings.folder?.path(percentEncoded: false) ?? "")
                    // The row's visible label is hidden from VoiceOver: name the value here.
                    .accessibilityLabel(folderLabel)
                    .accessibilityValue(folderName)
                Button(String(localized: "Choose…", comment: "Button")) {
                    ExportFolderPanel.choose(for: NSApp.keyWindow, model: model)
                }
            }
        }
        let wholePreviewNote = String(localized: "Exports the whole preview, without the crop.",
                                      comment: "Panel note under Export Preview, shown only while a crop is drawn")
        CompactDetailRow {
            Button(String(localized: "Export Preview", comment: "Panel button")) { model.export() }
                .disabled(!model.toolbar.canExport)
                .help(Text("Export the preview with these settings (⇧⌘E)", comment: "Tooltip"))
                // VoiceOver hears the note with the button, before using it.
                .accessibilityHint(model.cropRect != nil ? wholePreviewNote : "")
        }
        if model.cropRect != nil {
            // Visible without hovering: with a crop drawn, one could expect a cropped file.
            CompactDetailRow {
                Text(wholePreviewNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)  // already the button's hint
            }
        }
        switch model.lastExport {
        case .success(let url):
            CompactDetailRow {
                HStack(spacing: CompactPanelMetrics.columnSpacing) {
                    Text(url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                    Button(String(localized: "Show in Finder", comment: "Button")) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        case .failure(let error):
            CompactDetailRow {
                Text(Strings.exportError(error)).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case nil:
            EmptyView()
        }
    }

    /// The current template first, then the presets.
    private var templates: [String] {
        var list = [model.exportSettings.nameTemplate]
        for preset in ExportSettings.presetTemplates where !list.contains(preset) { list.append(preset) }
        return list
    }
}

/// Preview (Stop while a preview runs) and Scan.
private struct ActionButtons: View {
    @Bindable var model: AppModel

    var body: some View {
        let toolbar = model.toolbar
        HStack(spacing: 8) {
            if toolbar.canStop || toolbar.isStopping {
                Button {
                    model.stop()
                } label: {
                    Text("Stop", comment: "Menu item and toolbar button").frame(maxWidth: .infinity)
                }
                .tint(toolbar.stopIsProminent ? .red : nil)
                .disabled(toolbar.isStopping)
                .help(model.session.kind == .scan
                      ? String(localized: "Stop the scan (⌘. or Esc)", comment: "Tooltip")
                      : String(localized: "Stop the preview (⌘. or Esc)", comment: "Tooltip"))
            } else {
                Button {
                    // Through the window: on the real X1 it asks for the confirmation first.
                    NSApp.sendAction(#selector(MainWindowController.startPreview(_:)), to: nil, from: nil)
                } label: {
                    Text("Preview", comment: "Menu item and toolbar button").frame(maxWidth: .infinity)
                }
                .disabled(!toolbar.canPreview)
                .tint(toolbar.canPreview ? nil : .gray)  // a disabled prominent button stays tinted in dark mode
                .help(toolbar.previewBlock.map(Strings.previewBlockShort)
                      ?? (toolbar.previewNeedsConfirmation
                          ? String(localized: "Run FlexColor's captured preview on the real X1 (⌘R)", comment: "Tooltip")
                          : String(localized: "Run a preview on the virtual X1 (⌘R)", comment: "Tooltip")))
            }
            Button {
                NSApp.sendAction(#selector(MainWindowController.startScan(_:)), to: nil, from: nil)
            } label: {
                Text("Scan", comment: "Toolbar button").frame(maxWidth: .infinity)
            }
            .disabled(!toolbar.canScan)
            .tint(toolbar.canScan ? nil : .gray)  // a disabled prominent button stays tinted in dark mode
            .help(toolbar.scanBlock.map(Strings.scanBlock)
                  ?? (toolbar.scanNeedsConfirmation
                      ? String(localized: "Run FlexColor's captured 2 000 ppi scan on the real X1", comment: "Tooltip")
                      : String(localized: "Run FlexColor's captured 2 000 ppi scan on the virtual X1", comment: "Tooltip")))
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
    }
}
