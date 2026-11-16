// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing
import X1Image
@testable import X1ScanCore

struct ViewportTests {
    private let viewport = Viewport(imageWidth: 2004, imageHeight: 817, pixelAspectRatio: 3)

    @Test func documentIsStretchedByTheAspectRatioOnly() {
        #expect(viewport.documentSize == CGSize(width: 2004, height: 2451))
        #expect(Viewport(imageWidth: 10, imageHeight: 10).pixelAspectRatio == PreviewGeometry.pixelAspectRatio)
    }

    @Test func fitShowsTheWholeImage() {
        let view = CGSize(width: 1000, height: 800)
        let m = viewport.fitMagnification(in: view, margin: 0)
        #expect(abs(m - 800.0 / 2451) < 1e-9)
        #expect(viewport.documentSize.width * m <= 1000 && viewport.documentSize.height * m <= 800 + 1e-9)
    }

    @Test func stepsGoFrom6Point25To1600Percent() {
        let percents = Viewport.steps.map { ($0 * 100 * 100).rounded() / 100 }
        #expect(percents == [6.25, 8.33, 12.5, 16.67, 25, 33.33, 50, 66.67, 100, 200, 300, 400, 800, 1600])
        #expect(Viewport.minimumMagnification == 1.0 / 16 && Viewport.maximumMagnification == 16)
    }

    @Test func zoomInAndOutWalkTheSteps() {
        var v = viewport
        v.actualSize()
        #expect(v.magnification == 1 && v.mode == .fixed && v.currentStep == 1)
        v.zoomIn()
        #expect(v.magnification == 2)
        v.zoomIn(); v.zoomIn(); v.zoomIn()
        #expect(v.magnification == 8)
        v.zoomOut(); v.zoomOut(); v.zoomOut(); v.zoomOut(); v.zoomOut()
        #expect(v.magnification == 2.0 / 3)
    }

    /// After a pinch, ⌘+ and ⌘− go to the step strictly above or below (as Photoshop and Preview).
    @Test func betweenStepsGoesToTheNextStrictStep() {
        var v = viewport
        v.setMagnification(1.4)
        #expect(v.currentStep == nil)
        v.zoomIn()
        #expect(v.magnification == 2)
        v.setMagnification(1.4)
        v.zoomOut()
        #expect(v.magnification == 1)
        v.setMagnification(0.3)  // between 25 % and 33.3 %
        v.zoomIn()
        #expect(v.magnification == 1.0 / 3)
        v.setMagnification(0.3)
        v.zoomOut()
        #expect(v.magnification == 1.0 / 4)
    }

    @Test func magnificationIsClamped() {
        var v = viewport
        v.setMagnification(100)
        #expect(v.magnification == Viewport.maximumMagnification && !v.canZoomIn)
        v.zoomIn()
        #expect(v.magnification == Viewport.maximumMagnification)
        v.setMagnification(0)
        #expect(v.magnification == Viewport.minimumMagnification && !v.canZoomOut)
        v.zoomOut()
        #expect(v.magnification == Viewport.minimumMagnification)
    }

    @Test func fitAndFillFollowTheViewSize() {
        var v = viewport
        v.viewSizeChanged(CGSize(width: 1032, height: 832))
        #expect(v.mode == .fit)
        #expect(abs(v.magnification - 800.0 / 2451) < 1e-9, "16-point margin")
        v.viewSizeChanged(CGSize(width: 1032, height: 1632))  // taller window, or full screen
        #expect(abs(v.magnification - 1000.0 / 2004) < 1e-9)
        v.fill()
        #expect(v.mode == .fill)
        #expect(abs(v.magnification - 1632.0 / 2451) < 1e-9, "fills the height, width overflows")
        v.viewSizeChanged(CGSize(width: 1500, height: 900))  // palettes hidden: wider view
        #expect(abs(v.magnification - max(1500.0 / 2004, 900.0 / 2451)) < 1e-9)
        v.fit()
        #expect(abs(v.magnification - min(1468.0 / 2004, 868.0 / 2451)) < 1e-9)
    }

    @Test func aChosenMagnificationIsKeptWhenTheViewChanges() {
        var v = viewport
        v.viewSizeChanged(CGSize(width: 1000, height: 800))
        v.zoomIn()
        let chosen = v.magnification
        #expect(v.mode == .fixed)
        v.viewSizeChanged(CGSize(width: 400, height: 300))
        #expect(v.magnification == chosen)
        v.setMagnification(1.37)  // pinch
        v.viewSizeChanged(CGSize(width: 2000, height: 1500))
        #expect(v.magnification == 1.37 && v.mode == .fixed)
    }

    @Test func imageSizeChangeKeepsTheMode() {
        var v = Viewport(imageWidth: 0, imageHeight: 0, pixelAspectRatio: 3)
        v.viewSizeChanged(CGSize(width: 1032, height: 832))
        v.setImageSize(width: 2004, height: 817)
        #expect(v.mode == .fit && abs(v.magnification - 800.0 / 2451) < 1e-9)
        var fixed = Viewport(imageWidth: 0, imageHeight: 0, pixelAspectRatio: 3, mode: .fixed)
        fixed.viewSizeChanged(CGSize(width: 1032, height: 832))
        fixed.setImageSize(width: 2004, height: 817)
        #expect(fixed.magnification == 1, "startup zoom 100 %")
    }

    @Test func typedValues() {
        #expect(Viewport.magnification(fromTyped: "150") == 1.5)
        #expect(Viewport.magnification(fromTyped: " 150 % ") == 1.5)
        #expect(Viewport.magnification(fromTyped: "12,5") == 0.125)
        #expect(Viewport.magnification(fromTyped: "12.5%") == 0.125)
        #expect(Viewport.magnification(fromTyped: "5000") == Viewport.maximumMagnification)
        #expect(Viewport.magnification(fromTyped: "1") == Viewport.minimumMagnification)
        for invalid in ["", "%", "abc", "-50", "0", "1,2,3", "inf", "nan"] {
            #expect(Viewport.magnification(fromTyped: invalid) == nil, "\(invalid)")
        }
    }

    @Test func documentPointMapsToTheRightPixel() {
        #expect(viewport.pixel(atDocumentPoint: CGPoint(x: 0, y: 0)) == PixelCoordinate(x: 0, y: 0))
        #expect(viewport.pixel(atDocumentPoint: CGPoint(x: 10.9, y: 5.99)) == PixelCoordinate(x: 10, y: 1))
        #expect(viewport.pixel(atDocumentPoint: CGPoint(x: 2003.5, y: 2450.9)) == PixelCoordinate(x: 2003, y: 816))
        #expect(viewport.pixel(atDocumentPoint: CGPoint(x: 2004, y: 0)) == nil)
        #expect(viewport.pixel(atDocumentPoint: CGPoint(x: -0.1, y: 0)) == nil)
        #expect(viewport.pixel(atDocumentPoint: CGPoint(x: 0, y: 2451)) == nil)
    }

    @Test func cropRectangleIsNormalisedAndClipped() {
        let rect = PixelRect.spanning(PixelCoordinate(x: 50, y: 900), PixelCoordinate(x: -5, y: 10), width: 2004, height: 817)
        #expect(rect == PixelRect(x: 0, y: 10, width: 51, height: 807))
        #expect(viewport.documentRect(forPixelRect: rect) == CGRect(x: 0, y: 30, width: 51, height: 2421))
    }

    @Test func toolsAndSpaceHand() {
        #expect(Tool.forKey("Z") == .zoom && Tool.forKey("h") == .hand && Tool.forKey("c") == .crop)
        #expect(Tool.forKey("x") == nil)
        var state = ToolState()
        state.selected = .crop
        state.spaceHeld = true
        #expect(state.effective == .hand)
        state.spaceHeld = false
        #expect(state.effective == .crop)
    }
}

struct ImageModelTests {
    private func image() -> PreviewImage {
        // 2 × 2 pixels.
        PreviewImage(width: 2,
                     corrected: [0, 255, 256, 65535, 1000, 2000, 300, 400, 500, 600, 700, 800],
                     raw: [10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21])
    }

    @Test func probeGivesCorrectedAndRawValues() throws {
        let reading = try #require(PixelProbe.reading(at: PixelCoordinate(x: 1, y: 0), in: image()))
        #expect(reading.corrected == [65535, 1000, 2000])
        #expect(reading.raw == [13, 14, 15])
        #expect(PixelProbe.reading(at: PixelCoordinate(x: 2, y: 0), in: image()) == nil)
        #expect(PixelProbe.reading(at: PixelCoordinate(x: 0, y: 2), in: image()) == nil)
    }

    @Test func histogramBinsTheTopEightBits() {
        let histogram = Histogram(samples: image().corrected)
        #expect(histogram.pixelCount == 4)
        // Red values 0, 65535, 300, 600 → bins 0, 255, 1, 2.
        #expect(histogram.bins[0][0] == 1 && histogram.bins[0][255] == 1)
        #expect(histogram.bins[0][1] == 1 && histogram.bins[0][2] == 1)
        // Green 255, 1000, 400, 700 → bins 0, 3, 1, 2.
        #expect(histogram.bins[1][0] == 1 && histogram.bins[1][3] == 1)
        #expect(histogram.bins.map { $0.reduce(0, +) } == [4, 4, 4])
        for scale in Histogram.Scale.allCases {
            #expect(histogram.normalized(scale: scale).flatMap { $0 }.max() == 1)
            #expect(Histogram.empty.normalized(scale: scale).flatMap { $0 }.allSatisfy { $0 == 0 })
        }
    }

    @Test func histogramScales() {
        var red = [Int](repeating: 0, count: Histogram.binCount)
        red[0] = 10_000
        red[1] = 100
        let zeros = [Int](repeating: 0, count: Histogram.binCount)
        let histogram = Histogram(bins: [red, zeros, zeros], pixelCount: 10_100)
        #expect(histogram.normalized(scale: .linear)[0][1] == 0.01)
        #expect(histogram.normalized(scale: .squareRoot)[0][1] == 0.1)
        #expect(histogram.normalized().first?[1] == 0.01, "linear by default")
        let log = histogram.normalized(scale: .logarithmic)[0][1]
        #expect(abs(log - log1p(100) / log1p(10_000)) < 1e-12)
    }

    @Test func percentileCapCutsIsolatedPeaks() {
        // 768 non-empty bins of 100, two of them tall peaks.
        var red = [Int](repeating: 100, count: Histogram.binCount)
        red[10] = 1_000_000
        let green = [Int](repeating: 100, count: Histogram.binCount)
        var blue = [Int](repeating: 100, count: Histogram.binCount)
        blue[200] = 2_000_000
        let histogram = Histogram(bins: [red, green, blue], pixelCount: 0)
        // Without a cap the 100s are invisible next to the peaks.
        #expect(histogram.normalized(scale: .linear)[0][0] == 100.0 / 2_000_000)
        // 0.995 of 768 non-empty bins leaves out the tallest 3: the top is 100, the peaks are cut at 1.
        let capped = histogram.normalized(scale: .linear, peakPercentile: 0.995)
        #expect(capped[0][0] == 1 && capped[1][5] == 1)
        #expect(capped[0][10] == 1 && capped[2][200] == 1)
        #expect(histogram.normalized(scale: .linear, peakPercentile: 1) == histogram.normalized(scale: .linear))
        #expect(Histogram.empty.normalized(peakPercentile: 0.995).flatMap { $0 }.allSatisfy { $0 == 0 })
    }

    @Test func fewNonEmptyBinsAreNeverCut() {
        // A small uniform crop: 2 bins per channel, 900 and 100 pixels. The 9:1 ratio must stay.
        var channel = [Int](repeating: 0, count: Histogram.binCount)
        channel[40] = 900
        channel[41] = 100
        let capped = Histogram(bins: [channel, channel, channel], pixelCount: 1_000)
            .normalized(scale: .linear, peakPercentile: 0.995)
        for values in capped {
            #expect(values[40] == 1 && abs(values[41] - 1.0 / 9) < 1e-12)
        }
        // 199 non-empty bins: still under 1 in 200, nothing cut.
        var many = [Int](repeating: 0, count: Histogram.binCount)
        for bin in 0..<198 { many[bin] = 10 }
        many[250] = 1_000
        let few = Histogram(bins: [many, Array(repeating: 0, count: 256), Array(repeating: 0, count: 256)],
                            pixelCount: 0).normalized(scale: .linear, peakPercentile: 0.995)
        #expect(few[0][250] == 1 && few[0][0] == 0.01)
    }

    @Test func histogramOfARegion() {
        // 2 × 2 pixels; the right column only.
        let image = image()
        let right = Histogram(samples: image.corrected, width: 2, region: PixelRect(x: 1, y: 0, width: 1, height: 2))
        #expect(right.pixelCount == 2)
        // Red of (1,0) = 65535 → bin 255; red of (1,1) = 600 → bin 2.
        #expect(right.bins[0][255] == 1 && right.bins[0][2] == 1 && right.bins[0].reduce(0, +) == 2)
        #expect(Histogram(samples: image.corrected, width: 2, region: nil) == Histogram(samples: image.corrected))
        // Clipped to the image and to the rows received.
        let beyond = Histogram(samples: image.corrected, width: 2, region: PixelRect(x: -5, y: 1, width: 100, height: 100))
        #expect(beyond.pixelCount == 2, "row 1 only, both columns")
        #expect(Histogram(samples: image.corrected, width: 2, region: PixelRect(x: 3, y: 3, width: 2, height: 2)).pixelCount == 0)
    }

    @Test func displayImageIsLinear16BitRGB() throws {
        let cgImage = try #require(DisplayImage.make(from: image()))
        #expect(cgImage.width == 2 && cgImage.height == 2)
        #expect(cgImage.bitsPerComponent == 16 && cgImage.bitsPerPixel == 48)
        #expect(cgImage.colorSpace?.name == CGColorSpace.linearSRGB)
        #expect(DisplayImage.make(from: PreviewImage(width: 2, expectedHeight: 5)) == nil)
    }
}

struct ViewportDegenerateSizeTests {
    /// ⌘0 must not fall to 6.25 % because the image area size is not known yet.
    @Test func fitWaitsForARealViewSize() {
        var v = Viewport(imageWidth: 2004, imageHeight: 817, pixelAspectRatio: 3)
        v.actualSize()
        v.fit()
        #expect(v.mode == .fit && v.magnification == 1, "no size yet: kept")
        v.viewSizeChanged(CGSize(width: 1010, height: 0))
        #expect(v.magnification == 1, "degenerate size: kept")
        v.viewSizeChanged(CGSize(width: 1032, height: 832))
        #expect(abs(v.magnification - 800.0 / 2451) < 1e-9, "computed as soon as the size is real")
        v.viewSizeChanged(CGSize(width: 20, height: 20))
        #expect(abs(v.magnification - 800.0 / 2451) < 1e-9)
    }
}
