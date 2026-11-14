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

struct TIFFExportTests {
    /// A gradient with noise, so that the predictor and the compressors have work to do.
    private static let image: RGB16Image = {
        let width = 97, height = 41
        var samples = [UInt16](repeating: 0, count: width * height * 3)
        var seed: UInt32 = 12_345
        for y in 0..<height {
            for x in 0..<width {
                seed = seed &* 1_103_515_245 &+ 12_345
                let noise = Int(seed >> 20) & 0x3F
                let i = (y * width + x) * 3
                samples[i] = UInt16(min(x * 670 + noise, 65_535))
                samples[i + 1] = UInt16(min(y * 1_590 + noise, 65_535))
                samples[i + 2] = UInt16(min((x + y) * 470 + noise, 65_535))
            }
        }
        return RGB16Image(width: width, height: height, samples: samples)
    }()

    /// Decodes with ImageIO and returns the samples, channel by channel, as stored.
    /// ImageIO may pad 8-bit RGB to four bytes per pixel: only the first `channels` are kept.
    private func decode(_ data: Data, channels wanted: Int) throws -> (image: CGImage, samples: [UInt16]) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let bytes = try #require(image.dataProvider?.data as Data?)
        var samples: [UInt16] = []
        let channels = image.bitsPerPixel / image.bitsPerComponent
        for row in 0..<image.height {
            let rowStart = row * image.bytesPerRow
            for i in 0..<(image.width * channels) where i % channels < wanted {
                if image.bitsPerComponent == 16 {
                    let at = rowStart + 2 * i
                    let little = image.bitmapInfo.contains(.byteOrder16Little)
                    let a = UInt16(bytes[at]), b = UInt16(bytes[at + 1])
                    samples.append(little ? a | b << 8 : a << 8 | b)
                } else {
                    samples.append(UInt16(bytes[rowStart + i]))
                }
            }
        }
        return (image, samples)
    }

    @Test(arguments: TIFFFormat.allCases, TIFFCompression.allCases)
    func everyFormatAndCompressionReadsBackExactly(format: TIFFFormat, compression: TIFFCompression) throws {
        let profile: Data? = switch format {
        case .rgb8: CGColorSpace(name: CGColorSpace.sRGB)?.copyICCData() as Data?
        case .gray8: ICCProfiles.graySRGB
        default: nil
        }
        let data = TIFFWriter.data(for: Self.image, format: format, compression: compression, iccProfile: profile)
        #expect(TIFFWriter.data(for: Self.image, format: format, compression: compression, iccProfile: profile) == data,
                "reproducible")
        let (decoded, samples) = try decode(data, channels: format.channels)
        #expect(decoded.width == 97 && decoded.height == 41)
        #expect(decoded.bitsPerComponent == format.bitsPerSample)
        #expect(decoded.bitsPerPixel / decoded.bitsPerComponent >= format.channels)
        #expect(samples == ExportConversion.samples(of: Self.image, as: format), "values identical after decoding")
        let model = decoded.colorSpace?.model
        #expect(model == (format.isGray ? .monochrome : .rgb))
        if profile != nil { #expect(decoded.colorSpace?.copyICCData() != nil, "profile embedded") }
    }

    /// Large enough to fill the LZW table several times (Clear codes).
    @Test func lzwHandlesFullTables() throws {
        let width = 640, height = 200
        var seed: UInt32 = 7
        let samples: [UInt16] = (0..<(width * height * 3)).map { _ in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return UInt16(truncatingIfNeeded: seed >> 7)
        }
        let image = RGB16Image(width: width, height: height, samples: samples)
        for format in [TIFFFormat.rgb16, .gray8] {
            let data = TIFFWriter.data(for: image, format: format, compression: .lzw, iccProfile: nil)
            let (_, decoded) = try decode(data, channels: format.channels)
            #expect(decoded == ExportConversion.samples(of: image, as: format))
        }
    }

    @Test func compressionShrinksTheFile() {
        let none = TIFFWriter.data(for: Self.image, format: .rgb16, compression: .none, iccProfile: nil).count
        let lzw = TIFFWriter.data(for: Self.image, format: .rgb16, compression: .lzw, iccProfile: nil).count
        let zip = TIFFWriter.data(for: Self.image, format: .rgb16, compression: .deflate, iccProfile: nil).count
        #expect(none - TIFFFormat.rgb16.pixelBytes(width: 97, height: 41) < 400, "uncompressed: pixels plus a small header")
        #expect(zip < none && lzw < none)
    }

    @Test func eightBitUsesTheSRGBCurveAndGrayTheLuminance() {
        #expect(ExportConversion.srgbEncoded(0) == 0 && abs(ExportConversion.srgbEncoded(1) - 1) < 1e-12)
        #expect(abs(ExportConversion.srgbEncoded(0.18) - 0.461) < 0.001, "middle grey")
        let image = RGB16Image(width: 2, height: 1, samples: [65_535, 0, 0, 11_796, 11_796, 11_796])
        #expect(ExportConversion.samples(of: image, as: .rgb8) == [255, 0, 0, 118, 118, 118])
        #expect(ExportConversion.samples(of: image, as: .gray16) == [13_933, 11_796], "0.2126 × 65535; grey kept")
        #expect(ExportConversion.samples(of: image, as: .gray8)[1] == 118)
    }

    @Test func graySRGBProfileIsAValidGrayProfile() throws {
        let space = try #require(CGColorSpace(iccData: ICCProfiles.graySRGB as CFData))
        #expect(space.model == .monochrome)
        #expect(ICCProfiles.graySRGB.count % 4 == 0)
    }
}
