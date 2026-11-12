// SPDX-License-Identifier: MIT
import Foundation

/// Writes a baseline TIFF: RGB, 16 bits per channel, little-endian,
/// uncompressed, one strip, no colour profile. The bytes depend only on the
/// image, so output is reproducible.
public enum TIFFWriter {
    public static func data(for image: RGB16Image) -> Data {
        // Layout: header (8) | IFD (2 + 13 × 12 + 4) | BitsPerSample (6) | XResolution (8) | YResolution (8) | pixels
        let entryCount = 13
        let ifdOffset = 8
        let bitsOffset = ifdOffset + 2 + entryCount * 12 + 4
        let xResolutionOffset = bitsOffset + 6
        let yResolutionOffset = xResolutionOffset + 8
        let pixelOffset = yResolutionOffset + 8
        let pixelBytes = image.samples.count * 2
        precondition(pixelOffset + pixelBytes <= Int(UInt32.max), "image too large for a classic TIFF")

        var out = Data(capacity: pixelOffset + pixelBytes)
        func u16(_ value: UInt16) { out.append(UInt8(value & 0xFF)); out.append(UInt8(value >> 8)) }
        func u32(_ value: UInt32) { for shift in stride(from: 0, to: 32, by: 8) { out.append(UInt8(truncatingIfNeeded: value >> UInt32(shift))) } }
        func entry(_ tag: UInt16, short value: UInt16) { u16(tag); u16(3); u32(1); u16(value); u16(0) }
        func entry(_ tag: UInt16, long value: UInt32) { u16(tag); u16(4); u32(1); u32(value) }
        func entry(_ tag: UInt16, type: UInt16, count: UInt32, offset: Int) { u16(tag); u16(type); u32(count); u32(UInt32(offset)) }

        out.append(contentsOf: [0x49, 0x49, 0x2A, 0x00])  // "II", 42
        u32(UInt32(ifdOffset))

        u16(UInt16(entryCount))
        entry(256, long: UInt32(image.width))                      // ImageWidth
        entry(257, long: UInt32(image.height))                     // ImageLength
        entry(258, type: 3, count: 3, offset: bitsOffset)          // BitsPerSample 16,16,16
        entry(259, short: 1)                                       // Compression: none
        entry(262, short: 2)                                       // PhotometricInterpretation: RGB
        entry(273, long: UInt32(pixelOffset))                      // StripOffsets
        entry(277, short: 3)                                       // SamplesPerPixel
        entry(278, long: UInt32(image.height))                     // RowsPerStrip
        entry(279, long: UInt32(pixelBytes))                       // StripByteCounts
        entry(282, type: 5, count: 1, offset: xResolutionOffset)   // XResolution
        entry(283, type: 5, count: 1, offset: yResolutionOffset)   // YResolution
        entry(284, short: 1)                                       // PlanarConfiguration: interleaved
        entry(296, short: 2)                                       // ResolutionUnit: inch
        u32(0)                                                     // no next IFD

        u16(16); u16(16); u16(16)
        u32(72); u32(1)
        u32(72); u32(1)

        for sample in image.samples { u16(sample) }
        return out
    }

    public static func write(_ image: RGB16Image, to url: URL) throws {
        try data(for: image).write(to: url, options: .atomic)
    }
}
