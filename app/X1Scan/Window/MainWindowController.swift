// SPDX-License-Identifier: MIT
import AppKit
import X1Preview
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
    private var lastDetection: AppModel.Detection?
    /// Key X in crop mode, wherever the keyboard focus is in the window.
    private var cropKeyMonitor: Any?

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
        model.undoManager = window.undoManager  // Reset of the Framing section, undone by ⌘Z
        observers.append(Observing { [weak self] in self?.modelChanged() })
        cropKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let shortcut = self.windowKey(event) else { return event }
            // Held down: one action only; the repeats are swallowed.
            guard !event.isARepeat else { return nil }
            switch shortcut {
            case .swapProportions: self.model.toggleCropPortrait()
            case .tool(let tool): self.model.tools.selected = tool
            default: break
            }
            return nil
        }
    }

    /// Single keys handled by the window, whatever has the keyboard focus in
    /// it (a tab, a menu or a checkbox of the panel after a click, the
    /// canvas…), except while text is being typed (a field's editor) or a
    /// sheet is open; other windows (the custom ratio popover, Settings) are
    /// left alone: the tool keys (lot 1b: from any tab, C and R open
    /// Prepare > Framing) and, in crop mode, the swap of width and height
    /// (`AppShortcut.windowKeys`, the source of their tooltips too).
    private func windowKey(_ event: NSEvent) -> AppShortcut? {
        guard let window, event.window === window, window.attachedSheet == nil,
              // A text field being edited has the window's field editor (an NSText) as first responder.
              !(window.firstResponder is NSText) else { return nil }
        return AppShortcut.matching(KeyPress(event), among: AppShortcut.windowKeys(cropping: model.tools.showsCropOptions))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Called whenever an observed model value changes.
    private func modelChanged() {
        let detection = model.detection
        if detection != lastDetection {
            lastDetection = detection
            if detection == .notFound { Task { @MainActor in self.showNoScannerFound() } }
        }
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
        if let cropKeyMonitor { NSEvent.removeMonitor(cropKeyMonitor) }
        cropKeyMonitor = nil
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(selectHandTool(_:)): menuItem.state = model.tools.selected == .hand ? .on : .off
        case #selector(selectZoomTool(_:)): menuItem.state = model.tools.selected == .zoom ? .on : .off
        case #selector(selectCropTool(_:)): menuItem.state = model.tools.selected == .crop ? .on : .off
        case #selector(selectStraightenTool(_:)): menuItem.state = model.tools.selected == .straighten ? .on : .off
        case #selector(zoomToFit(_:)): menuItem.state = model.viewport.mode == .fit ? .on : .off
        case #selector(zoomToFill(_:)): menuItem.state = model.viewport.mode == .fill ? .on : .off
        case #selector(zoomToStep(_:)):
            menuItem.state = (menuItem.representedObject as? Double) == model.viewport.currentStep ? .on : .off
        case #selector(toggleGrid(_:)):
            menuItem.title = model.grid.isVisible ? Strings.hideGrid : Strings.showGrid
        case #selector(chooseGridKind(_:)):
            menuItem.state = (menuItem.representedObject as? String) == model.grid.kind.rawValue ? .on : .off
        case #selector(chooseGridColor(_:)):
            menuItem.state = (menuItem.representedObject as? String) == model.grid.color.rawValue ? .on : .off
        case #selector(chooseGridOpacity(_:)):
            menuItem.state = (menuItem.representedObject as? Double).map { abs($0 - model.grid.opacity) < 1e-9 } == true ? .on : .off
        case #selector(chooseGridDivisions(_:)):
            menuItem.state = (menuItem.representedObject as? Int) == model.grid.fineDivisions ? .on : .off
        case #selector(selectPanelTab(_:)):
            let tab = (menuItem.representedObject as? String).flatMap(PanelTab.init(rawValue:))
            menuItem.state = !model.panel.layout.isHidden && tab == model.panel.layout.tab ? .on : .off
        case #selector(toggleDiscoveryMode(_:)):
            menuItem.title = model.discoveryMode ? Strings.leaveDiscovery : Strings.enterDiscovery
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
        case #selector(toggleDiscoveryMode(_:)): return !model.isBusy
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
    /// the checks are confirmed first, every time.
    @objc func startPreview(_ sender: Any?) {
        guard model.toolbar.previewNeedsConfirmation else {
            model.startPreview()
            return
        }
        guard let window else { return }
        RealPreviewConfirmationAlert.run(for: window, askPowerCycle: model.realPreviewNeedsPowerCycle) { [model] confirmation in
            if case .failure(let error) = model.startRealPreview(confirmation), let id = IssueClassifier.id(for: error) {
                self.showIssue(UserIssue(id, context: String(localized: "The preview could not start", comment: "Alert title"),
                                         details: error.description))
            }
        }
    }
    /// Scan: on the virtual X1 at once; on the real X1 after the confirmation.
    @objc func startScan(_ sender: Any?) {
        let toolbar = model.toolbar
        guard toolbar.canScan else { return }
        guard toolbar.scanNeedsConfirmation else {
            model.startScan()
            return
        }
        guard let window else { return }
        RealScanConfirmationAlert.run(for: window) { [model] confirmation in
            if case .failure(let error) = model.startRealScan(confirmation), let id = IssueClassifier.id(for: error) {
                self.showIssue(UserIssue(id, context: String(localized: "The scan could not start", comment: "Alert title"),
                                         details: error.description))
            }
        }
    }
    @objc func stopPreview(_ sender: Any?) { model.stop() }

    /// File > Try Without a Scanner / Leave Discovery Mode (lot A).
    @objc func toggleDiscoveryMode(_ sender: Any?) {
        if model.discoveryMode {
            model.leaveDiscovery()
        } else {
            model.enterDiscovery(sampleSuffix: Strings.discoverySuffix)
        }
    }

    /// The presence check found no X1 (real source, at launch or after
    /// discovery mode): "No X1 found", which also offers discovery mode.
    func showNoScannerFound() {
        let issue = UserIssue(.noScanner, details: Strings.noScannerAtLaunchDetails)
        let enter: @MainActor () -> Void = { [weak self] in
            self?.model.enterDiscovery(sampleSuffix: Strings.discoverySuffix)
        }
        showIssue(issue, extra: [(Strings.enterDiscovery, enter)])
    }

    /// Esc: stops a running preview or scan; otherwise, in crop mode, cancels its changes
    /// (`AppModel.escape`). ⌘. goes to the menu's Stop while it is enabled, and here otherwise.
    override func cancelOperation(_ sender: Any?) { model.escape() }

    @objc func exportImage(_ sender: Any?) {
        Task {
            if case .failure(let error) = await model.export() {
                showIssue(UserIssue(IssueClassifier.id(for: error), context: String(localized: "Export failed", comment: "Alert title"),
                                    details: Strings.exportError(error)))
            }
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
    @objc func selectStraightenTool(_ sender: Any?) { model.tools.selected = .straighten }
    @objc func toggleSettingsPanel(_ sender: Any?) { model.panel.toggleHidden() }
    /// View > Prepare Tab… (⌥⌘1…): the tab, and the panel if it was hidden.
    @objc func selectPanelTab(_ sender: Any?) {
        guard let name = (sender as? NSMenuItem)?.representedObject as? String, let tab = PanelTab(rawValue: name) else { return }
        model.panel.select(tab)
        model.panel.layout.isHidden = false
    }
    @objc func rotateCounterclockwise(_ sender: Any?) { model.rotateCounterclockwise() }
    @objc func rotateClockwise(_ sender: Any?) { model.rotateClockwise() }
    @objc func mirrorHorizontally(_ sender: Any?) { model.mirrorHorizontally() }
    @objc func toggleGrid(_ sender: Any?) { model.toggleGrid() }
    @objc func chooseGridKind(_ sender: Any?) {
        if let name = (sender as? NSMenuItem)?.representedObject as? String, let kind = GridKind(rawValue: name) {
            model.showGrid(kind)
        }
    }
    /// Colour and opacity change the line, shown or not.
    @objc func chooseGridColor(_ sender: Any?) {
        if let name = (sender as? NSMenuItem)?.representedObject as? String, let color = GridColor(rawValue: name) {
            model.grid.color = color
        }
    }
    @objc func chooseGridOpacity(_ sender: Any?) {
        if let opacity = (sender as? NSMenuItem)?.representedObject as? Double { model.grid.opacity = opacity }
    }
    @objc func chooseGridDivisions(_ sender: Any?) {
        if let divisions = (sender as? NSMenuItem)?.representedObject as? Int {
            model.grid.fineDivisions = divisions
            model.showGrid(.fine)
        }
    }

    // MARK: Alerts

    /// Anomalies and failed stop sequences are shown in a message: they may
    /// mean the scanner needs attention. The cases and the moment are those of
    /// the alerts before lot A; only the presentation changed (step B): the
    /// technical text goes to Details, the advice to the steps.
    private func alertIfNeeded(for state: PreviewSession.State) {
        switch state {
        case .failed(let failure):
            var details = failure.description
            var context = model.session.kind == .scan
                ? String(localized: "The scan stopped after an anomaly", comment: "Alert title")
                : String(localized: "The preview stopped after an anomaly", comment: "Alert title")
            var steps: [String] = []
            if let outcome = failure.emergencyStop {
                details += "\n\n" + Strings.emergencyStop(outcome)
                if IssueClassifier.stopFailed(outcome) {
                    // Visible, as in the alert before: the stop did not complete.
                    context += "\n" + Strings.emergencyStop(outcome)
                    steps.append(Strings.powerCycleBeforeAnything)
                }
            }
            if model.lastPreviewWasReal {
                let advice: Advice
                switch failure.cause {
                case .anomaly(.couldNotOpen):
                    advice = Advice()  // nothing was sent: no advice to switch the scanner off
                case .anomaly(.unexpectedCarriagePosition), .anomaly(.startStateMismatch):
                    // Their own steps already say to switch the X1 off and on.
                    advice = realPreviewAdvice(stoppedBeforeScan: nil)
                case .anomaly(.unrecognisedStartState):
                    advice = realPreviewAdvice(stoppedBeforeScan: true)
                case .decoding:
                    // The scanner side completed, end of session included: only the log.
                    advice = realPreviewAdvice(stoppedBeforeScan: nil)
                case .anomaly:
                    advice = realPreviewAdvice(stoppedBeforeScan: failure.emergencyStop == nil)
                }
                // One power-cycle step, the strongest: "before anything else" wins.
                if steps.isEmpty { steps = advice.steps }
                details += advice.log
            }
            showIssue(UserIssue(IssueClassifier.id(for: failure), context: context, extraSteps: steps, details: details))
        case .finished where model.session.kind == .scan:
            if case .failure(let error) = model.lastScanSave {
                showIssue(UserIssue(IssueClassifier.id(for: error),
                                    context: String(localized: "The scan could not be saved", comment: "Alert title"),
                                    details: Strings.exportError(error)))
            }
        case .stopped(let outcome) where model.lastPreviewWasReal && model.session.kind == .scan:
            // Stop, change of source or quit during a scan on the real X1. `1b 00 08 06 01 00`
            // counts as SCAN: after it, the stop command was sent.
            let text = outcome.map(Strings.emergencyStop)
                ?? String(localized: "Scan stopped before its first SCAN; nothing more was sent.", comment: "Real scan stopped")
            showStopped(outcome, text: text, context: String(localized: "The scan on the real X1 was stopped", comment: "Alert title"))
        case .stopped(let outcome) where model.lastPreviewWasReal:
            // Stop, change of source or quit on the real X1: always reported, with the advice.
            let text = outcome.map(Strings.emergencyStop)
                ?? String(localized: "Preview stopped before SCAN; nothing more was sent.", comment: "Real preview stopped")
            showStopped(outcome, text: text, context: String(localized: "The preview on the real X1 was stopped", comment: "Alert title"))
        case .stopped(let outcome?) where outcome != .stoppedAndReady:
            showIssue(UserIssue(.stopIncomplete, details: Strings.emergencyStop(outcome)))
        default:
            break
        }
    }

    /// A run on the real X1 stopped on request (or by a change of source, or quitting).
    private func showStopped(_ outcome: EmergencyStopOutcome?, text: String, context: String) {
        let advice = realPreviewAdvice(stoppedBeforeScan: outcome == nil)
        let id: IssueID = IssueClassifier.stopFailed(outcome) ? .stopIncomplete : .stoppedByUser
        // A failed stop has its own, stronger step ("before anything else"): no second one.
        let steps = id == .stopIncomplete ? [] : advice.steps
        showIssue(UserIssue(id, context: context, extraSteps: steps, details: text + advice.log))
    }

    /// Steps and log after a run on the real X1 that did not complete.
    private struct Advice {
        var steps: [String] = []
        /// Appended to the details: the log's path.
        var log = ""
    }

    /// `stoppedBeforeScan` nil: only the log (the scanner side completed, or
    /// the message already gives its own advice).
    private func realPreviewAdvice(stoppedBeforeScan: Bool?) -> Advice {
        var advice = Advice()
        if stoppedBeforeScan == true {
            // The session and modes FlexColor set may still be active.
            advice.steps.append(Strings.powerCycleBeforeAnything)
        } else if stoppedBeforeScan == false {
            // The end of session (CF 00 02) is not sent on the stop path.
            advice.steps.append(String(localized: "Switch the X1 off and on again before another preview.",
                                       comment: "Advice after a preview on the real X1 stopped after SCAN"))
        }
        if let log = model.lastPreviewLog {
            advice.log += "\n\n" + String(localized: "Log: \(log.path(percentEncoded: false))", comment: "Path of the preview log")
            if model.lastPreviewLogIsIncomplete {
                advice.log += "\n" + String(localized: "Some lines could not be written: the log is incomplete.",
                                             comment: "Preview log incomplete")
            }
        }
        return advice
    }

    /// A message as a sheet of the main window.
    func showIssue(_ issue: UserIssue, extra: [(String, @MainActor () -> Void)] = []) {
        guard let window else { return }
        IssueSheet.present(issue, on: window, extra: extra)
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

/// Asked before every scan on the real X1: Start is enabled only when both
/// boxes are ticked. The frame and resolution are those of the capture.
@MainActor
enum RealScanConfirmationAlert {
    static func run(for window: NSWindow, start: @escaping @MainActor (RealScanConfirmation) -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Scan on the real X1", comment: "Confirmation title")
        alert.informativeText = String(
            localized: "FlexColor's captured 2 000 ppi scan will be sent to the scanner command for command. One value changes: the carriage position of the 400-line step, read on the scanner just before (within \(PreviewConfiguration.defaultPositionTolerance) of the capture). Any other difference stops it; Stop (⌘. or Esc) stays available. Every command is logged.\n\nThe capture's frame and resolution are used, not the panel's: 609 × 614 pixels at 2 000 ppi (7.7 × 7.8 mm), at the captured place. The panel's crop and resolution are ignored.\n\nHolder of the capture: 6×7, reference 50200403. Do not move it after the preview.",
            comment: "Confirmation text before a scan on the real X1")
        let boxes = [
            String(localized: "Same holder as the capture, film in place, nothing moved",
                   comment: "Real scan check"),
            String(localized: "Understood: the capture's frame and resolution", comment: "Real scan check"),
        ].map { NSButton(checkboxWithTitle: $0, target: nil, action: nil) }  // short titles: one line each
        let stack = NSStackView(views: boxes)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.frame = NSRect(x: 0, y: 0, width: max(460, stack.fittingSize.width), height: stack.fittingSize.height)
        alert.accessoryView = stack
        let startButton = alert.addButton(withTitle: String(localized: "Start Scan", comment: "Confirmation button"))
        alert.addButton(withTitle: String(localized: "Cancel", comment: "Button"))
        startButton.isEnabled = false
        startButton.keyEquivalent = ""  // Return must not start it by accident
        let watcher = ScanCheckboxWatcher(boxes: boxes, button: startButton)
        for box in boxes {
            box.target = watcher
            box.action = #selector(ScanCheckboxWatcher.changed(_:))
        }
        alert.beginSheetModal(for: window) { response in
            withExtendedLifetime(watcher) {}
            guard response == .alertFirstButtonReturn else { return }
            start(RealScanConfirmation(sameHolderNothingMoved: boxes[0].state == .on,
                                       captureFrameUnderstood: boxes[1].state == .on))
        }
    }

    @MainActor
    private final class ScanCheckboxWatcher: NSObject {
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

/// Asked before every preview on the real X1: Start is enabled only when
/// every box is ticked. The fourth box (switched off and on) is shown only
/// after a real preview that did not complete (docs/decisions.md).
@MainActor
enum RealPreviewConfirmationAlert {
    static func run(for window: NSWindow, askPowerCycle: Bool,
                    start: @escaping @MainActor (RealPreviewConfirmation) -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Preview on the real X1", comment: "Confirmation title")
        alert.informativeText = String(
            localized: "One of FlexColor's two captured previews, chosen by the scanner's state, will be sent to the scanner command for command. Any difference stops it; Stop (⌘. or Esc) stays available. Every command is logged.",
            comment: "Confirmation text before a preview on the real X1")
        var titles = [
            String(localized: "The X1 is on", comment: "Real preview check"),
            String(localized: "A holder is in place", comment: "Real preview check"),
            String(localized: "FlexColor is closed", comment: "Real preview check"),
        ]
        if askPowerCycle {
            titles.append(String(localized: "The X1 has been switched off and on since the interrupted preview",
                                 comment: "Real preview check, asked only after a real preview that did not complete"))
        }
        let boxes = titles.map { NSButton(checkboxWithTitle: $0, target: nil, action: nil) }
        let stack = NSStackView(views: boxes)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.frame = NSRect(x: 0, y: 0, width: 420, height: stack.fittingSize.height)
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
            start(RealPreviewConfirmation(scannerOn: ticked[0], holderInPlace: ticked[1], flexColorClosed: ticked[2],
                                          powerCycledSinceLastRealPreview: askPowerCycle && ticked[3]))
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
