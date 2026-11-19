// SPDX-License-Identifier: MIT
//
// Scan window calculator: a frame on the film and a resolution give the
// image window and the 400-line window of a scan (docs/protocol.md §9,
// "Window rules"; docs/decisions.md, "Window calculator").
//
// Simulator only. This target has no dependency and is not part of the
// X1Kit product: nothing here can reach the transport, the guards, the scan
// script or the app. Sending a computed window to the real X1 needs a change
// of CLAUDE.md rule 4 first, approved by the user.

/// The constants a calculator needs, all fitted on the FlexColor captures
/// of one calibration of the X1. A new set is added when the X1 is
/// recalibrated and the rules are measured again; sets are never edited.
public struct WindowCalibration: Sendable, Equatable {
    /// Name of the set, e.g. "origine-2026-11-19".
    public let name: String
    /// Holder format the set is for (FlexColor's name). Only "6×7" so far.
    public let holder: String
    /// Holder factor *f* × 10 000 (calibration ratio ÷ resolution).
    public let holderFactor: Int
    /// *M*: binning = min(4, ⌊*M* ÷ resolution⌋).
    public let maximumResolution: Int
    /// The closed menu of resolutions (ppi) a frame may be scanned at: only
    /// resolutions captured with this holder whose windows the calculator
    /// reproduces within the decided criteria (docs/decisions.md, "Window
    /// calculator v1").
    public let resolutions: [Int]
    /// Across the CCD: the frame origin is this many inches from CCD pixel
    /// 3 996 (*x*, protocol.md §9).
    public let acrossOrigin: Double
    /// Along the drum: the frame origin is this many inches from line 0 of
    /// offset 18.
    public let alongOrigin: Double
    /// Offsets 54 / 58 before the 400-line step, as a function of the optical
    /// resolution *O*: 58 = a58 − b58 ÷ *O*, 54 = a54 − b54 ÷ *O* − c54 × *O*.
    public let lens: LensModel
    /// Added to 54 and 58 in the 400-line window.
    public let focusLensOffset: Int
    /// Offset 10 of the 400-line window, whatever the resolution.
    public let focusRatio: Int
    /// Offset 62: line 0 of the drum, and units per inch.
    public let focusLineZero: Int
    public let focusUnitsPerInch: Int

    public struct LensModel: Sendable, Equatable {
        public let a58: Double, b58: Double, a54: Double, b54: Double, c54: Double
    }

    /// The X1's original calibration, measured on the captures of
    /// 2026-11-17 to -19 (scan-windows-2026-11-18.json, -19.json).
    ///
    /// - *f*, the lens model and the 400-line window: protocol.md §9,
    ///   [confirmed] on those captures (the lens model within 1); as rules
    ///   for other frames, [hypothesis]. Offset 62 (option A): within −6 to
    ///   +24 of FlexColor's value on those captures [confirmed]; the formula,
    ///   [hypothesis].
    /// - *M* = 3 200: [hypothesis]; the scans bound it to 3 000-3 999.
    /// - The menu (user's decision, 2026-11-19): 1 000, 1 500, 2 000, 3 000,
    ///   3 200 ppi. 600 ppi is captured but left out: offset 62 predicted
    ///   there is 43 to 53 units above FlexColor's, beyond the 32 decided.
    /// - The origin is the centre of essai-I's "centred" 1.0 × 1.0 cm frame
    ///   (sessions 2-7: 1.6427 to 1.6442 in along the drum, protocol.md §9),
    ///   centred by eye in FlexColor: a convention, not a measured centre of
    ///   the opening.
    public static let origin20261119 = WindowCalibration(
        name: "origine-2026-11-19",
        holder: "6×7",
        holderFactor: 10_000,
        maximumResolution: 3_200,
        resolutions: [1_000, 1_500, 2_000, 3_000, 3_200],
        acrossOrigin: -0.129,
        alongOrigin: 1.644,
        lens: LensModel(a58: 1_136_908, b58: 896_886_417, a54: 1_094_694, b54: 896_148_801, c54: 112.511),
        focusLensOffset: 10_000,
        focusRatio: 21_674_665,
        focusLineZero: 15_500,
        focusUnitsPerInch: 28_800
    )
}

/// A frame on the film, in inches from the calibration's origin: `left`
/// grows with the CCD pixels, `top` with the drum lines.
public struct FilmFrame: Sendable, Equatable {
    public var left: Double
    public var top: Double
    public var width: Double
    public var height: Double

    public init(left: Double, top: Double, width: Double, height: Double) {
        self.left = left
        self.top = top
        self.width = width
        self.height = height
    }
}

/// The fields of a 68-byte SET WINDOW data block (protocol.md §9). Every
/// byte not named here is 0, except the header's byte 7 (0x3C), in the
/// image, base and 400-line windows of the 31 captured scans (the start,
/// reference and calibration windows were not checked).
public struct ScanWindowFields: Sendable, Equatable {
    public var ratio: Int        // offset 10, LE32
    public var column: Int       // offset 14, LE16
    public var line: Int         // offset 18, LE16
    public var pixels: Int       // offset 22, LE16
    public var lines: Int        // offset 26, LE16
    public var byte48: Int       // byte 48
    public var binning: Int      // byte 49
    public var target: Int       // offset 50, LE16
    public var lens54: Int       // offset 54, LE32
    public var lens58: Int       // offset 58, LE32
    public var focusLine: Int    // offset 62, LE32

    public static let byteCount = 68

    public init(ratio: Int, column: Int, line: Int, pixels: Int, lines: Int, byte48: Int, binning: Int,
                target: Int, lens54: Int, lens58: Int, focusLine: Int) {
        self.ratio = ratio
        self.column = column
        self.line = line
        self.pixels = pixels
        self.lines = lines
        self.byte48 = byte48
        self.binning = binning
        self.target = target
        self.lens54 = lens54
        self.lens58 = lens58
        self.focusLine = focusLine
    }

    /// Reads the named fields of a 68-byte block; nil if the length is wrong.
    public init?(bytes: [UInt8]) {
        guard bytes.count == Self.byteCount else { return nil }
        func le(_ offset: Int, _ size: Int) -> Int {
            (0..<size).reduce(0) { $0 | Int(bytes[offset + $1]) << (8 * $1) }
        }
        self.init(ratio: le(10, 4), column: le(14, 2), line: le(18, 2), pixels: le(22, 2), lines: le(26, 2),
                  byte48: Int(bytes[48]), binning: Int(bytes[49]), target: le(50, 2),
                  lens54: le(54, 4), lens58: le(58, 4), focusLine: le(62, 4))
    }

    /// The 68 bytes: header `00 00 00 00 00 00 00 3c`, then the fields.
    public var bytes: [UInt8] {
        var b = [UInt8](repeating: 0, count: Self.byteCount)
        b[7] = 0x3C
        func put(_ value: Int, _ offset: Int, _ size: Int) {
            for i in 0..<size { b[offset + i] = UInt8(truncatingIfNeeded: value >> (8 * i)) }
        }
        put(ratio, 10, 4)
        put(column, 14, 2)
        put(line, 18, 2)
        put(pixels, 22, 2)
        put(lines, 26, 2)
        b[48] = UInt8(truncatingIfNeeded: byte48)
        b[49] = UInt8(truncatingIfNeeded: binning)
        put(target, 50, 2)
        put(lens54, 54, 4)
        put(lens58, 58, 4)
        put(focusLine, 62, 4)
        return b
    }
}

public enum ScanWindowCalculatorError: Error, Equatable, Sendable {
    /// Only the calibration's holder is supported.
    case unsupportedHolder(String)
    /// Not in the calibration's menu of resolutions.
    case resolutionNotInMenu(Int)
    /// Width or height rounds to no pixel or line.
    case emptyFrame
    /// The frame does not fit the CCD (offset 14 + width ≤ 7 992 ÷ binning).
    case outsideCCD
    /// The first line is before line 0, or a field does not fit 16 bits.
    case outsideDrum
    /// A coordinate is not finite, or 100 inches or more from the origin.
    case invalidFrame
    /// The focus line chosen plus the correction is not one of the 400
    /// lines swept (0-399).
    case focusOutsideSweep(Int)
}

/// The image window (before the 400-line step) and the 400-line window.
public struct ScanWindows: Sendable, Equatable {
    /// The image window as sent before the 400-line step. After that step
    /// it is sent again with offsets 54 / 58 at the focus chosen:
    /// `ScanWindowCalculator.imageWindow(_:focus:sharpestLine:correction:)`.
    public let image: ScanWindowFields
    /// The 400-line window. Its offset 50 (the position read on page 0x20
    /// just before it) is left at 0: it is read during the scan, not computed.
    public let focus: ScanWindowFields
}

public enum ScanWindowCalculator {
    /// CCD pixels (full width) and the middle pixel.
    static let ccdPixels = 7_992
    static let ccdMiddle = 3_996

    /// Binning at `resolution` (> 0).
    static func binning(resolution: Int, calibration: WindowCalibration) -> Int {
        min(4, calibration.maximumResolution / resolution)
    }

    /// Lines between the red and blue rows (20, 10, 7, 5 at binning 1-4; §10).
    static func gap(binning: Int) -> Int { (20 + binning / 2) / binning }

    /// Offset 62 of the 400-line window from the image window alone (option A
    /// of docs/decisions.md, "Offset 62"): 15 500 + 28 800 × the middle of
    /// the frame's image lines in inches, rounded to the nearest unit (halves
    /// away from zero). The one place this rounding is made: a future check
    /// of offset 62 must call this function, not compute it again; it would
    /// live in X1Preview (before the transport), the only target allowed to
    /// depend on X1Geometry. Nil for a window it cannot come from: binning
    /// outside 1-4, ratio 0, fewer lines than the priming lines, or a result
    /// outside 32 bits.
    public static func focusLinePosition(imageWindow w: ScanWindowFields, calibration: WindowCalibration) -> Int? {
        guard (1...4).contains(w.binning), w.ratio > 0 else { return nil }
        let g = gap(binning: w.binning)
        guard w.lines > 2 * g + 2 else { return nil }
        let middle = Double(w.line) + Double(w.lines - 2 * g - 2) / 2
        let units = (Double(calibration.focusUnitsPerInch) * middle / (Double(w.ratio) / 10_000)).rounded()
        let value = Double(calibration.focusLineZero) + units
        guard value.isFinite, value >= 0, value <= Double(UInt32.max) else { return nil }
        return Int(value)
    }

    /// Offsets 54 / 58 before the 400-line step, at optical resolution *O*,
    /// rounded to the nearest unit.
    public static func lens(opticalResolution o: Int, calibration c: WindowCalibration) -> (o54: Int, o58: Int) {
        let o = Double(o)
        let o58 = c.lens.a58 - c.lens.b58 / o
        let o54 = c.lens.a54 - c.lens.b54 / o - c.lens.c54 * o
        return (Int(o54.rounded()), Int(o58.rounded()))
    }

    /// Units of offsets 54 / 58 per line of the 400-line step (user's
    /// decision, 2026-11-19, from protocol.md §9 [hypothesis]: the focus is
    /// swept from base + 10 000 down by 50 per line).
    public static let focusUnitsPerLine = 50

    /// The two windows for `frame` at `resolution` ppi (one of the
    /// calibration's menu) with `holder` (FlexColor's format name).
    public static func windows(frame: FilmFrame, resolution: Int, holder: String,
                               calibration c: WindowCalibration = .origin20261119) throws -> ScanWindows {
        guard holder == c.holder else { throw ScanWindowCalculatorError.unsupportedHolder(holder) }
        guard c.resolutions.contains(resolution) else { throw ScanWindowCalculatorError.resolutionNotInMenu(resolution) }
        return try windowsWithoutMenu(frame: frame, resolution: resolution, calibration: c)
    }

    /// The image window as sent after the 400-line step: offsets 54 / 58 of
    /// the 400-line window minus 50 × (*i* + `correction`), *i* being the
    /// line chosen (0-399, `FocusSweep` in X1Image) and `correction` the
    /// user's, in lines (default 0). Refused unless *i* + `correction` is
    /// one of the 400 lines swept: the value sent is always a position the
    /// sweep went through.
    public static func imageWindow(_ image: ScanWindowFields, focus: ScanWindowFields,
                                   sharpestLine: Int, correction: Int = 0) throws -> ScanWindowFields {
        let (line, overflow) = sharpestLine.addingReportingOverflow(correction)
        guard !overflow, (0..<focusSweepLines).contains(line) else {
            throw ScanWindowCalculatorError.focusOutsideSweep(overflow ? Int.max : line)
        }
        var result = image
        result.lens54 = focus.lens54 - focusUnitsPerLine * line
        result.lens58 = focus.lens58 - focusUnitsPerLine * line
        return result
    }

    /// Lines read in the 400-line step.
    public static let focusSweepLines = 400

    /// `windows` without the menu check, for the tests that measure the
    /// resolutions left out of the menu (600 ppi). Not public.
    static func windowsWithoutMenu(frame: FilmFrame, resolution: Int,
                                   calibration c: WindowCalibration) throws -> ScanWindows {
        guard (1...c.maximumResolution).contains(resolution) else {
            throw ScanWindowCalculatorError.resolutionNotInMenu(resolution)
        }
        guard [frame.left, frame.top, frame.width, frame.height].allSatisfy({ $0.isFinite && abs($0) < 100 }) else {
            throw ScanWindowCalculatorError.invalidFrame
        }
        let b = binning(resolution: resolution, calibration: c)
        let g = gap(binning: b)
        let res = Double(resolution)
        let ratio = resolution * c.holderFactor * 5 / 3
        let linesPerInch = Double(ratio) / 10_000

        let column = Int((Double(ccdMiddle / b) + (c.acrossOrigin + frame.left) * res).rounded())
        let pixels = Int((frame.width * res).rounded())
        let line = Int(((c.alongOrigin + frame.top) * linesPerInch).rounded())
        let heightPixels = Int((frame.height * res).rounded())
        guard pixels > 0, heightPixels > 0 else { throw ScanWindowCalculatorError.emptyFrame }
        let lines = heightPixels * 5 / 3 + 2 * g + 2
        guard column >= 0, column + pixels <= ccdPixels / b else { throw ScanWindowCalculatorError.outsideCCD }
        guard line >= 0, line <= 0xFFFF, lines <= 0xFFFF else { throw ScanWindowCalculatorError.outsideDrum }

        let lens = lens(opticalResolution: resolution * b, calibration: c)
        let image = ScanWindowFields(ratio: ratio, column: column, line: line, pixels: pixels, lines: lines,
                                     byte48: 1, binning: b, target: 0,
                                     lens54: lens.o54, lens58: lens.o58, focusLine: c.focusLineZero)
        guard let focusLine = focusLinePosition(imageWindow: image, calibration: c) else {
            throw ScanWindowCalculatorError.outsideDrum
        }
        let focus = ScanWindowFields(ratio: c.focusRatio, column: column, line: 0, pixels: pixels, lines: 401,
                                     byte48: 1, binning: b, target: 0,
                                     lens54: lens.o54 + c.focusLensOffset, lens58: lens.o58 + c.focusLensOffset,
                                     focusLine: focusLine)
        return ScanWindows(image: image, focus: focus)
    }
}
