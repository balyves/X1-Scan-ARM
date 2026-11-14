// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import X1ScanCore

/// The image area: a magnifying scroll view holding the image, the floating
/// tool capsule on the left and the status bar at the bottom.
@MainActor
final class CanvasViewController: NSViewController {
    private let model: AppModel
    private let scrollView = NSScrollView()
    private let canvas: ImageCanvasView
    private var observers: [Observing] = []
    private var appliedDocumentSize: CGSize = .zero

    init(model: AppModel) {
        self.model = model
        canvas = ImageCanvasView(model: model)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let root = NSView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView = CenteringClipView()
        scrollView.documentView = canvas
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = Viewport.minimumMagnification
        scrollView.maxMagnification = Viewport.maximumMagnification
        scrollView.drawsBackground = true
        root.addSubview(scrollView)

        let capsule = NSHostingView(rootView: ToolCapsuleView(model: model))
        capsule.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(capsule)

        let status = NSHostingView(rootView: StatusBarView(model: model))
        status.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(status)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            // Below the toolbar, so that Zoom to Fit shows the whole image.
            scrollView.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: status.topAnchor),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            capsule.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            capsule.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])
        view = root

        NotificationCenter.default.addObserver(self, selector: #selector(liveMagnifyEnded(_:)),
                                               name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observers.append(Observing { [weak self] in self?.applyViewport() })
        observers.append(Observing { [weak self] in
            guard let self else { return }
            let level = model.settings.canvasBackground.srgbLevel
            scrollView.backgroundColor = NSColor(srgbRed: level, green: level, blue: level, alpha: 1)
        })
        observers.append(Observing { [weak self] in
            guard let self else { return }
            _ = model.session.imageRevision
            model.refreshImage()
        })
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(canvas)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let size = scrollView.contentSize
        if size != model.viewSize { model.viewSizeChanged(size) }
    }

    /// Mirrors the model's viewport in the scroll view.
    private func applyViewport() {
        let viewport = model.viewport
        let size = viewport.documentSize
        if size != appliedDocumentSize {
            appliedDocumentSize = size
            canvas.setFrameSize(size)
        }
        let target = CGFloat(viewport.magnification)
        if abs(scrollView.magnification - target) > 0.0001 {
            let visible = scrollView.documentVisibleRect
            let center = NSPoint(x: visible.midX, y: visible.midY)
            scrollView.setMagnification(target, centeredAt: center)
        }
    }

    @objc private func liveMagnifyEnded(_ notification: Notification) {
        model.magnificationChanged(Double(scrollView.magnification))
    }
}

/// Keeps the document centred when it is smaller than the visible area.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        let frame = document.frame
        if rect.width > frame.width { rect.origin.x = (frame.width - rect.width) / 2 }
        if rect.height > frame.height { rect.origin.y = (frame.height - rect.height) / 2 }
        return rect
    }
}
