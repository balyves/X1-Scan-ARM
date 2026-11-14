// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import X1Image
import X1ScanCore

/// The settings panel on the right (step 3, after Epson Scan 2): Scanner,
/// Original, Main / Advanced tabs, Output, and the Preview and Scan buttons.
/// Small controls everywhere, as in Xcode's inspectors.
struct SettingsPanelView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PanelSectionView(model: model, section: .scanner, title: Strings.panelSection(.scanner)) {
                        ScannerSection(model: model)
                    }
                    PanelSectionView(model: model, section: .original, title: Strings.panelSection(.original)) {
                        OriginalSection(model: model)
                    }
                    PanelSectionView(model: model, section: .settings, title: Strings.panelSection(.settings)) {
                        TabsSection(model: model)
                    }
                    PanelSectionView(model: model, section: .output, title: Strings.panelSection(.output)) {
                        OutputSection(model: model)
                    }
                }
                .padding(.bottom, 8)
            }
            Divider()
            ActionButtons(model: model)
                .padding(10)
        }
        .controlSize(.small)
        .font(.callout)
    }
}

/// A foldable section with a small header.
private struct PanelSectionView<Content: View>: View {
    @Bindable var model: AppModel
    let section: PanelSection
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        let folded = model.panel.layout.isFolded(section)
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy(duration: 0.15)) { model.panel.toggleFolded(section) }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(folded ? 0 : 90))
                        .foregroundStyle(.secondary)
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(folded ? Text("Collapsed", comment: "Palette state") : Text("Expanded", comment: "Palette state"))
            if !folded {
                content()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        Divider().padding(.horizontal, 8)
    }
}

/// Label and control on one row, labels aligned.
private struct PanelRow<Control: View>: View {
    let label: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
            control().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ScannerSection: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelRow(label: String(localized: "Source", comment: "Panel label: scanner source")) {
                Picker(String(localized: "Source", comment: "Panel label: scanner source"), selection: $model.source) {
                    ForEach(ScannerSourceKind.allCases, id: \.self) { Text(Strings.source($0)).tag($0) }
                }
                .labelsHidden()
                .disabled(model.session.isBusy)
            }
            PanelRow(label: String(localized: "State", comment: "Scanner information label")) {
                Text(Strings.statusDetail(model.statusLine, session: model.session)).lineLimit(2)
            }
            HStack {
                Button(String(localized: "Read Identity", comment: "Menu item and button")) {
                    NSApp.sendAction(#selector(AppDelegate.readIdentity(_:)), to: nil, from: nil)
                }
                .disabled(model.source == .real && model.realStatus == .reading)
                Button(String(localized: "Information…", comment: "Panel button: opens Scanner Information")) {
                    NSApp.sendAction(#selector(AppDelegate.showScannerInformation(_:)), to: nil, from: nil)
                }
            }
        }
    }
}

private struct OriginalSection: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelRow(label: String(localized: "Film", comment: "Panel label: film type")) {
                Picker(String(localized: "Film", comment: "Panel label: film type"), selection: $model.scanSettings.filmType) {
                    ForEach(FilmType.allCases, id: \.self) { Text(Strings.filmType($0)).tag($0) }
                }
                .labelsHidden()
            }
            PanelRow(label: String(localized: "Holder", comment: "Panel label: film holder")) {
                TextField(String(localized: "Not specified", comment: "Holder placeholder"),
                          text: $model.scanSettings.holder)
                    .textFieldStyle(.roundedBorder)
            }
            NotYetNote()
        }
    }
}

/// Saved, but not sent to the scanner yet.
private struct NotYetNote: View {
    var body: some View {
        Text("Saved; applied to the scanner with real scans (a later step).", comment: "Panel note")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TabsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(String(localized: "Settings", comment: "Panel section: Main / Advanced"),
                   selection: Binding { model.panel.layout.tab } set: { model.panel.layout.tab = $0 }) {
                Text("Main", comment: "Panel tab").tag(PanelTab.main)
                Text("Advanced", comment: "Panel tab").tag(PanelTab.advanced)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch model.panel.layout.tab {
            case .main: MainTab(model: model)
            case .advanced:
                Text("Advanced settings come with real scans; only settings that work are shown here.",
                     comment: "Panel: empty Advanced tab")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct MainTab: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelRow(label: String(localized: "Resolution", comment: "Panel label")) {
                HStack(spacing: 4) {
                    TextField(value: $model.scanSettings.resolution, format: .number.grouping(.never)) { EmptyView() }
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                    Text("ppi", comment: "Unit: pixels per inch").foregroundStyle(.secondary)
                }
            }
            PanelRow(label: String(localized: "Input", comment: "Panel label: input size")) {
                Text(pixels(model.inputPixelSize)).monospacedDigit()
            }
            PanelRow(label: String(localized: "Scale", comment: "Panel label")) {
                HStack(spacing: 4) {
                    TextField(value: $model.scanSettings.scalePercent, format: .number.grouping(.never)) { EmptyView() }
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 52)
                    Text(verbatim: "%").foregroundStyle(.secondary)
                }
            }
            PanelRow(label: String(localized: "Output", comment: "Panel label: output size")) {
                Text(pixels(model.inputPixelSize.map {
                    let scale = Double(model.scanSettings.scalePercent) / 100
                    return (Int((Double($0.width) * scale).rounded()), Int((Double($0.height) * scale).rounded()))
                })).monospacedDigit()
            }
            Text("Sizes in preview pixels; millimetres once the preview resolution is confirmed. Resolution, scale and crop apply to the scan (a later step): Export Preview writes the whole preview.",
                 comment: "Panel note under the sizes")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HistogramDisclosure(model: model)
        }
    }

    private func pixels(_ size: (width: Int, height: Int)?) -> String {
        guard let size else { return "—" }
        return String(localized: "\(size.width) × \(size.height) px", comment: "Image size in pixels")
    }
}

private struct HistogramDisclosure: View {
    @Bindable var model: AppModel

    var body: some View {
        let folded = model.panel.layout.isFolded(.histogram)
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy(duration: 0.15)) { model.panel.toggleFolded(.histogram) }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(folded ? 0 : 90))
                        .foregroundStyle(.secondary)
                    Text("Histogram", comment: "Palette title")
                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if !folded { HistogramView(model: model) }
        }
        .padding(.top, 4)
    }
}

private struct OutputSection: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelRow(label: String(localized: "Format", comment: "Export palette label")) {
                Picker(String(localized: "Format", comment: "Export palette label"), selection: $model.exportSettings.format) {
                    ForEach(TIFFFormat.allCases, id: \.self) { Text(Strings.exportFormat($0)).tag($0) }
                }
                .labelsHidden()
            }
            if model.exportSettings.format.usesSRGBCurve {
                Label(String(localized: "8 bits: sRGB curve and profile (provisional); fewer levels than the raw 16 bits.",
                             comment: "Export warning for 8-bit formats"),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PanelRow(label: String(localized: "Compression", comment: "Panel label")) {
                Picker(String(localized: "Compression", comment: "Panel label"), selection: $model.exportSettings.compression) {
                    ForEach(TIFFCompression.allCases, id: \.self) { Text(Strings.compression($0)).tag($0) }
                }
                .labelsHidden()
            }
            PanelRow(label: String(localized: "Name", comment: "Panel label: file name template")) {
                HStack(spacing: 4) {
                    Picker(String(localized: "Name", comment: "Panel label: file name template"),
                           selection: $model.exportSettings.nameTemplate) {
                        ForEach(templates, id: \.self) { Text(verbatim: $0).tag($0) }
                    }
                    .labelsHidden()
                    Button(String(localized: "Edit…", comment: "Panel button: opens Settings > Export")) {
                        NSApp.sendAction(#selector(AppDelegate.showExportSettings(_:)), to: nil, from: nil)
                    }
                }
            }
            Text(ExportNameHelp.next(model))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
            PanelRow(label: String(localized: "Folder", comment: "Export palette label")) {
                HStack(spacing: 4) {
                    Text(model.exportSettings.folder?.lastPathComponent
                         ?? String(localized: "None", comment: "No export folder chosen"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(model.exportSettings.folder?.path(percentEncoded: false) ?? "")
                    Spacer(minLength: 4)
                    Button(String(localized: "Choose…", comment: "Button")) {
                        ExportFolderPanel.choose(for: NSApp.keyWindow, model: model)
                    }
                }
            }
            Button(String(localized: "Export Preview", comment: "Panel button")) { model.export() }
                .disabled(!model.toolbar.canExport)
                .help(Text("Export the preview with these settings (⇧⌘E)", comment: "Tooltip"))
            switch model.lastExport {
            case .success(let url):
                HStack {
                    Text(url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                    Button(String(localized: "Show in Finder", comment: "Button")) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            case .failure(let error):
                Text(Strings.exportError(error)).font(.caption).foregroundStyle(.red)
            case nil:
                EmptyView()
            }
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
                .help(Text("Stop the preview (⌘. or Esc)", comment: "Tooltip"))
            } else {
                Button {
                    model.startPreview()
                } label: {
                    Text("Preview", comment: "Menu item and toolbar button").frame(maxWidth: .infinity)
                }
                .disabled(!toolbar.canPreview)
                .help(toolbar.previewBlock.map(Strings.previewBlock)
                      ?? String(localized: "Run a preview on the virtual X1 (⌘R)", comment: "Tooltip"))
            }
            Button {
                NSApp.sendAction(#selector(MainWindowController.startScan(_:)), to: nil, from: nil)
            } label: {
                Text("Scan", comment: "Toolbar button").frame(maxWidth: .infinity)
            }
            .disabled(!toolbar.canScan)
            .help(Text("Scanning comes in a later version.", comment: "Tooltip"))
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
    }
}
