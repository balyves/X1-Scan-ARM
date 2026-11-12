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

    /// Bins scaled to 0...1 for drawing, against the largest bin of all
    /// channels. `logarithmic` compresses tall peaks.
    public func normalized(logarithmic: Bool = false) -> [[Double]] {
        let transform: (Int) -> Double = logarithmic ? { log1p(Double($0)) } : { Double($0) }
        let peak = bins.flatMap { $0 }.map(transform).max() ?? 0
        guard peak > 0 else { return bins.map { $0.map { _ in 0 } } }
        return bins.map { $0.map { transform($0) / peak } }
    }
}
