// SPDX-License-Identifier: MIT
import Compression
import Foundation

/// Sample layout of an exported TIFF.
public enum TIFFFormat: String, Sendable, Hashable, CaseIterable, Codable {
    /// RGB, 16 bits per channel, linear, no profile: the raw scanner values. Default.
    case rgb16
    /// RGB, 8 bits per channel, sRGB curve, sRGB profile embedded.
    case rgb8
    /// Grey, 16 bits, linear, no profile.
    case gray16
    /// Grey, 8 bits, sRGB curve, grey profile with the sRGB curve embedded.
    case gray8

    public var channels: Int { self == .rgb16 || self == .rgb8 ? 3 : 1 }
    public var bitsPerSample: Int { self == .rgb16 || self == .gray16 ? 16 : 8 }
    public var isGray: Bool { channels == 1 }
    /// 8-bit formats are encoded with the sRGB curve; 16-bit formats stay linear.
    public var usesSRGBCurve: Bool { bitsPerSample == 8 }

    /// Uncompressed pixel bytes for an image of this size.
    public func pixelBytes(width: Int, height: Int) -> Int {
        width * height * channels * bitsPerSample / 8
    }
}

public enum TIFFCompression: String, Sendable, Hashable, CaseIterable, Codable {
    case none
    /// LZW (TIFF compression 5), with the horizontal predictor.
    case lzw
    /// ZIP: Deflate in a zlib stream (TIFF compression 8), with the horizontal predictor.
    case deflate

    var tag: UInt16 {
        switch self {
        case .none: 1
        case .lzw: 5
        case .deflate: 8
        }
    }
}

/// Converts the linear 16-bit RGB values for export. Documented in
/// docs/decisions.md ("Export formats").
public enum ExportConversion {
    /// Luminance of linear RGB with the Rec. 709 / sRGB coefficients.
    /// [hypothesis] The X1's primaries are unknown; provisional until the IT8 profile.
    public static let luminanceWeights = (red: 0.2126, green: 0.7152, blue: 0.0722)

    /// Linear 0...1 to the sRGB-encoded value, 0...1 (IEC 61966-2-1).
    public static func srgbEncoded(_ linear: Double) -> Double {
        let v = min(max(linear, 0), 1)
        let encoded = v <= 0.003_130_8 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        return min(max(encoded, 0), 1)
    }

    /// 16-bit linear to 8-bit sRGB, through a 65 536-entry table.
    static let srgb8Table: [UInt8] = (0...65_535).map {
        UInt8((srgbEncoded(Double($0) / 65_535) * 255).rounded())
    }

    /// The samples of `image` in `format`, before the predictor and compression.
    public static func samples(of image: RGB16Image, as format: TIFFFormat) -> [UInt16] {
        let pixels = image.width * image.height
        let rgb = image.samples
        switch format {
        case .rgb16:
            return rgb
        case .rgb8:
            return rgb.map { UInt16(srgb8Table[Int($0)]) }
        case .gray16, .gray8:
            let w = luminanceWeights
            var gray = [UInt16](repeating: 0, count: pixels)
            for i in 0..<pixels {
                let y = w.red * Double(rgb[3 * i]) + w.green * Double(rgb[3 * i + 1]) + w.blue * Double(rgb[3 * i + 2])
                let value = UInt16(min(max(y.rounded(), 0), 65_535))
                gray[i] = format == .gray8 ? UInt16(srgb8Table[Int(value)]) : value
            }
            return gray
        }
    }
}

/// Writes a TIFF, little-endian, one strip, from linear 16-bit RGB:
/// RGB or grey, 16 or 8 bits, no compression, LZW or Deflate (both with the
/// horizontal predictor), an optional ICC profile. The bytes depend only on
/// the inputs, so output is reproducible.
public enum TIFFWriter {
    /// RGB, 16 bits, uncompressed, no profile (step 1 behaviour).
    public static func data(for image: RGB16Image) -> Data {
        data(for: image, format: .rgb16, compression: .none, iccProfile: nil)
    }

    /// `resolution`: pixels per inch written in XResolution / YResolution (72 by default).
    /// `description`: an ImageDescription (ASCII), only when given (the application's samples).
    public static func data(for image: RGB16Image, format: TIFFFormat, compression: TIFFCompression,
                            iccProfile: Data?, resolution: Int = 72, description: String? = nil) -> Data {
        let samples = ExportConversion.samples(of: image, as: format)
        var pixels = bytes(of: samples, bitsPerSample: format.bitsPerSample)
        if compression != .none {
            applyPredictor(&pixels, width: image.width, height: image.height, channels: format.channels,
                           bytesPerSample: format.bitsPerSample / 8)
        }
        let strip: Data = switch compression {
        case .none: pixels
        case .lzw: LZW.encode(pixels)
        case .deflate: Zlib.compress(pixels)
        }
        return container(width: image.width, height: image.height, format: format, compression: compression,
                         strip: strip, iccProfile: iccProfile, resolution: UInt32(max(resolution, 1)),
                         description: description)
    }

    public static func write(_ image: RGB16Image, to url: URL) throws {
        try data(for: image).write(to: url, options: .atomic)
    }

    // MARK: Layout

    private static func bytes(of samples: [UInt16], bitsPerSample: Int) -> Data {
        if bitsPerSample == 8 { return Data(samples.map { UInt8($0) }) }
        var out = Data(count: samples.count * 2)
        out.withUnsafeMutableBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for (i, s) in samples.enumerated() {
                bytes[2 * i] = UInt8(s & 0xFF)
                bytes[2 * i + 1] = UInt8(s >> 8)
            }
        }
        return out
    }

    /// TIFF predictor 2: each sample minus the same channel of the pixel on
    /// its left, row by row, modulo 2^bits (little-endian samples).
    static func applyPredictor(_ data: inout Data, width: Int, height: Int, channels: Int, bytesPerSample: Int) {
        data.withUnsafeMutableBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            let rowSamples = width * channels
            for row in 0..<height {
                let base = row * rowSamples
                var i = rowSamples - 1
                while i >= channels {
                    let at = base + i, left = base + i - channels
                    if bytesPerSample == 1 {
                        bytes[at] = bytes[at] &- bytes[left]
                    } else {
                        let value = UInt16(bytes[2 * at]) | UInt16(bytes[2 * at + 1]) << 8
                        let previous = UInt16(bytes[2 * left]) | UInt16(bytes[2 * left + 1]) << 8
                        let diff = value &- previous
                        bytes[2 * at] = UInt8(diff & 0xFF)
                        bytes[2 * at + 1] = UInt8(diff >> 8)
                    }
                    i -= 1
                }
            }
        }
    }

    private static func container(width: Int, height: Int, format: TIFFFormat, compression: TIFFCompression,
                                  strip: Data, iccProfile: Data?, resolution: UInt32, description: String?) -> Data {
        // Layout: header | IFD | BitsPerSample (RGB) | XResolution | YResolution | ICC profile | strip
        var entries: [(tag: UInt16, type: UInt16, count: UInt32, value: UInt32, extra: Data?)] = []
        func short(_ tag: UInt16, _ value: UInt16) { entries.append((tag, 3, 1, UInt32(value), nil)) }
        func long(_ tag: UInt16, _ value: UInt32) { entries.append((tag, 4, 1, value, nil)) }
        func block(_ tag: UInt16, _ type: UInt16, _ count: UInt32, _ data: Data) { entries.append((tag, type, count, 0, data)) }
        func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }
        func le32(_ v: UInt32) -> Data { Data((0..<4).map { UInt8(truncatingIfNeeded: v >> UInt32(8 * $0)) }) }

        let bits = UInt16(format.bitsPerSample)
        long(256, UInt32(width))                                         // ImageWidth
        long(257, UInt32(height))                                        // ImageLength
        if format.channels == 3 {
            block(258, 3, 3, le16(bits) + le16(bits) + le16(bits))       // BitsPerSample
        } else {
            short(258, bits)
        }
        short(259, compression.tag)                                      // Compression
        short(262, format.isGray ? 1 : 2)                                // Photometric: BlackIsZero / RGB
        if let description {                                             // ImageDescription: ASCII, NUL-terminated
            let ascii = Data(description.unicodeScalars.map { $0.isASCII ? UInt8($0.value) : UInt8(ascii: "?") }) + Data([0])
            block(270, 2, UInt32(ascii.count), ascii)
        }
        long(273, 0)                                                     // StripOffsets (patched below)
        short(277, UInt16(format.channels))                              // SamplesPerPixel
        long(278, UInt32(height))                                        // RowsPerStrip
        long(279, UInt32(strip.count))                                   // StripByteCounts
        block(282, 5, 1, le32(resolution) + le32(1))                     // XResolution
        block(283, 5, 1, le32(resolution) + le32(1))                     // YResolution
        short(284, 1)                                                    // PlanarConfiguration: interleaved
        short(296, 2)                                                    // ResolutionUnit: inch
        if compression != .none { short(317, 2) }                       // Predictor: horizontal
        if let iccProfile { block(34675, 7, UInt32(iccProfile.count), iccProfile) }  // ICC profile
        entries.sort { $0.tag < $1.tag }

        let ifdOffset = 8
        let extraOffset = ifdOffset + 2 + entries.count * 12 + 4
        var extras = Data()
        var resolved: [(UInt16, UInt16, UInt32, UInt32)] = []
        for entry in entries {
            if let extra = entry.extra {
                if extra.count <= 4 {
                    var padded = extra
                    padded.append(Data(count: 4 - extra.count))
                    resolved.append((entry.tag, entry.type, entry.count, padded.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))
                } else {
                    resolved.append((entry.tag, entry.type, entry.count, UInt32(extraOffset + extras.count)))
                    extras.append(extra)
                    if extras.count % 2 == 1 { extras.append(0) }  // word alignment
                }
            } else {
                resolved.append((entry.tag, entry.type, entry.count, entry.value))
            }
        }
        let stripOffset = extraOffset + extras.count
        precondition(stripOffset + strip.count <= Int(UInt32.max), "image too large for a classic TIFF")


        var out = Data(capacity: stripOffset + strip.count)
        out.append(contentsOf: [0x49, 0x49, 0x2A, 0x00])
        out.append(le32(UInt32(ifdOffset)))
        out.append(le16(UInt16(resolved.count)))
        for (tag, type, count, value) in resolved {
            out.append(le16(tag)); out.append(le16(type)); out.append(le32(count))
            let v = tag == 273 ? UInt32(stripOffset) : value
            if type == 3 && count == 1 {
                out.append(le16(UInt16(v))); out.append(le16(0))
            } else {
                out.append(le32(v))
            }
        }
        out.append(le32(0))  // no next IFD
        out.append(extras)
        out.append(strip)
        return out
    }
}

/// TIFF LZW (compression 5): codes of 9 to 12 bits, most significant bit
/// first, Clear 256, EndOfInformation 257, "early change" of the code width.
enum LZW {
    static func encode(_ input: Data) -> Data {
        var out = Data()
        var bitBuffer: UInt32 = 0
        var bitCount = 0
        var width = 9
        func emit(_ code: Int) {
            bitBuffer = (bitBuffer << UInt32(width)) | UInt32(code)
            bitCount += width
            while bitCount >= 8 {
                out.append(UInt8(truncatingIfNeeded: bitBuffer >> UInt32(bitCount - 8)))
                bitCount -= 8
            }
        }
        var table: [Int: Int] = [:]  // (prefix << 8 | byte) → code
        var next = 258
        func reset() {
            table.removeAll(keepingCapacity: true)
            next = 258
            width = 9
        }
        emit(256)
        var prefix = -1
        for byte in input {
            let b = Int(byte)
            if prefix < 0 { prefix = b; continue }
            let key = prefix << 8 | b
            if let code = table[key] {
                prefix = code
                continue
            }
            emit(prefix)
            table[key] = next
            next += 1
            // The decoder switches one code early (TIFF LZW).
            if next > (1 << width) - 1, width < 12 { width += 1 }
            if next >= 4094 {
                emit(256)
                reset()
            }
            prefix = b
        }
        if prefix >= 0 {
            emit(prefix)
            next += 1
            if next > (1 << width) - 1, width < 12 { width += 1 }
        }
        emit(257)
        if bitCount > 0 { out.append(UInt8(truncatingIfNeeded: bitBuffer << UInt32(8 - bitCount))) }
        return out
    }
}

/// zlib stream (RFC 1950) around raw Deflate from Apple's Compression framework.
enum Zlib {
    static func compress(_ input: Data) -> Data {
        var out = Data([0x78, 0x9C])
        out.append(rawDeflate(input))
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in input {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        let adler = b << 16 | a
        out.append(contentsOf: [UInt8(adler >> 24), UInt8(truncatingIfNeeded: adler >> 16),
                                UInt8(truncatingIfNeeded: adler >> 8), UInt8(truncatingIfNeeded: adler)])
        return out
    }

    private static func rawDeflate(_ input: Data) -> Data {
        guard !input.isEmpty else { return Data([0x03, 0x00]) }  // empty final fixed block
        let capacity = input.count + input.count / 10 + 1_024
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { dst in
            input.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                          src.bindMemory(to: UInt8.self).baseAddress!, input.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        precondition(written > 0, "Deflate failed")
        return output.prefix(written)
    }
}
