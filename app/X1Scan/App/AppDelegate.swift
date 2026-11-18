// SPDX-License-Identifier: MIT
import AppKit
import X1ScanCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var model: AppModel?
    private var windowController: MainWindowController?
    private var settingsController: SettingsWindowController?
    private var scannerInfoController: ScannerInfoWindowController?
    private var observers: [Observing] = []
    private var quitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel(virtualScanner: {
            // tests/fixtures, copied into the bundle's resources.
            guard let resources = Bundle.main.resourceURL else { throw CocoaError(.fileNoSuchFile) }
            return try VirtualScanner.load(fixturesDirectory: resources)
        })
        self.model = model
        observers.append(Observing {
            NSApp.appearance = switch model.settings.appearance {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        })
        NSApp.mainMenu = MainMenu.make()
        let windowController = MainWindowController(model: model)
        self.windowController = windowController
        windowController.showWindow(nil)
        NSApp.activate()
        #if DEBUG
        DebugSnapshot.run(window: windowController.window, model: model)
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: Menu actions (reached through the responder chain)

    /// The standard About panel, with both licences as credits: the code is
    /// MIT, the icon is not (LICENSE, LICENSE-ICON, copied into the app).
    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: Self.aboutCredits()])
    }

    static func aboutCredits(bundle: Bundle = .main) -> NSAttributedString {
        // The icon licence first: it is short, and visible without scrolling.
        let sections = [
            (String(localized: "Icon licence (not MIT)", comment: "About panel: heading above the icon licence text"), "LICENSE-ICON"),
            (String(localized: "Code licence (MIT)", comment: "About panel: heading above the MIT licence text"), "LICENSE"),
        ]
        let credits = NSMutableAttributedString()
        let heading: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize),
                                                      .foregroundColor: NSColor.labelColor]
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                                                   .foregroundColor: NSColor.secondaryLabelColor]
        for (index, (title, file)) in sections.enumerated() {
            let text = bundle.url(forResource: file, withExtension: nil)
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
                ?? String(localized: "\(file) is missing from the application.", comment: "About panel: a licence file was not found; %@ is its name")
            if index > 0 { credits.append(NSAttributedString(string: "\n\n")) }
            credits.append(NSAttributedString(string: title + "\n\n", attributes: heading))
            credits.append(NSAttributedString(string: unwrapped(text), attributes: body))
        }
        return credits
    }

    /// Joins the hard-wrapped lines of each paragraph, so the panel wraps the
    /// text to its own width; list items ("- ") keep their line breaks.
    static func unwrapped(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n\n")
            .map { paragraph in
                let lines = paragraph.components(separatedBy: "\n")
                return lines.contains { $0.hasPrefix("- ") } ? paragraph : lines.joined(separator: " ")
            }
            .joined(separator: "\n\n")
    }

    @objc func showSettings(_ sender: Any?) {
        guard let model else { return }
        if settingsController == nil {
            settingsController = SettingsWindowController(model: model)
            settingsController?.window?.center()
        }
        settingsController?.showWindow(nil)
    }

    /// Settings > Export, from the panel's Edit… button.
    @objc func showExportSettings(_ sender: Any?) {
        guard let model else { return }
        if settingsController == nil {
            settingsController = SettingsWindowController(model: model)
            settingsController?.window?.center()
        }
        settingsController?.show(.export)
    }

    /// Settings > Holders, from the panel's holder button.
    @objc func showHolderSettings(_ sender: Any?) {
        guard let model else { return }
        if settingsController == nil {
            settingsController = SettingsWindowController(model: model)
            settingsController?.window?.center()
        }
        settingsController?.show(.holders)
    }

    @objc func showScannerInformation(_ sender: Any?) {
        guard let model else { return }
        if scannerInfoController == nil { scannerInfoController = ScannerInfoWindowController(model: model) }
        scannerInfoController?.showWindow(nil)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { model != nil }

    /// A running preview is stopped first. After SCAN the stop sequence (DB,
    /// then 0xDF = 00 00) must complete before the app quits. A read of the
    /// real X1 in progress is also left to finish (the device is then closed).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.isBusy else { return .terminateNow }
        guard !quitting else { return .terminateLater }
        quitting = true
        Task {
            await model.stopAndWait()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
