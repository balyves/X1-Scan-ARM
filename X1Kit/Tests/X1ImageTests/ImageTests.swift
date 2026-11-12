// SPDX-License-Identifier: MIT
import Foundation
import ImageIO
import Testing
import X1Image
import X1Preview
import X1TestSupport
import X1Transport

struct CorrectionTests {
    @Test func flatFieldUsesColumnMeans() throws {
        // 2 columns; white 1000 / 2000, dark 0 / 1000.
        let white = RGB16Image(width: 2, height: 2, samples: [900, 900, 900, 2000, 2000, 2000,
                                                              1100, 1100, 1100, 2000, 2000, 2000])
        let dark = RGB16Image(width: 2, height: 1, samples: [0, 0, 0, 1000, 1000, 1000])
        let reference = try FlatFieldReference(white: white, dark: dark)
        let raw = RGB16Image(width: 2, height: 1, samples: [500, 0, 1000, 1500, 3000, 1000])
        let linear = try reference.apply(to: raw)
        let expected: [Float] = [0.5, 0, 1, 0.5, 1, 0]
        #expect(zip(linear.values, expected).allSatisfy { abs($0 - $1) < 1e-6 }, "\(linear.values)")
    }

    @Test func lineGapRealignsRedAndBlue() {
        // One column; each channel holds its row number.
        let rows: [Float] = [0, 1, 2, 3, 4]
        let image = LinearImage(width: 1, height: 5, values: rows.flatMap { [$0, $0, $0] })
        let realigned = LineGap.realign(image, gap: 1)
        #expect(realigned.height == 3)
        // Output row k: red from k + 2, green from k + 1, blue from k.
        #expect(realigned.values == [2, 1, 0, 3, 2, 1, 4, 3, 2])
    }

    @Test func tiffIsAValid16BitRGBFile() throws {
        let image = RGB16Image(width: 3, height: 2, samples: (0..<18).map { UInt16($0 * 3000) })
        let data = TIFFWriter.data(for: image)
        #expect(Array(data.prefix(4)) == [0x49, 0x49, 0x2A, 0x00])
        #expect(TIFFWriter.data(for: image) == data)  // reproducible

        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 3)
        #expect(decoded.height == 2)
        #expect(decoded.bitsPerComponent == 16)
        #expect(decoded.bitsPerPixel == 48)
    }
}

struct PreviewDecodeTests {
    /// Runs the preview against the simulator, decodes it and compares the
    /// result with the synthetic film.
    @Test func decodedPreviewMatchesTheSyntheticFilm() async throws {
        let simulator = try Fixtures.simulator()
        let capture = try await PreviewRunner(transport: simulator, configuration: .simulator).run()
        let width = PreviewScript.previewPixelsPerLine
        let linear = try PreviewDecoding.decode(white: capture.whiteReference, dark: capture.darkReference,
                                                image: capture.image, width: width)
        #expect(linear.width == 2004)
        #expect(linear.height == 819 - 2)

        // Decoded row k is film row (lead-in lines + k + 1), see LineGap.
        let profile = try Fixtures.calibrationProfile()
        let film = simulator.film
        let firstRow = capture.leadIn.count + 1
        let usable = (0..<width).filter { column in
            (0..<3).allSatisfy { profile.white[column][$0] - profile.dark[column][$0] >= 2000 }
        }
        #expect(usable.count > 1500, "most columns see the light")

        var worst: Double = 0
        for row in 0..<linear.height {
            for column in usable {
                for channel in 0..<3 {
                    let expected = film.transmission(row: firstRow + row, column: column, channel: channel, width: width)
                    let value = Double(linear.values[(row * width + column) * 3 + channel])
                    worst = max(worst, abs(value - expected))
                }
            }
        }
        #expect(worst < 0.001, "largest error \(worst)")

        let url = FileManager.default.temporaryDirectory.appending(path: "x1kit-preview-\(UUID().uuidString).tif")
        defer { try? FileManager.default.removeItem(at: url) }
        try TIFFWriter.write(linear.toRGB16(), to: url)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 2004 && decoded.height == 817 && decoded.bitsPerComponent == 16)
    }
}

struct IncrementalDecodeTests {
    /// Block by block, the decoder gives exactly the batch result.
    @Test func incrementalDecodingEqualsBatchDecoding() async throws {
        let simulator = try Fixtures.simulator()
        let capture = try await PreviewRunner(transport: simulator, configuration: .simulator).run()
        let width = PreviewScript.previewPixelsPerLine
        let batch = try PreviewDecoding.decode(white: capture.whiteReference, dark: capture.darkReference,
                                               image: capture.image, width: width)

        var decoder = try IncrementalPreviewDecoder(white: capture.whiteReference, dark: capture.darkReference,
                                                    width: width)
        var completed = 0
        for block in capture.image {
            let rows = try decoder.append(block)
            #expect(rows.lowerBound == completed)
            completed = rows.upperBound
        }
        #expect(decoder.image == batch)

        // Raw samples go through the same realignment, before the flat field.
        let raw = try RGB16Image(littleEndianBlocks: capture.image, width: width)
        let row = 100, column = 700
        let stride = width * 3
        #expect(decoder.rawSamples[row * stride + column * 3] == raw.samples[(row + 2) * stride + column * 3])
        #expect(decoder.rawSamples[row * stride + column * 3 + 1] == raw.samples[(row + 1) * stride + column * 3 + 1])
        #expect(decoder.rawSamples[row * stride + column * 3 + 2] == raw.samples[row * stride + column * 3 + 2])
    }

    @Test func firstRowsWaitForTheLineGap() throws {
        let line = [UInt8](repeating: 0x10, count: 4 * 6)
        var decoder = try IncrementalPreviewDecoder(white: [line], dark: [[UInt8](repeating: 0, count: 4 * 6)], width: 4)
        #expect(try decoder.append(line).isEmpty)
        #expect(try decoder.append(line).isEmpty)
        #expect(try decoder.append(line) == 0..<1)
        #expect(throws: ImageError.self) { try decoder.append([0, 1, 2]) }
    }
}
