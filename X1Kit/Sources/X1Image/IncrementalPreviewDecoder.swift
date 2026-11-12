// SPDX-License-Identifier: MIT

/// Decodes a preview block by block, as the image lines arrive, so that an
/// application can show the image while it is being scanned.
///
/// The result is identical to `PreviewDecoding.decode` on the same blocks:
/// flat field from the white and dark references, then line-gap realignment.
/// An output row is available as soon as the input row that gives its red
/// channel (`row + 2·lineGap`) has arrived.
///
/// Besides the corrected values, the decoder keeps the raw sensor samples
/// realigned the same way, so that each output pixel can show what the CCD
/// actually read for its three channels.
public struct IncrementalPreviewDecoder: Sendable {
    public let width: Int
    public let lineGap: Int
    public let reference: FlatFieldReference

    /// Corrected, realigned values in 0...1: `height` × `width` × 3.
    public private(set) var values: [Float] = []
    /// Raw samples realigned like `values`, before the flat field.
    public private(set) var rawSamples: [UInt16] = []
    /// Number of complete output rows.
    public private(set) var height = 0

    private var inputRaw: [UInt16] = []
    private var inputLinear: [Float] = []
    private var inputRows = 0
    private let scale: [Float]

    public init(white: [[UInt8]], dark: [[UInt8]], width: Int, lineGap: Int = 1) throws {
        precondition(lineGap >= 0)
        self.width = width
        self.lineGap = lineGap
        let reference = try FlatFieldReference(white: RGB16Image(littleEndianBlocks: white, width: width),
                                               dark: RGB16Image(littleEndianBlocks: dark, width: width))
        self.reference = reference
        // Same scale as FlatFieldReference.apply.
        scale = (0..<width * 3).map { 1 / max(reference.white[$0] - reference.dark[$0], 1) }
    }

    /// Appends one READ block (whole lines, RGB 16-bit little-endian) and
    /// returns the output rows it completed (possibly empty).
    @discardableResult
    public mutating func append(_ block: [UInt8]) throws -> Range<Int> {
        let stride = width * 3
        let bytesPerLine = stride * 2
        guard block.count.isMultiple(of: bytesPerLine) else {
            throw ImageError.malformedBlock(index: inputRows, size: block.count, bytesPerLine: bytesPerLine)
        }
        let lines = block.count / bytesPerLine
        inputRaw.reserveCapacity(inputRaw.count + lines * stride)
        inputLinear.reserveCapacity(inputLinear.count + lines * stride)
        for line in 0..<lines {
            let base = line * bytesPerLine
            for index in 0..<stride {
                let offset = base + index * 2
                let sample = UInt16(block[offset]) | UInt16(block[offset + 1]) << 8
                inputRaw.append(sample)
                let value = (Float(sample) - reference.dark[index]) * scale[index]
                inputLinear.append(min(max(value, 0), 1))
            }
        }
        inputRows += lines

        let first = height
        let available = max(inputRows - 2 * lineGap, 0)
        guard available > first else { return first..<first }
        values.reserveCapacity(available * stride)
        rawSamples.reserveCapacity(available * stride)
        for row in first..<available {
            // Same mapping as LineGap.realign: red from row + 2·gap, green from row + gap, blue from row.
            let red = (row + 2 * lineGap) * stride
            let green = (row + lineGap) * stride
            let blue = row * stride
            for column in 0..<width {
                let c = column * 3
                values.append(inputLinear[red + c])
                values.append(inputLinear[green + c + 1])
                values.append(inputLinear[blue + c + 2])
                rawSamples.append(inputRaw[red + c])
                rawSamples.append(inputRaw[green + c + 1])
                rawSamples.append(inputRaw[blue + c + 2])
            }
        }
        height = available
        return first..<available
    }

    /// The rows decoded so far, as a linear image.
    public var image: LinearImage {
        LinearImage(width: width, height: height, values: values)
    }

    /// The raw sensor samples of the rows decoded so far, realigned.
    public var rawImage: RGB16Image {
        RGB16Image(width: width, height: height, samples: rawSamples)
    }
}
