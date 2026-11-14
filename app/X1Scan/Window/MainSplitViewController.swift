// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import X1ScanCore

/// Image area on the left; on the right, the tool column glued to the
/// settings panel, in one split view item: they resize and hide together.
@MainActor
final class MainSplitViewController: NSSplitViewController {
    private let model: AppModel
    private let panelItem: NSSplitViewItem
    private var observers: [Observing] = []
    private var applyingWidth = false
    /// False until the saved width has been applied: the first layout passes
    /// (panel at its minimum) must not be saved over it.
    private var widthRestored = false

    init(model: AppModel) {
        self.model = model
        let canvas = CanvasViewController(model: model)
        let panel = NSHostingController(rootView: PanelColumnView(model: model))
        panel.sizingOptions = []
        // A plain item: the panel is a fixed part of the window, not an inspector.
        panelItem = NSSplitViewItem(viewController: panel)
        // Collapsible only while the model hides it (applyHidden), so that dragging
        // the divider or shrinking the window cannot hide it behind the model's back.
        panelItem.canCollapse = false
        // Just above the image area (250): resizing the window resizes the image
        // area, and dragging the divider still moves (a holding priority of 750
        // was above the drag's and froze the panel at its minimum width).
        panelItem.holdingPriority = NSLayoutConstraint.Priority(260)
        panelItem.minimumThickness = InspectorLayout.minimumWidth + PanelColumnView.toolWidth
        panelItem.maximumThickness = InspectorLayout.maximumWidth + PanelColumnView.toolWidth
        super.init(nibName: nil, bundle: nil)
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
            setPanelWidth(model.panel.layout.width)
            widthRestored = true
        }
    }

    /// One command hides or shows the panel (View menu). The image area then
    /// grows and Fit or Fill is recomputed.
    private func applyHidden() {
        let hidden = model.panel.layout.isHidden
        guard panelItem.isCollapsed != hidden else { return }
        if hidden {
            panelItem.canCollapse = true
            panelItem.isCollapsed = true
        } else {
            // The layout passes of showing the panel must not save an intermediate width.
            let width = model.panel.layout.width
            applyingWidth = true
            panelItem.isCollapsed = false
            panelItem.canCollapse = false
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                setPanelWidth(width)
                applyingWidth = false
            }
        }
    }

    private func setPanelWidth(_ width: Double) {
        // arrangedSubviews: on macOS 26 subviews also holds the divider view.
        guard splitView.arrangedSubviews.count == 2, !panelItem.isCollapsed else { return }
        let wasApplying = applyingWidth
        applyingWidth = true
        defer { applyingWidth = wasApplying }
        splitView.layoutSubtreeIfNeeded()
        let total = CGFloat(width) + PanelColumnView.toolWidth
        splitView.setPosition(splitView.bounds.width - total - splitView.dividerThickness, ofDividerAt: 0)
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        // Remember the width chosen by dragging the divider.
        guard widthRestored, !applyingWidth, !panelItem.isCollapsed, splitView.arrangedSubviews.count == 2, view.window != nil,
              notification.userInfo?["NSSplitViewDividerIndex"] != nil else { return }
        model.panel.setWidth(Double(splitView.arrangedSubviews[1].frame.width - PanelColumnView.toolWidth))
    }
}

/// Tool column and settings panel, side by side.
struct PanelColumnView: View {
    static let toolWidth: CGFloat = 37

    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            ToolColumnView(model: model)
            Divider()
            SettingsPanelView(model: model)
                .frame(maxWidth: .infinity)
        }
    }
}
