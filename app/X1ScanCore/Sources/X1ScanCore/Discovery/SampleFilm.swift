// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import ImageIO
import X1Transport

/// The film of discovery mode (lot A, step C). Today the virtual X1's
/// synthetic test pattern; later a photograph of the user's own film, with
/// its licence in a separate file, as for the icon. The place is
/// `app/X1Scan/Sample/`: once `discovery-film.tiff` is there (copied into the
/// application's resources), the virtual X1 of discovery mode reads its
/// transmission from it instead of the pattern. No photograph is in the
/// repository yet (user's decision).
public enum SampleFilm {
    /// Name of the image in the application's resources.
    public static let resourceName = "discovery-film"
    public static let resourceExtension = "tiff"

    /// The photograph's film, if the application has one.
    public static func load(bundle: Bundle) -> SyntheticFilm? {
        bundle.url(forResource: resourceName, withExtension: resourceExtension).flatMap(load(url:))
    }

    public static func load(url: URL) -> SyntheticFilm? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return film(from: image)
    }

    /// A film whose transmission is `image` (sRGB, decoded to linear),
    /// stretched to the line's width, rows at the same scale (with
    /// `rowsPerColumn`: preview rows are 3 times taller than wide), edges
    /// repeated beyond the image.
    public static func film(from image: CGImage, rowsPerColumn: Double = 1) -> SyntheticFilm? {
        let width = image.width, height = image.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height * 4))
        let linear: [Double] = (0...255).map { value in
            let c = Double(value) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return SyntheticFilm { row, column, channel, lineWidth in
            let scale = Double(width) / Double(max(lineWidth, 1))
            let x = min(max(Int(Double(column) * scale), 0), width - 1)
            let y = min(max(Int(Double(row) * scale * rowsPerColumn), 0), height - 1)
            return linear[Int(bytes[(y * width + x) * 4 + min(max(channel, 0), 2)])]
        }
    }
}
