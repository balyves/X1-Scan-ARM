// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import X1ScanCore

/// Detached palettes: one floating utility panel (NSPanel) per palette whose
/// placement is `.floating`, kept in step with `PaletteLayout`. Moving or
/// resizing a panel saves its frame; closing it hides the palette; its
/// Attach button puts it back in the column.
@MainActor
final class FloatingPalettes: NSObject, NSWindowDelegate {
    /// The one instance, set by the main window; used by the palette menus.
    private(set) static weak var shared: FloatingPalettes?

    private let model: AppModel
    private weak var mainWindow: NSWindow?
    private var panels: [PaletteID: NSPanel] = [:]
    private var observers: [Observing] = []
    /// Set while `sync` closes or moves panels, so that it is not taken for
    /// the user hiding or moving the palette.
    private var changingFromModel = false

    init(model: AppModel, mainWindow: NSWindow?) {
        self.model = model
        self.mainWindow = mainWindow
        super.init()
        Self.shared = self
        observers.append(Observing { [weak self] in self?.sync() })
    }

    /// Detaches `id` into a panel at `screenPoint` (top left), or beside the main window.
    static func detach(_ id: PaletteID, model: AppModel, at screenPoint: NSPoint? = nil) {
        let size = NSSize(width: 300, height: 360)
        var origin: NSPoint
        if let screenPoint {
            origin = NSPoint(x: screenPoint.x - 40, y: screenPoint.y - size.height + 12)
        } else if let window = shared?.mainWindow {
            let index = CGFloat(model.layout.layout.visibleFloatingPalettes.count)
            origin = NSPoint(x: window.frame.maxX - size.width - 320 - index * 24,
                             y: window.frame.maxY - size.height - 90 - index * 24)
        } else {
            origin = NSPoint(x: 200, y: 200)
        }
        if let screen = (shared?.mainWindow?.screen ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
            origin.y = min(max(origin.y, screen.minY), screen.maxY - size.height)
        }
        model.layout.detach(id, frame: StoredFrame(x: origin.x, y: origin.y, width: size.width, height: size.height))
    }

    private func sync() {
        let layout = model.layout.layout
        let wanted = layout.visibleFloatingPalettes
        for (id, panel) in panels where !wanted.contains(id) {
            changingFromModel = true
            panel.close()
            changingFromModel = false
            panels[id] = nil
        }
        for id in wanted {
            guard case .floating(let stored) = layout.placement(of: id) else { continue }
            let frame = NSRect(x: stored.x, y: stored.y, width: stored.width, height: stored.height)
            if let panel = panels[id] {
                // The panel's own frame wins while the user moves or resizes it; the
                // model's frame is applied otherwise (workspace, reset).
                if panel.frame != frame, !panel.inLiveResize {
                    changingFromModel = true
                    panel.setFrame(frame, display: true)
                    changingFromModel = false
                }
            } else {
                panels[id] = makePanel(for: id, frame: frame)
            }
        }
    }

    private func makePanel(for id: PaletteID, frame stored: NSRect) -> NSPanel {
        // A saved frame may be on a screen that is gone, or damaged: keep it visible and usable.
        var frame = stored
        frame.size.width = max(frame.width, 240)
        frame.size.height = max(frame.height, 160)
        if let visible = (NSScreen.screens.first { $0.visibleFrame.intersects(frame) } ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        let panel = NSPanel(contentRect: frame,
                            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.setFrame(frame, display: false)
        panel.title = Strings.paletteTitle(id)
        panel.isFloatingPanel = true
        panel.collectionBehavior.insert(.fullScreenAuxiliary)  // stays with the main window in full screen
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.minSize = NSSize(width: 240, height: 160)
        panel.identifier = NSUserInterfaceItemIdentifier(id.rawValue)
        panel.contentView = NSHostingView(rootView: FloatingPaletteView(model: model, id: id))
        panel.delegate = self
        panel.orderFront(nil)
        return panel
    }

    // MARK: NSWindowDelegate

    func windowDidMove(_ notification: Notification) { saveFrame(of: notification.object) }
    func windowDidResize(_ notification: Notification) { saveFrame(of: notification.object) }
    func windowDidEndLiveResize(_ notification: Notification) { saveFrame(of: notification.object) }

    func windowWillClose(_ notification: Notification) {
        guard !changingFromModel, let panel = notification.object as? NSPanel, let id = palette(of: panel) else { return }
        panels[id] = nil
        model.layout.setHidden(id, true)  // shown again from the Window menu, at the same place
    }

    private func saveFrame(of object: Any?) {
        guard !changingFromModel, let panel = object as? NSPanel, let id = palette(of: panel) else { return }
        let frame = panel.frame
        model.layout.setFloatingFrame(StoredFrame(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height),
                                      for: id)
    }

    private func palette(of panel: NSPanel) -> PaletteID? {
        panels.first { $0.value === panel }?.key
    }
}

/// Content of a floating panel: the palette, with an Attach button.
private struct FloatingPaletteView: View {
    @Bindable var model: AppModel
    let id: PaletteID

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    // Drag handle: dropped on the column, the palette is attached there.
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .contentShape(.rect)
                        .draggable(PaletteDrag.payload(id)) {
                            Text(Strings.paletteTitle(id)).font(.headline).padding(6)
                        }
                        .help(Text("Drag onto the column to attach", comment: "Tooltip: floating palette drag handle"))
                    Spacer()
                    Button(String(localized: "Attach", comment: "Floating palette: put it back in the column")) {
                        model.layout.attach(id)
                    }
                    .controlSize(.small)
                }
                PaletteContent(model: model, id: id)
            }
            .padding(12)
        }
        .frame(minWidth: 240, minHeight: 120)
    }
}

/// Root view of the image area: accepts a palette dropped on it and
/// detaches it into a floating panel at the drop point.
final class PaletteDropView: NSView {
    var onDrop: ((PaletteID, NSPoint) -> Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.string])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private func palette(in info: any NSDraggingInfo) -> PaletteID? {
        info.draggingPasteboard.string(forType: .string).flatMap(PaletteDrag.palette(from:))
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { operation(for: sender) }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { operation(for: sender) }

    /// The operation the drag source allows (SwiftUI's draggable may offer only copy).
    private func operation(for sender: any NSDraggingInfo) -> NSDragOperation {
        guard palette(in: sender) != nil else { return [] }
        let mask = sender.draggingSourceOperationMask
        return mask.contains(.move) ? .move : (mask.contains(.copy) ? .copy : .generic)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let id = palette(in: sender), let window else { return false }
        let point = window.convertPoint(toScreen: sender.draggingLocation)
        return onDrop?(id, point) ?? false
    }
}
