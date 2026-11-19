// SPDX-License-Identifier: MIT

/// Our own choice of the sharpest line of the 400-line focus step of a scan
/// (docs/protocol.md §12, "400-line step"; docs/decisions.md, "Window
/// calculator v1: focus"). FlexColor's own measure is not known: each
/// measure here is a [hypothesis], compared with FlexColor's line *i* on the
/// captured scans by `FocusSweepReportTests`. Simulator only: nothing here
/// sends anything.
public enum FocusSweep {
    /// Number of one-line reads after `1b 00 08 06 01 00`. [confirmed]
    public static let lineCount = 400

    /// A sharpness measure of one line (green channel, flat-fielded).
    public enum Measure: String, CaseIterable, Sendable {
        /// Mean squared difference between neighbouring pixels (gradient
        /// energy).
        case gradientEnergy
        /// Variance of the second difference (1-D Laplacian).
        case laplacianVariance
        /// Gradient energy divided by the squared mean level of the line, so
        /// that a change of brightness along the sweep does not count as
        /// sharpness.
        case normalizedGradientEnergy
    }

    /// The measure used until a criterion is set: gradient energy. User's
    /// decision of 2026-11-19, provisional; the criterion is set after the
    /// recalibration (docs/decisions.md, "Window calculator v1").
    public static let provisionalMeasure = Measure.gradientEnergy

    /// Errors of `sharpestLine`.
    public enum FocusError: Error, Equatable, Sendable {
        /// Not exactly `lineCount` lines, or lines of different lengths.
        case wrongShape
        /// Fewer than three pixels per line.
        case tooNarrow
    }

    /// The green channel of each line, flat-fielded with `reference`:
    /// `focus` holds the 400 lines as read (margin + width pixels each).
    public static func greenLines(focus: RGB16Image, geometry: ScanGeometry,
                                  reference: FlatFieldReference) throws -> [[Double]] {
        guard focus.width == geometry.pixelsPerLine else {
            throw ImageError.widthMismatch(expected: geometry.pixelsPerLine, received: focus.width)
        }
        guard reference.width == geometry.width else {
            throw ImageError.widthMismatch(expected: geometry.width, received: reference.width)
        }
        let frame = focus.rows(Array(0..<focus.height), columns: geometry.margin..<geometry.pixelsPerLine)
        let flat = try reference.apply(to: frame)
        return (0..<flat.height).map { row in
            (0..<flat.width).map { Double(flat.values[(row * flat.width + $0) * 3 + 1]) }
        }
    }

    /// The score of one line.
    public static func score(_ line: [Double], measure: Measure) -> Double {
        let n = line.count
        guard n >= 3 else { return 0 }
        switch measure {
        case .gradientEnergy, .normalizedGradientEnergy:
            var sum = 0.0
            for k in 1..<n {
                let d = line[k] - line[k - 1]
                sum += d * d
            }
            let energy = sum / Double(n - 1)
            guard measure == .normalizedGradientEnergy else { return energy }
            let mean = line.reduce(0, +) / Double(n)
            return mean > 0 ? energy / (mean * mean) : 0
        case .laplacianVariance:
            var values: [Double] = []
            values.reserveCapacity(n - 2)
            for k in 1..<(n - 1) { values.append(line[k - 1] - 2 * line[k] + line[k + 1]) }
            let mean = values.reduce(0, +) / Double(values.count)
            return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        }
    }

    /// The line *i* (0-399) with the highest score; the first one on a tie.
    /// No smoothing along the sweep.
    public static func sharpestLine(_ lines: [[Double]], measure: Measure) throws -> Int {
        guard lines.count == lineCount, let width = lines.first?.count,
              lines.allSatisfy({ $0.count == width }) else { throw FocusError.wrongShape }
        guard width >= 3 else { throw FocusError.tooNarrow }
        let scores = lines.map { score($0, measure: measure) }
        var best = 0
        for k in scores.indices where scores[k] > scores[best] { best = k }
        return best
    }
}
