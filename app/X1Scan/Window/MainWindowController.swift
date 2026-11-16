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
        window.minSize = NSSize(width: 760, height: 520)
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
        default: return true
        }
    }

    // MARK: Actions

    /// ⌘R and the panel's Preview button. On the real X1 (hidden setting on),
    /// the three checks are confirmed first, every time.
    @objc func startPreview(_ sender: Any?) {
        guard model.toolbar.previewNeedsConfirmation else {
            model.startPreview()
            return
        }
        guard let window else { return }
        RealPreviewConfirmationAlert.run(for: window) { [model] confirmation in
            if case .failure(let error) = model.startRealPreview(confirmation), error != .notAllowed {
                self.showAlert(String(localized: "The preview could not start", comment: "Alert title"),
                               error.description)
            }
        }
    }
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

    // MARK: Alerts

    /// Anomalies and failed stop sequences are shown in an alert: they may
    /// mean the scanner needs attention.
    private func alertIfNeeded(for state: PreviewSession.State) {
        switch state {
        case .failed(let failure):
            var text = failure.description
            if let outcome = failure.emergencyStop { text += "\n\n" + Strings.emergencyStop(outcome) }
            if model.lastPreviewWasReal {
                switch failure.cause {
                case .anomaly(.couldNotOpen):
                    break  // nothing was sent: no advice to switch the scanner off
                case .anomaly(.notJustSwitchedOn):
                    // First page 0x20 read: only reads, D2 and the session start were sent.
                    text += "\n\n" + String(localized: "On the real X1 the preview only runs right after the scanner is switched on. Only reads, the startup command and the session start were sent: no window, mode, exposure, image read or scan.",
                                             comment: "Real preview stopped: the X1 was not just switched on")
                    text += realPreviewAdvice(stoppedBeforeScan: true)
                case .decoding:
                    // The scanner side completed, end of session included: only the log.
                    text += realPreviewAdvice(stoppedBeforeScan: nil)
                case .anomaly:
                    text += realPreviewAdvice(stoppedBeforeScan: failure.emergencyStop == nil)
                }
            }
            showAlert(String(localized: "The preview stopped after an anomaly", comment: "Alert title"), text)
        case .stopped(let outcome) where model.lastPreviewWasReal:
            // Stop, change of source or quit on the real X1: always reported, with the advice.
            var text = outcome.map(Strings.emergencyStop)
                ?? String(localized: "Preview stopped before SCAN; nothing more was sent.", comment: "Real preview stopped")
            text += realPreviewAdvice(stoppedBeforeScan: outcome == nil)
            showAlert(String(localized: "The preview on the real X1 was stopped", comment: "Alert title"), text)
        case .stopped(let outcome?) where outcome != .stoppedAndReady:
            showAlert(String(localized: "The stop sequence did not complete", comment: "Alert title"),
                      Strings.emergencyStop(outcome))
        default:
            break
        }
    }

    /// Advice and log after a preview on the real X1 that did not complete.
    /// `stoppedBeforeScan` nil: the scanner side completed, only the log.
    private func realPreviewAdvice(stoppedBeforeScan: Bool?) -> String {
        var text = ""
        if stoppedBeforeScan == true {
            // The session and modes FlexColor set may still be active.
            text += "\n\n" + String(localized: "Switch the X1 off and on again before anything else.",
                                     comment: "Advice after a preview on the real X1 stopped before SCAN")
        } else if stoppedBeforeScan == false {
            // The end of session (CF 00 02) is not sent on the stop path.
            text += "\n\n" + String(localized: "Switch the X1 off and on again before another preview.",
                                     comment: "Advice after a preview on the real X1 stopped after SCAN")
        }
        if let log = model.lastPreviewLog {
            text += "\n\n" + String(localized: "Log: \(log.path(percentEncoded: false))", comment: "Path of the preview log")
            if model.lastPreviewLogIsIncomplete {
                text += "\n" + String(localized: "Some lines could not be written: the log is incomplete.",
                                      comment: "Preview log incomplete")
            }
        }
        return text
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

/// Asked before every preview on the real X1: Start is enabled only when
/// the three boxes are ticked.
@MainActor
enum RealPreviewConfirmationAlert {
    static func run(for window: NSWindow, start: @escaping @MainActor (RealPreviewConfirmation) -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Preview on the real X1", comment: "Confirmation title")
        alert.informativeText = String(
            localized: "FlexColor's captured preview will be sent to the scanner, command for command. Any difference stops it; Stop (⌘. or Esc) stays available. Every command is logged.",
            comment: "Confirmation text before a preview on the real X1")
        let boxes = [
            String(localized: "The X1 is on", comment: "Real preview check"),
            String(localized: "A holder is in place", comment: "Real preview check"),
            String(localized: "FlexColor is closed", comment: "Real preview check"),
        ].map { NSButton(checkboxWithTitle: $0, target: nil, action: nil) }
        let stack = NSStackView(views: boxes)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.frame = NSRect(x: 0, y: 0, width: 300, height: 66)
        alert.accessoryView = stack
        let startButton = alert.addButton(withTitle: String(localized: "Start Preview", comment: "Confirmation button"))
        alert.addButton(withTitle: String(localized: "Cancel", comment: "Button"))
        startButton.isEnabled = false
        startButton.keyEquivalent = ""  // Return must not start it by accident
        let watcher = CheckboxWatcher(boxes: boxes, button: startButton)
        for box in boxes {
            box.target = watcher
            box.action = #selector(CheckboxWatcher.changed(_:))
        }
        alert.beginSheetModal(for: window) { response in
            withExtendedLifetime(watcher) {}
            guard response == .alertFirstButtonReturn else { return }
            let ticked = boxes.map { $0.state == .on }
            start(RealPreviewConfirmation(scannerOn: ticked[0], holderInPlace: ticked[1], flexColorClosed: ticked[2]))
        }
    }

    @MainActor
    private final class CheckboxWatcher: NSObject {
        let boxes: [NSButton]
        let button: NSButton

        init(boxes: [NSButton], button: NSButton) {
            self.boxes = boxes
            self.button = button
        }

        @objc func changed(_ sender: NSButton) {
            button.isEnabled = boxes.allSatisfy { $0.state == .on }
        }
    }
}
