// SPDX-License-Identifier: MIT
import AppKit
import X1ScanCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var model: AppModel?
    private var windowController: MainWindowController?
    private var settingsController: SettingsWindowController?
    private var scannerInfoController: ScannerInfoWindowController?
    private var helpController: HelpWindowController?
    private var installationController: InstallationCheckWindowController?
    /// The help's pages in the Help menu's search results (kept: AppKit holds it weakly).
    private var helpSearch: HelpSearch?
    private var observers: [Observing] = []
    private var quitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let virtualScanner: () throws -> VirtualScanner = {
            // tests/fixtures, copied into the bundle's resources.
            guard let resources = Bundle.main.resourceURL else { throw CocoaError(.fileNoSuchFile) }
            return try VirtualScanner.load(fixturesDirectory: resources)
        }
        #if DEBUG
        // Debug only: no X1 and an invented registry for the presence check and the
        // installation check of the model, to try the launch and discovery mode paths
        // without a scanner (DebugSnapshot.noScannerRegistry).
        let model = DebugSnapshot.noScannerRegistry().map { registry in
            AppModel(virtualScanner: virtualScanner, presence: { false }, installation: { registry })
        } ?? AppModel(virtualScanner: virtualScanner)
        #else
        let model = AppModel(virtualScanner: virtualScanner)
        #endif
        self.model = model
        observers.append(Observing {
            NSApp.appearance = switch model.settings.appearance {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        })
        NSApp.mainMenu = MainMenu.make()
        let help = HelpModel(library: HelpModel.load())
        helpController = HelpWindowController(model: help)
        if let library = help.library {
            let search = HelpSearch(library: library,
                                    open: { [weak self] in self?.showHelp(page: $0.pageID, anchor: $0.anchor) },
                                    openAll: { [weak self] query in
                                        self?.showHelp(page: HelpLibrary.pageIDs[0])
                                        self?.helpController?.model.query = query
                                    })
            helpSearch = search
            NSApp.registerUserInterfaceItemSearchHandler(search)
        }
        let windowController = MainWindowController(model: model)
        self.windowController = windowController
        windowController.showWindow(nil)
        NSApp.activate()
        // Lot A: with the real X1 as the source, the presence check (the I/O Registry only:
        // nothing opened, nothing sent); none found gives "No X1 found" with discovery mode.
        model.sampleFilm = SampleFilm.load(bundle: .main)
        Task { await model.detectScanner() }
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

    /// Help > X1 Scan Help (⌘?): the help window, at its home page the first time.
    @objc func showHelpWindow(_ sender: Any?) {
        helpController?.showWindow(nil)
    }

    /// The help window at a page and, optionally, a section of it.
    func showHelp(page: String, anchor: String? = nil) {
        helpController?.show(page: page, anchor: anchor)
    }

    #if DEBUG
    /// DebugSnapshot types into the help's search field and writes the window.
    var helpControllerForDebug: HelpWindowController? { helpController }
    #endif

    /// Help > Check Installation…, the "No X1 found" message's button, and the
    /// launch when the adapter or the driver is missing. Never with the
    /// message: a "No X1 found" sheet still open is closed first.
    @objc func showInstallationCheck(_ sender: Any?) {
        windowController?.closeNoScannerMessage()
        if installationController == nil { installationController = InstallationCheckWindowController() }
        installationController?.showWindow(nil)
    }

    /// The installation check is on screen (the "No X1 found" message then waits).
    var installationCheckShown: Bool { installationController?.isShown ?? false }
    #if DEBUG
    var installationControllerForDebug: InstallationCheckWindowController? { installationController }
    #endif

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
