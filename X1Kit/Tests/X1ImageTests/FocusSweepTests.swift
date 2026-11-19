// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import X1Image

struct FocusSweepTests {
    /// 400 synthetic lines: an edge blurred by |k − sharp| pixels at line k.
    private static func sweep(sharp: Int, width: Int = 64) -> [[Double]] {
        (0..<FocusSweep.lineCount).map { k in
            let blur = Double(abs(k - sharp)) / 10 + 0.5
            return (0..<width).map { x in 0.2 + 0.6 / (1 + exp(-(Double(x) - 32) / blur)) }
        }
    }

    @Test func eachMeasureFindsTheSharpestSyntheticLine() throws {
        for measure in FocusSweep.Measure.allCases {
            for sharp in [0, 137, 200, 399] {
                #expect(try FocusSweep.sharpestLine(Self.sweep(sharp: sharp), measure: measure) == sharp,
                        "\(measure) \(sharp)")
            }
        }
    }

    @Test func normalizedMeasureIgnoresBrightness() throws {
        // Same edge on every line; the brightness rises along the sweep.
        let lines = (0..<FocusSweep.lineCount).map { k in
            (0..<64).map { x in (1 + Double(k) / 100) * (x < 32 ? 0.2 : 0.4) }
        }
        #expect(try FocusSweep.sharpestLine(lines, measure: .gradientEnergy) == 399)
        let scores = lines.map { FocusSweep.score($0, measure: .normalizedGradientEnergy) }
        #expect(scores.allSatisfy { abs($0 - scores[0]) < 1e-12 * scores[0] })
    }

    @Test func refusesTheWrongShape() {
        #expect(throws: FocusSweep.FocusError.wrongShape) {
            try FocusSweep.sharpestLine(Array(Self.sweep(sharp: 3).prefix(399)), measure: .gradientEnergy)
        }
        var ragged = Self.sweep(sharp: 3)
        ragged[5].removeLast()
        #expect(throws: FocusSweep.FocusError.wrongShape) {
            try FocusSweep.sharpestLine(ragged, measure: .gradientEnergy)
        }
        #expect(throws: FocusSweep.FocusError.tooNarrow) {
            try FocusSweep.sharpestLine(Array(repeating: [0.5, 0.5], count: 400), measure: .gradientEnergy)
        }
    }
}

/// Our sharpest line against FlexColor's on the captured scans: a report,
/// not a test with a criterion (the user sets the criterion from it,
/// docs/decisions.md, "Window calculator v1: focus"). Set X1_FOCUS_CHECK_DIR
/// to a folder written by `tools/decode/export_focus.py` (outside the
/// repository: it holds image data). Skipped otherwise (and in CI).
struct FocusSweepReportTests {
    struct Row {
        let label: String
        let ppi: Int
        let binning: Int
        let holder: String
        let flexColor: Int
        let ours: [FocusSweep.Measure: Int]
    }

    /// Captures of other holders (ScanWindowFixtures.holders); every other
    /// capture with a scan is of the 6×7 (essai-C to -F: the 6×7 lens
    /// values of §9 in their windows).
    static let otherHolders = ["essai-J3": "24×36×4", "essai-J3-2": "24×36", "essai-J4": "4×5"]
    /// The resolutions of the calculator's menu (docs/decisions.md).
    static let menu: Set = [1_000, 1_500, 2_000, 3_000, 3_200]

    @Test(.enabled(if: ProcessInfo.processInfo.environment["X1_FOCUS_CHECK_DIR"] != nil))
    func report() throws {
        let root = URL(filePath: ProcessInfo.processInfo.environment["X1_FOCUS_CHECK_DIR"]!)
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path()).filter { !$0.hasPrefix(".") }
            .sorted { a, b in
                let (pa, na) = Self.split(a), (pb, nb) = Self.split(b)
                return pa == pb ? na < nb : pa < pb
            }
        var rows: [Row] = []
        var skipped: [String] = []
        for name in names {
            let directory = root.appending(path: name)
            let text = try String(contentsOf: directory.appending(path: "focus.txt"), encoding: .utf8)
            var f: [String: Int] = [:]
            for pair in text.split(whereSeparator: \.isWhitespace) {
                let kv = pair.split(separator: "=")
                if kv.count == 2, let v = Int(kv[1]) { f[String(kv[0])] = v }
            }
            guard let image54 = f["image54"], let base54 = f["base54"], let image58 = f["image58"],
                  let base58 = f["base58"], let full = f["full"], let column = f["column"],
                  let width = f["width"], let binning = f["binning"] else {
                skipped.append(name)
                continue
            }
            let delta = base54 + 10_000 - image54
            try #require(delta % 50 == 0 && base58 + 10_000 - image58 == delta, "\(name)")
            let geometry = ScanGeometry(firstColumn: column, width: width, binning: binning)
            let calibration = try RGB16Image(
                littleEndianBlocks: [Array(try Data(contentsOf: directory.appending(path: "calibration.bin")))], width: full)
            let reference = try ScanDecoding.reference(calibration: calibration, geometry: geometry)
            let focus = try RGB16Image(
                littleEndianBlocks: [Array(try Data(contentsOf: directory.appending(path: "focus.bin")))],
                width: geometry.pixelsPerLine)
            let lines = try FocusSweep.greenLines(focus: focus, geometry: geometry, reference: reference)
            var ours: [FocusSweep.Measure: Int] = [:]
            for measure in FocusSweep.Measure.allCases {
                ours[measure] = try FocusSweep.sharpestLine(lines, measure: measure)
            }
            let capture = Self.split(name).0
            rows.append(Row(label: name, ppi: f["ppi"] ?? 0, binning: binning,
                            holder: Self.otherHolders[capture] ?? "6×7", flexColor: delta / 50, ours: ours))
        }
        let measures = FocusSweep.Measure.allCases
        var report = skipped.isEmpty ? "" : "skipped (no image window or no calibration): \(skipped)\n"
        report += "scan holder ppi binning flexcolor_i, then ours − flexcolor: "
            + measures.map(\.rawValue).joined(separator: " ") + "\n"
        for row in rows {
            report += "\(row.label) \(row.holder) \(row.ppi) \(row.binning) \(row.flexColor) "
                + measures.map { "\(row.ours[$0]! - row.flexColor)" }.joined(separator: " ") + "\n"
        }
        let groups: [(String, [Row])] = [
            ("all scans", rows),
            ("6×7 at the menu's resolutions", rows.filter { $0.holder == "6×7" && Self.menu.contains($0.ppi) }),
        ]
        for (title, group) in groups {
            report += "\n\(title) (\(group.count) scans):\n"
            for measure in measures {
                let signed = group.map { Double($0.ours[measure]! - $0.flexColor) }
                let absolute = signed.map(abs)
                let n = Double(max(group.count, 1))
                report += "  \(measure.rawValue): max |diff| \(Int(absolute.max() ?? 0)), mean |diff| "
                    + String(format: "%.1f", absolute.reduce(0, +) / n)
                    + ", mean diff " + String(format: "%+.1f", signed.reduce(0, +) / n)
                    + ", within 5 lines \(absolute.filter { $0 <= 5 }.count)"
                    + ", within 10 \(absolute.filter { $0 <= 10 }.count)\n"
            }
        }
        print(report)
        if let out = ProcessInfo.processInfo.environment["X1_FOCUS_REPORT"] {
            try report.write(toFile: out, atomically: true, encoding: .utf8)
        }
        #expect(!rows.isEmpty)
    }

    static func split(_ name: String) -> (String, Int) {
        guard let i = name.lastIndex(of: "-") else { return (name, 0) }
        return (String(name[..<i]), Int(name[name.index(after: i)...]) ?? 0)
    }
}
