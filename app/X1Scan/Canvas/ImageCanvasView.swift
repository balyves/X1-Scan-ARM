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
    /// One line of one screen point; green by default (apart from the crop
    /// frame, the rule in yellow and the exposure zones in red and blue),
    /// colour and opacity chosen by the user.
    private let gridLayer = CAShapeLayer()
    /// Crop mode (lot 1): the image outside the frame darkened, the frame's handles.
    private let shadeLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    /// The straightening rule and its label.
    private let rulerLayer = CAShapeLayer()
    private let rulerEdgeLayer = CAShapeLayer()
    private let rulerLabel = CATextLayer()
    private var observers: [Observing] = []
    private var trackingArea: NSTrackingArea?
    private var dragStart: (point: NSPoint, origin: NSPoint)?
    private var cropDrag: CropDrag?
    /// The rule drawn: its ends (display coordinates) and the result, until the next one.
    private var ruler: (start: CGPoint, end: CGPoint, label: String?)?
    private var appliedTool: Tool?

    /// What a drag with the crop tool does.
    private enum CropDrag {
        /// A new frame from this point.
        case draw(from: CGPoint)
        /// The frame moved, from where the drag started.
        case move(from: CGPoint, frame: CGRect)
        /// A corner dragged; the opposite one stays.
        case resize(fixed: CGPoint)
    }

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
        shadeLayer.fillColor = NSColor.black.withAlphaComponent(0.5).cgColor
        shadeLayer.fillRule = .evenOdd
        handlesLayer.fillColor = NSColor.white.cgColor
        handlesLayer.strokeColor = NSColor.black.withAlphaComponent(0.6).cgColor
        rulerLayer.fillColor = NSColor.systemYellow.cgColor
        rulerLayer.strokeColor = NSColor.systemYellow.cgColor
        rulerEdgeLayer.strokeColor = NSColor.black.withAlphaComponent(0.6).cgColor
        rulerEdgeLayer.fillColor = nil
        rulerLabel.foregroundColor = NSColor.systemYellow.cgColor
        rulerLabel.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        rulerLabel.cornerRadius = 3
        rulerLabel.alignmentMode = .center
        rulerLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        sourceLayer.anchorPoint = .zero
        sourceLayer.addSublayer(pendingLayer)
        sourceLayer.addSublayer(imageLayer)
        zonesLayer.contentsGravity = .resize
        zonesLayer.magnificationFilter = .nearest
        zonesLayer.opacity = 0.75
        sourceLayer.addSublayer(zonesLayer)
        for sublayer in [sourceLayer, pendingLayer, imageLayer, zonesLayer, cropLayer, gridLayer,
                         shadeLayer, handlesLayer, rulerEdgeLayer, rulerLayer, rulerLabel] {
            sublayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "path": NSNull(),
                                "transform": NSNull(), "lineWidth": NSNull(), "hidden": NSNull(),
                                "string": NSNull(), "fontSize": NSNull(), "frame": NSNull()]
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
        layer.addSublayer(shadeLayer)
        layer.addSublayer(gridLayer)
        layer.addSublayer(cropLayer)
        layer.addSublayer(handlesLayer)
        layer.addSublayer(rulerEdgeLayer)
        layer.addSublayer(rulerLayer)
        layer.addSublayer(rulerLabel)
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
        updateCrop(viewport)
        updateRuler(viewport)
        CATransaction.commit()
    }

    /// One screen point, in document coordinates.
    private func screenPoint(_ viewport: Viewport) -> CGFloat { 1 / max(viewport.magnification, 0.01) }

    /// The frame: dashed outside crop mode; in crop mode solid, with handles, the rest darkened.
    private func updateCrop(_ viewport: Viewport) {
        let editing = model.tools.showsCropOptions && model.session.image != nil
        guard let frame = model.cropFrameInDocument, model.session.image != nil else {
            cropLayer.isHidden = true
            shadeLayer.isHidden = true
            handlesLayer.isHidden = true
            return
        }
        let point = screenPoint(viewport)
        cropLayer.path = CGPath(rect: frame, transform: nil)
        cropLayer.isHidden = false
        if editing {
            cropLayer.strokeColor = NSColor.white.cgColor
            cropLayer.lineWidth = point
            cropLayer.lineDashPattern = nil
            let shade = CGMutablePath()
            shade.addRect(bounds.insetBy(dx: -bounds.width, dy: -bounds.height))
            shade.addRect(frame)
            shadeLayer.path = shade
            shadeLayer.isHidden = false
            let side = 8 * point
            let handles = CGMutablePath()
            for corner in corners(of: frame) {
                handles.addRect(CGRect(x: corner.x - side / 2, y: corner.y - side / 2, width: side, height: side))
            }
            handlesLayer.path = handles
            handlesLayer.lineWidth = point
            handlesLayer.isHidden = false
        } else {
            cropLayer.strokeColor = NSColor.controlAccentColor.cgColor
            cropLayer.lineWidth = 1.5 * point
            cropLayer.lineDashPattern = [NSNumber(value: 6 * point), NSNumber(value: 4 * point)]
            shadeLayer.isHidden = true
            handlesLayer.isHidden = true
        }
    }

    private func corners(of rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
    }

    /// The rule: a dashed yellow line and its result ("−1.3° · horizontal") next to its end.
    private func updateRuler(_ viewport: Viewport) {
        guard let ruler, model.tools.selected == .straighten else {
            rulerLayer.isHidden = true
            rulerEdgeLayer.isHidden = true
            rulerLabel.isHidden = true
            return
        }
        let point = screenPoint(viewport)
        let path = CGMutablePath()
        path.move(to: ruler.start)
        path.addLine(to: ruler.end)
        rulerLayer.path = path
        rulerLayer.lineWidth = 2 * point
        rulerLayer.lineDashPattern = [NSNumber(value: 6 * point), NSNumber(value: 4 * point)]
        rulerLayer.isHidden = false
        // A dark edge under the dashes: visible on light and yellow areas.
        rulerEdgeLayer.path = path
        rulerEdgeLayer.lineWidth = 4 * point
        rulerEdgeLayer.isHidden = false
        guard let label = ruler.label else {
            rulerLabel.isHidden = true
            return
        }
        // The label keeps its screen size at any zoom.
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        rulerLabel.string = label
        rulerLabel.fontSize = 12 * point
        rulerLabel.contentsScale = (window?.backingScaleFactor ?? 2) * viewport.magnification
        let width = (label as NSString).size(withAttributes: [.font: font]).width + 12
        rulerLabel.frame = CGRect(x: ruler.end.x + 8 * point, y: ruler.end.y - 10 * point,
                                  width: width * point, height: 18 * point)
        rulerLabel.isHidden = false
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

    /// The grid over the whole image shown, one screen point wide at any zoom;
    /// while cropping, the crop grid inside the frame instead.
    private func updateGrid(_ viewport: Viewport) {
        let grid = model.grid
        var area = CGRect(origin: .zero, size: viewport.documentSize)
        var kind: GridKind? = grid.isVisible ? grid.kind : nil
        if model.tools.showsCropOptions {
            area = model.cropFrameInDocument ?? area
            kind = model.cropGridKind
        }
        guard let kind, model.session.image != nil, area.width > 0 else {
            gridLayer.isHidden = true
            return
        }
        let path = CGMutablePath()
        for (start, end) in GridSettings.lines(kind, in: area, fineDivisions: grid.fineDivisions) {
            path.move(to: start)
            path.addLine(to: end)
        }
        gridLayer.path = path
        // One screen point at any zoom: thin, and never lost between two device pixels.
        gridLayer.lineWidth = screenPoint(viewport)
        // Set here so that it follows the appearance (light or dark) and the settings.
        let color: NSColor = switch grid.color {
        case .green: .systemGreen
        case .pink: .systemPink
        case .white: .white
        case .black: .black
        }
        gridLayer.strokeColor = color.withAlphaComponent(grid.opacity).cgColor
        gridLayer.isHidden = false
    }

    // MARK: Cursor and tracking

    private func updateCursor() {
        let tool = model.tools.effective
        guard tool != appliedTool else { return }
        appliedTool = tool
        if tool != .straighten { ruler = nil }  // the rule's result goes with its tool
        window?.invalidateCursorRects(for: self)
    }

    private var toolCursor: NSCursor {
        switch model.tools.effective {
        case .hand: dragStart == nil ? .openHand : .closedHand
        case .zoom: NSEvent.modifierFlags.contains(.option) ? .zoomOut : .zoomIn
        case .crop, .straighten: .crosshair
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
            cropDrag = cropDrag(startingAt: point)
        case .straighten:
            guard model.session.image != nil else { return }
            ruler = (point, point, nil)
            updateLayers()
        }
    }

    /// On a corner handle: resize; inside the frame: move; elsewhere: a new frame.
    private func cropDrag(startingAt point: CGPoint) -> CropDrag {
        guard let frame = model.cropFrameInDocument, model.tools.showsCropOptions else { return .draw(from: point) }
        let reach = 8 * screenPoint(model.viewport)
        let all = corners(of: frame)
        if let index = all.firstIndex(where: { hypot($0.x - point.x, $0.y - point.y) <= reach }) {
            return .resize(fixed: all[3 - index])  // the diagonally opposite corner
        }
        if frame.contains(point) { return .move(from: point, frame: frame) }
        return .draw(from: point)
    }

    /// The rectangle from `anchor` to `point`, with the proportions the crop keeps.
    private func spanned(from anchor: CGPoint, to point: CGPoint) -> CGRect {
        var width = abs(point.x - anchor.x), height = abs(point.y - anchor.y)
        if let ratio = model.cropRatio, ratio > 0 {
            if width / max(height, 1e-9) > ratio { height = width / ratio } else { width = height * ratio }
        }
        let x = point.x >= anchor.x ? anchor.x : anchor.x - width
        let y = point.y >= anchor.y ? anchor.y : anchor.y - height
        return CGRect(x: x, y: y, width: width, height: height)
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
            let point = convert(event.locationInWindow, from: nil)
            switch cropDrag {
            case .draw(let anchor):
                let rect = spanned(from: anchor, to: point)
                if rect.width >= 2 * screenPoint(model.viewport), rect.height >= 2 * screenPoint(model.viewport) {
                    model.setCropFrame(documentRect: rect)
                }
            case .move(let start, let frame):
                model.setCropFrame(documentRect: frame.offsetBy(dx: point.x - start.x, dy: point.y - start.y))
            case .resize(let fixed):
                model.setCropFrame(documentRect: spanned(from: fixed, to: point))
            case nil:
                break
            }
        case .straighten:
            guard let start = ruler?.start else { return }
            let end = convert(event.locationInWindow, from: nil)
            let label = Straighten.correction(from: start, to: end).map {
                Strings.straightenLabel(angle: CropSettings.clampedAngle(model.recipe.crop.angle + $0.angle), axis: $0.axis)
            }
            ruler = (start, end, label)
            updateLayers()
        case .zoom:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        cropDrag = nil
        if model.tools.effective == .straighten, let ruler {
            // The rule turns the image: the line drawn is then horizontal (or vertical).
            if let applied = model.straighten(from: ruler.start, to: ruler.end) {
                self.ruler = (ruler.start, ruler.end, Strings.straightenLabel(angle: applied.angle, axis: applied.axis))
            } else {
                self.ruler = nil
            }
            updateLayers()
        }
        window?.invalidateCursorRects(for: self)
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
        let cropping = model.tools.showsCropOptions
        if first == " " {
            if !event.isARepeat { model.tools.spaceHeld = true }
        } else if cropping, first == "x" || first == "X" {
            model.toggleCropPortrait()  // exchange width and height of the proportions
        } else if cropping, event.keyCode == 123 || event.keyCode == 124 {  // ← →: the angle, 0.1° (⇧: 1°)
            let step = event.modifierFlags.contains(.shift) ? 1.0 : CropSettings.angleStep
            model.setCropAngle(model.recipe.crop.angle + (event.keyCode == 124 ? step : -step))
        } else if cropping, event.keyCode == 36 || event.keyCode == 76 {  // Return: Done
            model.tools.selected = .hand
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
