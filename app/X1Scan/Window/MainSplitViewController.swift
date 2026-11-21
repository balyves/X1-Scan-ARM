// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import X1ScanCore

/// Image area on the left; on the right, the tool column glued to the
/// settings panel, in one split view item. The settings panel can be hidden
/// alone (the tool column stays): View › Hide Settings Panel (⌥⌘P), or the
/// divider dragged to the right edge; it comes back with ⌥⌘P, ⌥⌘1 to ⌥⌘3,
/// or the divider dragged from the edge (user's request of 2026-11-21).
/// The state is saved (`InspectorLayout.isHidden`).
@MainActor
final class MainSplitViewController: NSSplitViewController, NSViewToolTipOwner {
    private let model: AppModel
    private let panelItem: NSSplitViewItem
    private var observers: [Observing] = []
    private var applyingWidth = false
    /// False until the saved width has been applied: the first layout passes
    /// (panel at its minimum) must not be saved over it.
    private var widthRestored = false
    /// The hidden state the split view shows now (the model's may be ahead).
    private var shownHidden = false
    /// The panel's width when the current drag of the divider began: put
    /// back when the drag hides the panel, so that it comes back at the
    /// width it had, not at the smallest one it went through.
    private var widthAtDragStart: Double?

    /// The panel item's thickness with the settings panel shown, at least and at most.
    private static let shownMinimum: CGFloat = InspectorLayout.minimumWidth + PanelColumnView.toolWidth
    private static let shownMaximum: CGFloat = InspectorLayout.maximumWidth + PanelColumnView.toolWidth
    /// A drag hides the panel past half its smallest width; it shows it again a little further
    /// left, so that a hesitating drag does not make it flicker.
    private static let hideBelow: CGFloat = PanelColumnView.toolWidth + InspectorLayout.minimumWidth / 2 - 20
    private static let showAbove: CGFloat = PanelColumnView.toolWidth + InspectorLayout.minimumWidth / 2 + 20

    init(model: AppModel) {
        self.model = model
        let canvas = CanvasViewController(model: model)
        let panel = NSHostingController(rootView: PanelColumnView(model: model))
        panel.sizingOptions = []
        // A plain item: the panel is a fixed part of the window, not an inspector.
        panelItem = NSSplitViewItem(viewController: panel)
        // Never collapsed: hiding the settings panel keeps the tool column, so
        // the item narrows to the column instead (applyHidden).
        panelItem.canCollapse = false
        // Just above the image area (250): resizing the window resizes the image
        // area, and dragging the divider still moves (a holding priority of 750
        // was above the drag's and froze the panel at its minimum width).
        panelItem.holdingPriority = NSLayoutConstraint.Priority(260)
        panelItem.minimumThickness = Self.shownMinimum
        panelItem.maximumThickness = Self.shownMaximum
        super.init(nibName: nil, bundle: nil)
        // Before the items: tells when a drag of the divider begins and ends.
        let divided = DividerTrackingSplitView()
        divided.isVertical = true
        divided.dividerStyle = .thin
        splitView = divided
        divided.dragBegan = { [weak self] in
            guard let self else { return }
            widthAtDragStart = shownHidden ? nil : model.panel.layout.width
        }
        divided.dragEnded = { [weak self] in self?.widthAtDragStart = nil }
        addSplitViewItem(NSSplitViewItem(viewController: canvas))
        addSplitViewItem(panelItem)
        splitView.autosaveName = nil  // the width is part of InspectorLayout
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        observers.append(Observing { [weak self] in self?.applyHidden() })
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // After the window's first layout pass, otherwise the position is overridden.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if shownHidden { setThickness(PanelColumnView.toolWidth) } else { setPanelWidth(model.panel.layout.width) }
            widthRestored = true
            updateToolTip()
        }
    }

    /// The model's hidden state, from a command (⌥⌘P, ⌥⌘1…) or a drag. The
    /// image area then grows or shrinks and Fit or Fill is recomputed.
    private func applyHidden() {
        let hidden = model.panel.layout.isHidden
        guard hidden != shownHidden else { return }
        setThicknessLimits(hidden: hidden)
        // The layout passes of the change must not save an intermediate width.
        let width = model.panel.layout.width
        applyingWidth = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if shownHidden { setThickness(PanelColumnView.toolWidth) } else { setPanelWidth(width) }
            applyingWidth = false
            updateToolTip()
        }
    }

    /// Hidden: the item is exactly the tool column. Shown: the panel's limits.
    /// The order keeps the minimum below the maximum at every step.
    private func setThicknessLimits(hidden: Bool) {
        shownHidden = hidden
        if hidden {
            panelItem.minimumThickness = PanelColumnView.toolWidth
            panelItem.maximumThickness = PanelColumnView.toolWidth
        } else {
            panelItem.maximumThickness = Self.shownMaximum
            panelItem.minimumThickness = Self.shownMinimum
        }
    }

    private func setPanelWidth(_ width: Double) {
        setThickness(CGFloat(width) + PanelColumnView.toolWidth)
    }

    /// The panel item's thickness (tool column included).
    private func setThickness(_ total: CGFloat) {
        // arrangedSubviews: on macOS 26 subviews also holds the divider view.
        guard splitView.arrangedSubviews.count == 2 else { return }
        let wasApplying = applyingWidth
        applyingWidth = true
        defer { applyingWidth = wasApplying }
        splitView.layoutSubtreeIfNeeded()
        splitView.setPosition(splitView.bounds.width - total - splitView.dividerThickness, ofDividerAt: 0)
    }

    /// While the divider is dragged: past the threshold towards the right
    /// edge the settings panel hides (only the tool column stays), and back
    /// past it the panel shows again, at the width dragged to (at least its
    /// smallest). Also called by `setPosition`, whose positions are always
    /// on the right side of the threshold. Declared by NSSplitViewController
    /// for Swift but not implemented at run time: no call to super.
    override func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat,
                            ofSubviewAt dividerIndex: Int) -> CGFloat {
        guard dividerIndex == 0, widthRestored else { return proposedPosition }
        let available: CGFloat = splitView.bounds.width - splitView.dividerThickness
        let proposed: CGFloat = available - proposedPosition  // the panel item's thickness asked for
        let hide = shownHidden ? proposed <= Self.showAbove : proposed < Self.hideBelow
        if hide != shownHidden {
            if hide, let widthAtDragStart { model.panel.setWidth(widthAtDragStart) }
            setThicknessLimits(hidden: hide)
            if model.panel.layout.isHidden != hide { model.panel.layout.isHidden = hide }
            updateToolTip()
        }
        let thickness: CGFloat = hide ? PanelColumnView.toolWidth : min(max(proposed, Self.shownMinimum), Self.shownMaximum)
        return available - thickness
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        updateToolTip()
        // Remember the width chosen by dragging the divider (never the hidden state's column alone).
        guard widthRestored, !applyingWidth, !shownHidden, splitView.arrangedSubviews.count == 2, view.window != nil,
              notification.userInfo?["NSSplitViewDividerIndex"] != nil else { return }
        let width = Double(splitView.arrangedSubviews[1].frame.width - PanelColumnView.toolWidth)
        guard width >= InspectorLayout.minimumWidth - 0.5 else { return }
        model.panel.setWidth(width)
    }

    // MARK: Tooltip of the divider

    /// The divider's tooltip, over its whole height (a split view divider has none of its own).
    private func updateToolTip() {
        splitView.removeAllToolTips()
        guard splitView.arrangedSubviews.count == 2 else { return }
        let x = splitView.arrangedSubviews[0].frame.maxX
        // A little wider than the drawn line, as the area where the divider can be grabbed.
        let rect = NSRect(x: x - 2, y: 0, width: splitView.dividerThickness + 4, height: splitView.bounds.height)
        splitView.addToolTip(rect, owner: self, userData: nil)
    }

    nonisolated func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
                          userData data: UnsafeMutableRawPointer?) -> String {
        MainActor.assumeIsolated { Strings.tooltip(.panelDivider) }
    }
}

/// A split view that says when the user starts and stops dragging its
/// divider (its own mouse tracking runs inside `mouseDown`).
final class DividerTrackingSplitView: NSSplitView {
    var dragBegan: () -> Void = {}
    var dragEnded: () -> Void = {}

    override func mouseDown(with event: NSEvent) {
        dragBegan()
        super.mouseDown(with: event)
        dragEnded()
    }
}

/// Tool column and settings panel, side by side.
struct PanelColumnView: View {
    static let toolWidth: CGFloat = 37

    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            ToolColumnView(model: model)
            // Settings panel hidden (⌥⌘P, or the divider dragged to the edge): the column alone.
            if !model.panel.layout.isHidden {
                Divider()
                SettingsPanelView(model: model)
                    .frame(maxWidth: .infinity)
            }
        }
        // Opaque on its own: with the settings panel hidden, nothing else fills the item
        // (the window showed what was behind it).
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
