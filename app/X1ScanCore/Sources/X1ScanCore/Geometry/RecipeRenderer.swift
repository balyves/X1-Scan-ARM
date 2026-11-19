// SPDX-License-Identifier: MIT
import CoreGraphics
import X1Image

/// Renders a recipe into pixels, for Export. The display never uses this:
/// it shows the same geometry with layer transforms.
public enum RecipeRenderer {
    /// `image` with `recipe` applied. `pixelAspectRatio`: height of a source
    /// pixel relative to its width (3 for a preview, 1 for a scan).
    public static func render(_ image: RGB16Image, pixelAspectRatio: Double, recipe: Recipe) -> RGB16Image {
        // Quarter turns and mirror: an exact permutation, the pixels keep their
        // shape (a preview pixel turned a quarter is 3 times wider than tall).
        let turned = recipe.orientation.apply(to: image)
        let pixelSize = orientedPixelSize(pixelAspectRatio: pixelAspectRatio, orientation: recipe.orientation)
        let physical = CGSize(width: Double(turned.width) * pixelSize.width, height: Double(turned.height) * pixelSize.height)
        var crop = recipe.crop
        crop.frame = crop.effectiveFrame(imageSize: physical)
        guard !crop.isIdentity else { return turned }
        // Then the fine angle (Lanczos-3) and the crop.
        return Resample.apply(crop, to: turned, pixelSize: pixelSize)
    }

    /// Physical width and height of a pixel after the turns: a preview pixel
    /// (1 × 3) turned a quarter is 3 × 1.
    public static func orientedPixelSize(pixelAspectRatio: Double, orientation: Orientation) -> CGSize {
        orientation.swapsAxes ? CGSize(width: pixelAspectRatio, height: 1) : CGSize(width: 1, height: pixelAspectRatio)
    }

    /// Width and height of the file Export writes for an image of
    /// `width` × `height` source pixels.
    public static func outputSize(width: Int, height: Int, pixelAspectRatio: Double, recipe: Recipe) -> (width: Int, height: Int) {
        let turned = recipe.orientation.orientedSize(width: width, height: height)
        let pixelSize = orientedPixelSize(pixelAspectRatio: pixelAspectRatio, orientation: recipe.orientation)
        let physical = CGSize(width: Double(turned.width) * pixelSize.width, height: Double(turned.height) * pixelSize.height)
        guard let frame = recipe.crop.effectiveFrame(imageSize: physical)?.intersection(CGRect(x: 0, y: 0, width: 1, height: 1)),
              !frame.isNull, frame.width > 0, frame.height > 0 else { return turned }
        if recipe.crop.angle == 0 {
            let cropped = Resample.croppedBounds(width: turned.width, height: turned.height, normalized: frame)
            return (cropped.x1 - cropped.x0, cropped.y1 - cropped.y0)
        }
        let step = min(pixelSize.width, pixelSize.height)
        return (max(Int((frame.width * physical.width / step).rounded()), 1),
                max(Int((frame.height * physical.height / step).rounded()), 1))
    }
}
