// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import X1ScanCore

/// Image area on the left, palette column (an inspector item) on the right.
/// In icon-bar mode the column is narrowed to a fixed width.
@MainActor
final class MainSplitViewController: NSSplitViewController {
    private static let iconBarWidth: CGFloat = 52

    private let model: AppModel
    private let paletteItem: NSSplitViewItem
    private var observers: [Observing] = []
    private var appliedMode: ColumnMode?

    init(model: AppModel) {
        self.model = model
        let canvas = CanvasViewController(model: model)
        let column = NSHostingController(rootView: PaletteColumnView(model: model))
        column.sizingOptions = []
        paletteItem = NSSplitViewItem(inspectorWithViewController: column)
        paletteItem.canCollapse = false
        paletteItem.holdingPriority = .defaultHigh
        super.init(nibName: nil, bundle: nil)
        addSplitViewItem(NSSplitViewItem(viewController: canvas))
        addSplitViewItem(paletteItem)
        splitView.autosaveName = nil  // the width is part of PaletteLayout
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        observers.append(Observing { [weak self] in self?.applyColumnMode() })
    }

    private func applyColumnMode() {
        let layout = model.layout.layout
        guard layout.columnMode != appliedMode else { return }
        appliedMode = layout.columnMode
        switch layout.columnMode {
        case .expanded:
            paletteItem.minimumThickness = PaletteLayout.minimumColumnWidth
            paletteItem.maximumThickness = PaletteLayout.maximumColumnWidth
            setColumnWidth(layout.columnWidth)
        case .iconBar:
            paletteItem.minimumThickness = Self.iconBarWidth
            paletteItem.maximumThickness = Self.iconBarWidth
            setColumnWidth(Self.iconBarWidth)
        }
    }

    private func setColumnWidth(_ width: CGFloat) {
        guard splitView.subviews.count == 2 else { return }
        splitView.layoutSubtreeIfNeeded()
        splitView.setPosition(splitView.bounds.width - width - splitView.dividerThickness, ofDividerAt: 0)
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        // Remember the width chosen by dragging, in expanded mode only.
        guard appliedMode == .expanded, splitView.subviews.count == 2, view.window != nil,
              notification.userInfo?["NSSplitViewDividerIndex"] != nil else { return }
        model.layout.setColumnWidth(splitView.subviews[1].frame.width)
    }
}
