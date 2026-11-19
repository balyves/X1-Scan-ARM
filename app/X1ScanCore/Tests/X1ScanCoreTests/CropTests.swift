// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import Testing
import X1Image
import X1Transport
@testable import X1ScanCore

struct CropGeometryTests {
    private let image = CGSize(width: 600, height: 400)

    @Test func anglesAreClampedAndStepped() {
        var crop = CropSettings()
        crop.angle = 1.234
        #expect(abs(crop.angle - 1.2) < 1e-9)
        crop.angle = -80
        #expect(crop.angle == -45)
        crop.angle = .nan
        #expect(crop.angle == 0)
    }

    @Test func largestFrameHasNoEmptyCorners() {
        for angle in [0.0, 0.3, -1.3, 5, -12.5, 30, 45] {
            for ratio in [nil, 1.0, 4.0 / 3, 6.0 / 7, 1.5] as [Double?] {
                let frame = CropGeometry.largestFrame(ratio: ratio, imageSize: image, angle: angle)
                #expect(CropGeometry.fits(frame, imageSize: image, angle: angle), "\(angle)° \(String(describing: ratio))")
                // Largest: 1 % bigger no longer fits (except at 0°, where it fills the image).
                let bigger = frame.insetBy(dx: -frame.width * 0.005, dy: -frame.height * 0.005)
                #expect(!CropGeometry.fits(bigger, imageSize: image, angle: angle))
                if let ratio { #expect(abs(frame.width / frame.height - ratio) < 1e-9) }
            }
        }
        #expect(CropGeometry.largestFrame(ratio: nil, imageSize: image, angle: 0) == CGRect(origin: .zero, size: image))
    }

    @Test func constrainedMovesThenShrinks() {
        // A small frame past the right edge: moved back inside, same size.
        let small = CGRect(x: 580, y: 100, width: 100, height: 100)
        let moved = CropGeometry.constrained(small, imageSize: image, angle: 0)
        #expect(abs(moved.width - 100) < 1e-6 && abs(moved.maxX - 600) < 1e-6)
        #expect(abs(moved.minY - 100) < 1e-6, "moved across the edge only, no drift along it")
        // Turned 2°: still the smallest move, and inside.
        let turned = CropGeometry.constrained(small, imageSize: image, angle: 2)
        #expect(CropGeometry.fits(turned, imageSize: image, angle: 2) && abs(turned.width - 100) < 1e-6)
        #expect(abs(turned.minY - 100) < 1e-6, "pushed against the right edge: moved across it")
        // The whole image turned 3°: shrunk about the centre, proportions kept.
        let whole = CGRect(origin: .zero, size: image)
        let shrunk = CropGeometry.constrained(whole, imageSize: image, angle: 3)
        #expect(CropGeometry.fits(shrunk, imageSize: image, angle: 3))
        #expect(abs(shrunk.width / shrunk.height - 1.5) < 1e-6 && abs(shrunk.midX - 300) < 1e-6)
        #expect(shrunk.width > 550, "only what the angle needs")
    }

    @Test func aspects() {
        #expect(CropAspect.free.namedRatio(imageRatio: 2) == nil)
        #expect(CropAspect.original.namedRatio(imageRatio: 0.5) == 0.5)
        #expect(CropAspect.ratio(width: 6, height: 7).namedRatio(imageRatio: 1) == 6.0 / 7, "as named: 6 wide, 7 high")
        #expect(CropAspect.ratio(width: 24, height: 36).namedRatio(imageRatio: 1) == 24.0 / 36)
        var crop = CropSettings()
        crop.aspect = .ratio(width: 6, height: 7)
        crop.portrait = true
        #expect(crop.ratio(imageSize: CGSize(width: 10, height: 10)) == 7.0 / 6, "X exchanges width and height")
        #expect(CropAspect.custom(13, 18) == .ratio(width: 13, height: 18))
        #expect(CropAspect.custom(0, 18) == nil && CropAspect.custom(1, 100) == nil)
        let reshaped = CropGeometry.reshaped(CGRect(x: 0, y: 0, width: 200, height: 200), ratio: 4)
        #expect(abs(reshaped.width * reshaped.height - 40_000) < 1e-6 && abs(reshaped.midX - 100) < 1e-9)
    }
}

struct StraightenTests {
    @Test func horizontalLines() throws {
        // A line leaning down to the right by 2°: turn the image 2° counterclockwise (−2).
        let lean = 2 * Double.pi / 180
        let a = CGPoint(x: 0, y: 0), b = CGPoint(x: 100 * cos(lean), y: 100 * sin(lean))
        let result = try #require(Straighten.correction(from: a, to: b))
        #expect(result.axis == .horizontal && abs(result.angle + 2) < 1e-9)
        // Drawn the other way: same line, same correction.
        let reverse = try #require(Straighten.correction(from: b, to: a))
        #expect(abs(reverse.angle + 2) < 1e-9)
    }

    @Test func verticalLines() throws {
        // Bottom end 1.3° to the right of the top end: the line leans counterclockwise, turn +1.3.
        let lean = 1.3 * Double.pi / 180
        let top = CGPoint(x: 0, y: 0), bottom = CGPoint(x: 100 * sin(lean), y: 100 * cos(lean))
        let result = try #require(Straighten.correction(from: top, to: bottom))
        #expect(result.axis == .vertical && abs(result.angle - 1.3) < 1e-9)
    }

    @Test func tooShort() {
        #expect(Straighten.correction(from: .zero, to: CGPoint(x: 1, y: 1)) == nil)
    }
}

struct ResampleTests {
    private func gradient(width: Int, height: Int) -> RGB16Image {
        RGB16Image(width: width, height: height, samples: (0..<width * height).flatMap { index -> [UInt16] in
            let x = index % width, y = index / width
            return [UInt16(x * 1_000), UInt16(y * 1_000), 30_000]
        })
    }

    @Test func noAngleCropsWholePixels() {
        var crop = CropSettings()
        crop.frame = CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.5)
        let out = Resample.apply(crop, to: gradient(width: 8, height: 4), pixelSize: CGSize(width: 1, height: 3))
        #expect(out.width == 4 && out.height == 2, "no resampling: the pixels keep their shape")
        #expect(Array(out.samples[0..<3]) == [2_000, 2_000, 30_000])
    }

    @Test func tinyAngleStaysCloseToTheSource() {
        // A tiny angle: the result stays very close to the source (Lanczos interpolates).
        var crop = CropSettings()
        crop.angle = 0.1
        let source = gradient(width: 40, height: 40)
        crop.frame = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let out = Resample.apply(crop, to: source, pixelSize: CGSize(width: 1, height: 1))
        #expect(out.width == 20 && out.height == 20)
        // Centre pixel of the output ≈ centre of the source (x = y = 19.5…20 → about 20 000).
        let centre = (10 * 20 + 10) * 3
        #expect(abs(Int(out.samples[centre]) - 20_000) < 600)
        #expect(out.samples[centre + 2] == 30_000, "a flat channel stays flat")
    }

    @Test func previewPixelsBecomeSquare() {
        var crop = CropSettings()
        crop.angle = 1
        let out = Resample.apply(crop, to: gradient(width: 30, height: 10), pixelSize: CGSize(width: 1, height: 3))
        #expect(out.width == 30 && out.height == 30)
    }

    @Test func lanczosKernel() {
        #expect(Resample.lanczos(0) == 1)
        #expect(abs(Resample.lanczos(1)) < 1e-12 && abs(Resample.lanczos(2)) < 1e-12)
        #expect(Resample.lanczos(3) == 0 && Resample.lanczos(-3.5) == 0)
    }

    @Test func quarterTurnOfAFeatureMatchesTheExactPermutation() {
        // A 90° fine angle is not allowed (±45°), so compare a 0.0 resample of a turned
        // image with the exact permutation: the recipe renderer must not resample turns.
        let image = gradient(width: 6, height: 4)
        let recipe = Recipe(orientation: Orientation(quarterTurns: 1))
        let out = RecipeRenderer.render(image, pixelAspectRatio: 1, recipe: recipe)
        #expect(out == Orientation(quarterTurns: 1).apply(to: image))
    }
}

struct RecipeCropTests {
    @Test func jsonRoundTripWithCrop() throws {
        var crop = CropSettings()
        crop.angle = -1.3
        crop.frame = CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.6)
        crop.aspect = .ratio(width: 6, height: 7)
        crop.portrait = true
        crop.locked = true
        crop.constrained = false
        let recipe = Recipe(orientation: Orientation(quarterTurns: 1), crop: crop)
        let data = try recipe.jsonData()
        #expect(try Recipe.decode(from: data) == recipe)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""frame" : {"#) && text.contains(#""angle" : -1.3"#))
        // A version 1 file written before the crop (step B) still reads.
        let old = #"{"version":1,"orientation":{"quarterTurns":2,"mirrored":false}}"#
        #expect(try Recipe.decode(from: Data(old.utf8)).crop == CropSettings())
    }

    @Test func effectiveFrameWithAnAngle() throws {
        var crop = CropSettings()
        let size = CGSize(width: 300, height: 200)
        #expect(crop.effectiveFrame(imageSize: size) == nil, "no angle, no frame: the whole image")
        crop.angle = 4
        let frame = try #require(crop.effectiveFrame(imageSize: size))
        let physical = CGRect(x: frame.minX * 300, y: frame.minY * 200, width: frame.width * 300, height: frame.height * 200)
        #expect(CropGeometry.fits(physical, imageSize: size, angle: 4), "no empty corners")
        crop.constrained = false
        #expect(crop.effectiveFrame(imageSize: size) == nil, "constraint off: the whole turned image")
    }

    @Test func outputSizeFollowsTheRecipe() {
        var recipe = Recipe(orientation: Orientation(quarterTurns: 1))
        // Preview 100 × 20 pixels of 1 × 3: turned, 20 × 100 pixels of 3 × 1 (physical 60 × 100).
        #expect(RecipeRenderer.outputSize(width: 100, height: 20, pixelAspectRatio: 3, recipe: recipe) == (20, 100))
        recipe.crop.frame = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        #expect(RecipeRenderer.outputSize(width: 100, height: 20, pixelAspectRatio: 3, recipe: recipe) == (10, 50))
        recipe.crop.constrained = false
        recipe.crop.angle = 1
        // With an angle: square pixels of the shorter side, 30 × 50.
        #expect(RecipeRenderer.outputSize(width: 100, height: 20, pixelAspectRatio: 3, recipe: recipe) == (30, 50))
        // Constraint on: the frame (here past the turned image's corner) is moved inside.
        recipe.crop.constrained = true
        let size = RecipeRenderer.outputSize(width: 100, height: 20, pixelAspectRatio: 3, recipe: recipe)
        let rendered = RecipeRenderer.render(RGB16Image(width: 100, height: 20, samples: Array(repeating: 1_000, count: 6_000)),
                                             pixelAspectRatio: 3, recipe: recipe)
        #expect(rendered.width == size.width && rendered.height == size.height)
        #expect(rendered.samples.allSatisfy { $0 == 1_000 }, "a flat image stays flat, no empty corners")
    }
}

@MainActor
struct CropModelTests {
    private func model(_ defaults: UserDefaults) -> AppModel {
        let inspector = ScannerInspector { FakeConnection(responses: [:], openError: TransportError.deviceBusy) }
        return AppModel(virtualScanner: { try TestFixtures.scanner() }, inspector: inspector, defaults: defaults)
    }

    @Test func cropAPIOnAPreview() async throws {
        let suite = "X1ScanCoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        do {
            let model = model(defaults)
            model.startPreview()
            await model.session.waitUntilIdle()
            model.refreshImage()
            await model.waitForRendering()
            let space = model.viewport.documentSize  // 2004 × 2451
            // A proportion without a frame: the largest frame of that proportion appears.
            model.setCropAspect(.ratio(width: 6, height: 7))
            let frame = try #require(model.cropFrameInDocument)
            #expect(abs(frame.width / frame.height - 6.0 / 7) < 1e-6, "6×7 as named: 6 wide, 7 high")
            model.toggleCropPortrait()
            let swapped = try #require(model.cropFrameInDocument)
            #expect(abs(swapped.width / swapped.height - 7.0 / 6) < 1e-6, "X exchanges them")
            // A frame dragged past the edge stays inside the image (constraint on).
            model.setCropFrame(documentRect: CGRect(x: space.width - 100, y: 10, width: 400, height: 300))
            let moved = try #require(model.cropFrameInDocument)
            #expect(moved.maxX <= space.width + 1e-6)
            // The rule: a line 2° down to the right becomes horizontal: −2°.
            let lean = 2 * Double.pi / 180
            let applied = try #require(model.straighten(from: .zero, to: CGPoint(x: 500 * cos(lean), y: 500 * sin(lean))))
            #expect(abs(applied.angle + 2) < 1e-9 && applied.axis == .horizontal)
            #expect(CropGeometry.fits(try #require(model.cropFrameInDocument), imageSize: space, angle: -2))
            // The histogram counts the pixels under the frame.
            await model.waitForRendering()
            let region = try #require(model.cropRect)
            #expect(model.histogram.pixelCount == region.width * region.height)
            // A quarter turn turns the frame with the image (step F); the angle stays.
            model.rotateClockwise()
            #expect(model.recipe.crop.frame != nil && model.recipe.crop.angle == -2)
        }
    }
}

/// Step F: the frame and the angle follow the image's turns and mirror.
struct CropFollowsOrientationTests {
    private func near(_ a: CGRect?, _ b: CGRect?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return abs(a.minX - b.minX) < 1e-12 && abs(a.minY - b.minY) < 1e-12
            && abs(a.width - b.width) < 1e-12 && abs(a.height - b.height) < 1e-12
    }

    private var sample: CropSettings {
        var crop = CropSettings()
        crop.frame = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        crop.aspect = .ratio(width: 6, height: 7)
        crop.angle = 1.5
        return crop
    }

    @Test func quarterTurnsAreExact() {
        var crop = sample
        crop.turnQuarter(clockwise: true)
        // Clockwise, unit square: (u, v) → (1 − v, u).
        #expect(near(crop.frame, CGRect(x: 0.4, y: 0.1, width: 0.4, height: 0.3)))
        #expect(crop.portrait, "6×7 becomes 7×6")
        #expect(crop.angle == 1.5, "a quarter turn keeps the fine angle")
        crop.turnQuarter(clockwise: false)
        #expect(near(crop.frame, sample.frame) && !crop.portrait && crop.angle == sample.angle, "there and back")
        var around = sample
        for _ in 0..<4 { around.turnQuarter(clockwise: true) }
        #expect(near(around.frame, sample.frame) && around.portrait == sample.portrait, "four quarters: back home")
        for _ in 0..<4 { around.turnQuarter(clockwise: false) }
        #expect(near(around.frame, sample.frame))
        // The image's own proportions are not exchanged: they turn with the image.
        var original = sample
        original.aspect = .original
        original.turnQuarter(clockwise: true)
        #expect(!original.portrait)
    }

    @Test func mirrorIsExact() {
        var crop = sample
        crop.mirrorHorizontally()
        #expect(near(crop.frame, CGRect(x: 0.6, y: 0.2, width: 0.3, height: 0.4)))
        #expect(crop.angle == -1.5 && !crop.portrait)
        crop.mirrorHorizontally()
        #expect(near(crop.frame, sample.frame) && crop.angle == 1.5, "there and back")
    }

    @Test func proportionsFollowTheFrameDirection() {
        let image = CGSize(width: 300, height: 200)
        var crop = CropSettings()
        // An upright frame and 6×9 (upright as named): stays upright.
        crop.choose(.ratio(width: 6, height: 9), imageSize: image, currentFrame: CGRect(x: 0, y: 0, width: 50, height: 90))
        #expect(!crop.portrait && crop.ratio(imageSize: image) == 6.0 / 9)
        // A flat frame and 6×9: turned flat, 9×6.
        crop.choose(.ratio(width: 6, height: 9), imageSize: image, currentFrame: CGRect(x: 0, y: 0, width: 90, height: 50))
        #expect(crop.portrait && crop.ratio(imageSize: image) == 9.0 / 6)
        // No frame: the image's direction (here flat).
        crop.choose(.ratio(width: 4, height: 5), imageSize: image, currentFrame: nil)
        #expect(crop.ratio(imageSize: image) == 5.0 / 4)
        // Original follows the frame's direction too: an upright frame on a flat image gets 200:300.
        crop.choose(.original, imageSize: image, currentFrame: CGRect(x: 0, y: 0, width: 50, height: 90))
        #expect(crop.portrait && abs((crop.ratio(imageSize: image) ?? 0) - 2.0 / 3) < 1e-12)
        // A square ratio has no direction.
        crop.choose(.ratio(width: 6, height: 6), imageSize: image, currentFrame: CGRect(x: 0, y: 0, width: 90, height: 50))
        #expect(!crop.portrait)
    }
}

/// Step F, on a preview: after turns and mirrors the frame covers the same source pixels.
@MainActor
struct CropFollowsOrientationModelTests {
    @Test func frameCoversTheSamePixels() async throws {
        let suite = "X1ScanCoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let inspector = ScannerInspector { FakeConnection(responses: [:], openError: TransportError.deviceBusy) }
        let model = AppModel(virtualScanner: { try TestFixtures.scanner() }, inspector: inspector, defaults: defaults)
        model.startPreview()
        await model.session.waitUntilIdle()
        model.refreshImage()
        await model.waitForRendering()
        model.cropRect = PixelRect(x: 300, y: 100, width: 500, height: 200)
        let pixels = try #require(model.cropRect)
        for step in 0..<4 {
            model.rotateClockwise()
            #expect(model.cropRect == pixels, "after \(step + 1) quarter turn(s): \(String(describing: model.cropRect))")
        }
        model.mirrorHorizontally()
        #expect(model.cropRect == pixels, "mirrored")
        model.rotateCounterclockwise()
        model.mirrorHorizontally()
        model.rotateClockwise()
        #expect(model.cropRect == pixels, "turned and mirrored, there and back")
        // With a fine angle: the frame still covers the same pixels (to the pixel, rounding).
        model.setCropAngle(1.5)
        let turned = try #require(model.cropRect)
        model.rotateClockwise()
        model.mirrorHorizontally()
        let after = try #require(model.cropRect)
        #expect(abs(after.x - turned.x) <= 1 && abs(after.y - turned.y) <= 1
                && abs(after.width - turned.width) <= 2 && abs(after.height - turned.height) <= 2)
        #expect(model.recipe.crop.angle == -1.5)
    }

    /// Through the model, on a preview (pixels 3 times taller than wide): a
    /// ratio keeps the frame's direction; a custom ratio is kept as typed.
    @Test func ratioKeepsTheFrameDirectionOnAPreview() async throws {
        let suite = "X1ScanCoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let inspector = ScannerInspector { FakeConnection(responses: [:], openError: TransportError.deviceBusy) }
        let model = AppModel(virtualScanner: { try TestFixtures.scanner() }, inspector: inspector, defaults: defaults)
        model.startPreview()
        await model.session.waitUntilIdle()
        model.refreshImage()
        // Upright frame (display points): 6×9 stays upright.
        model.setCropFrame(documentRect: CGRect(x: 100, y: 100, width: 400, height: 900))
        model.setCropAspect(.ratio(width: 6, height: 9))
        let upright = try #require(model.cropFrameInDocument)
        #expect(upright.height > upright.width && abs(upright.width / upright.height - 6.0 / 9) < 1e-6)
        // Flat frame: 6×9 turned flat.
        model.setCropFrame(documentRect: CGRect(x: 100, y: 100, width: 900, height: 400))
        model.setCropAspect(.ratio(width: 6, height: 9))
        let flat = try #require(model.cropFrameInDocument)
        #expect(flat.width > flat.height && abs(flat.width / flat.height - 9.0 / 6) < 1e-6)
        // Custom, typed 13 wide and 18 high: kept so, even on a flat frame.
        model.setCropAspect(.ratio(width: 13, height: 18), asTyped: true)
        let typed = try #require(model.cropFrameInDocument)
        #expect(abs(typed.width / typed.height - 13.0 / 18) < 1e-6)
    }
}
