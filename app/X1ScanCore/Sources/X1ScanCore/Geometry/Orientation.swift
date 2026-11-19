// SPDX-License-Identifier: MIT
import CoreGraphics
import X1Image

/// Orientation of the image relative to the scanner's pixels (lot 1): an
/// optional horizontal mirror of the original, then quarter turns clockwise.
/// Quarter turns and the mirror are exact permutations of the pixels, never a
/// resampling.
public struct Orientation: Sendable, Hashable, Codable {
    /// Quarter turns clockwise, 0...3, applied after the mirror.
    public private(set) var quarterTurns: Int
    /// Mirrored left to right, before the turns.
    public private(set) var mirrored: Bool

    public static let identity = Orientation()

    public init(quarterTurns: Int = 0, mirrored: Bool = false) {
        self.quarterTurns = ((quarterTurns % 4) + 4) % 4
        self.mirrored = mirrored
    }

    /// Width and height are exchanged (a quarter or three quarter turn).
    public var swapsAxes: Bool { quarterTurns % 2 == 1 }

    /// Turns the image as shown a quarter clockwise.
    public mutating func rotateClockwise() { quarterTurns = (quarterTurns + 1) % 4 }

    /// Turns the image as shown a quarter counterclockwise.
    public mutating func rotateCounterclockwise() { quarterTurns = (quarterTurns + 3) % 4 }

    /// Mirrors the image as shown left to right. Mirroring a turned image is
    /// the mirror of the original turned the other way: H·R^q = R^-q·H.
    public mutating func mirrorHorizontally() {
        quarterTurns = (4 - quarterTurns) % 4
        mirrored.toggle()
    }

    /// Size of the oriented image for a source of `width` × `height`.
    public func orientedSize(width: Int, height: Int) -> (width: Int, height: Int) {
        swapsAxes ? (height, width) : (width, height)
    }

    /// Size of the oriented image, for real-valued sizes.
    public func orientedSize(_ size: CGSize) -> CGSize {
        swapsAxes ? CGSize(width: size.height, height: size.width) : size
    }

    /// Maps a point of a source of `size` (origin top left, y down) to the
    /// oriented image. Works for pixel indices with `size` reduced by one
    /// (`size - 1`) and for continuous coordinates with the full size.
    public func orientedPoint(_ point: CGPoint, sourceSize size: CGSize) -> CGPoint {
        point.applying(orientedTransform(sourceSize: size))
    }

    /// Inverse of `orientedPoint`.
    public func sourcePoint(_ point: CGPoint, sourceSize size: CGSize) -> CGPoint {
        point.applying(orientedTransform(sourceSize: size).inverted())
    }

    /// The affine map from source coordinates to oriented coordinates
    /// (origin top left, y down), for a source of `size`.
    public func orientedTransform(sourceSize size: CGSize) -> CGAffineTransform {
        var transform = CGAffineTransform.identity
        var current = size
        if mirrored {
            // x → w − x
            transform = transform.concatenating(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: current.width, ty: 0))
        }
        for _ in 0..<quarterTurns {
            // A quarter turn clockwise with y down: (x, y) → (h − y, x).
            transform = transform.concatenating(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: current.height, ty: 0))
            current = CGSize(width: current.height, height: current.width)
        }
        return transform
    }

    /// The pixels of `image` in this orientation: an exact permutation.
    public func apply(to image: RGB16Image) -> RGB16Image {
        guard self != .identity else { return image }
        let (width, height) = orientedSize(width: image.width, height: image.height)
        var out = [UInt16](repeating: 0, count: image.samples.count)
        let sw = image.width, sh = image.height
        image.samples.withUnsafeBufferPointer { source in
            out.withUnsafeMutableBufferPointer { target in
                for oy in 0..<height {
                    for ox in 0..<width {
                        let (sx, sy) = sourcePixel(x: ox, y: oy, sourceWidth: sw, sourceHeight: sh)
                        let s = (sy * sw + sx) * 3
                        let t = (oy * width + ox) * 3
                        target[t] = source[s]
                        target[t + 1] = source[s + 1]
                        target[t + 2] = source[s + 2]
                    }
                }
            }
        }
        return RGB16Image(width: width, height: height, samples: out)
    }

    /// The source pixel shown at oriented pixel (x, y).
    public func sourcePixel(x: Int, y: Int, sourceWidth: Int, sourceHeight: Int) -> (x: Int, y: Int) {
        // Undo the turns (each one counterclockwise), then the mirror.
        var px = x, py = y
        var w = swapsAxes ? sourceHeight : sourceWidth  // width of the current stage
        var h = swapsAxes ? sourceWidth : sourceHeight
        for _ in 0..<quarterTurns {
            // Inverse of (x, y) → (h' − 1 − y, x) where h' is the height before the turn.
            let previousWidth = h, previousHeight = w
            let nx = py
            let ny = previousHeight - 1 - px
            px = nx
            py = ny
            w = previousWidth
            h = previousHeight
        }
        if mirrored { px = sourceWidth - 1 - px }
        return (px, py)
    }
}
