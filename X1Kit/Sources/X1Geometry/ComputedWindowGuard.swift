// SPDX-License-Identifier: MIT
//
// Check of the computed windows of a scan, simulator only (docs/decisions.md,
// "Window calculator v1"). Like the calculator, it lives in X1Geometry, which
// nothing in the app, the transport or the scan script can reach: it is not
// an extension of CapturedSequenceGuard, and it guards nothing sent to the
// real X1 (CLAUDE.md rule 4 unchanged).

/// What `ComputedWindowGuard` refuses.
public enum ComputedWindowError: Error, Equatable, Sendable {
    /// Offset 62 of the 400-line window is not the value option A gives
    /// from the image window (`expected` nil: no value can come from it).
    case focusLine(sent: Int, expected: Int?)
    /// A field of the 400-line window is not the constant of the
    /// calibration or the image window's (name of the field).
    case focusWindowField(String)
    /// Offsets 54 / 58 of the image window after the step are not one of
    /// the 400 positions swept: `base + 10 000 − 50 × k`, k = 0...399, the
    /// same k for both.
    case focusNotSwept(lens54: Int, lens58: Int)
    /// A field other than 54 / 58 of the image window after the step is not
    /// the one of the image window before it (name of the field).
    case imageWindowField(String)
}

/// Checks the computed windows of a scan before they would be sent. Every
/// value is recomputed from the windows alone, with the same functions as
/// the calculator (one rounding, one place).
public enum ComputedWindowGuard {
    /// The 400-line window against the image window (before the step):
    /// the calibration's constants, the image window's column, width and
    /// binning, and offset 62 by option A exactly (no tolerance: the
    /// calculator and the guard round in the same function).
    public static func checkFocusWindow(_ focus: ScanWindowFields, image: ScanWindowFields,
                                        calibration c: WindowCalibration) throws {
        let expected = ScanWindowCalculator.focusLinePosition(imageWindow: image, calibration: c)
        guard focus.focusLine == expected else {
            throw ComputedWindowError.focusLine(sent: focus.focusLine, expected: expected)
        }
        let checks: [(String, Bool)] = [
            ("ratio", focus.ratio == c.focusRatio),
            ("column", focus.column == image.column),
            ("line", focus.line == 0),
            ("pixels", focus.pixels == image.pixels),
            ("lines", focus.lines == ScanWindowCalculator.focusSweepLines + 1),
            ("byte48", focus.byte48 == image.byte48),
            ("binning", focus.binning == image.binning),
            ("lens54", focus.lens54 == image.lens54 + c.focusLensOffset),
            ("lens58", focus.lens58 == image.lens58 + c.focusLensOffset),
        ]
        if let failed = checks.first(where: { !$0.1 }) { throw ComputedWindowError.focusWindowField(failed.0) }
    }

    /// The image window sent after the step: every field but 54 / 58 as in
    /// the image window before it, and 54 / 58 one of the positions the
    /// 400-line window swept, the same line for both. Returns that line.
    @discardableResult
    public static func checkImageWindowAfterStep(_ after: ScanWindowFields, before: ScanWindowFields,
                                                 focus: ScanWindowFields) throws -> Int {
        let checks: [(String, Bool)] = [
            ("ratio", after.ratio == before.ratio),
            ("column", after.column == before.column),
            ("line", after.line == before.line),
            ("pixels", after.pixels == before.pixels),
            ("lines", after.lines == before.lines),
            ("byte48", after.byte48 == before.byte48),
            ("binning", after.binning == before.binning),
            ("target", after.target == before.target),
            ("focusLine", after.focusLine == before.focusLine),
        ]
        if let failed = checks.first(where: { !$0.1 }) { throw ComputedWindowError.imageWindowField(failed.0) }
        return try checkFocusPosition(imageAfterStep: after, focus: focus)
    }

    /// Offsets 54 / 58 of the image window sent after the step: one of the
    /// positions the 400-line window swept, the same line for both. Returns
    /// that line. Only 54 / 58: `checkImageWindowAfterStep` checks the
    /// whole window.
    @discardableResult
    public static func checkFocusPosition(imageAfterStep image: ScanWindowFields,
                                          focus: ScanWindowFields) throws -> Int {
        let step = ScanWindowCalculator.focusUnitsPerLine
        let d54 = focus.lens54 - image.lens54, d58 = focus.lens58 - image.lens58
        guard d54 == d58, d54 >= 0, d54 % step == 0, d54 / step < ScanWindowCalculator.focusSweepLines else {
            throw ComputedWindowError.focusNotSwept(lens54: image.lens54, lens58: image.lens58)
        }
        return d54 / step
    }
}
