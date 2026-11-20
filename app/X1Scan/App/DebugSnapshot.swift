// SPDX-License-Identifier: MIT
#if DEBUG
import AppKit
import SwiftUI
import WebKit
import X1ScanCore

/// Debug builds only: lets a developer check the window without screen
/// recording permission. Launch arguments:
///   -X1ScanSnapshot <path.png>   render the window into a PNG after a few seconds
///   -X1ScanAutoPreview YES       start a preview on the virtual X1 at launch
///   -X1ScanHidePanel YES         hide the settings panel
///   -X1ScanZoomFill YES          Fill Window instead of the startup zoom
///   -X1ScanOpenHistogram YES     unfold the histogram in the panel
///   -X1ScanQuarterTurns <n>      turn the image n quarters clockwise (lot 1)
///   -X1ScanMirror YES            mirror the image (lot 1)
///   -X1ScanZones YES             show the exposure zones over the preview (lot 1)
///   -X1ScanGrid <kind>           show the grid: thirds, fine or centre (lot 1)
///   -X1ScanCropDemo YES          draw a centred crop on the preview before the snapshot
///                                (needs -X1ScanAutoPreview YES)
///   -X1ScanTool <tool>           select a tool: hand, zoom, crop, straighten (lot 1)
///   -X1ScanAngle <degrees>       fine angle, after the crop demo (lot 1)
///   -X1ScanTab <tab>             show a panel tab: prepare, scan, output (lot 1b)
///   -X1ScanPrintTooltips YES     print every tooltip with a shortcut (in the launch's language), quit
///   -X1ScanPanelWidth <points>   panel width (bounded to 280-480; saved like a drag)
///   -X1ScanAspect <a>            crop proportions: free, original or W:H, e.g. 24:36
///   -X1ScanKeyProbe YES          click the tabs and a field, press C or R after each, print
///                                the keyboard focus and the tool selected, quit (KeyProbe)
///   -X1ScanResizeProbe YES       resize the window, move the divider, hide and show the panel,
///                                print the sizes, put the window frame and panel layout back, quit
///   -X1ScanHelpSnapshot <path>   open the help window, write it (<path>, sidebar) and its page
///                                (<path>-page.png, `WKWebView.takeSnapshot`), quit (lot A)
///   -X1ScanHelpPage <id[#anchor]> the help page to open (default: index)
///   -X1ScanHelpSearch <text>     typed into the help's search field
/// The snapshot also writes each Settings pane, Scanner Information and the
/// About panel (`<path>-settings-<n>.png`, `<path>-info.png`,
/// `<path>-floating-*.png`), serial always masked.
/// These arguments change the saved panel layout like a user would.
/// Never used against the real scanner: the preview only runs on the virtual X1.
/// Write the PNGs outside the repository: they show the counters and the
/// (masked) serial number of the capture.
@MainActor
enum DebugSnapshot {
    static func run(window: NSWindow?, model: AppModel) {
        let arguments = UserDefaults.standard
        if arguments.bool(forKey: "X1ScanPrintTooltips") {
            for tooltip in ShortcutTooltip.allCases {
                FileHandle.standardError.write(Data("TOOLTIP \(tooltip.rawValue): \(Strings.tooltip(tooltip))\n".utf8))
            }
            NSApp.terminate(nil)
            return
        }
        if let path = arguments.string(forKey: "X1ScanHelpSnapshot") {
            helpSnapshot(to: path, arguments: arguments)
            return
        }
        if arguments.bool(forKey: "X1ScanHidePanel"), !model.panel.layout.isHidden { model.panel.toggleHidden() }
        if arguments.bool(forKey: "X1ScanZoomFill") { model.zoomToFill() }
        if arguments.bool(forKey: "X1ScanOpenHistogram"), model.panel.layout.isFolded(.histogram) {
            model.panel.toggleFolded(.histogram)
        }
        for _ in 0..<max(arguments.integer(forKey: "X1ScanQuarterTurns"), 0) { model.rotateClockwise() }
        if arguments.bool(forKey: "X1ScanMirror") { model.mirrorHorizontally() }
        if arguments.bool(forKey: "X1ScanZones") { model.showsExposureZones = true }
        if let tab = arguments.string(forKey: "X1ScanTab").flatMap(PanelTab.init(rawValue:)) { model.panel.select(tab) }
        if arguments.object(forKey: "X1ScanPanelWidth") != nil { model.panel.setWidth(arguments.double(forKey: "X1ScanPanelWidth")) }
        if let aspect = arguments.string(forKey: "X1ScanAspect") {
            let parts = aspect.split(separator: ":").compactMap { Double($0) }
            if aspect == "free" {
                model.setCropAspect(.free)
            } else if aspect == "original" {
                model.setCropAspect(.original)
            } else if parts.count == 2, let ratio = CropAspect.custom(parts[0], parts[1]) {
                model.setCropAspect(ratio)  // validated as the Custom… popover does
            } else {
                FileHandle.standardError.write(Data("X1ScanAspect: \(aspect) not understood\n".utf8))
            }
        }
        if let kind = arguments.string(forKey: "X1ScanGrid").flatMap(GridKind.init(rawValue:)) { model.showGrid(kind) }
        if arguments.bool(forKey: "X1ScanAutoPreview") { model.startPreview() }
        if arguments.bool(forKey: "X1ScanKeyProbe"), let window { KeyProbe.run(window: window, model: model) }
        if arguments.bool(forKey: "X1ScanResizeProbe"), let window {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                @MainActor func report(_ label: String) {
                    let split = (window.contentViewController as? NSSplitViewController)?.splitView
                    let widths = split?.arrangedSubviews.map { Int($0.frame.width) } ?? []
                    FileHandle.standardError.write(Data("PROBE \(label): window=\(window.frame.size) min=\(window.minSize) max=\(window.maxSize) contentMin=\(window.contentMinSize) panes=\(widths)\n".utf8))
                }
                report("start")
                let savedFrame = window.frame
                let savedLayout = model.panel.layout
                var frame = window.frame
                frame.size = NSSize(width: frame.width + 300, height: frame.height + 100)
                window.setFrame(frame, display: true)
                report("bigger")
                frame.size = NSSize(width: 900, height: 560)
                window.setFrame(frame, display: true)
                report("smaller")
                if let controller = window.contentViewController as? NSSplitViewController {
                    let split = controller.splitView
                    // Each bound of the panel (tool column included), then beyond both.
                    let tool = PanelColumnView.toolWidth
                    for width in [InspectorLayout.minimumWidth + tool, InspectorLayout.maximumWidth + tool,
                                  InspectorLayout.minimumWidth + tool - 40, InspectorLayout.maximumWidth + tool + 120] {
                        split.setPosition(split.bounds.width - width - split.dividerThickness, ofDividerAt: 0)
                        try? await Task.sleep(for: .milliseconds(300))
                        report("divider \(Int(width))")
                    }
                }
                window.layoutIfNeeded()
                report("after layout")
                let before = model.panel.layout.width
                model.panel.toggleHidden()
                try? await Task.sleep(for: .milliseconds(300))
                model.panel.toggleHidden()
                try? await Task.sleep(for: .milliseconds(500))
                FileHandle.standardError.write(Data("PROBE hide/show: width \(before) -> \(model.panel.layout.width)\n".utf8))
                report("after hide/show")
                // Put back what the probe changed (window frame and panel layout are saved).
                model.panel.layout = savedLayout
                window.setFrame(savedFrame, display: false)
                NSApp.terminate(nil)
            }
        }
        guard let path = arguments.string(forKey: "X1ScanSnapshot"), let window else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(arguments.bool(forKey: "X1ScanAutoPreview") ? 7 : 2))
            if arguments.bool(forKey: "X1ScanCropDemo") {
                // In preview pixels, on the final size (not the rows received so far).
                if let image = model.session.image {
                    model.cropRect = PixelRect(x: image.width / 4, y: image.expectedHeight / 4,
                                               width: image.width / 2, height: image.expectedHeight / 2)
                } else {
                    FileHandle.standardError.write(Data("X1ScanCropDemo: no preview image, no crop drawn\n".utf8))
                }
            }
            if arguments.object(forKey: "X1ScanAngle") != nil { model.setCropAngle(arguments.double(forKey: "X1ScanAngle")) }
            if let tool = arguments.string(forKey: "X1ScanTool").flatMap(Tool.init(rawValue:)) { model.tools.selected = tool }
            model.pointer = PixelCoordinate(x: 1000, y: 400)
            try? await Task.sleep(for: .milliseconds(300))
            FileHandle.standardError.write(Data("""
                state=\(model.session.state) lines=\(model.session.progress.linesReceived) \
                image=\(model.displayImage.map { "\($0.width)x\($0.height)" } ?? "nil") \
                viewport=\(model.viewport.magnification) mode=\(model.viewport.mode) view=\(model.viewSize) \
                histogram=\(model.histogram.pixelCount) reading=\(String(describing: model.pixelReading))

                """.utf8))
            guard let view = window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
            // Each split pane on its own as well (glass is not rendered by cacheDisplay).
            if let split = window.contentViewController as? NSSplitViewController {
                for (index, item) in split.splitViewItems.enumerated() {
                    let pane = item.viewController.view
                    guard let paneRep = pane.bitmapImageRepForCachingDisplay(in: pane.bounds) else { continue }
                    pane.cacheDisplay(in: pane.bounds, to: paneRep)
                    let panePath = path.replacingOccurrences(of: ".png", with: "-pane\(index).png")
                    try? paneRep.representation(using: .png, properties: [:])?.write(to: URL(filePath: panePath))
                }
            }
            render(AnyView(ScannerInfoView(model: model, alwaysMasksSerial: true)),
                   to: path.replacingOccurrences(of: ".png", with: "-info.png"))
            let settings = SettingsWindowController(model: model)
            if let settingsWindow = settings.window, let tabs = settingsWindow.contentViewController as? NSTabViewController {
                for index in tabs.tabViewItems.indices {
                    tabs.selectedTabViewItemIndex = index
                    try? await Task.sleep(for: .milliseconds(300))
                    guard let view = settingsWindow.contentView,
                          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(filePath: path.replacingOccurrences(of: ".png", with: "-settings-\(index).png")))
                }
            }
            // The About panel, with both licences (written as -floating-panel).
            (NSApp.delegate as? AppDelegate)?.showAbout(nil)
            try? await Task.sleep(for: .milliseconds(500))
            // Other panels (colour panel excluded).
            for panel in NSApp.windows where panel is NSPanel && panel.isVisible && !(panel is NSColorPanel) {
                guard let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let name = panel.identifier?.rawValue ?? "panel"
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(filePath: path.replacingOccurrences(of: ".png", with: "-floating-\(name).png")))
            }
            NSApp.terminate(nil)
        }
    }

    /// The help window at a page (and a search), then quit.
    private static func helpSnapshot(to path: String, arguments: UserDefaults) {
        Task { @MainActor in
            guard let delegate = NSApp.delegate as? AppDelegate else { return }
            let target = (arguments.string(forKey: "X1ScanHelpPage") ?? HelpLibrary.pageIDs[0])
                .split(separator: "#", maxSplits: 1).map(String.init)
            delegate.showHelp(page: target[0], anchor: target.count > 1 ? target[1] : nil)
            if let query = arguments.string(forKey: "X1ScanHelpSearch") { delegate.helpControllerForDebug?.model.query = query }
            try? await Task.sleep(for: .seconds(2))
            if let view = delegate.helpControllerForDebug?.window?.contentView {
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
                }
                if let web = firstSubview(of: WKWebView.self, in: view),
                   let image = try? await web.takeSnapshot(configuration: nil),
                   let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(filePath: path.replacingOccurrences(of: ".png", with: "-page.png")))
                }
            }
            NSApp.terminate(nil)
        }
    }

    private static func firstSubview<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews { if let match = firstSubview(of: type, in: subview) { return match } }
        return nil
    }

    private static func render(_ view: AnyView, to path: String) {
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
    }
}
#endif
