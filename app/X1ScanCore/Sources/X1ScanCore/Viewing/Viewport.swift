// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import X1Image

/// How the magnification is chosen.
public enum ZoomMode: String, Sendable, Hashable, Codable {
    /// The whole image in the view; follows the view size.
    case fit
    /// The view filled with the image (part may be hidden); follows the view size.
    case fill
    /// A magnification chosen by the user (step, pinch, typed value); kept when the view changes.
    case fixed
}

/// Zoom and geometry of the image area. Pure value type, no view.
///
/// The image is shown in a "document" whose size is the image size with the
/// height multiplied by `pixelAspectRatio`: preview pixels are taller than
/// wide. Magnification 1 shows one image pixel across one point
/// ("actual size"). The aspect correction is display only.
public struct Viewport: Sendable, Hashable {
    /// Zoom steps for Zoom In / Zoom Out: 6.25 % to 1600 %.
    public static let steps: [Double] = [1.0 / 16, 1.0 / 12, 1.0 / 8, 1.0 / 6, 1.0 / 4, 1.0 / 3, 1.0 / 2, 2.0 / 3,
                                         1, 2, 3, 4, 8, 16]
    public static var minimumMagnification: Double { steps.first! }
    public static var maximumMagnification: Double { steps.last! }
    /// Margin around the image in Fit mode, in points.
    public static let fitMargin: Double = 16

    public var imageWidth: Int
    /// Final height of the image (rows still arriving included).
    public var imageHeight: Int
    public var pixelAspectRatio: Double
    public private(set) var magnification: Double = 1
    public private(set) var mode: ZoomMode = .fit
    /// Last view size seen, used to recompute Fit and Fill.
    public private(set) var viewSize: CGSize = .zero

    public init(imageWidth: Int, imageHeight: Int, pixelAspectRatio: Double = PreviewGeometry.pixelAspectRatio,
                mode: ZoomMode = .fit) {
        precondition(pixelAspectRatio > 0)
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.pixelAspectRatio = pixelAspectRatio
        self.mode = mode
    }

    /// Size of the document at magnification 1, in points.
    public var documentSize: CGSize {
        CGSize(width: Double(imageWidth), height: Double(imageHeight) * pixelAspectRatio)
    }

    /// Magnification that shows the whole image in `viewSize`, with `margin` points around it.
    public func fitMagnification(in viewSize: CGSize, margin: Double = Viewport.fitMargin) -> Double {
        let size = documentSize
        guard size.width > 0, size.height > 0 else { return 1 }
        let width = max(viewSize.width - 2 * margin, 1)
        let height = max(viewSize.height - 2 * margin, 1)
        return Self.clamp(min(width / size.width, height / size.height))
    }

    /// Magnification that fills `viewSize` with the image, without margin.
    public func fillMagnification(in viewSize: CGSize) -> Double {
        let size = documentSize
        guard size.width > 0, size.height > 0 else { return 1 }
        return Self.clamp(max(max(viewSize.width, 1) / size.width, max(viewSize.height, 1) / size.height))
    }

    /// The view changed size (window, full screen, palettes shown or hidden):
    /// Fit and Fill are recomputed, a fixed magnification is kept.
    public mutating func viewSizeChanged(_ size: CGSize) {
        viewSize = size
        recompute()
    }

    /// The image changed size: same mode, recomputed for Fit and Fill.
    public mutating func setImageSize(width: Int, height: Int) {
        imageWidth = width
        imageHeight = height
        recompute()
    }

    public mutating func fit() {
        mode = .fit
        recompute()
    }

    public mutating func fill() {
        mode = .fill
        recompute()
    }

    public mutating func actualSize() {
        setMagnification(1)
    }

    /// Next step strictly above the current magnification (as Photoshop and Preview).
    public mutating func zoomIn() {
        setMagnification(Self.steps.first { $0 > magnification * 1.0001 } ?? Self.maximumMagnification)
    }

    /// Next step strictly below the current magnification.
    public mutating func zoomOut() {
        setMagnification(Self.steps.last { $0 < magnification / 1.0001 } ?? Self.minimumMagnification)
    }

    /// Any magnification (step, pinch, typed value), clamped; kept when the view changes.
    public mutating func setMagnification(_ value: Double) {
        magnification = Self.clamp(value)
        mode = .fixed
    }

    public var canZoomIn: Bool { magnification < Self.maximumMagnification / 1.0001 }
    public var canZoomOut: Bool { magnification > Self.minimumMagnification * 1.0001 }

    /// The step equal to the magnification, if it is one (for the menu check marks).
    public var currentStep: Double? {
        mode == .fixed ? Self.steps.first { abs($0 - magnification) < 1e-9 } : nil
    }

    /// A typed zoom value: "150", "150 %", "12,5", "12.5%". Returns the
    /// magnification (1.5 for 150 %), clamped, or nil if it is not a positive number.
    public static func magnification(fromTyped text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .filter { !$0.isWhitespace }
        guard !cleaned.isEmpty, let percent = Double(cleaned), percent.isFinite, percent > 0 else { return nil }
        return clamp(percent / 100)
    }

    /// The image pixel under a point of the document (magnification 1
    /// coordinates, origin top left), or nil outside the image.
    public func pixel(atDocumentPoint point: CGPoint) -> PixelCoordinate? {
        let x = Int((point.x).rounded(.down))
        let y = Int((point.y / pixelAspectRatio).rounded(.down))
        guard point.x >= 0, point.y >= 0, x < imageWidth, y < imageHeight else { return nil }
        return PixelCoordinate(x: x, y: y)
    }

    /// Document rectangle covered by an image rectangle (pixels).
    public func documentRect(forPixelRect rect: PixelRect) -> CGRect {
        CGRect(x: Double(rect.x), y: Double(rect.y) * pixelAspectRatio,
               width: Double(rect.width), height: Double(rect.height) * pixelAspectRatio)
    }

    private mutating func recompute() {
        switch mode {
        case .fit: magnification = fitMagnification(in: viewSize)
        case .fill: magnification = fillMagnification(in: viewSize)
        case .fixed: break
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, minimumMagnification), maximumMagnification)
    }
}

public struct PixelCoordinate: Sendable, Hashable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public struct PixelRect: Sendable, Hashable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The rectangle spanned by two pixels (both included), in any order,
    /// clipped to an image of `width` × `height`.
    public static func spanning(_ a: PixelCoordinate, _ b: PixelCoordinate, width: Int, height: Int) -> PixelRect {
        let x0 = min(max(min(a.x, b.x), 0), max(width - 1, 0))
        let y0 = min(max(min(a.y, b.y), 0), max(height - 1, 0))
        let x1 = min(max(max(a.x, b.x), 0), max(width - 1, 0))
        let y1 = min(max(max(a.y, b.y), 0), max(height - 1, 0))
        return PixelRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)
    }
}
