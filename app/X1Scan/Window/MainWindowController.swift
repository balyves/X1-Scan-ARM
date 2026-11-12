// SPDX-License-Identifier: MIT
import AppKit
import X1ScanCore

/// The main window: toolbar, split view (image area, palette column), menu
/// actions and their validation. All decisions come from `AppModel`; this
/// class only forwards and mirrors.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate,
    NSMenuItemValidation, NSToolbarItemValidation {
    private let model: AppModel
    private let splitController: MainSplitViewController
    private var observers: [Observing] = []
    private var lastAlertedState: PreviewSession.State?

    private enum Item {
        static let preview = NSToolbarItem.Identifier("preview")
        static let scan = NSToolbarItem.Identifier("scan")
        static let stop = NSToolbarItem.Identifier("stop")
        static let export = NSToolbarItem.Identifier("export")
        static let palettes = NSToolbarItem.Identifier("palettes")
    }

    init(model: AppModel) {
        self.model = model
        splitController = MainSplitViewController(model: model)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "X1 Scan"
        window.minSize = NSSize(width: 760, height: 480)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentViewController = splitController
        window.setContentSize(NSSize(width: 1280, height: 820))
        window.center()
        window.setFrameAutosaveName("MainWindow")
        window.toolbarStyle = .unified
        super.init(window: window)
        window.delegate = self

        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        observers.append(Observing { [weak self] in self?.modelChanged() })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Called whenever an observed model value changes.
    private func modelChanged() {
        let toolbar = model.toolbar  // read inside the tracking: re-validated on every change
        let state = model.session.state
        window?.toolbar?.validateVisibleItems()
        if let item = window?.toolbar?.items.first(where: { $0.itemIdentifier == Item.preview }) {
            item.toolTip = toolbar.previewBlock.map(Strings.previewBlock)
                ?? String(localized: "Run a preview on the virtual X1 (⌘R)", comment: "Tooltip")
        }
        if state != lastAlertedState {
            lastAlertedState = state
            Task { @MainActor in self.alertIfNeeded(for: state) }
        }
    }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Item.preview, Item.scan, .space, Item.stop, .flexibleSpace, Item.export, Item.palettes]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.target = self
        item.autovalidates = true
        switch identifier {
        case Item.preview:
            configure(item, String(localized: "Preview", comment: "Menu item and toolbar button"), "eye",
                      #selector(startPreview(_:)))
        case Item.scan:
            configure(item, String(localized: "Scan", comment: "Toolbar button"), "scanner",
                      #selector(startScan(_:)))
            item.toolTip = String(localized: "Scanning comes in a later version.", comment: "Tooltip")
        case Item.stop:
            configure(item, String(localized: "Stop", comment: "Menu item and toolbar button"), "stop.fill",
                      #selector(stopPreview(_:)))
            item.style = .prominent
            item.backgroundTintColor = .systemRed
            item.toolTip = String(localized: "Stop the preview (⌘. or Esc)", comment: "Tooltip")
        case Item.export:
            configure(item, String(localized: "Export", comment: "Palette title"), "square.and.arrow.up",
                      #selector(exportImage(_:)))
            item.toolTip = String(localized: "Export a raw 16-bit TIFF (⇧⌘E)", comment: "Tooltip")
        case Item.palettes:
            configure(item, String(localized: "Palettes", comment: "Toolbar button"), "sidebar.trailing",
                      #selector(toggleColumnMode(_:)))
            item.toolTip = String(localized: "Show the palettes in full or as icons (⌥⌘P)", comment: "Tooltip")
        default:
            return nil
        }
        return item
    }

    private func configure(_ item: NSToolbarItem, _ label: String, _ symbol: String, _ action: Selector) {
        item.label = label
        item.paletteLabel = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.action = action
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        validate(item.action)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(selectVirtualSource(_:)): menuItem.state = model.source == .virtual ? .on : .off
        case #selector(selectRealSource(_:)): menuItem.state = model.source == .real ? .on : .off
        case #selector(toggleColumnMode(_:)): menuItem.state = model.layout.layout.columnMode == .iconBar ? .on : .off
        case #selector(selectHandTool(_:)): menuItem.state = model.tools.selected == .hand ? .on : .off
        case #selector(selectZoomTool(_:)): menuItem.state = model.tools.selected == .zoom ? .on : .off
        case #selector(selectCropTool(_:)): menuItem.state = model.tools.selected == .crop ? .on : .off
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
        case #selector(zoomToFit(_:)), #selector(zoomToActualSize(_:)): return model.session.image != nil
        case #selector(selectRealSource(_:)), #selector(selectVirtualSource(_:)): return !model.session.isBusy
        case #selector(readRealScanner(_:)): return model.source == .real && model.realStatus != .reading
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
    @objc func zoomToActualSize(_ sender: Any?) { model.zoomToActualSize() }
    @objc func zoomIn(_ sender: Any?) { model.zoomIn() }
    @objc func zoomOut(_ sender: Any?) { model.zoomOut() }
    @objc func selectHandTool(_ sender: Any?) { model.tools.selected = .hand }
    @objc func selectZoomTool(_ sender: Any?) { model.tools.selected = .zoom }
    @objc func selectCropTool(_ sender: Any?) { model.tools.selected = .crop }
    @objc func toggleColumnMode(_ sender: Any?) { model.layout.toggleColumnMode() }
    @objc func resetPaletteLayout(_ sender: Any?) { model.layout.resetToDefault() }
    @objc func selectVirtualSource(_ sender: Any?) { model.source = .virtual }
    @objc func selectRealSource(_ sender: Any?) { model.source = .real }

    @objc func readRealScanner(_ sender: Any?) {
        Task { await model.readRealScanner() }
    }

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

/// The folder chooser of the Export palette and of File > Choose Export Folder.
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
