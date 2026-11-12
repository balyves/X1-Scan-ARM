// SPDX-License-Identifier: MIT

public enum ImageError: Error, Hashable, CustomStringConvertible {
    case malformedBlock(index: Int, size: Int, bytesPerLine: Int)
    case noLines
    case widthMismatch(expected: Int, received: Int)

    public var description: String {
        switch self {
        case .malformedBlock(let index, let size, let bytesPerLine):
            "block \(index): \(size) bytes is not a multiple of \(bytesPerLine)"
        case .noLines:
            "no lines"
        case .widthMismatch(let expected, let received):
            "width \(received), \(expected) expected"
        }
    }
}

/// 16-bit RGB image, channels interleaved, rows top to bottom. This is the
/// scanner's own format once the little-endian bytes are decoded.
public struct RGB16Image: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// width × height × 3 samples.
    public var samples: [UInt16]

    public init(width: Int, height: Int, samples: [UInt16]) {
        precondition(samples.count == width * height * 3, "sample count does not match the size")
        self.width = width
        self.height = height
        self.samples = samples
    }

    /// Decodes READ blocks: RGB interleaved, 16-bit little-endian. [confirmed]
    public init(littleEndianBlocks blocks: [[UInt8]], width: Int) throws {
        let bytesPerLine = width * 6
        var samples: [UInt16] = []
        samples.reserveCapacity(blocks.reduce(0) { $0 + $1.count } / 2)
        for (index, block) in blocks.enumerated() {
            guard block.count.isMultiple(of: bytesPerLine) else {
                throw ImageError.malformedBlock(index: index, size: block.count, bytesPerLine: bytesPerLine)
            }
            var offset = 0
            while offset < block.count {
                samples.append(UInt16(block[offset]) | UInt16(block[offset + 1]) << 8)
                offset += 2
            }
        }
        guard !samples.isEmpty else { throw ImageError.noLines }
        self.init(width: width, height: samples.count / (width * 3), samples: samples)
    }
}

/// Linear RGB image in 0...1, channels interleaved. Processing works on this.
public struct LinearImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var values: [Float]

    public init(width: Int, height: Int, values: [Float]) {
        precondition(values.count == width * height * 3, "value count does not match the size")
        self.width = width
        self.height = height
        self.values = values
    }

    /// Linear 16-bit encoding: 0 → 0, 1 → 65 535. No gamma, no profile.
    public func toRGB16() -> RGB16Image {
        RGB16Image(width: width, height: height,
                   samples: values.map { UInt16((min(max($0, 0), 1) * 65_535).rounded()) })
    }
}
