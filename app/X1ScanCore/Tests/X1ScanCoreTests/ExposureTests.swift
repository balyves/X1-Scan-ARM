// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import X1ScanCore

struct ExposureMeterTests {
    private let thresholds = ExposureThresholds(fullScale: 65_535, clipLevel: 60_000, noiseFloor: 1_000,
                                                tailFraction: 0)

    @Test func countsClippedAndNoisePixels() {
        // 4 pixels: one clipped (any channel), one in the noise (all channels), two in between.
        let raw: [UInt16] = [65_000, 10, 10,   500, 900, 1_000,   2_000, 3_000, 4_000,   30_000, 30_000, 30_000]
        let reading = ExposureMeter.measure(raw: raw, thresholds: thresholds)
        #expect(reading.pixelCount == 4)
        #expect(reading.clippedFraction == 0.25)
        #expect(reading.noiseFraction == 0.25)
    }

    @Test func usedRangeBetweenNoiseFloorAndClipping() {
        // Levels from 1 000 to 30 500: half of the 1 000…60 000 range (59 000), from the floor up.
        let raw: [UInt16] = [1_000, 1_000, 1_000,   30_500, 30_500, 30_500]
        let reading = ExposureMeter.measure(raw: raw, thresholds: thresholds)
        #expect(abs(reading.usedRange - 0.5) < 1e-9)
        #expect(reading.clippedFraction == 0 && reading.noiseFraction == 0.5)
        // Everything clipped or black: the range is clamped to 0...1.
        let full = ExposureMeter.measure(raw: [0, 0, 0, 65_535, 65_535, 65_535], thresholds: thresholds)
        #expect(full.usedRange == 1)
    }

    @Test func tailsAreIgnored() {
        // 1 000 pixels at 20 000, one dust pixel at 65 000: with a 0.1 % tail, the top is 20 000.
        var raw = [UInt16](repeating: 20_000, count: 3_000)
        raw += [65_000, 65_000, 65_000]
        var withTail = thresholds
        withTail.tailFraction = 0.001
        let reading = ExposureMeter.measure(raw: raw, thresholds: withTail)
        #expect(abs(reading.high - 20_000 / 65_535) < 1e-9)
        #expect(reading.clippedFraction > 0, "the clipped pixel still counts as clipped")
    }

    @Test func emptyImage() {
        #expect(ExposureMeter.measure(raw: []) == .empty)
    }

    @Test func maskMarksTheZones() {
        let raw: [UInt16] = [65_000, 10, 10,   500, 900, 1_000,   30_000, 30_000, 30_000]
        let mask = ExposureMeter.zoneMask(raw: raw, thresholds: thresholds)
        #expect(Array(mask[0..<4]) == [255, 0, 0, 255], "clipped: red")
        #expect(Array(mask[4..<8]) == [0, 0, 255, 255], "noise: blue")
        #expect(Array(mask[8..<12]) == [0, 0, 0, 0], "elsewhere: transparent")
    }

    @Test func provisionalValuesAreTheOnlyOnesUsed() {
        // Provisional (docs/decisions.md, "Lot 1: exposure indicator"): change both together.
        #expect(ExposureThresholds.provisional.clipLevel == 64_000)
        #expect(ExposureThresholds.provisional.noiseFloor == 1_024)
    }
}
