// SPDX-License-Identifier: MIT

/// Per-column, per-channel white and dark levels from the calibration lines.
public struct FlatFieldReference: Sendable, Equatable {
    public let width: Int
    /// width × 3 mean levels.
    public let white: [Float]
    public let dark: [Float]

    public init(white: RGB16Image, dark: RGB16Image) throws {
        guard white.width == dark.width else {
            throw ImageError.widthMismatch(expected: white.width, received: dark.width)
        }
        width = white.width
        self.white = Self.columnMeans(white)
        self.dark = Self.columnMeans(dark)
    }

    private static func columnMeans(_ image: RGB16Image) -> [Float] {
        let stride = image.width * 3
        var sums = [Double](repeating: 0, count: stride)
        for row in 0..<image.height {
            let base = row * stride
            for index in 0..<stride { sums[index] += Double(image.samples[base + index]) }
        }
        return sums.map { Float($0 / Double(max(image.height, 1))) }
    }

    /// `(raw − dark) / (white − dark)` per column and channel, clamped to 0...1. [confirmed on a preview]
    public func apply(to raw: RGB16Image) throws -> LinearImage {
        guard raw.width == width else { throw ImageError.widthMismatch(expected: width, received: raw.width) }
        let stride = width * 3
        let scale = (0..<stride).map { 1 / max(white[$0] - dark[$0], 1) }
        var values = [Float](repeating: 0, count: raw.samples.count)
        for row in 0..<raw.height {
            let base = row * stride
            for index in 0..<stride {
                let value = (Float(raw.samples[base + index]) - dark[index]) * scale[index]
                values[base + index] = min(max(value, 0), 1)
            }
        }
        return LinearImage(width: raw.width, height: raw.height, values: values)
    }
}

/// Realignment of the three CCD rows. [confirmed on a preview]
public enum LineGap {
    /// At preview resolution red leads green by one line and blue trails by
    /// one line (`gap` = 1). Output row k takes red from input row k + 2·gap,
    /// green from k + gap and blue from k; `gap` lines are lost at the top and
    /// at the bottom.
    public static func realign(_ image: LinearImage, gap: Int = 1) -> LinearImage {
        precondition(gap >= 0)
        guard gap > 0 else { return image }
        let height = max(image.height - 2 * gap, 0)
        let stride = image.width * 3
        var values = [Float](repeating: 0, count: height * stride)
        for row in 0..<height {
            let red = (row + 2 * gap) * stride
            let green = (row + gap) * stride
            let blue = row * stride
            let out = row * stride
            for column in 0..<image.width {
                let c = column * 3
                values[out + c] = image.values[red + c]
                values[out + c + 1] = image.values[green + c + 1]
                values[out + c + 2] = image.values[blue + c + 2]
            }
        }
        return LinearImage(width: image.width, height: height, values: values)
    }
}

/// Turns the reads of a preview into an image: flat field from the white and
/// dark reference lines, then line-gap realignment. Linear, no colour profile.
public enum PreviewDecoding {
    public static func decode(white: [[UInt8]], dark: [[UInt8]], image: [[UInt8]],
                              width: Int, lineGap: Int = 1) throws -> LinearImage {
        let reference = try FlatFieldReference(
            white: RGB16Image(littleEndianBlocks: white, width: width),
            dark: RGB16Image(littleEndianBlocks: dark, width: width))
        let raw = try RGB16Image(littleEndianBlocks: image, width: width)
        return LineGap.realign(try reference.apply(to: raw), gap: lineGap)
    }
}
