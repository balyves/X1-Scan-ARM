// SPDX-License-Identifier: MIT
import X1Image

/// The preview as far as it has been decoded.
///
/// - `corrected`: flat field and line gap applied, linear, 16-bit. This is
///   exactly what the TIFF export writes and what the screen shows.
/// - `raw`: the CCD samples behind each output pixel (realigned, before
///   the flat field).
public struct PreviewImage: Sendable, Equatable {
    public let width: Int
    /// Rows the finished preview will have.
    public let expectedHeight: Int
    public private(set) var height = 0
    public private(set) var corrected: [UInt16] = []
    public private(set) var raw: [UInt16] = []

    public init(width: Int, expectedHeight: Int) {
        self.width = width
        self.expectedHeight = expectedHeight
    }

    /// Test and preview helper: a complete image.
    public init(width: Int, corrected: [UInt16], raw: [UInt16]) {
        precondition(corrected.count == raw.count && corrected.count.isMultiple(of: width * 3))
        self.width = width
        height = corrected.count / (width * 3)
        expectedHeight = height
        self.corrected = corrected
        self.raw = raw
    }

    /// Copies `rows` (just completed) from the decoder.
    mutating func append(rows: Range<Int>, from decoder: IncrementalPreviewDecoder) {
        guard !rows.isEmpty else { return }
        precondition(rows.lowerBound == height && decoder.width == width)
        let stride = width * 3
        let range = rows.lowerBound * stride..<rows.upperBound * stride
        corrected.append(contentsOf: decoder.values[range].map(LinearImage.sample16))
        raw.append(contentsOf: decoder.rawSamples[range])
        height = rows.upperBound
    }

    public var isComplete: Bool { height >= expectedHeight }

    /// The corrected image, as exported.
    public var exportImage: RGB16Image {
        RGB16Image(width: width, height: height, samples: corrected)
    }
}
