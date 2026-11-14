// SPDX-License-Identifier: MIT
import Foundation
import ImageIO
import Testing
import X1Image
@testable import X1ScanCore

struct InspectorLayoutTests {
    @Test func defaultsAndLimits() {
        var layout = InspectorLayout()
        #expect(layout.width == InspectorLayout.defaultWidth && !layout.isHidden && layout.tab == .main)
        #expect(layout.isFolded(.histogram) && !layout.isFolded(.scanner), "histogram folded by default")
        layout.setWidth(10)
        #expect(layout.width == InspectorLayout.minimumWidth)
        layout.setWidth(.infinity)
        #expect(layout.width == InspectorLayout.defaultWidth)
        layout.setWidth(10_000)
        #expect(layout.width == InspectorLayout.maximumWidth)
        layout.toggleFolded(.histogram)
        layout.toggleFolded(.output)
        #expect(!layout.isFolded(.histogram) && layout.isFolded(.output))
    }

    @Test func decodesUnknownValuesSafely() throws {
        let json = #"{"width":9999,"isHidden":true,"folded":["output","future"],"tab":"future"}"#
        let layout = try JSONDecoder().decode(InspectorLayout.self, from: Data(json.utf8))
        #expect(layout.width == InspectorLayout.maximumWidth && layout.isHidden)
        #expect(layout.folded == [.output] && layout.tab == .main)
        var changed = InspectorLayout()
        changed.tab = .advanced
        changed.toggleFolded(.scanner)
        #expect(try JSONDecoder().decode(InspectorLayout.self, from: JSONEncoder().encode(changed)) == changed)
    }

    @MainActor
    @Test func controllerSavesAndRemovesThePaletteKeys() {
        withTemporaryDefaults { defaults in
            defaults.set(Data("old".utf8), forKey: "PaletteLayout")
            defaults.set(Data("old".utf8), forKey: "Workspaces")
            let controller = PanelController(defaults: defaults)
            #expect(defaults.object(forKey: "PaletteLayout") == nil && defaults.object(forKey: "Workspaces") == nil)
            controller.toggleHidden()
            controller.setWidth(333)
            controller.toggleFolded(.original)
            let reloaded = PanelController(defaults: defaults)
            #expect(reloaded.layout == controller.layout && reloaded.layout.isHidden && reloaded.layout.width == 333)
        }
    }
}

struct ScanSettingsTests {
    @Test func storedAndBounded() throws {
        var settings = ScanSettings()
        #expect(settings.filmType == .positive && settings.holder.isEmpty)
        settings.resolution = 1
        #expect(settings.resolution == ScanSettings.resolutionRange.lowerBound)
        settings.scalePercent = 0
        #expect(settings.scalePercent == 1)
        settings.filmType = .colorNegative
        settings.holder = "35 mm strip"
        #expect(try JSONDecoder().decode(ScanSettings.self, from: JSONEncoder().encode(settings)) == settings)
        let odd = try JSONDecoder().decode(ScanSettings.self, from: Data(#"{"filmType":"slide","resolution":-4}"#.utf8))
        #expect(odd.filmType == .positive && odd.resolution == ScanSettings.resolutionRange.lowerBound)
    }

    @Test func rgbUnits() {
        #expect(RGBUnit.eightBit.value(65_535) == 255 && RGBUnit.eightBit.value(0) == 0)
        #expect(RGBUnit.eightBit.value(32_896) == 128)
        #expect(RGBUnit.percent.value(65_535) == 100)
        #expect(RGBUnit.sixteenBit.value(1_234) == 1_234)
    }
}

struct ZoomMenuTests {
    /// The menu resolves only a confirmed title; nothing happens while browsing.
    @Test func entriesAndTitles() {
        let title: (ZoomMenuEntry) -> String = {
            switch $0 {
            case .fit: "Fit"
            case .fill: "Fill"
            case .step(let v): "\(Int((v * 100).rounded()))%"
            }
        }
        #expect(ZoomMenuEntry.all.count == 2 + Viewport.steps.count)
        #expect(ZoomMenuEntry.entry(titled: "Fit", title: title) == .fit)
        #expect(ZoomMenuEntry.entry(titled: "200%", title: title) == .step(2))
        #expect(ZoomMenuEntry.entry(titled: "150", title: title) == nil, "typed value: parsed separately")
    }
}

struct TokenInsertionTests {
    @Test func insertsAtTheCaretWithSeparators() {
        let t = ExportToken.roll
        #expect(t.insert(into: "X1-preview", at: 0) == ("{roll}-X1-preview", 7))
        #expect(t.insert(into: "X1-preview", at: 10) == ("X1-preview-{roll}", 17))
        #expect(t.insert(into: "X1-preview", at: nil).text == "X1-preview-{roll}", "no caret: at the end")
        #expect(t.insert(into: "X1-preview", at: 3) == ("X1-{roll}-preview", 10), "after a separator: none added before")
        #expect(t.insert(into: "AB", at: 1) == ("A-{roll}-B", 9))
        #expect(t.insert(into: "", at: 0) == ("{roll}", 6))
        #expect(t.insert(into: "A_B", at: 1, selectionLength: 1) == ("A-{roll}-B", 9), "selection replaced")
        #expect(t.insert(into: "abc", at: 99).text == "abc-{roll}", "caret out of range: at the end")
        // Several buttons in a row, the caret following: separated tokens, not glued at the start.
        var text = "X1-preview", caret = 10
        for token in [ExportToken.date, .counter] {
            (text, caret) = token.insert(into: text, at: caret)
        }
        #expect(text == "X1-preview-{date}-{n}")
    }
}

struct ExportFormatTests {
    @Test func formatSelectsItsDefaultCompression() throws {
        var settings = ExportSettings()
        #expect(settings.format == .rgb16 && settings.compression == .deflate, "ZIP in 16 bits")
        settings.format = .rgb8
        #expect(settings.compression == .lzw, "LZW in 8 bits")
        settings.compression = .none
        settings.format = .rgb8
        #expect(settings.compression == .none, "same format: the choice is kept")
        settings.format = .gray16
        #expect(settings.compression == .deflate)
        #expect(try JSONDecoder().decode(ExportSettings.self, from: JSONEncoder().encode(settings)) == settings)
        let older = try JSONDecoder().decode(ExportSettings.self, from: Data(#"{"nameTemplate":"A"}"#.utf8))
        #expect(older.format == .rgb16 && older.compression == .deflate)
    }

    @Test func eachFormatIsWrittenAndReadBack() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = PreviewImage(width: 4, corrected: (0..<(4 * 3 * 3)).map { UInt16($0 * 1_800) },
                                 raw: Array(repeating: 0, count: 36))
        for format in TIFFFormat.allCases {
            var settings = ExportSettings(folder: folder, nameTemplate: format.rawValue + "-{n}")
            settings.format = format
            let url = try ExportService.export(image, settings: settings)
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(decoded.width == 4 && decoded.height == 3 && decoded.bitsPerComponent == format.bitsPerSample)
            #expect((decoded.colorSpace?.model == .monochrome) == format.isGray)
            #expect(ExportService.estimatedBytes(for: image, settings: settings) == format.pixelBytes(width: 4, height: 3))
        }
    }
}
