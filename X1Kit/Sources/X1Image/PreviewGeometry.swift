// SPDX-License-Identifier: MIT

/// Geometry of preview pixels.
public enum PreviewGeometry {
    /// Height of a preview pixel (along the drum) divided by its width
    /// (across the CCD). **[hypothesis]**: about 3 (docs/protocol.md §9 and
    /// §10: the preview's step ratio is a third of the calibration ratio, and
    /// FlexColor's preview geometry is reproduced with 3). To be adjusted with
    /// captures of real scans.
    ///
    /// This is the only place the value is set in Swift. It is used for
    /// display only: decoded and exported images keep the scanner's pixels.
    /// (`tools/decode/decode_preview.py` has its own `--aspect` option, default 3.)
    public static let pixelAspectRatio: Double = 3
}
