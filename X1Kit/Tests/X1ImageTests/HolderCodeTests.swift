// SPDX-License-Identifier: MIT
import Foundation
import Testing
import X1Image
import X1TestSupport

/// The holder code lines of 2026-11-18 (tests/fixtures/holders/holder-code-lines.json).
struct HolderCodeTests {
    struct Line: Decodable {
        let capture: String
        let session: Int
        let format_shown: String
        let pixels: Int
        let samples: String

        var rgb: [UInt16] {
            let data = Data(base64Encoded: samples) ?? Data()
            return stride(from: 0, to: data.count - 1, by: 2).map { UInt16(data[$0]) | UInt16(data[$0 + 1]) << 8 }
        }
    }
    struct File: Decodable { let lines: [Line] }

    static func lines() throws -> [Line] {
        let url = Fixtures.directory.appending(path: "holders/holder-code-lines.json")
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).lines
    }

    /// The codes read from the raw data (docs/protocol.md §13), by capture
    /// and session.
    static let expected: [String: Set<Int>] = [
        "essai-H 2": [13], "essai-H 3": [15], "essai-H 4": [14], "essai-H 5": [7, 12, 13], "essai-H 6": [7, 15],
        "essai-H 7": [7, 13, 14, 15], "essai-H 8": [12, 14],
        "essai-K 1": [14, 15], // 6×7, full CCD width (8 016 pixels, binning 1)
    ]

    @Test func everyCodeLineDecodes() throws {
        let lines = try Self.lines()
        #expect(lines.count == 8)
        for line in lines {
            let key = "\(line.capture) \(line.session)"
            let code = try #require(HolderCode.decode(rgb: line.rgb, pixels: line.pixels), "\(key)")
            #expect(code.slots == Self.expected[key], "\(key), \(line.format_shown)")
        }
        #expect(Set(lines.compactMap { HolderCode.decode(rgb: $0.rgb, pixels: $0.pixels) }).count == 8,
                "eight holders, eight codes")
    }

    // MARK: Changes to a real line (session 5: the smallest pitch, about 32 pixels)

    private static func line(_ session: Int) throws -> Line {
        try #require(try lines().first { $0.capture == "essai-H" && $0.session == session })
    }

    /// Bright runs of the green channel (start, length), as the decoder sees them.
    private static func runs(_ rgb: [UInt16], pixels: Int) -> [(start: Int, length: Int)] {
        let green = (0..<pixels).map { Int(rgb[$0 * 3 + 1]) }
        let threshold = ((green.min() ?? 0) + (green.max() ?? 0)) / 2
        var runs: [(Int, Int)] = [], start: Int?
        for (i, v) in green.enumerated() {
            if v > threshold { if start == nil { start = i } } else if let s = start { runs.append((s, i - s)); start = nil }
        }
        return runs
    }

    private static func set(_ rgb: inout [UInt16], _ range: Range<Int>, to value: UInt16) {
        for pixel in range { rgb[pixel * 3] = value; rgb[pixel * 3 + 1] = value; rgb[pixel * 3 + 2] = value }
    }

    /// One pixel more or less at the edge of any bar still decodes the same.
    @Test func oneEdgePixelDoesNotMatter() throws {
        let line = try Self.line(5)
        let bars = Self.runs(line.rgb, pixels: line.pixels)
        for bar in bars {
            for shift in [-1, 1] {
                var rgb = line.rgb
                let edge = shift < 0 ? bar.start - 1 : bar.start
                let bright = rgb[(bar.start + 1) * 3 + 1]
                Self.set(&rgb, edge..<(edge + 1), to: shift < 0 ? bright : 0)
                #expect(HolderCode.decode(rgb: rgb, pixels: line.pixels)?.slots == Self.expected["essai-H 5"],
                        "bar at \(bar.start), shift \(shift)")
            }
        }
    }

    /// A hot pixel does not move the threshold.
    @Test func aHotPixelDoesNotMatter() throws {
        let line = try Self.line(8)
        var rgb = line.rgb
        Self.set(&rgb, 1000..<1001, to: 65535)
        #expect(HolderCode.decode(rgb: rgb, pixels: line.pixels)?.slots == Self.expected["essai-H 8"])
    }

    /// The patterns that are not a holder code give nil.
    @Test func otherPatternsGiveNothing() throws {
        let line = try Self.line(2)
        let bars = Self.runs(line.rgb, pixels: line.pixels)
        let pitch = (bars[3].start - bars[0].start) / 3
        let bright = line.rgb[(bars[0].start + 1) * 3 + 1]
        func decode(_ change: (inout [UInt16]) -> Void) -> HolderCode? {
            var rgb = line.rgb
            change(&rgb)
            return HolderCode.decode(rgb: rgb, pixels: line.pixels)
        }
        // Slot 4 bright.
        #expect(decode { Self.set(&$0, (bars[0].start + 4 * pitch)..<(bars[0].start + 4 * pitch + bars[0].length), to: bright) } == nil)
        // Slot 5 dark (a frame slot).
        #expect(decode { Self.set(&$0, bars[4].start..<(bars[4].start + bars[4].length), to: 0) } == nil)
        // A wider bar.
        #expect(decode { Self.set(&$0, bars[6].start..<(bars[6].start + bars[6].length * 2), to: bright) } == nil)
        // A bar half a pitch off the grid.
        #expect(decode {
            let bar = bars[6]
            Self.set(&$0, bar.start..<(bar.start + bar.length), to: 0)
            Self.set(&$0, (bar.start + pitch / 2)..<(bar.start + pitch / 2 + bar.length), to: bright)
        } == nil)
        // No code on the line: all bright, all dark, a single step.
        let pixels = line.pixels
        #expect(HolderCode.decode(rgb: Array(repeating: 30000, count: pixels * 3), pixels: pixels) == nil)
        #expect(HolderCode.decode(rgb: Array(repeating: 0, count: pixels * 3), pixels: pixels) == nil)
        var step = Array(repeating: UInt16(0), count: pixels * 3)
        Self.set(&step, (pixels / 2)..<pixels, to: 30000)
        #expect(HolderCode.decode(rgb: step, pixels: pixels) == nil)
        // A buffer of the wrong size.
        #expect(HolderCode.decode(rgb: line.rgb, pixels: pixels - 1) == nil)
        #expect(HolderCode.decode(rgb: [], pixels: 0) == nil)
    }
}
