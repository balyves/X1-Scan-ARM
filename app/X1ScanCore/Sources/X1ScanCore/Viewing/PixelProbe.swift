// SPDX-License-Identifier: MIT

/// The values under the cursor, for the Info palette.
public struct PixelReading: Sendable, Hashable {
    public var coordinate: PixelCoordinate
    /// Corrected 16-bit values (flat field, line gap), as exported. R, G, B.
    public var corrected: [UInt16]
    /// Raw CCD samples behind the same pixel, before the flat field. R, G, B.
    public var raw: [UInt16]
}

public enum PixelProbe {
    /// Reading at `coordinate`, or nil if that row has not arrived yet or is outside the image.
    public static func reading(at coordinate: PixelCoordinate, in image: PreviewImage) -> PixelReading? {
        guard coordinate.x >= 0, coordinate.y >= 0, coordinate.x < image.width, coordinate.y < image.height else {
            return nil
        }
        let base = (coordinate.y * image.width + coordinate.x) * 3
        return PixelReading(coordinate: coordinate,
                            corrected: Array(image.corrected[base..<base + 3]),
                            raw: Array(image.raw[base..<base + 3]))
    }
}
