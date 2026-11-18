// SPDX-License-Identifier: MIT
#if DEBUG
import AppKit
import SwiftUI
import X1ScanCore

/// Debug builds only: lets a developer check the window without screen
/// recording permission. Launch arguments:
///   -X1ScanSnapshot <path.png>   render the window into a PNG after a few seconds
///   -X1ScanAutoPreview YES       start a preview on the virtual X1 at launch
///   -X1ScanHidePanel YES         hide the settings panel
///   -X1ScanZoomFill YES          Fill Window instead of the startup zoom
///   -X1ScanOpenHistogram YES     unfold the histogram in the panel
///   -X1ScanCropDemo YES          draw a centred crop on the preview before the snapshot
///                                (needs -X1ScanAutoPreview YES)
///   -X1ScanResizeProbe YES       resize the window, move the divider, hide and show the panel,
///                                print the sizes, put the window frame and panel layout back, quit
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
        if arguments.bool(forKey: "X1ScanHidePanel"), !model.panel.layout.isHidden { model.panel.toggleHidden() }
        if arguments.bool(forKey: "X1ScanZoomFill") { model.zoomToFill() }
        if arguments.bool(forKey: "X1ScanOpenHistogram"), model.panel.layout.isFolded(.histogram) {
            model.panel.toggleFolded(.histogram)
        }
        if arguments.bool(forKey: "X1ScanAutoPreview") { model.startPreview() }
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
