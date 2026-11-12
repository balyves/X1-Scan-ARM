// SPDX-License-Identifier: MIT
import AppKit
import X1ScanCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var windowController: MainWindowController?
    private var quitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel(virtualScanner: {
            // tests/fixtures, copied into the bundle's resources.
            guard let resources = Bundle.main.resourceURL else { throw CocoaError(.fileNoSuchFile) }
            return try VirtualScanner.load(fixturesDirectory: resources)
        })
        self.model = model
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
