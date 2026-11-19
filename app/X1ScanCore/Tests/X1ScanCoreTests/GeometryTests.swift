// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import ImageIO
import Testing
import X1Image
import X1Transport
@testable import X1ScanCore

/// All 8 orientations: 4 turns, mirrored or not.
private let allOrientations: [Orientation] = (0..<8).map { Orientation(quarterTurns: $0 % 4, mirrored: $0 >= 4) }

/// A 3 × 2 image whose red sample is the pixel's index (0...5), green 100 + index, blue 200 + index.
private func indexImage(width: Int = 3, height: Int = 2) -> RGB16Image {
    RGB16Image(width: width, height: height, samples: (0..<width * height).flatMap {
        [UInt16($0), UInt16(100 + $0), UInt16(200 + $0)]
    })
}

/// Width and height of a written TIFF.
private func tiffSize(_ url: URL) throws -> (width: Int, height: Int) {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    return (image.width, image.height)
}

/// The red samples, row by row.
private func reds(_ image: RGB16Image) -> [[Int]] {
    (0..<image.height).map { y in (0..<image.width).map { Int(image.samples[(y * image.width + $0) * 3]) } }
}

struct OrientationTests {
    @Test func turnsAndMirrorsCompose() {
        var orientation = Orientation()
        for _ in 0..<4 { orientation.rotateClockwise() }
        #expect(orientation == .identity)
        orientation.rotateClockwise()
        orientation.rotateCounterclockwise()
        #expect(orientation == .identity)
        orientation.mirrorHorizontally()
        orientation.mirrorHorizontally()
        #expect(orientation == .identity)
        #expect(Orientation(quarterTurns: -1) == Orientation(quarterTurns: 3))
    }

    @Test func knownPermutations() {
        // Source (red = index):
        //   0 1 2
        //   3 4 5
        let image = indexImage()
        #expect(reds(Orientation(quarterTurns: 1).apply(to: image)) == [[3, 0], [4, 1], [5, 2]], "clockwise")
        #expect(reds(Orientation(quarterTurns: 2).apply(to: image)) == [[5, 4, 3], [2, 1, 0]], "half turn")
        #expect(reds(Orientation(quarterTurns: 3).apply(to: image)) == [[2, 5], [1, 4], [0, 3]], "counterclockwise")
        #expect(reds(Orientation(mirrored: true).apply(to: image)) == [[2, 1, 0], [5, 4, 3]], "mirror")
        // Channels travel together.
        let turned = Orientation(quarterTurns: 1).apply(to: image)
        #expect(Array(turned.samples[0..<3]) == [3, 103, 203])
    }

    @Test func permutationIsExactAndReversible() {
        let image = indexImage(width: 5, height: 3)
        for orientation in allOrientations {
            let out = orientation.apply(to: image)
            #expect(out.samples.sorted() == image.samples.sorted(), "a permutation: \(orientation)")
            let size = orientation.orientedSize(width: 5, height: 3)
            #expect(out.width == size.width && out.height == size.height)
        }
    }

    @Test func mirrorActsOnTheImageAsShown() {
        // Mirroring after a turn mirrors what is shown, not the original.
        let image = indexImage(width: 4, height: 3)
        for start in allOrientations {
            var mirrored = start
            mirrored.mirrorHorizontally()
            let shown = reds(start.apply(to: image))
            #expect(reds(mirrored.apply(to: image)) == shown.map { $0.reversed() }, "\(start)")
            var turned = start
            turned.rotateClockwise()
            let expected = (0..<shown[0].count).map { x in (0..<shown.count).reversed().map { shown[$0][x] } }
            #expect(reds(turned.apply(to: image)) == expected, "clockwise from \(start)")
        }
    }

    @Test func continuousMapMatchesThePixels() {
        // The affine map (display) and the pixel permutation (export) agree at pixel centres.
        let width = 5, height = 3
        let size = CGSize(width: width, height: height)
        for orientation in allOrientations {
            let oriented = orientation.orientedSize(width: width, height: height)
            for oy in 0..<oriented.height {
                for ox in 0..<oriented.width {
                    let source = orientation.sourcePixel(x: ox, y: oy, sourceWidth: width, sourceHeight: height)
                    let point = orientation.orientedPoint(CGPoint(x: Double(source.x) + 0.5, y: Double(source.y) + 0.5),
                                                          sourceSize: size)
                    #expect(abs(point.x - (Double(ox) + 0.5)) < 1e-9 && abs(point.y - (Double(oy) + 0.5)) < 1e-9)
                    let back = orientation.sourcePoint(point, sourceSize: size)
                    #expect(abs(back.x - (Double(source.x) + 0.5)) < 1e-9)
                }
            }
        }
    }
}

struct ViewportOrientationTests {
    @Test func documentFollowsTheTurns() {
        var viewport = Viewport(imageWidth: 100, imageHeight: 20, pixelAspectRatio: 3)
        #expect(viewport.documentSize == CGSize(width: 100, height: 60))
        viewport.orientation = Orientation(quarterTurns: 1)
        #expect(viewport.documentSize == CGSize(width: 60, height: 100))
        // Top left of the display after a clockwise turn: the bottom left pixel of the source.
        #expect(viewport.pixel(atDocumentPoint: CGPoint(x: 1, y: 1)) == PixelCoordinate(x: 1, y: 19))
        #expect(viewport.documentRect(forPixelRect: PixelRect(x: 0, y: 19, width: 1, height: 1))
                == CGRect(x: 0, y: 0, width: 3, height: 1))
    }
}

struct RecipeTests {
    @Test func jsonRoundTrip() throws {
        let recipe = Recipe(orientation: Orientation(quarterTurns: 3, mirrored: true))
        let data = try recipe.jsonData()
        #expect(try Recipe.decode(from: data) == recipe)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""version" : 1"#))
    }

    @Test func refusesAnotherVersion() {
        let json = #"{"version":2,"orientation":{"quarterTurns":0,"mirrored":false}}"#
        #expect(throws: Recipe.DecodingError.unsupportedVersion(2)) { try Recipe.decode(from: Data(json.utf8)) }
    }

    @Test func fileNextToTheImage() {
        let url = URL(filePath: "/tmp/X1-07.tif")
        #expect(Recipe.fileURL(forImage: url).lastPathComponent == "X1-07.x1recipe.json")
    }
}

struct RecipeExportTests {
    private func preview() -> PreviewImage {
        let image = indexImage()
        return PreviewImage(width: image.width, corrected: image.samples, raw: image.samples)
    }

    @Test func masterStaysRawAndVersionsNeverReplaceIt() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = ExportSettings(folder: folder, nameTemplate: "scan")
        let recipe = Recipe(orientation: Orientation(quarterTurns: 1))
        let master = try ExportService.export(preview(), settings: settings, recipe: recipe)
        #expect(master.lastPathComponent == "scan.tif")
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "scan.x1recipe.json").path))
        let masterSize = try tiffSize(master)
        #expect(masterSize.width == 3 && masterSize.height == 2, "the master keeps the scanner's pixels")

        let v1 = try ExportService.export(preview(), settings: settings, recipe: recipe, applyRecipe: true,
                                          versionOf: master)
        let v2 = try ExportService.export(preview(), settings: settings, recipe: recipe, applyRecipe: true,
                                          versionOf: master)
        #expect(v1.lastPathComponent == "scan_v1.tif" && v2.lastPathComponent == "scan_v2.tif")
        // The panel's "Next file" follows the same rules.
        #expect(ExportService.nextFileName(settings: settings, versionOf: master, withRecipe: true) == "scan_v3.tif")
        try FileManager.default.removeItem(at: folder.appending(path: "scan_v2.tif"))
        #expect(ExportService.nextFileName(settings: settings, versionOf: master, withRecipe: true) == "scan_v3.tif",
                "an orphan recipe keeps its name taken")
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "scan_v1.x1recipe.json").path))
        let turned = try tiffSize(v1)
        #expect(turned.width == 2 && turned.height == 3, "the version is turned")
        #expect(try Recipe.decode(from: Data(contentsOf: folder.appending(path: "scan_v2.x1recipe.json"))) == recipe)
    }

    @Test func versionSkipsAnOrphanRecipe() {
        let master = URL(filePath: "/x/X1-07.tif")
        let taken: Set = ["X1-07_v1.tif", "X1-07_v2.tif"]
        #expect(ExportService.versionFileName(of: master) { taken.contains($0) } == "X1-07_v3.tif")
    }
}

struct GridTests {
    private let area = CGRect(x: 0, y: 0, width: 300, height: 120)

    @Test func thirdsAndCentre() {
        let thirds = GridSettings.lines(.thirds, in: area)
        #expect(thirds.count == 4)
        #expect(thirds.contains { $0.0 == CGPoint(x: 100, y: 0) && $0.1 == CGPoint(x: 100, y: 120) })
        #expect(thirds.contains { $0.0 == CGPoint(x: 0, y: 80) && $0.1 == CGPoint(x: 300, y: 80) })
        let centre = GridSettings.lines(.centre, in: area)
        #expect(centre.count == 2 && centre[0].0.x == 150 && centre[1].0.y == 60)
    }

    @Test func fineGridHasSquareCellsFromTheCentre() {
        // 10 squares across 300: spacing 30, lines at 150 ± 30k.
        let lines = GridSettings.lines(.fine, in: area, fineDivisions: 10)
        let xs = Set(lines.filter { $0.0.x == $0.1.x }.map(\.0.x))
        let ys = Set(lines.filter { $0.0.y == $0.1.y }.map(\.0.y))
        #expect(xs == [30, 60, 90, 120, 150, 180, 210, 240, 270])
        #expect(ys == [30, 60, 90])
        #expect(GridSettings.lines(.fine, in: .zero).isEmpty)
    }

    @Test func settingsDecodeSafely() throws {
        var grid = GridSettings()
        #expect(!grid.isVisible && grid.kind == .thirds)
        grid.isVisible = true
        grid.kind = .fine
        grid.fineDivisions = 1_000
        #expect(grid.fineDivisions == 64)
        #expect(try JSONDecoder().decode(GridSettings.self, from: JSONEncoder().encode(grid)) == grid)
        let future = #"{"isVisible":true,"kind":"golden","fineDivisions":"x"}"#
        let decoded = try JSONDecoder().decode(GridSettings.self, from: Data(future.utf8))
        #expect(decoded.isVisible && decoded.kind == .thirds && decoded.fineDivisions == GridSettings.defaultDivisions)
        let huge = try JSONDecoder().decode(GridSettings.self, from: Data(#"{"fineDivisions":1000}"#.utf8))
        #expect(huge.fineDivisions == 64, "bounded when read back too")
        // Colour and opacity: green and 70 % by default, bounded, unknown values fall back.
        #expect(GridSettings().color == .green && GridSettings().opacity == 0.7)
        var styled = GridSettings()
        styled.color = .pink
        styled.opacity = 0.05
        #expect(styled.opacity == 0.3)
        #expect(try JSONDecoder().decode(GridSettings.self, from: JSONEncoder().encode(styled)) == styled)
        let odd = try JSONDecoder().decode(GridSettings.self, from: Data(#"{"color":"purple","opacity":7}"#.utf8))
        #expect(odd.color == .green && odd.opacity == 1)
        let faint = try JSONDecoder().decode(GridSettings.self, from: Data(#"{"opacity":0.1}"#.utf8))
        #expect(faint.opacity == 0.3, "too low when read back: bounded too")
        // The menu always has a checked opacity: the default is one of the choices, all within the range.
        #expect(GridSettings.opacityChoices.contains(GridSettings.defaultOpacity))
        #expect(GridSettings.opacityChoices.allSatisfy(GridSettings.opacityRange.contains))
    }
}

@MainActor
struct GridModelTests {
    @Test func gridIsSavedAndRestored() throws {
        try withTemporaryDefaults { defaults in
            let inspector = ScannerInspector { FakeConnection(responses: [:], openError: TransportError.deviceBusy) }
            let model = AppModel(virtualScanner: { try TestFixtures.scanner() }, inspector: inspector, defaults: defaults)
            model.showGrid(.centre)
            model.toggleGrid()
            #expect(!model.grid.isVisible && model.grid.kind == .centre)
            model.toggleGrid()
            let reloaded = AppModel(virtualScanner: { try TestFixtures.scanner() }, inspector: inspector, defaults: defaults)
            #expect(reloaded.grid.isVisible && reloaded.grid.kind == .centre)
        }
    }
}
