// SPDX-License-Identifier: MIT
import Foundation
import CoreGraphics

/// Builds the `CGImage` the canvas shows.
///
/// The samples are the corrected 16-bit values (the export), tagged with a
/// linear colour space so that ColorSync converts them for the display.
/// **[hypothesis]** The X1's primaries are not known: linear sRGB is a
/// provisional choice (decisions.md), to be replaced by a scanner profile.
public enum DisplayImage {
    public static var colorSpaceName: CFString { CGColorSpace.linearSRGB }

    public static func make(from image: PreviewImage) -> CGImage? {
        guard image.height > 0, let space = CGColorSpace(name: colorSpaceName) else { return nil }
        let bytesPerRow = image.width * 6
        let data = image.corrected.withUnsafeBufferPointer { Data(buffer: $0) }  // host order: little-endian
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue | CGImageByteOrderInfo.order16Little.rawValue)
        return CGImage(width: image.width, height: image.height, bitsPerComponent: 16, bitsPerPixel: 48,
                       bytesPerRow: bytesPerRow, space: space, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
