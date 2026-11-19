// SPDX-License-Identifier: MIT
import Foundation
import Testing
import X1TestSupport

/// The rules behind FlexColor's scan windows (docs/protocol.md §9, "Window
/// rules"), checked on the 15 scans of 2026-11-18 and the 16 of 2026-11-19
/// (tests/fixtures/scan-windows-2026-11-18.json, -19.json). Nothing here builds a
/// window for the scanner: these rules are a [hypothesis] for a future
/// window calculator, and this test shows that they reproduce every captured
/// value.
struct ScanWindowRulesTests {
    /// Per holder: drum factor × 10 000 (calibration ratio ÷ resolution) and
    /// *M* (binning = min(4, *M* ÷ resolution)). *M* is a [hypothesis]: the
    /// scans only bound it (§9); 6 300 for the 24×36 is not even observed at
    /// a run start, any value of 4 000 or more gives the same binning here.
    private static let holders: [String: (factor: Int, maximum: Int)] = [
        "essai-I": (10_000, 3_200),   // 6×7
        "essai-L": (10_000, 3_200),   // 6×7 (part H)
        "essai-N": (10_000, 3_200),   // 6×7 (part K)
        "essai-J3": (9_770, 6_300),   // 24×36×4
        "essai-J3-2": (10_245, 6_300), // 24×36
        "essai-J4": (8_855, 2_040),   // 4×5
    ]

    private struct Window {
        let bytes: [UInt8]
        init(_ bytes: [UInt8]) { self.bytes = bytes }
        func le(_ offset: Int, _ size: Int) -> Int {
            (0..<size).reduce(0) { $0 | Int(bytes[offset + $1]) << (8 * $1) }
        }
        var ratio: Int { le(10, 4) }
        var column: Int { le(14, 2) }
        var line: Int { le(18, 2) }
        var pixels: Int { le(22, 2) }
        var lines: Int { le(26, 2) }
        var binning: Int { Int(bytes[49]) }
        var target: Int { le(50, 2) }
        var o54: Int { le(54, 4) }
        var o58: Int { le(58, 4) }
        var o62: Int { le(62, 4) }
    }

    private struct ScanCase {
        let capture: String
        let session: Int
        let scan: ScanWindowFixtures.Scan
        let image: Window
        let focus: Window
        let focusTarget: Int?
        let base: Window
        /// Nil when FlexColor skipped the calibration and references (some scans of part H).
        let referencesFirst: Bool?
    }

    private static func loadCases() throws -> [ScanCase] {
        try ScanWindowFixtures.load().map {
            ScanCase(capture: $0.capture, session: $0.session, scan: $0.scan, image: Window($0.image),
                     focus: Window($0.focus), focusTarget: $0.focusTarget, base: Window($0.base),
                     referencesFirst: $0.referencesFirst)
        }
    }

    private static let loaded = Result { try loadCases() }

    private var cases: [ScanCase] { get throws { try Self.loaded.get() } }

    @Test func thirtyOneScans() throws {
        #expect(try cases.count == 31)
        #expect(try cases.filter { $0.capture == "essai-I" }.count == 12)
        #expect(try cases.filter { $0.capture == "essai-L" }.count == 8)
        #expect(try cases.filter { $0.capture == "essai-N" }.count == 8)
        // FlexColor skipped the calibration and references in four scans of part H, one of part K.
        let skipped = try cases.filter { $0.referencesFirst == nil }.map { "\($0.capture) \($0.session)" }
        #expect(skipped == ["essai-L 6", "essai-L 8", "essai-L 9", "essai-L 10", "essai-N 8"])
    }

    /// Resolution, binning, width and lines of the image window.
    @Test func imageWindow() throws {
        for c in try cases {
            let holder = Self.holders[c.capture]!
            let binning = min(4, holder.maximum / c.scan.ppi)
            let gap = (20 + binning / 2) / binning // 20, 10, 7, 5
            let label = "\(c.capture) session \(c.session)"
            #expect(c.image.ratio == c.scan.ppi * holder.factor * 5 / 3, "\(label)")
            #expect(c.image.binning == binning, "\(label)")
            #expect(c.image.pixels == c.scan.tiff_width, "\(label)")
            #expect(c.image.lines == c.scan.tiff_height * 5 / 3 + 2 * gap + 2, "\(label)")
            // White and black references before the 400-line step at an optical
            // resolution of 3 000 and above, after it at 2 400 and below.
            if let first = c.referencesFirst {
                #expect(first == (c.scan.ppi * binning >= 3_000), "\(label)")
            }
        }
    }

    /// The 400-line window and the focus correction of the image window.
    @Test func focusWindow() throws {
        for c in try cases {
            let label = "\(c.capture) session \(c.session)"
            #expect(c.focus.column == c.image.column && c.focus.pixels == c.image.pixels, "\(label)")
            #expect(c.focus.line == 0 && c.focus.lines == 401 && c.focus.binning == c.image.binning, "\(label)")
            #expect(c.focus.target == c.focusTarget, "\(label): the position read just before")
            #expect(c.focus.o54 == c.base.o54 + 10_000 && c.focus.o58 == c.base.o58 + 10_000, "\(label)")
            let correction = c.image.o54 - c.base.o54
            #expect(c.image.o58 - c.base.o58 == correction && correction % 50 == 0 && abs(correction) < 10_000, "\(label)")
        }
    }

    /// Offset 62 of the 400-line window: the drum position of the middle of
    /// the frame's image lines, 15 500 + 28 800 per inch (§9), within 25.
    @Test func focusLinePosition() throws {
        for c in try cases {
            let gap = (20 + c.image.binning / 2) / c.image.binning
            let middle = Double(c.image.line) + Double(c.image.lines - 2 * gap - 2) / 2
            let expected = 15_500 + 28_800 * middle / (Double(c.image.ratio) / 10_000)
            #expect(abs(Double(c.focus.o62) - expected) <= 25, "\(c.capture) session \(c.session): \(c.focus.o62)")
        }
    }

    /// Part K (zoom 100 %): one frame left untouched gives the same offset 62
    /// at 3 200, 2 000 (twice) and 1 000 ppi, and one 600 ppi output pixel
    /// (28 800 ÷ 600 = 48) less at 600 ppi (docs/protocol.md §9).
    @Test func partKUntouchedFrame() throws {
        let frame = try cases.filter { $0.capture == "essai-N" && (2...6).contains($0.session) }
        #expect(frame.map(\.scan.ppi) == [3_200, 2_000, 2_000, 1_000, 600])
        #expect(frame.map(\.focus.o62) == [59_713, 59_713, 59_713, 59_713, 59_713 - 48])
    }

    /// 6×7: offsets 54 and 58 before the focus step follow the optical
    /// resolution O = resolution × binning (lens model fitted on six values
    /// of O, §9; essai-I's scans have four of them: 2 000, 2 400, 3 000,
    /// 3 200), within 1.
    @Test func sixBySevenOptics() throws {
        let sixBySeven = try cases.filter { ["essai-I", "essai-L", "essai-N"].contains($0.capture) }
        // essai-L adds O = 2 880 (960 ppi at binning 3), a value not used to fit the model.
        #expect(Set(sixBySeven.map { $0.scan.ppi * $0.image.binning }) == [2_000, 2_400, 2_880, 3_000, 3_200])
        for c in sixBySeven {
            let optical = Double(c.scan.ppi * c.image.binning)
            let o58 = 1_136_908 - 896_886_417 / optical
            let o54 = 1_094_694 - 896_148_801 / optical - 112.511 * optical
            #expect(abs(Double(c.base.o58) - o58) <= 1, "\(c.capture) session \(c.session)")
            #expect(abs(Double(c.base.o54) - o54) <= 1, "\(c.capture) session \(c.session)")
        }
    }

    /// 6×7, the same centred frame at six resolutions (sessions 2-7): across
    /// the CCD, the frame centre is at the same distance from CCD pixel 3 996
    /// (in inches); along the drum, the frame starts at the same distance
    /// (offset 18 ÷ lines per inch, ratio ÷ 10 000).
    @Test func sixBySevenFramePosition() throws {
        let centred = try cases.filter { $0.capture == "essai-I" && (2...7).contains($0.session) }
        #expect(centred.count == 6)
        let across = centred.map { c in
            (Double(c.image.column) + Double(c.image.pixels) / 2 - 3_996 / Double(c.image.binning)) / Double(c.scan.ppi)
        }
        let along = centred.map { Double($0.image.line) / (Double($0.image.ratio) / 10_000) }
        #expect(across.max()! - across.min()! < 0.003, "\(across)")
        #expect(along.max()! - along.min()! < 0.002, "\(along)")
    }
}
