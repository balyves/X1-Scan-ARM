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
/// The snapshot also writes each Settings pane and Scanner Information
/// (`<path>-settings-<n>.png`, `<path>-info.png`), serial always masked.
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
        guard let path = arguments.string(forKey: "X1ScanSnapshot"), let window else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(arguments.bool(forKey: "X1ScanAutoPreview") ? 7 : 2))
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
