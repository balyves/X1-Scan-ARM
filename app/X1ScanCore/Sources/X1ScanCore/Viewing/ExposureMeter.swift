// SPDX-License-Identifier: MIT
import Foundation

/// Thresholds of the exposure indicator, on the raw CCD samples (before the
/// flat field), 16-bit.
///
/// **Provisional (lot 1).** These values are not measured: they are round
/// guesses near both ends of the 16-bit scale, so that the indicator can be
/// built and tried. They are to be replaced by measurements on the X1 (dark
/// frames for the noise floor, an over-exposed frame for the clipping
/// level); see docs/decisions.md, "Lot 1: exposure indicator".
public struct ExposureThresholds: Sendable, Hashable {
    /// Full scale of the raw samples.
    public var fullScale: Double
    /// A pixel with any channel at or above this is counted as clipped.
    public var clipLevel: UInt16
    /// A pixel whose channels are all at or below this is counted as near the noise floor.
    public var noiseFloor: UInt16
    /// Share of the pixels ignored at each end when measuring the range used
    /// (isolated defects, dust), as a fraction.
    public var tailFraction: Double

    public init(fullScale: Double, clipLevel: UInt16, noiseFloor: UInt16, tailFraction: Double) {
        self.fullScale = fullScale
        self.clipLevel = clipLevel
        self.noiseFloor = noiseFloor
        self.tailFraction = tailFraction
    }

    /// The only values used by the application in lot 1. Provisional.
    public static let provisional = ExposureThresholds(fullScale: 65_535, clipLevel: 64_000, noiseFloor: 1_024,
                                                       tailFraction: 0.001)
}

/// What the exposure indicator shows, measured read-only on the raw samples
/// of a preview. All values are fractions in 0...1.
public struct ExposureReading: Sendable, Hashable {
    /// Pixels with at least one channel at or above the clipping level.
    public var clippedFraction: Double
    /// Pixels with every channel at or below the noise floor.
    public var noiseFraction: Double
    /// Darkest and brightest levels used (ends ignored), on the full scale.
    public var low: Double
    public var high: Double
    /// Share of the useful range (noise floor to clipping level) the image uses.
    public var usedRange: Double
    public var pixelCount: Int

    public static let empty = ExposureReading(clippedFraction: 0, noiseFraction: 0, low: 0, high: 0, usedRange: 0,
                                              pixelCount: 0)
}

public enum ExposureMeter {
    /// Measures `raw` (RGB interleaved). The darkest level is the per-pixel
    /// minimum channel, the brightest the per-pixel maximum, each taken at
    /// the `tailFraction` percentile.
    public static func measure(raw: [UInt16], thresholds: ExposureThresholds = .provisional) -> ExposureReading {
        let count = raw.count / 3
        guard count > 0 else { return .empty }
        // Histograms of the per-pixel minimum and maximum, on the full 16 bits.
        var minimums = [Int](repeating: 0, count: 65_536)
        var maximums = [Int](repeating: 0, count: 65_536)
        var clipped = 0, noise = 0
        raw.withUnsafeBufferPointer { samples in
            var index = 0
            for _ in 0..<count {
                let r = samples[index], g = samples[index + 1], b = samples[index + 2]
                let low = min(r, g, b), high = max(r, g, b)
                minimums[Int(low)] += 1
                maximums[Int(high)] += 1
                if high >= thresholds.clipLevel { clipped += 1 }
                if high <= thresholds.noiseFloor { noise += 1 }
                index += 3
            }
        }
        let skip = Int((Double(count) * thresholds.tailFraction).rounded(.down))
        let low = Double(level(minimums, rank: skip))
        let high = Double(level(maximums, rank: count - 1 - skip))
        let floor = Double(thresholds.noiseFloor), ceiling = Double(thresholds.clipLevel)
        let used = (min(high, ceiling) - max(low, floor)) / (ceiling - floor)
        return ExposureReading(clippedFraction: Double(clipped) / Double(count),
                               noiseFraction: Double(noise) / Double(count),
                               low: low / thresholds.fullScale, high: high / thresholds.fullScale,
                               usedRange: min(max(used, 0), 1), pixelCount: count)
    }

    /// The level at `rank` (0-based) in a histogram.
    private static func level(_ histogram: [Int], rank: Int) -> Int {
        var seen = 0
        for (value, number) in histogram.enumerated() {
            seen += number
            if seen > rank { return value }
        }
        return histogram.count - 1
    }

    /// The overlay of the clipped (red) and near-noise (blue) pixels, RGBA
    /// 8-bit premultiplied, same size as the raw image; transparent elsewhere.
    public static func zoneMask(raw: [UInt16], thresholds: ExposureThresholds = .provisional) -> [UInt8] {
        let count = raw.count / 3
        var mask = [UInt8](repeating: 0, count: count * 4)
        raw.withUnsafeBufferPointer { samples in
            mask.withUnsafeMutableBufferPointer { out in
                for pixel in 0..<count {
                    let i = pixel * 3
                    let high = max(samples[i], samples[i + 1], samples[i + 2])
                    if high >= thresholds.clipLevel {
                        out[pixel * 4] = 255; out[pixel * 4 + 3] = 255
                    } else if high <= thresholds.noiseFloor {
                        out[pixel * 4 + 2] = 255; out[pixel * 4 + 3] = 255
                    }
                }
            }
        }
        return mask
    }
}
