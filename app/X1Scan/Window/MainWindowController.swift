// SPDX-License-Identifier: MIT
import AppKit
import X1ScanCore

/// The main window: no toolbar (Preview, Stop and Scan are in the settings
/// panel, everything is in the menus), a split view (image area; tool column
/// and settings panel), menu actions and their validation. All decisions
/// come from `AppModel`; this class only forwards and mirrors.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    private let model: AppModel
    private let splitController: MainSplitViewController
    private var observers: [Observing] = []
    private var lastAlertedState: PreviewSession.State?

    init(model: AppModel) {
        self.model = model
        splitController = MainSplitViewController(model: model)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "X1 Scan"
        window.minSize = NSSize(width: 820, height: 520)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentViewController = splitController
        window.setContentSize(NSSize(width: 1280, height: 820))
        window.center()
        window.setFrameAutosaveName("MainWindow")
        super.init(window: window)
        window.delegate = self
        observers.append(Observing { [weak self] in self?.modelChanged() })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Called whenever an observed model value changes.
    private func modelChanged() {
        let state = model.session.state
        if state != lastAlertedState {
            lastAlertedState = state
            Task { @MainActor in self.alertIfNeeded(for: state) }
        }
    }

    /// Closing the main window quits, even if Settings or Scanner Information
    /// is open: there is no way to reopen it. Quitting stops a running preview
    /// first (AppDelegate.applicationShouldTerminate).
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(selectVirtualSource(_:)): menuItem.state = model.source == .virtual ? .on : .off
        case #selector(selectRealSource(_:)): menuItem.state = model.source == .real ? .on : .off
        case #selector(selectHandTool(_:)): menuItem.state = model.tools.selected == .hand ? .on : .off
        case #selector(selectZoomTool(_:)): menuItem.state = model.tools.selected == .zoom ? .on : .off
        case #selector(selectCropTool(_:)): menuItem.state = model.tools.selected == .crop ? .on : .off
        case #selector(zoomToFit(_:)): menuItem.state = model.viewport.mode == .fit ? .on : .off
        case #selector(zoomToFill(_:)): menuItem.state = model.viewport.mode == .fill ? .on : .off
        case #selector(zoomToStep(_:)):
            menuItem.state = (menuItem.representedObject as? Double) == model.viewport.currentStep ? .on : .off
        case #selector(toggleSettingsPanel(_:)):
            menuItem.title = model.panel.layout.isHidden
                ? String(localized: "Show Settings Panel", comment: "Menu item")
                : String(localized: "Hide Settings Panel", comment: "Menu item")
        default: break
        }
        return validate(menuItem.action)
    }

    private func validate(_ action: Selector?) -> Bool {
        let toolbar = model.toolbar
        switch action {
        case #selector(startPreview(_:)): return toolbar.canPreview
        case #selector(startScan(_:)): return toolbar.canScan
        case #selector(stopPreview(_:)): return toolbar.canStop
        case #selector(exportImage(_:)): return toolbar.canExport
        case #selector(zoomIn(_:)): return model.session.image != nil && model.viewport.canZoomIn
        case #selector(zoomOut(_:)): return model.session.image != nil && model.viewport.canZoomOut
        case #selector(zoomToFit(_:)), #selector(zoomToFill(_:)), #selector(zoomToActualSize(_:)),
             #selector(zoomToStep(_:)):
            return model.session.image != nil
        case #selector(selectRealSource(_:)), #selector(selectVirtualSource(_:)): return !model.session.isBusy
        default: return true
        }
    }

    // MARK: Actions

    @objc func startPreview(_ sender: Any?) { model.startPreview() }
    @objc func startScan(_ sender: Any?) {}
    @objc func stopPreview(_ sender: Any?) { model.stop() }

    /// Esc (and ⌘. through the menu): stop.
    override func cancelOperation(_ sender: Any?) { model.stop() }

    @objc func exportImage(_ sender: Any?) {
        if case .failure(let error) = model.export() {
            showAlert(String(localized: "Export failed", comment: "Alert title"), Strings.exportError(error))
        }
    }

    @objc func chooseExportFolder(_ sender: Any?) {
        guard let window else { return }
        ExportFolderPanel.choose(for: window, model: model)
    }

    @objc func zoomToFit(_ sender: Any?) { model.zoomToFit() }
    @objc func zoomToFill(_ sender: Any?) { model.zoomToFill() }
    @objc func zoomToStep(_ sender: Any?) {
        if let step = (sender as? NSMenuItem)?.representedObject as? Double { model.zoom(to: step) }
    }
    @objc func zoomToActualSize(_ sender: Any?) { model.zoomToActualSize() }
    @objc func zoomIn(_ sender: Any?) { model.zoomIn() }
    @objc func zoomOut(_ sender: Any?) { model.zoomOut() }
    @objc func selectHandTool(_ sender: Any?) { model.tools.selected = .hand }
    @objc func selectZoomTool(_ sender: Any?) { model.tools.selected = .zoom }
    @objc func selectCropTool(_ sender: Any?) { model.tools.selected = .crop }
    @objc func toggleSettingsPanel(_ sender: Any?) { model.panel.toggleHidden() }
    @objc func selectVirtualSource(_ sender: Any?) { model.source = .virtual }
    @objc func selectRealSource(_ sender: Any?) { model.source = .real }

    // MARK: Alerts

    /// Anomalies and failed stop sequences are shown in an alert: they may
    /// mean the scanner needs attention.
    private func alertIfNeeded(for state: PreviewSession.State) {
        switch state {
        case .failed(let failure):
            var text = failure.description
            if let outcome = failure.emergencyStop { text += "\n\n" + Strings.emergencyStop(outcome) }
            showAlert(String(localized: "The preview stopped after an anomaly", comment: "Alert title"), text)
        case .stopped(let outcome?) where outcome != .stoppedAndReady:
            showAlert(String(localized: "The stop sequence did not complete", comment: "Alert title"),
                      Strings.emergencyStop(outcome))
        default:
            break
        }
    }

    private func showAlert(_ title: String, _ text: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = text
        alert.beginSheetModal(for: window)
    }
}

/// The folder chooser of the panel, Settings > Export and File > Choose Export Folder.
@MainActor
enum ExportFolderPanel {
    static func choose(for window: NSWindow?, model: AppModel) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose", comment: "Open panel button")
        panel.directoryURL = model.exportSettings.folder
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, let url = panel.url { model.exportSettings.folder = url }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: completion) } else {
            completion(panel.runModal())
        }
    }
}
