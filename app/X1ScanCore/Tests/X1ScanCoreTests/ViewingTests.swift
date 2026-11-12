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

    @Test func zoomStepsAndClamping() {
        var v = viewport
        v.actualSize()
        v.zoomIn()
        #expect(v.magnification == 1.5 && !v.fitsWindow)
        v.zoomOut(); v.zoomOut()
        #expect(v.magnification == 2.0 / 3)
        v.setMagnification(0.3)  // between 1/4 and 1/3
        v.zoomIn()
        #expect(v.magnification == 1.0 / 3)
        v.setMagnification(100)
        #expect(v.magnification == Viewport.maximumMagnification && !v.canZoomIn)
        v.zoomIn()
        #expect(v.magnification == Viewport.maximumMagnification)
        v.setMagnification(0)
        #expect(v.magnification == Viewport.minimumMagnification && !v.canZoomOut)
        v.fit(in: CGSize(width: 500, height: 500))
        #expect(v.fitsWindow)
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
        let normalized = histogram.normalized()
        #expect(normalized.flatMap { $0 }.max() == 1)
        #expect(Histogram.empty.normalized().flatMap { $0 }.allSatisfy { $0 == 0 })
    }

    @Test func displayImageIsLinear16BitRGB() throws {
        let cgImage = try #require(DisplayImage.make(from: image()))
        #expect(cgImage.width == 2 && cgImage.height == 2)
        #expect(cgImage.bitsPerComponent == 16 && cgImage.bitsPerPixel == 48)
        #expect(cgImage.colorSpace?.name == CGColorSpace.linearSRGB)
        #expect(DisplayImage.make(from: PreviewImage(width: 2, expectedHeight: 5)) == nil)
    }
}
