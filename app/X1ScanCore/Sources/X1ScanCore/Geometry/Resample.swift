// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import X1Image

/// Fine rotation and crop of an oriented image, for Export (lot 1). The
/// samples are read as they are and summed in floating point (Double).
///
/// Square pixels without an angle (a scan): the crop takes whole pixels, no
/// resampling. With an angle, or pixels that are not square (a preview's
/// 1 × 3, session of 2026-11-25: a file always has square pixels), the
/// image is resampled with a Lanczos-3 kernel, in floating point, onto
/// square pixels the size of the source pixel's shorter side (a preview's
/// 1 × 3 pixels give 3 times more rows).
public enum Resample {
    /// Lanczos kernel radius, in source pixels.
    public static let radius = 3

    /// `image` (already turned and mirrored) with `crop` applied.
    /// `pixelSize`: physical width and height of one pixel of `image`.
    public static func apply(_ crop: CropSettings, to image: RGB16Image, pixelSize: CGSize) -> RGB16Image {
        let physical = CGSize(width: Double(image.width) * pixelSize.width,
                              height: Double(image.height) * pixelSize.height)
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let normalized = (crop.frame ?? unit).intersection(unit)
        guard !normalized.isNull, normalized.width > 0, normalized.height > 0 else { return image }
        if crop.angle == 0 && pixelSize.width == pixelSize.height { return cropped(image, to: normalized) }
        let frame = CGRect(x: normalized.minX * physical.width, y: normalized.minY * physical.height,
                           width: normalized.width * physical.width, height: normalized.height * physical.height)
        let step = min(pixelSize.width, pixelSize.height)
        let width = max(Int((frame.width / step).rounded()), 1)
        let height = max(Int((frame.height / step).rounded()), 1)
        return rotated(image, angle: crop.angle, pixelSize: pixelSize, physical: physical, frame: frame,
                       step: step, width: width, height: height)
    }

    /// Whole pixels of `normalized` (rounded to the nearest pixel edges).
    /// The whole pixels a normalised frame covers (rounded to the nearest edges, at least one).
    static func croppedBounds(width: Int, height: Int, normalized: CGRect) -> (x0: Int, y0: Int, x1: Int, y1: Int) {
        let x0 = min(max(Int((normalized.minX * Double(width)).rounded()), 0), width - 1)
        let y0 = min(max(Int((normalized.minY * Double(height)).rounded()), 0), height - 1)
        let x1 = min(max(Int((normalized.maxX * Double(width)).rounded()), x0 + 1), width)
        let y1 = min(max(Int((normalized.maxY * Double(height)).rounded()), y0 + 1), height)
        return (x0, y0, x1, y1)
    }

    static func cropped(_ image: RGB16Image, to normalized: CGRect) -> RGB16Image {
        let (x0, y0, x1, y1) = croppedBounds(width: image.width, height: image.height, normalized: normalized)
        if x0 == 0, y0 == 0, x1 == image.width, y1 == image.height { return image }
        var samples = [UInt16]()
        samples.reserveCapacity((x1 - x0) * (y1 - y0) * 3)
        for y in y0..<y1 {
            let start = (y * image.width + x0) * 3
            samples.append(contentsOf: image.samples[start..<start + (x1 - x0) * 3])
        }
        return RGB16Image(width: x1 - x0, height: y1 - y0, samples: samples)
    }

    /// Lanczos-3 weight at distance `x` (in source pixels).
    @inline(__always)
    static func lanczos(_ x: Double) -> Double {
        let ax = abs(x)
        if ax < 1e-9 { return 1 }
        if ax >= Double(radius) { return 0 }
        let px = Double.pi * x
        return Double(radius) * sin(px) * sin(px / Double(radius)) / (px * px)
    }

    private static func rotated(_ image: RGB16Image, angle: Double, pixelSize: CGSize, physical: CGSize,
                                frame: CGRect, step: Double, width: Int, height: Int) -> RGB16Image {
        let sw = image.width, sh = image.height
        let radians = -angle * .pi / 180  // a point of the frame, back into the image's axes
        let c = cos(radians), s = sin(radians)
        let cx = physical.width / 2, cy = physical.height / 2
        var out = [UInt16](repeating: 0, count: width * height * 3)
        let rows = height
        out.withUnsafeMutableBufferPointer { target in
            let target = UnsafeMutableSendablePointer(base: target.baseAddress!)
            image.samples.withUnsafeBufferPointer { input in
                let input = UnsafeSendablePointer(base: input.baseAddress!)
                DispatchQueue.concurrentPerform(iterations: rows) { j in
                    var wx = [Double](repeating: 0, count: 2 * radius)
                    var wy = [Double](repeating: 0, count: 2 * radius)
                    for i in 0..<width {
                        let px = frame.minX + (Double(i) + 0.5) * step - cx
                        let py = frame.minY + (Double(j) + 0.5) * step - cy
                        // Continuous source pixel coordinates (centres at integer + 0.5).
                        let sx = (cx + px * c - py * s) / pixelSize.width - 0.5
                        let sy = (cy + px * s + py * c) / pixelSize.height - 0.5
                        let t = (j * width + i) * 3
                        // Outside the image (constraint off): left black.
                        guard sx > -0.5, sy > -0.5, sx < Double(sw) - 0.5, sy < Double(sh) - 0.5 else { continue }
                        let ix = Int(sx.rounded(.down)), iy = Int(sy.rounded(.down))
                        var sumX = 0.0, sumY = 0.0
                        for k in 0..<2 * radius {
                            wx[k] = lanczos(sx - Double(ix - radius + 1 + k))
                            wy[k] = lanczos(sy - Double(iy - radius + 1 + k))
                            sumX += wx[k]
                            sumY += wy[k]
                        }
                        var r = 0.0, g = 0.0, b = 0.0
                        for ky in 0..<2 * radius {
                            let y = min(max(iy - radius + 1 + ky, 0), sh - 1)  // edges repeated
                            var rr = 0.0, gg = 0.0, bb = 0.0
                            for kx in 0..<2 * radius {
                                let x = min(max(ix - radius + 1 + kx, 0), sw - 1)
                                let base = (y * sw + x) * 3
                                let w = wx[kx]
                                rr += w * Double(input.base[base])
                                gg += w * Double(input.base[base + 1])
                                bb += w * Double(input.base[base + 2])
                            }
                            let w = wy[ky]
                            r += w * rr
                            g += w * gg
                            b += w * bb
                        }
                        let norm = 1 / (sumX * sumY)
                        target.base[t] = clamp16(r * norm)
                        target.base[t + 1] = clamp16(g * norm)
                        target.base[t + 2] = clamp16(b * norm)
                    }
                }
            }
        }
        return RGB16Image(width: width, height: height, samples: out)
    }

    @inline(__always)
    private static func clamp16(_ value: Double) -> UInt16 {
        UInt16(min(max(value.rounded(), 0), 65_535))
    }
}

/// Pointers shared by the rows of `concurrentPerform`: each row writes its own samples only.
private struct UnsafeMutableSendablePointer: @unchecked Sendable {
    let base: UnsafeMutablePointer<UInt16>
}

private struct UnsafeSendablePointer: @unchecked Sendable {
    let base: UnsafePointer<UInt16>
}
