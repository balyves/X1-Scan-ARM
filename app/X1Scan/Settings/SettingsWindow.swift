// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import X1ScanCore

/// X1 Scan > Settings… (⌘,): an icon toolbar at the top (General, Display,
/// Export, Holders, Scanner), as in the settings of Mail or Safari. Each pane is a
/// SwiftUI form; the window takes the height of the pane shown.
@MainActor
final class SettingsWindowController: NSWindowController {
    enum Pane: Int { case general, display, export, holders, scanner }

    /// Shows the window on `pane`.
    func show(_ pane: Pane) {
        (window?.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex = pane.rawValue
        showWindow(nil)
    }

    init(model: AppModel) {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.crossfade, .allowUserInteraction]
        // Grouped forms scroll and have no natural height: each pane gets its own.
        func pane(_ title: String, _ symbol: String, height: CGFloat, _ view: some View) {
            let hosting = NSHostingController(rootView: view.frame(width: 520, height: height))
            hosting.sizingOptions = [.preferredContentSize]
            hosting.title = title
            let item = NSTabViewItem(viewController: hosting)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        pane(String(localized: "General", comment: "Settings tab"), "gearshape", height: 230, GeneralSettings(settings: model.settings))
        pane(String(localized: "Display", comment: "Settings tab"), "display", height: 280, DisplaySettings(settings: model.settings))
        pane(String(localized: "Export", comment: "Palette title"), "square.and.arrow.up", height: 400, ExportSettingsForm(model: model))
        pane(String(localized: "Holders", comment: "Settings tab"), "film.stack", height: 460, HolderSettings(model: model))
        pane(String(localized: "Scanner", comment: "Menu"), "scanner", height: 220, ScannerSettings(model: model))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}

private struct GeneralSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            // The note is the menu's subtitle: on the same row, read with it by VoiceOver.
            Picker(selection: $settings.language) {
                ForEach(InterfaceLanguage.allCases, id: \.self) { Text(Strings.language($0)).tag($0) }
            } label: {
                Text(String(localized: "Language", comment: "Setting"))
                Text("Restart X1 Scan to apply the language.", comment: "Setting note under the Language menu")
            }
            Toggle(String(localized: "Hide the serial number", comment: "Setting"), isOn: $settings.hidesSerialNumber)
            Text("Shown as FX1••••••• in Scanner Information.", comment: "Setting note")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct DisplaySettings: View {
    @Bindable var settings: AppSettings

    /// The background menu: the presets, then Custom… (opens the colour panel).
    private enum BackgroundChoice: Hashable {
        case preset(CanvasBackground)
        case custom
    }

    private var choice: Binding<BackgroundChoice> {
        Binding {
            if case .custom = settings.canvasBackground { .custom } else { .preset(settings.canvasBackground) }
        } set: { newValue in
            switch newValue {
            case .preset(let background): settings.canvasBackground = background
            case .custom: BackgroundColorPanel.show(settings: settings)
            }
        }
    }

    var body: some View {
        Form {
            Picker(String(localized: "Appearance", comment: "Setting"), selection: $settings.appearance) {
                ForEach(AppearanceSetting.allCases, id: \.self) { Text(Strings.appearance($0)).tag($0) }
            }
            LabeledContent(String(localized: "Background around the image", comment: "Setting")) {
                HStack {
                    Picker(String(localized: "Background around the image", comment: "Setting"), selection: choice) {
                        ForEach(CanvasBackground.presets, id: \.self) {
                            Text(Strings.canvasBackground($0)).tag(BackgroundChoice.preset($0))
                        }
                        Divider()
                        Text(Strings.canvasBackground(.custom(SRGBColor(red: 0, green: 0, blue: 0))))
                            .tag(BackgroundChoice.custom)
                    }
                    .labelsHidden()
                    .fixedSize()
                    swatch
                }
            }
            HStack {
                Spacer()
                Button(String(localized: "Neutral grey 18 %", comment: "Background around the image")) {
                    settings.canvasBackground = .neutralGray
                }
                .disabled(settings.canvasBackground == .neutralGray)
            }
            Picker(String(localized: "Zoom when opening", comment: "Setting"), selection: $settings.startupZoom) {
                ForEach(StartupZoom.allCases, id: \.self) { Text(Strings.startupZoom($0)).tag($0) }
            }
            Picker(String(localized: "RGB values", comment: "Setting: unit of the RGB values in the bottom bar"),
                   selection: $settings.rgbUnit) {
                ForEach(RGBUnit.allCases, id: \.self) { Text(Strings.rgbUnit($0)).tag($0) }
            }
        }
        .formStyle(.grouped)
    }

    /// The current colour; a click opens the colour panel.
    private var swatch: some View {
        let color = settings.canvasBackground.color
        return Button {
            BackgroundColorPanel.show(settings: settings)
        } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary.opacity(0.5)))
                .frame(width: 28, height: 18)
        }
        .buttonStyle(.plain)
        .help(Text("Custom…", comment: "Background around the image: chosen with the colour panel"))
    }
}

/// The system colour panel, applied live to the background around the image.
@MainActor
final class BackgroundColorPanel: NSObject {
    private static var shared: BackgroundColorPanel?
    private let settings: AppSettings

    private init(settings: AppSettings) { self.settings = settings }

    static func show(settings: AppSettings) {
        let bridge = BackgroundColorPanel(settings: settings)
        shared = bridge
        let panel = NSColorPanel.shared
        let color = settings.canvasBackground.color
        panel.setTarget(nil)
        panel.color = NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.setTarget(bridge)
        panel.setAction(#selector(colorChanged(_:)))
        panel.orderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        guard let srgb = sender.color.usingColorSpace(.sRGB) else { return }
        settings.canvasBackground = .custom(SRGBColor(red: srgb.redComponent, green: srgb.greenComponent,
                                                      blue: srgb.blueComponent))
    }
}

/// Shared with the panel's Output section: both edit `AppModel.exportSettings`.
struct ExportSettingsForm: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            LabeledContent(String(localized: "Folder", comment: "Export palette label")) {
                HStack {
                    Text(model.exportSettings.folder?.path(percentEncoded: false)
                         ?? String(localized: "None", comment: "No export folder chosen"))
                        .lineLimit(1)
                        .truncationMode(.head)
                    Button(String(localized: "Choose…", comment: "Button")) {
                        ExportFolderPanel.choose(for: NSApp.keyWindow, model: model)
                    }
                }
            }
            Section(String(localized: "File name", comment: "Export palette label")) {
                ExportNameBuilder(model: model)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ScannerSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Picker(String(localized: "Source", comment: "Panel label: scanner source"), selection: $model.source) {
                ForEach(ScannerSourceKind.allCases, id: \.self) { Text(Strings.source($0)).tag($0) }
            }
            .disabled(model.session.isBusy || model.discoveryMode)
            if model.discoveryMode {
                Text(Strings.sourceInDiscovery)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Read Identity is in Scanner > Scanner Information (\(AppShortcut.scannerInformation.shortcut?.display(names: Strings.keyNames) ?? "")); the state is in the bottom bar.",
                 comment: "Settings > Scanner note; %@ is the shortcut of Scanner Information (⌘I), from the shortcuts' own source")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(String(localized: "Source at launch", comment: "Setting"), selection: $settings.startupSource) {
                ForEach(StartupSource.allCases, id: \.self) { Text(Strings.startupSource($0)).tag($0) }
            }
            Text(Strings.launchPresenceNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
