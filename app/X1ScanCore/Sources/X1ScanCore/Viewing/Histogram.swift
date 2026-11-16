// SPDX-License-Identifier: MIT
import Foundation

/// RGB histogram of the corrected 16-bit values (what is exported), 256 bins per channel.
public struct Histogram: Sendable, Hashable {
    public static let binCount = 256

    /// `[red, green, blue]`, each `binCount` counts.
    public let bins: [[Int]]
    public let pixelCount: Int

    public init(bins: [[Int]], pixelCount: Int) {
        precondition(bins.count == 3 && bins.allSatisfy { $0.count == Self.binCount })
        self.bins = bins
        self.pixelCount = pixelCount
    }

    public static let empty = Histogram(bins: Array(repeating: Array(repeating: 0, count: binCount), count: 3),
                                        pixelCount: 0)

    /// Counts every pixel of `samples` (RGB interleaved). The bin of a value is its top 8 bits.
    public init(samples: [UInt16]) {
        var red = [Int](repeating: 0, count: Self.binCount)
        var green = red
        var blue = red
        var index = 0
        let end = samples.count - samples.count % 3
        while index < end {
            red[Int(samples[index] >> 8)] += 1
            green[Int(samples[index + 1] >> 8)] += 1
            blue[Int(samples[index + 2] >> 8)] += 1
            index += 3
        }
        self.init(bins: [red, green, blue], pixelCount: end / 3)
    }

    /// Counts the pixels of `region` only (the crop), in an image of `width`
    /// pixels per row (RGB interleaved); the whole image when `region` is nil.
    /// The region is clipped to the rows received so far.
    public init(samples: [UInt16], width: Int, region: PixelRect?) {
        guard let region, width > 0 else {
            self.init(samples: samples)
            return
        }
        let rows = samples.count / (width * 3)
        let left = min(max(region.x, 0), width), right = min(max(region.x + region.width, left), width)
        let top = min(max(region.y, 0), rows), bottom = min(max(region.y + region.height, top), rows)
        var red = [Int](repeating: 0, count: Self.binCount)
        var green = red
        var blue = red
        for row in top..<bottom {
            var index = (row * width + left) * 3
            let end = (row * width + right) * 3
            while index < end {
                red[Int(samples[index] >> 8)] += 1
                green[Int(samples[index + 1] >> 8)] += 1
                blue[Int(samples[index + 2] >> 8)] += 1
                index += 3
            }
        }
        self.init(bins: [red, green, blue], pixelCount: (right - left) * (bottom - top))
    }

    /// Vertical scale of the drawing. Linear by default (heights proportional
    /// to pixel counts); logarithmic as an option, for the small bins that a
    /// few tall ones flatten. Square root is kept for callers that want it.
    public enum Scale: String, Sendable, Hashable, CaseIterable {
        case linear
        case squareRoot
        case logarithmic
    }

    /// Bins scaled to 0...1 for drawing. With `peakPercentile` below 1, the
    /// top of the scale is that percentile of all the bins of the three
    /// channels (nearest rank; 0.995 of 768 bins: the 4th tallest), and taller
    /// bins are drawn cut at 1, so that a few isolated peaks do not flatten the
    /// rest. When fewer bins are non-empty than one in `1 - peakPercentile`
    /// (under 200 for 0.995, e.g. a small uniform crop), nothing is cut: the
    /// top is the largest bin and the ratios between bins stay true. 1, the
    /// default, never cuts.
    public func normalized(scale: Scale = .linear, peakPercentile: Double = 1) -> [[Double]] {
        let transform: (Int) -> Double = switch scale {
        case .linear: { Double($0) }
        case .squareRoot: { Double($0).squareRoot() }
        case .logarithmic: { log1p(Double($0)) }
        }
        let values = bins.flatMap { $0 }.map(transform).sorted()
        guard let largest = values.last, largest > 0 else { return bins.map { $0.map { _ in 0 } } }
        let fraction = min(max(peakPercentile.isFinite ? peakPercentile : 1, 0), 1)
        var top = largest
        let nonEmpty = values.count { $0 > 0 }
        // Small margin: 1 − 0.9 is 0.0999…98 in binary, and 10 bins must still count as enough.
        if fraction < 1, Double(nonEmpty) * (1 - fraction) >= 1 - 1e-9 {
            let rank = max(Int((fraction * Double(values.count)).rounded(.up)) - 1, 0)
            if values[rank] > 0 { top = values[rank] }
        }
        return bins.map { $0.map { min(transform($0) / top, 1) } }
    }
}
