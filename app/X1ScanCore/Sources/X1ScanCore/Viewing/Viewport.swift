// SPDX-License-Identifier: MIT
import CoreGraphics
import X1Image

/// Zoom and geometry of the image area. Pure value type, no view.
///
/// The image is shown in a "document" whose size is the image size with the
/// height multiplied by `pixelAspectRatio`: preview pixels are taller than
/// wide. Magnification 1 shows one image pixel across one point
/// ("actual size"). The aspect correction is display only.
public struct Viewport: Sendable, Hashable {
    /// Zoom steps for Zoom In / Zoom Out.
    public static let steps: [Double] = [1.0 / 16, 1.0 / 12, 1.0 / 8, 1.0 / 6, 1.0 / 4, 1.0 / 3, 1.0 / 2, 2.0 / 3,
                                         1, 1.5, 2, 3, 4, 6, 8, 12, 16]
    public static var minimumMagnification: Double { steps.first! }
    public static var maximumMagnification: Double { steps.last! }

    public var imageWidth: Int
    /// Final height of the image (rows still arriving included).
    public var imageHeight: Int
    public var pixelAspectRatio: Double
    public var magnification: Double = 1
    /// When true, the magnification follows the view size.
    public var fitsWindow = true

    public init(imageWidth: Int, imageHeight: Int, pixelAspectRatio: Double = PreviewGeometry.pixelAspectRatio) {
        precondition(pixelAspectRatio > 0)
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.pixelAspectRatio = pixelAspectRatio
    }

    /// Size of the document at magnification 1, in points.
    public var documentSize: CGSize {
        CGSize(width: Double(imageWidth), height: Double(imageHeight) * pixelAspectRatio)
    }

    /// Magnification that shows the whole image in `viewSize`, with `margin` points around it.
    public func fitMagnification(in viewSize: CGSize, margin: Double = 16) -> Double {
        let size = documentSize
        guard size.width > 0, size.height > 0 else { return 1 }
        let width = max(viewSize.width - 2 * margin, 1)
        let height = max(viewSize.height - 2 * margin, 1)
        return Self.clamp(min(width / size.width, height / size.height))
    }

    public mutating func fit(in viewSize: CGSize) {
        magnification = fitMagnification(in: viewSize)
        fitsWindow = true
    }

    public mutating func actualSize() {
        magnification = 1
        fitsWindow = false
    }

    /// Next step up. From a magnification between two steps, goes to the upper one.
    public mutating func zoomIn() {
        magnification = Self.steps.first { $0 > magnification * 1.0001 } ?? Self.maximumMagnification
        fitsWindow = false
    }

    public mutating func zoomOut() {
        magnification = Self.steps.last { $0 < magnification / 1.0001 } ?? Self.minimumMagnification
        fitsWindow = false
    }

    /// Any magnification (pinch), clamped.
    public mutating func setMagnification(_ value: Double) {
        magnification = Self.clamp(value)
        fitsWindow = false
    }

    public var canZoomIn: Bool { magnification < Self.maximumMagnification / 1.0001 }
    public var canZoomOut: Bool { magnification > Self.minimumMagnification * 1.0001 }

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
