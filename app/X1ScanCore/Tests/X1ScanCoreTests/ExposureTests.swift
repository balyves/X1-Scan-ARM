// SPDX-License-Identifier: MIT
import Foundation
import Testing
import X1Transport
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
        #expect(Array(mask[4..<8]) == [150, 40, 220, 255], "noise: violet")
        #expect(Array(mask[8..<12]) == [0, 0, 0, 0], "elsewhere: transparent")
    }

    @Test func provisionalValuesAreTheOnlyOnesUsed() {
        // Provisional (docs/decisions.md, "Lot 1: exposure indicator"): change both together.
        #expect(ExposureThresholds.provisional.clipLevel == 64_000)
        #expect(ExposureThresholds.provisional.noiseFloor == 1_024)
    }
}

/// The virtual X1's film has a clipped and a dense patch (user's tests of
/// lot 1, 2026-11-20), so that the overlay can be tried. Apart from the
/// dense patch, the only pixels near the noise floor are the first columns
/// of the preview, where the calibration's white reference is at the dark
/// level: that is the thin violet line at the left edge of the image.
@MainActor
struct VirtualExposurePatchTests {
    @Test func previewShowsBothZones() async throws {
        let suite = "X1ScanCoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let inspector = ScannerInspector { FakeConnection(responses: [:], openError: TransportError.deviceBusy) }
        let model = AppModel(virtualScanner: { try TestFixtures.scanner() }, inspector: inspector, defaults: defaults)
        model.startPreview()
        await model.session.waitUntilIdle()
        model.viewSizeChanged(CGSize(width: 800, height: 600))
        model.refreshImage()
        await model.waitForRendering()
        let image = try #require(model.session.image)
        let reading = try #require(model.exposure)
        #expect(reading.clippedFraction > 0.005 && reading.noiseFraction > 0.005)

        let thresholds = ExposureThresholds.provisional
        let patches = SyntheticFilm.patchColumns(width: image.width)
        var clippedColumns = Set<Int>(), noiseColumns = Set<Int>(), noiseRows = Set<Int>()
        for row in 0..<image.height {
            for column in 0..<image.width {
                let i = (row * image.width + column) * 3
                let high = max(image.raw[i], image.raw[i + 1], image.raw[i + 2])
                if high >= thresholds.clipLevel { clippedColumns.insert(column) }
                if high <= thresholds.noiseFloor {
                    noiseColumns.insert(column)
                    if column >= 5 { noiseRows.insert(row) }
                }
            }
        }
        // Clipped: the bright patch only.
        #expect(clippedColumns == Set(patches.clipped))
        // Near the noise floor: the dense patch, and the first five columns (the left edge).
        #expect(noiseColumns == Set(0..<5).union(patches.dense))
        // The dense patch is a band of rows (100 film rows, give or take the R/B line gap).
        let first = try #require(noiseRows.min()), last = try #require(noiseRows.max())
        let rows = first...last
        #expect(rows.count >= 98 && rows.count <= 102 && noiseRows.count == rows.count)
    }
}
