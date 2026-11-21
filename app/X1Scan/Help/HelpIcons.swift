// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import X1ScanCore

extension Image {
    /// The icon of a tool or of an icon button, from the table the help uses too (`AppIcon`).
    init(_ icon: AppIcon) {
        switch icon.source {
        case .symbol(let name):
            self.init(systemName: name)
        case .drawn:
            // Drawn icons have their own view (`SwapDimensionsIcon`); never shown through `Image`.
            assertionFailure("\(icon) is drawn by its own view")
            self.init(systemName: "questionmark")
        }
    }
}

/// The help's icons (`{icon:<key>}` in a page), rendered when a page is shown
/// from the same names as the interface: a black PNG on a transparent
/// background, used by the page as a CSS mask, so that it takes the text's
/// colour in light and dark mode. Nothing is stored in the repository.
@MainActor
enum HelpIcons {
    /// Rendered height in pixels: about 3× the 15 px of the page.
    private static let pixelHeight: CGFloat = 48
    private static var cache: [AppIcon: String] = [:]

    /// A `data:` URL of `icon`, or nil if it cannot be rendered.
    static func dataURL(_ icon: AppIcon) -> String? {
        if let cached = cache[icon] { return cached }
        guard let png = png(icon) else { return nil }
        let url = "data:image/png;base64," + png.base64EncodedString()
        cache[icon] = url
        return url
    }

    private static func png(_ icon: AppIcon) -> Data? {
        let image: CGImage?
        switch icon.source {
        case .symbol(let name):
            image = symbol(name)
        case .drawn:
            // As in the panel: the frame of the image (landscape), then exchanged.
            let renderer = ImageRenderer(content: SwapDimensionsIcon(upright: false)
                .frame(width: SwapDimensionsIcon.size.width, height: SwapDimensionsIcon.size.height)
                .foregroundStyle(Color.black))
            renderer.scale = pixelHeight / SwapDimensionsIcon.size.height
            image = renderer.cgImage
        }
        guard let image else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private static func symbol(_ name: String) -> CGImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pixelHeight * 0.75, weight: .regular)
            .applying(.init(paletteColors: [.black]))
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        let size = symbol.size
        let width = Int(size.width.rounded(.up)), height = Int(size.height.rounded(.up))
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        symbol.draw(in: NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
