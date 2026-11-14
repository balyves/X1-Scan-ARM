// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import X1ScanCore

/// X1 Scan > Settings… (⌘,): General, Display, Export, Scanner.
@MainActor
final class SettingsWindowController: NSWindowController {
    init(model: AppModel) {
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Settings", comment: "Window title")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            Tab(String(localized: "General", comment: "Settings tab"), systemImage: "gearshape") {
                GeneralSettings(settings: model.settings)
            }
            Tab(String(localized: "Display", comment: "Settings tab"), systemImage: "display") {
                DisplaySettings(settings: model.settings)
            }
            Tab(String(localized: "Export", comment: "Palette title"), systemImage: "square.and.arrow.up") {
                ExportSettingsForm(model: model)
            }
            Tab(String(localized: "Scanner", comment: "Menu"), systemImage: "scanner") {
                ScannerSettings(settings: model.settings)
            }
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Picker(String(localized: "Language", comment: "Setting"), selection: $settings.language) {
                ForEach(InterfaceLanguage.allCases, id: \.self) { Text(Strings.language($0)).tag($0) }
            }
            Text("The language changes at the next launch.", comment: "Setting note")
                .font(.caption)
                .foregroundStyle(.secondary)
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

    var body: some View {
        Form {
            Picker(String(localized: "Appearance", comment: "Setting"), selection: $settings.appearance) {
                ForEach(AppearanceSetting.allCases, id: \.self) { Text(Strings.appearance($0)).tag($0) }
            }
            Picker(String(localized: "Background around the image", comment: "Setting"),
                   selection: $settings.canvasBackground) {
                ForEach(CanvasBackground.allCases, id: \.self) { Text(Strings.canvasBackground($0)).tag($0) }
            }
            Picker(String(localized: "Zoom when opening", comment: "Setting"), selection: $settings.startupZoom) {
                ForEach(StartupZoom.allCases, id: \.self) { Text(Strings.startupZoom($0)).tag($0) }
            }
        }
        .formStyle(.grouped)
    }
}

/// Shared with the Export palette: both edit `AppModel.exportSettings`.
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
            TextField(String(localized: "File name", comment: "Export palette label"),
                      text: $model.exportSettings.nameTemplate)
            Text(ExportNameHelp.tokens).font(.caption).foregroundStyle(.secondary)
            Text(ExportNameHelp.next(model)).font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct ScannerSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Picker(String(localized: "Source at launch", comment: "Setting"), selection: $settings.startupSource) {
                ForEach(StartupSource.allCases, id: \.self) { Text(Strings.startupSource($0)).tag($0) }
            }
            Text("The real X1 is never read at launch: use Scanner > Read Identity.", comment: "Setting note")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

/// Help under the file name, in the Export palette and in Settings.
@MainActor
enum ExportNameHelp {
    static var tokens: String {
        String(localized: "{date}, {time} and {n} are replaced by the date, the time and a number.",
               comment: "Export file name tokens. Both {time} and {heure} work; French shows {heure}")
    }

    static func next(_ model: AppModel) -> String {
        _ = model.lastExport  // recomputed after each export: the number moves on
        return String(localized: "Next file: \(model.nextExportFileName())", comment: "Export: name of the next file")
    }
}
