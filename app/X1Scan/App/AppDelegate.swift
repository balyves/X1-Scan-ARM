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

    @objc func showSettings(_ sender: Any?) {
        guard let model else { return }
        if settingsController == nil {
            settingsController = SettingsWindowController(model: model)
            settingsController?.window?.center()
        }
        settingsController?.showWindow(nil)
    }

    @objc func showScannerInformation(_ sender: Any?) {
        guard let model else { return }
        if scannerInfoController == nil { scannerInfoController = ScannerInfoWindowController(model: model) }
        scannerInfoController?.showWindow(nil)
    }

    /// Real X1: reads identity, state and counters (reads only, device closed
    /// afterwards). Virtual X1: its identity comes from the fixtures. Either
    /// way the Scanner Information window shows the result.
    @objc func readIdentity(_ sender: Any?) {
        guard let model else { return }
        showScannerInformation(sender)
        if model.source == .real { Task { await model.readRealScanner() } }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let model else { return false }
        switch menuItem.action {
        case #selector(readIdentity(_:)): return model.source == .virtual || model.realStatus != .reading
        default: return true
        }
    }

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
