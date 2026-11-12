// SPDX-License-Identifier: MIT
import AppKit
import QuartzCore
import X1ScanCore

/// The document view of the image area. Its frame is the viewport's document
/// size (image height × pixel aspect ratio); the scroll view magnifies it.
///
/// The image is the contents of a layer. Core Animation colour-matches it
/// from its colour space (linear sRGB, provisional) to the display's profile.
@MainActor
final class ImageCanvasView: NSView {
    private let model: AppModel
    private let pendingLayer = CALayer()
    private let imageLayer = CALayer()
    private let cropLayer = CAShapeLayer()
    private var observers: [Observing] = []
    private var trackingArea: NSTrackingArea?
    private var dragStart: (point: NSPoint, origin: NSPoint)?
    private var cropStart: PixelCoordinate?
    private var appliedTool: Tool?

    init(model: AppModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        pendingLayer.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .nearest  // pixels stay visible when zoomed in
        imageLayer.minificationFilter = .trilinear
        cropLayer.fillColor = nil
        cropLayer.strokeColor = NSColor.controlAccentColor.cgColor
        cropLayer.lineWidth = 1.5
        cropLayer.lineDashPattern = [6, 4]
        for sublayer in [pendingLayer, imageLayer, cropLayer] {
            sublayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "path": NSNull()]
        }
        observers.append(Observing { [weak self] in self?.updateLayers() })
        observers.append(Observing { [weak self] in self?.updateCursor() })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func makeBackingLayer() -> CALayer {
        let layer = CALayer()
        layer.addSublayer(pendingLayer)
        layer.addSublayer(imageLayer)
        layer.addSublayer(cropLayer)
        return layer
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateLayers()
    }

    // MARK: Layers

    private func updateLayers() {
        let viewport = model.viewport
        let image = model.displayImage
        let crop = model.cropRect
        let pixelAspect = viewport.pixelAspectRatio
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pendingLayer.frame = bounds
        pendingLayer.isHidden = image == nil && model.session.image == nil
        imageLayer.contents = image
        if let image {
            // Only the rows received so far, stretched by the aspect ratio.
            imageLayer.frame = CGRect(x: 0, y: 0, width: CGFloat(image.width),
                                      height: CGFloat(image.height) * pixelAspect)
        }
        if let crop {
            cropLayer.path = CGPath(rect: viewport.documentRect(forPixelRect: crop), transform: nil)
            cropLayer.isHidden = false
        } else {
            cropLayer.isHidden = true
        }
        CATransaction.commit()
    }

    // MARK: Cursor and tracking

    private func updateCursor() {
        let tool = model.tools.effective
        guard tool != appliedTool else { return }
        appliedTool = tool
        window?.invalidateCursorRects(for: self)
    }

    private var toolCursor: NSCursor {
        switch model.tools.effective {
        case .hand: dragStart == nil ? .openHand : .closedHand
        case .zoom: NSEvent.modifierFlags.contains(.option) ? .zoomOut : .zoomIn
        case .crop: .crosshair
        }
    }

    override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: toolCursor)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow,
                                                         .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        model.pointer = pixel(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        model.pointer = nil
    }

    private func pixel(for event: NSEvent) -> PixelCoordinate? {
        model.viewport.pixel(atDocumentPoint: convert(event.locationInWindow, from: nil))
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        switch model.tools.effective {
        case .hand:
            guard let clip = enclosingScrollView?.contentView else { return }
            dragStart = (event.locationInWindow, clip.bounds.origin)
            NSCursor.closedHand.set()
        case .zoom:
            zoom(at: point, out: event.modifierFlags.contains(.option))
        case .crop:
            guard model.session.image != nil else { return }
            let clamped = clampedPixel(at: point)
            cropStart = clamped
            model.cropRect = PixelRect.spanning(clamped, clamped, width: model.viewport.imageWidth,
                                                height: model.viewport.imageHeight)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        model.pointer = pixel(for: event)
        switch model.tools.effective {
        case .hand:
            guard let (start, origin) = dragStart, let scrollView = enclosingScrollView else { return }
            // Window points to document points: divide by the magnification. The document is flipped.
            let scale = scrollView.magnification
            let dx = (event.locationInWindow.x - start.x) / scale
            let dy = (event.locationInWindow.y - start.y) / scale
            scrollView.contentView.scroll(to: NSPoint(x: origin.x - dx, y: origin.y + dy))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        case .crop:
            guard let cropStart else { return }
            let current = clampedPixel(at: convert(event.locationInWindow, from: nil))
            model.cropRect = PixelRect.spanning(cropStart, current, width: model.viewport.imageWidth,
                                                height: model.viewport.imageHeight)
        case .zoom:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        cropStart = nil
        window?.invalidateCursorRects(for: self)
    }

    private func clampedPixel(at point: NSPoint) -> PixelCoordinate {
        let viewport = model.viewport
        let x = min(max(Int(point.x.rounded(.down)), 0), max(viewport.imageWidth - 1, 0))
        let y = min(max(Int((point.y / viewport.pixelAspectRatio).rounded(.down)), 0), max(viewport.imageHeight - 1, 0))
        return PixelCoordinate(x: x, y: y)
    }

    /// Zoom tool: next step in or out, keeping the clicked point under the pointer.
    private func zoom(at point: NSPoint, out: Bool) {
        guard model.session.image != nil, let scrollView = enclosingScrollView else { return }
        if out { model.zoomOut() } else { model.zoomIn() }
        scrollView.setMagnification(CGFloat(model.viewport.magnification), centeredAt: point)
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let characters = event.charactersIgnoringModifiers, let first = characters.first else {
            super.keyDown(with: event)
            return
        }
        if first == " " {
            if !event.isARepeat { model.tools.spaceHeld = true }
        } else if let tool = Tool.forKey(first) {
            model.tools.selected = tool
        } else if event.keyCode == 53 {  // Esc
            model.stop()
        } else {
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            model.tools.spaceHeld = false
        } else {
            super.keyUp(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        if model.tools.effective == .zoom { window?.invalidateCursorRects(for: self) }
    }
}
