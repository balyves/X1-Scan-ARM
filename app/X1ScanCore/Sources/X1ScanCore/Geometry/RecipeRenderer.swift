// SPDX-License-Identifier: MIT
import X1Image

/// Renders a recipe into pixels, for Export. The display never uses this:
/// it shows the same geometry with layer transforms.
public enum RecipeRenderer {
    /// `image` with `recipe` applied. `pixelAspectRatio`: height of a source
    /// pixel relative to its width (3 for a preview, 1 for a scan).
    public static func render(_ image: RGB16Image, pixelAspectRatio: Double, recipe: Recipe) -> RGB16Image {
        // Quarter turns and mirror: an exact permutation, the pixels keep their
        // shape (a preview pixel turned a quarter is 3 times wider than tall).
        recipe.orientation.apply(to: image)
    }
}
