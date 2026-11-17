// SPDX-License-Identifier: MIT

/// Where the frame of a scan sits in the lines the X1 sends, from the image
/// window (docs/protocol.md §9, §10).
public struct ScanGeometry: Sendable, Equatable {
    /// Window offset 14: first CCD pixel of the frame, at the scan resolution.
    public let firstColumn: Int
    /// Window offset 22: pixels per line of the frame. [confirmed]
    public let width: Int
    /// Window byte 49: horizontal binning. [hypothesis]
    public let binning: Int

    public init(firstColumn: Int, width: Int, binning: Int) {
        precondition(width > 0 && binning > 0)
        self.firstColumn = firstColumn
        self.width = width
        self.binning = binning
    }

    /// Reads the fields from the 68 bytes of a SET WINDOW.
    public init?(windowData data: [UInt8]) {
        guard data.count >= 68, data[49] > 0 else { return nil }
        func le16(_ offset: Int) -> Int { Int(data[offset]) | Int(data[offset + 1]) << 8 }
        guard le16(22) > 0 else { return nil }
        self.init(firstColumn: le16(14), width: le16(22), binning: Int(data[49]))
    }

    /// Extra pixels at the start of every line: 24 at full resolution, 8 with
    /// binning 3, 6 in the preview (binning 4). The rule 24 / binning, like
    /// byte 49 being the binning, is a [hypothesis] (docs/protocol.md §9, §10).
    public var margin: Int { 24 / binning }

    /// Pixels per line as sent by the scanner.
    public var pixelsPerLine: Int { width + margin }
}

/// Turns the reads of a scan into an image (docs/protocol.md §10, §12).
/// Linear, no colour profile. Same steps as tools/decode/decode_scan.py, whose
/// geometry matches FlexColor's TIFFs of three scans (1 000, 2 000, 3 200 ppi;
/// correlation of log values, docs/protocol.md §10); the values do not, since
/// FlexColor applies its own tone curve and profile.
public enum ScanDecoding {
    /// Lines read per output line: FlexColor reads floor(output × 5/3) image
    /// lines. [confirmed]
    public static let linesPerOutputLine = 5.0 / 3.0
    /// Input line of output line 0: best match with FlexColor's TIFF at
    /// 2 000 ppi (0 to 0.33 differ by less than 0.001 in correlation).
    public static let phase = 0.25

    /// Line gap of the three CCD rows, from the number of priming lines
    /// (one-line reads right after SCAN): priming = 2 × gap + 1. [confirmed]
    /// for gaps 1 (preview), 7 and 20.
    public static func lineGap(primingLines: Int) -> Int { max(primingLines - 1, 0) / 2 }

    /// Per-column white and dark of the frame from the full-width calibration
    /// read (50 white lines, then 180 dark lines; split by level).
    public static func reference(calibration: RGB16Image, geometry: ScanGeometry) throws -> FlatFieldReference {
        let start = geometry.margin + geometry.firstColumn
        guard start + geometry.width <= calibration.width else {
            throw ImageError.widthMismatch(expected: start + geometry.width, received: calibration.width)
        }
        var levels: [Double] = []
        for row in 0..<calibration.height {
            var sum = 0.0
            for column in 0..<calibration.width { sum += Double(calibration.samples[(row * calibration.width + column) * 3 + 1]) }
            levels.append(sum / Double(calibration.width))
        }
        let split = ((levels.max() ?? 0) + (levels.min() ?? 0)) / 2
        let bright = levels.indices.filter { levels[$0] > split }
        let dim = levels.indices.filter { levels[$0] <= split }
        guard !bright.isEmpty, !dim.isEmpty else { throw ImageError.noLines }
        return try FlatFieldReference(white: calibration.rows(bright, columns: start..<(start + geometry.width)),
                                      dark: calibration.rows(dim, columns: start..<(start + geometry.width)))
    }

    /// Decodes a scan.
    /// - calibration: the blocks of the full-width calibration read.
    /// - image: every image block after `1b 00 00 01 01 00`, priming lines
    ///   included (they are the first lines of the image).
    public static func decode(calibration: [[UInt8]], calibrationWidth: Int, image: [[UInt8]],
                              geometry: ScanGeometry, primingLines: Int) throws -> LinearImage {
        let reference = try reference(calibration: RGB16Image(littleEndianBlocks: calibration, width: calibrationWidth),
                                      geometry: geometry)
        let raw = try RGB16Image(littleEndianBlocks: image, width: geometry.pixelsPerLine)
        let frame = raw.rows(Array(0..<raw.height), columns: geometry.margin..<geometry.pixelsPerLine)
        let aligned = LineGap.realign(try reference.apply(to: frame), gap: lineGap(primingLines: primingLines))
        let image = resampleLines(aligned)
        guard image.height > 0 else { throw ImageError.noLines }
        return image
    }

    /// Output line j is input line 5/3 × j + phase, linearly interpolated;
    /// floor(input lines × 3/5) output lines.
    public static func resampleLines(_ image: LinearImage) -> LinearImage {
        let height = image.height * 3 / 5
        let stride = image.width * 3
        var values = [Float](repeating: 0, count: height * stride)
        for row in 0..<height {
            let position = linesPerOutputLine * Double(row) + phase
            let lower = min(Int(position), image.height - 1)
            let upper = min(lower + 1, image.height - 1)
            let fraction = Float(position - Double(lower))
            for index in 0..<stride {
                let a = image.values[lower * stride + index]
                let b = image.values[upper * stride + index]
                values[row * stride + index] = a + (b - a) * fraction
            }
        }
        return LinearImage(width: image.width, height: height, values: values)
    }
}

extension RGB16Image {
    /// The given rows, restricted to a range of columns.
    func rows(_ rows: [Int], columns: Range<Int>) -> RGB16Image {
        var samples: [UInt16] = []
        samples.reserveCapacity(rows.count * columns.count * 3)
        for row in rows {
            let base = (row * width + columns.lowerBound) * 3
            samples.append(contentsOf: self.samples[base..<(base + columns.count * 3)])
        }
        return RGB16Image(width: columns.count, height: rows.count, samples: samples)
    }
}
