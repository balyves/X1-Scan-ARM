// SPDX-License-Identifier: MIT
import AppKit
import QuartzCore
import X1ScanCore

/// The document view of the image area. Its frame is the viewport's document
/// size (image height × pixel aspect ratio); the scroll view magnifies it.
///
/// The image is the contents of a layer. Core Animation colour-matches it
/// from its colour space (linear sRGB, provisional) to the display's profile.
///
/// Lot 1: the frame is the *displayed* document (turned and mirrored). The
/// image layers sit in a source layer whose transform turns them; the
/// overlays (crop) are drawn in display coordinates.
@MainActor
final class ImageCanvasView: NSView {
    private let model: AppModel
    /// Holds the image in source document coordinates; turned by its transform.
    private let sourceLayer = CALayer()
    private let pendingLayer = CALayer()
    private let imageLayer = CALayer()
    /// Clipped and near-noise pixels of the preview (lot 1), over the image, turned with it.
    private let zonesLayer = CALayer()
    private let cropLayer = CAShapeLayer()
    /// The grid (lot 1), in display coordinates; never part of an export.
    /// A light line over a wider dark one, visible on light and dark images.
    private let gridLayer = CAShapeLayer()
    private let gridEdgeLayer = CAShapeLayer()
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
        gridLayer.fillColor = nil
        gridLayer.strokeColor = NSColor.white.withAlphaComponent(0.85).cgColor
        gridEdgeLayer.fillColor = nil
        gridEdgeLayer.strokeColor = NSColor.black.withAlphaComponent(0.55).cgColor
        sourceLayer.anchorPoint = .zero
        sourceLayer.addSublayer(pendingLayer)
        sourceLayer.addSublayer(imageLayer)
        zonesLayer.contentsGravity = .resize
        zonesLayer.magnificationFilter = .nearest
        zonesLayer.opacity = 0.75
        sourceLayer.addSublayer(zonesLayer)
        for sublayer in [sourceLayer, pendingLayer, imageLayer, zonesLayer, cropLayer, gridEdgeLayer, gridLayer] {
            sublayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "path": NSNull(),
                                "transform": NSNull(), "lineWidth": NSNull(), "hidden": NSNull()]
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
        layer.addSublayer(sourceLayer)
        layer.addSublayer(gridEdgeLayer)
        layer.addSublayer(gridLayer)
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
        let sourceSize = viewport.sourceDocumentSize
        sourceLayer.bounds = CGRect(origin: .zero, size: sourceSize)
        sourceLayer.position = .zero
        sourceLayer.setAffineTransform(viewport.displayTransform)
        pendingLayer.frame = CGRect(origin: .zero, size: sourceSize)
        pendingLayer.isHidden = image == nil && model.session.image == nil
        imageLayer.contents = image
        if let image {
            // Only the rows received so far, stretched by the aspect ratio.
            imageLayer.frame = CGRect(x: 0, y: 0, width: CGFloat(image.width),
                                      height: CGFloat(image.height) * pixelAspect)
        }
        updateZones(viewport)
        updateGrid(viewport)
        if let crop {
            cropLayer.path = CGPath(rect: viewport.documentRect(forPixelRect: crop), transform: nil)
            cropLayer.isHidden = false
        } else {
            cropLayer.isHidden = true
        }
        CATransaction.commit()
    }

    /// The zone overlay: only on the preview it was measured on.
    private func updateZones(_ viewport: Viewport) {
        let size = model.exposureZonesSize
        guard model.showsExposureZones, model.session.kind == .preview, let zones = model.exposureZones,
              let size, size.width == viewport.imageWidth, size.height == viewport.imageHeight else {
            zonesLayer.isHidden = true
            zonesLayer.contents = nil
            return
        }
        zonesLayer.contents = zones
        zonesLayer.frame = CGRect(origin: .zero, size: viewport.sourceDocumentSize)
        zonesLayer.isHidden = false
    }

    /// The grid over the whole image shown, one screen point wide at any zoom.
    private func updateGrid(_ viewport: Viewport) {
        let grid = model.grid
        let area = CGRect(origin: .zero, size: viewport.documentSize)
        guard grid.isVisible, model.session.image != nil, area.width > 0 else {
            gridLayer.isHidden = true
            gridEdgeLayer.isHidden = true
            return
        }
        let path = CGMutablePath()
        for (start, end) in GridSettings.lines(grid.kind, in: area, fineDivisions: grid.fineDivisions) {
            path.move(to: start)
            path.addLine(to: end)
        }
        let point = 1 / max(viewport.magnification, 0.01)  // one screen point
        gridLayer.path = path
        gridLayer.lineWidth = point
        gridLayer.isHidden = false
        gridEdgeLayer.path = path
        gridEdgeLayer.lineWidth = 3 * point
        gridEdgeLayer.isHidden = false
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
        let point = viewport.sourceDocumentPoint(atDisplayPoint: point)
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
