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

    /// Test helper: a preview stopped after the rows of `corrected`.
    init(width: Int, expectedHeight: Int, receivedRows corrected: [UInt16]) {
        precondition(corrected.count.isMultiple(of: width * 3) && corrected.count / (width * 3) <= expectedHeight)
        self.width = width
        self.expectedHeight = expectedHeight
        height = corrected.count / (width * 3)
        self.corrected = corrected
        raw = corrected
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

    /// The corrected image at its expected height, the rows not received
    /// black: the area the screen shows and the crop frame is drawn on, for
    /// rendering a recipe (session of 2026-11-25: a frame drawn on a stopped
    /// preview took the received rows for the whole image).
    public var fullHeightExportImage: RGB16Image {
        guard height < expectedHeight else { return exportImage }
        return RGB16Image(width: width, height: expectedHeight,
                          samples: corrected + [UInt16](repeating: 0, count: (expectedHeight - height) * width * 3))
    }
}
