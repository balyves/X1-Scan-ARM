// SPDX-License-Identifier: MIT
import Testing
import X1Geometry
import X1TestSupport

/// The window calculator against the 31 scans FlexColor made with the
/// original calibration (scan-windows-2026-11-18.json, -19.json; docs/
/// decisions.md, "Window calculator"). Simulator only: nothing is sent.
///
/// The captures do not hold FlexColor's frame (only a description such as
/// "1.0 × 1.0 cm, centre"), so:
/// - family 1 takes each scan's frame from its own image window and TIFF
///   size: a consistency and non-regression test (a round trip), not a
///   validation; offsets 14, 18, 22, 26 are equal by construction;
/// - family 2 takes the frame of one scan and predicts the other scans of
///   the same untouched frame at other resolutions: the real prediction.
/// Every field is compared on its own; offset 62 of the 400-line window
/// must be within 32 units (option A), every other field equal. The fields
/// that differ are listed below as they are, not fitted away.
struct ScanWindowCalculatorTests {
    private static let calibration = WindowCalibration.origin20261119
    private static let loaded = Result { try ScanWindowFixtures.load() }
    private var cases: [ScanWindowFixtures.ScanCase] { get throws { try Self.loaded.get() } }

    private static func fields(_ bytes: [UInt8]) -> ScanWindowFields { ScanWindowFields(bytes: bytes)! }

    /// The frame of a captured scan, from its image window and TIFF height.
    private static func frame(of c: ScanWindowFixtures.ScanCase) -> FilmFrame {
        let w = fields(c.image)
        let res = Double(c.scan.ppi)
        let linesPerInch = Double(w.ratio) / 10_000
        return FilmFrame(left: (Double(w.column) - Double(3_996 / w.binning)) / res - calibration.acrossOrigin,
                         top: Double(w.line) / linesPerInch - calibration.alongOrigin,
                         width: Double(w.pixels) / res,
                         height: Double(c.scan.tiff_height) / res)
    }

    /// "label window.field computed−captured" for every field that differs.
    private static func differences(_ label: String, computed: ScanWindows,
                                    image: ScanWindowFields, base: ScanWindowFields,
                                    focus: ScanWindowFields, only: Set<String>? = nil) -> [String] {
        var result: [String] = []
        func check(_ name: String, _ a: Int, _ b: Int, tolerance: Int = 0) {
            if let only, !only.contains(name) { return }
            if abs(a - b) > tolerance { result.append("\(label) \(name) \(a - b)") }
        }
        let i = computed.image, f = computed.focus
        check("image.10", i.ratio, image.ratio)
        check("image.14", i.column, image.column)
        check("image.18", i.line, image.line)
        check("image.22", i.pixels, image.pixels)
        check("image.26", i.lines, image.lines)
        check("image.48", i.byte48, image.byte48)
        check("image.49", i.binning, image.binning)
        check("image.50", i.target, image.target)
        // 54 / 58 before FlexColor's focus correction: the window before the 400-line one.
        check("image.54", i.lens54, base.lens54)
        check("image.58", i.lens58, base.lens58)
        check("image.62", i.focusLine, image.focusLine)
        check("focus.10", f.ratio, focus.ratio)
        check("focus.14", f.column, focus.column)
        check("focus.18", f.line, focus.line)
        check("focus.22", f.pixels, focus.pixels)
        check("focus.26", f.lines, focus.lines)
        check("focus.48", f.byte48, focus.byte48)
        check("focus.49", f.binning, focus.binning)
        // focus.50 is the position read during the scan: not computed.
        check("focus.54", f.lens54, focus.lens54)
        check("focus.58", f.lens58, focus.lens58)
        check("focus.62", f.focusLine, focus.focusLine, tolerance: 32)
        return result
    }

    private var sixBySeven: [ScanWindowFixtures.ScanCase] {
        get throws { try cases.filter { ScanWindowFixtures.holders[$0.capture] == "6×7" } }
    }

    @Test func scans() throws {
        #expect(try cases.count == 31)
        #expect(try sixBySeven.count == 28)
    }

    /// The fields this test does not read by name are 0 (and byte 7 is
    /// 0x3C) in every captured window: the named fields are the whole window.
    @Test func namedFieldsAreTheWholeWindow() throws {
        for c in try cases {
            for window in [c.image, c.focus, c.base] {
                #expect(Self.fields(window).bytes == window, "\(c.label)")
            }
        }
    }

    /// The other holders are refused.
    @Test func otherHoldersRefused() throws {
        let others = try cases.filter { ScanWindowFixtures.holders[$0.capture] != "6×7" }
        #expect(others.map(\.capture) == ["essai-J3", "essai-J4", "essai-J3-2"])
        for c in others {
            let holder = ScanWindowFixtures.holders[c.capture]!
            #expect(throws: ScanWindowCalculatorError.unsupportedHolder(holder)) {
                try ScanWindowCalculator.windows(frame: Self.frame(of: c), resolution: c.scan.ppi, holder: holder)
            }
        }
    }

    @Test func limits() throws {
        let frame = FilmFrame(left: -0.1, top: -0.1, width: 0.2, height: 0.2)
        for resolution in [300, 599, 3_201] {
            #expect(throws: ScanWindowCalculatorError.resolutionOutOfRange(resolution)) {
                try ScanWindowCalculator.windows(frame: frame, resolution: resolution, holder: "6×7")
            }
        }
        #expect(throws: ScanWindowCalculatorError.emptyFrame) {
            try ScanWindowCalculator.windows(frame: FilmFrame(left: 0, top: 0, width: 0, height: 0.2),
                                             resolution: 2_000, holder: "6×7")
        }
        #expect(throws: ScanWindowCalculatorError.outsideCCD) {
            try ScanWindowCalculator.windows(frame: FilmFrame(left: 2, top: 0, width: 0.2, height: 0.2),
                                             resolution: 2_000, holder: "6×7")
        }
        #expect(throws: ScanWindowCalculatorError.outsideDrum) {
            try ScanWindowCalculator.windows(frame: FilmFrame(left: 0, top: -2, width: 0.2, height: 0.2),
                                             resolution: 2_000, holder: "6×7")
        }
        #expect(throws: ScanWindowCalculatorError.emptyFrame) {
            try ScanWindowCalculator.windows(frame: FilmFrame(left: 0, top: 0, width: 0.2, height: 0.0001),
                                             resolution: 2_000, holder: "6×7")
        }
        #expect(throws: ScanWindowCalculatorError.outsideCCD) {
            try ScanWindowCalculator.windows(frame: FilmFrame(left: -2, top: 0, width: 0.2, height: 0.2),
                                             resolution: 2_000, holder: "6×7")
        }
        #expect(throws: ScanWindowCalculatorError.outsideDrum) {  // first line beyond 16 bits
            try ScanWindowCalculator.windows(frame: FilmFrame(left: 0, top: 30, width: 0.2, height: 0.2),
                                             resolution: 3_200, holder: "6×7")
        }
        for bad in [Double.nan, .infinity, 1e16] {
            #expect(throws: ScanWindowCalculatorError.invalidFrame) {
                try ScanWindowCalculator.windows(frame: FilmFrame(left: 0, top: 0, width: 0.2, height: bad),
                                                 resolution: 2_000, holder: "6×7")
            }
        }
    }

    /// Offset 62 is not computed from a window it cannot come from.
    @Test func focusLineRefusesMalformedWindows() {
        let c = Self.calibration
        let good = ScanWindowFields(ratio: 33_333_333, column: 100, line: 4_800, pixels: 394, lines: 698,
                                    byte48: 1, binning: 1, target: 0, lens54: 0, lens58: 0, focusLine: 15_500)
        #expect(ScanWindowCalculator.focusLinePosition(imageWindow: good, calibration: c) != nil)
        var w = good; w.binning = 0
        #expect(ScanWindowCalculator.focusLinePosition(imageWindow: w, calibration: c) == nil)
        w = good; w.binning = 5
        #expect(ScanWindowCalculator.focusLinePosition(imageWindow: w, calibration: c) == nil)
        w = good; w.ratio = 0
        #expect(ScanWindowCalculator.focusLinePosition(imageWindow: w, calibration: c) == nil)
        w = good; w.lines = 42
        #expect(ScanWindowCalculator.focusLinePosition(imageWindow: w, calibration: c) == nil)
        w = good; w.line = 65_535; w.ratio = 1  // beyond 32 bits
        #expect(ScanWindowCalculator.focusLinePosition(imageWindow: w, calibration: c) == nil)
    }

    /// The 400-line window's constants are the same in all 31 captured scans.
    @Test func focusWindowConstants() throws {
        for c in try cases {
            let f = Self.fields(c.focus), b = Self.fields(c.base)
            #expect(f.ratio == Self.calibration.focusRatio && f.line == 0 && f.lines == 401 && f.byte48 == 1,
                    "\(c.label)")
            #expect(f.lens54 - b.lens54 == Self.calibration.focusLensOffset
                    && f.lens58 - b.lens58 == Self.calibration.focusLensOffset, "\(c.label)")
        }
    }

    /// Family 1, consistency / non-regression (round trip): each scan's frame
    /// from its own window, every field compared. Known differences: offset
    /// 54 of the lens model, rounded, is 1 too high at O = 2 000, 2 880 and
    /// 3 000 (the model is within 1, protocol.md §9).
    @Test func familyOneRoundTrip() throws {
        var found: [String] = []
        for c in try sixBySeven {
            let computed = try ScanWindowCalculator.windows(frame: Self.frame(of: c), resolution: c.scan.ppi,
                                                            holder: "6×7")
            found += Self.differences("\(c.capture) \(c.session)", computed: computed,
                                      image: Self.fields(c.image), base: Self.fields(c.base),
                                      focus: Self.fields(c.focus))
        }
        #expect(found == Self.familyOneDifferences, "\(found)")
    }

    /// 14 scans: O = 3 000 (essai-I 3, 4, 6; essai-N 5), 2 000 (essai-I 5,
    /// 8-13; essai-N 3, 4) and 2 880 (essai-L 3).
    static let familyOneDifferences: [String] = [
        "essai-I 3 image.54 1", "essai-I 3 focus.54 1",
        "essai-I 4 image.54 1", "essai-I 4 focus.54 1",
        "essai-I 5 image.54 1", "essai-I 5 focus.54 1",
        "essai-I 6 image.54 1", "essai-I 6 focus.54 1",
        "essai-I 8 image.54 1", "essai-I 8 focus.54 1",
        "essai-I 9 image.54 1", "essai-I 9 focus.54 1",
        "essai-I 10 image.54 1", "essai-I 10 focus.54 1",
        "essai-I 11 image.54 1", "essai-I 11 focus.54 1",
        "essai-I 12 image.54 1", "essai-I 12 focus.54 1",
        "essai-I 13 image.54 1", "essai-I 13 focus.54 1",
        "essai-L 3 image.54 1", "essai-L 3 focus.54 1",
        "essai-N 3 image.54 1", "essai-N 3 focus.54 1",
        "essai-N 4 image.54 1", "essai-N 4 focus.54 1",
        "essai-N 5 image.54 1", "essai-N 5 focus.54 1",
    ]

    /// Offset 62 by option A, against FlexColor's value, on the 28 scans
    /// (family 1): within −6 to +24 (protocol.md §9).
    @Test func focusLineAgainstFlexColor() throws {
        var spread: [Int] = []
        for c in try sixBySeven {
            let computed = try ScanWindowCalculator.windows(frame: Self.frame(of: c), resolution: c.scan.ppi,
                                                            holder: "6×7")
            spread.append(computed.focus.focusLine - Self.fields(c.focus).focusLine)
        }
        #expect(spread.min() == -6 && spread.max() == 24, "\(spread.sorted())")
    }

    /// Family 2, prediction: the frame of the first scan of each group,
    /// untouched in FlexColor, gives the windows of the other scans of the
    /// group at other resolutions. Offsets 14, 18, 22, 26 and 62 (the others
    /// do not depend on the frame: family 1).
    @Test func familyTwoPrediction() throws {
        let groups: [(String, [Int])] = [
            ("essai-I", [7, 2, 3, 4, 5, 6]),  // 1.0 × 1.0 cm, centred: 3 200 → 600-3 000 ppi
            ("essai-L", [2, 3, 4]),           // part H, zoom 160 %: 3 200 → 960, 3 200 ppi
            ("essai-N", [2, 3, 4, 5, 6]),     // part K, P0: 3 200 → 2 000, 2 000, 1 000, 600 ppi
            ("essai-N", [8, 9]),              // part K, moved frame: 3 200 → 600 ppi
        ]
        let fields: Set = ["image.14", "image.18", "image.22", "image.26", "focus.14", "focus.22", "focus.62"]
        let all = try sixBySeven
        var found: [String] = []
        for (capture, sessions) in groups {
            let scans = try sessions.map { s in try #require(all.first { $0.capture == capture && $0.session == s }) }
            let frame = Self.frame(of: scans[0])
            for c in scans.dropFirst() {
                let computed = try ScanWindowCalculator.windows(frame: frame, resolution: c.scan.ppi, holder: "6×7")
                found += Self.differences("\(capture) \(scans[0].session)→\(c.session)", computed: computed,
                                          image: Self.fields(c.image), base: Self.fields(c.base),
                                          focus: Self.fields(c.focus), only: fields)
            }
        }
        #expect(found == Self.familyTwoDifferences, "\(found)")
    }

    /// Offset 14 up to 5 pixels (binning 1, 3 200 → 2 000 ppi), 18 and 22
    /// by 1; offset 62 beyond 32 units at 600 ppi (43 to 53: FlexColor's
    /// value there is about one 600 ppi output pixel, 48 units, lower;
    /// protocol.md §9, part K).
    static let familyTwoDifferences: [String] = [
        "essai-I 7→2 image.14 1",
        "essai-I 7→2 image.18 1",
        "essai-I 7→2 image.22 -1",
        "essai-I 7→2 focus.14 1",
        "essai-I 7→2 focus.22 -1",
        "essai-I 7→2 focus.62 48",
        "essai-I 7→3 image.14 1",
        "essai-I 7→3 image.18 1",
        "essai-I 7→3 focus.14 1",
        "essai-I 7→4 image.14 1",
        "essai-I 7→4 focus.14 1",
        "essai-I 7→5 image.14 5",
        "essai-I 7→5 image.18 1",
        "essai-I 7→5 focus.14 5",
        "essai-I 7→6 image.14 2",
        "essai-I 7→6 image.18 1",
        "essai-I 7→6 image.22 -1",
        "essai-I 7→6 focus.14 2",
        "essai-I 7→6 focus.22 -1",
        "essai-L 2→3 image.14 1",
        "essai-L 2→3 focus.14 1",
        "essai-N 2→3 image.14 4",
        "essai-N 2→3 image.18 -1",
        "essai-N 2→3 focus.14 4",
        "essai-N 2→4 image.14 4",
        "essai-N 2→4 image.18 -1",
        "essai-N 2→4 focus.14 4",
        "essai-N 2→5 image.14 2",
        "essai-N 2→5 focus.14 2",
        "essai-N 2→6 image.14 1",
        "essai-N 2→6 image.18 1",
        "essai-N 2→6 focus.14 1",
        "essai-N 2→6 focus.62 43",
        "essai-N 8→9 image.14 1",
        "essai-N 8→9 image.18 1",
        "essai-N 8→9 focus.14 1",
        "essai-N 8→9 focus.62 53",
    ]
}
