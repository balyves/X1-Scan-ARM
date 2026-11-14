// SPDX-License-Identifier: MIT
#if DEBUG
import AppKit
import SwiftUI
import X1ScanCore

/// Debug builds only: lets a developer check the window without screen
/// recording permission. Launch arguments:
///   -X1ScanSnapshot <path.png>   render the window into a PNG after a few seconds
///   -X1ScanAutoPreview YES       start a preview on the virtual X1 at launch
///   -X1ScanIconBar YES           show the palettes as icons
///   -X1ScanHideAllPalettes YES   hide every palette (column collapsed)
///   -X1ScanZoomFill YES          Fill Window instead of the startup zoom
/// The snapshot also writes the Settings window (first tab) and Scanner
/// Information (`<path>-settings.png`, `<path>-info.png`), serial always masked.
/// Never used against the real scanner: the preview only runs on the virtual X1.
/// Write the PNGs outside the repository: they show the counters and the
/// (masked) serial number of the capture.
@MainActor
enum DebugSnapshot {
    static func run(window: NSWindow?, model: AppModel) {
        let arguments = UserDefaults.standard
        if arguments.bool(forKey: "X1ScanIconBar"), model.layout.layout.columnMode == .expanded {
            model.layout.toggleColumnMode()
        }
        if arguments.bool(forKey: "X1ScanHideAllPalettes"), !model.layout.layout.allHidden {
            model.layout.toggleAllHidden()
        }
        if arguments.bool(forKey: "X1ScanZoomFill") { model.zoomToFill() }
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
            // Palette contents through ImageRenderer (scroll views are not captured by cacheDisplay).
            let palettes = VStack(alignment: .leading, spacing: 16) {
                ForEach(model.layout.registry.ids, id: \.self) { id in
                    Text(Strings.paletteTitle(id)).font(.headline)
                    PaletteContent(model: model, id: id)
                }
            }
            .padding(12)
            .frame(width: 270)
            .background(Color(nsColor: .windowBackgroundColor))
            let renderer = ImageRenderer(content: palettes)
            renderer.scale = 2
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff) {
                try? bitmap.representation(using: .png, properties: [:])?
                    .write(to: URL(filePath: path.replacingOccurrences(of: ".png", with: "-palettes.png")))
            }
            // Settings tabs and Scanner Information, in offscreen windows (AppKit controls included).
            let tabs: [AnyView] = [AnyView(SettingsView(model: model)), AnyView(ScannerInfoView(model: model, alwaysMasksSerial: true))]
            for (index, view) in tabs.enumerated() {
                let suffix = index == 0 ? "-settings.png" : "-info.png"
                render(view, to: path.replacingOccurrences(of: ".png", with: suffix))
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
