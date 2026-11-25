// SPDX-License-Identifier: MIT
import Foundation
import ImageIO
import Testing
import X1Image
import X1Transport
@testable import X1ScanCore

struct InspectorLayoutTests {
    @Test func defaultsAndLimits() {
        var layout = InspectorLayout()
        #expect(layout.width == InspectorLayout.defaultWidth && !layout.isHidden)
        #expect(layout.folded == [.histogram], "all sections open at first launch, except the histogram (lot 1)")
        layout.setWidth(10)
        #expect(layout.width == InspectorLayout.minimumWidth)
        layout.setWidth(.infinity)
        #expect(layout.width == InspectorLayout.defaultWidth)
        layout.setWidth(10_000)
        #expect(layout.width == InspectorLayout.maximumWidth)
        // Decision of 2026-11-16 (docs/decisions.md, step 3): 280-480 pt, 300 at first launch.
        #expect(InspectorLayout.minimumWidth == 280 && InspectorLayout.maximumWidth == 480
                && InspectorLayout.defaultWidth == 300)
        layout.toggleFolded(.histogram)
        layout.toggleFolded(.output)
        #expect(!layout.isFolded(.histogram) && layout.isFolded(.output))
    }

    @Test func decodesUnknownValuesSafely() throws {
        let json = #"{"width":9999,"isHidden":true,"folded":["output","scanner","future"],"tab":"future"}"#
        let layout = try JSONDecoder().decode(InspectorLayout.self, from: Data(json.utf8))
        #expect(layout.width == InspectorLayout.maximumWidth && layout.isHidden)
        #expect(layout.folded == [.output])
        #expect(layout.tab == .prepare, "an unknown tab gives Prepare")
        var changed = InspectorLayout()
        changed.toggleFolded(.original)
        #expect(try JSONDecoder().decode(InspectorLayout.self, from: JSONEncoder().encode(changed)) == changed)
    }

    @Test func migratesTheSettingsSectionOfStep3() throws {
        // Step 3 saved the Main / Advanced section as "settings", with a tab: now the Scan section.
        let json = #"{"width":300,"isHidden":false,"folded":["settings"],"tab":"advanced"}"#
        let layout = try JSONDecoder().decode(InspectorLayout.self, from: Data(json.utf8))
        #expect(layout.folded == [.scan], "histogram open: it was open in the saved layout")
        #expect(layout.tab == .prepare, "the Advanced tab of step 3 is not a panel tab of lot 1b")
        let saved = String(decoding: try JSONEncoder().encode(layout), as: UTF8.self)
        #expect(!saved.contains("advanced") && !saved.contains("settings") && saved.contains(#""tab":"prepare""#))
    }

    /// Lot 1b: Prepare, Scan, Output; Develop (lot 3) has its place but is not shown.
    @Test func tabsAndTheirSections() throws {
        #expect(PanelTab.visible == [.prepare, .scan, .output])
        #expect(PanelTab.allCases == [.prepare, .scan, .develop, .output], "Develop between Scan and Output")
        #expect(PanelTab.prepare.sections == [.original, .framing])
        #expect(PanelTab.scan.sections == [.scan] && PanelTab.output.sections == [.output])
        let inTabs = Set(PanelTab.allCases.flatMap(\.sections))
        #expect(!inTabs.contains(.histogram) && !inTabs.contains(.exposure), "common to every tab")
        var layout = InspectorLayout()
        #expect(layout.tab == .prepare, "Prepare at first launch")
        layout.select(.output)
        #expect(layout.tab == .output)
        layout.select(.develop)
        #expect(layout.tab == .output, "a hidden tab is not selected")
        let saved = try JSONDecoder().decode(InspectorLayout.self, from: JSONEncoder().encode(layout))
        #expect(saved.tab == .output)
        let hidden = try JSONDecoder().decode(InspectorLayout.self, from: Data(#"{"tab":"develop"}"#.utf8))
        #expect(hidden.tab == .prepare, "a saved hidden tab gives Prepare")
    }

    @MainActor
    @Test func tabAndFoldsAreRememberedAndFramingShown() {
        withTemporaryDefaults { defaults in
            let controller = PanelController(defaults: defaults)
            controller.select(.scan)
            controller.setFolded(.framing, true)
            controller.setFolded(.exposure, true)
            let reloaded = PanelController(defaults: defaults)
            #expect(reloaded.layout.tab == .scan && reloaded.layout.isFolded(.framing) && reloaded.layout.isFolded(.exposure))
            reloaded.showFraming()
            #expect(reloaded.layout.tab == .prepare && !reloaded.layout.isFolded(.framing))
            #expect(reloaded.layout.isFolded(.exposure), "other sections keep their state")
        }
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
        #expect(settings.filmType == .positive && settings.holderID == nil)
        settings.resolution = 1
        #expect(settings.resolution == ScanSettings.resolutionRange.lowerBound)
        settings.scalePercent = 0
        #expect(settings.scalePercent == 1)
        settings.filmType = .colorNegative
        settings.holderID = "50200401"
        #expect(try JSONDecoder().decode(ScanSettings.self, from: JSONEncoder().encode(settings)) == settings)
        let odd = try JSONDecoder().decode(ScanSettings.self, from: Data(#"{"filmType":"slide","resolution":-4}"#.utf8))
        #expect(odd.filmType == .positive && odd.resolution == ScanSettings.resolutionRange.lowerBound)
    }

    @Test func rgbUnits() {
        #expect(RGBUnit.eightBit.value(65_535) == 255 && RGBUnit.eightBit.value(0) == 0)
        #expect(RGBUnit.eightBit.value(11_796) == 118, "middle grey (18 %), sRGB-encoded as in Photoshop")
        let exported = ExportConversion.samples(of: RGB16Image(width: 1, height: 1, samples: [11_796, 11_796, 11_796]),
                                                as: .rgb8)
        #expect(RGBUnit.eightBit.value(11_796) == Double(exported[0]), "as in an 8-bit export")
        #expect(RGBUnit.eightBit.isSRGBEncoded && !RGBUnit.percent.isSRGBEncoded && !RGBUnit.sixteenBit.isSRGBEncoded)
        #expect(abs(RGBUnit.percent.value(11_796) - 18) < 0.01, "percent stays linear")
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
        }
    }
}

@MainActor
struct HolderTests {
    @Test func defaultListFromTheDataFile() {
        let all = DefaultHolders.all
        #expect(all.count == 21)
        #expect(Set(all.map(\.id)).count == all.count, "unique references")
        #expect(all.allSatisfy { $0.id == $0.reference })
        #expect(DefaultHolders.standardIDs == ["50200401", "50200402", "50200428"])
        let sixBySeven = all.first { $0.reference == "50200403" }
        #expect(sixBySeven?.format == "6×7" && sixBySeven?.apertures == [HolderAperture(width: 57, height: 70)])
        #expect(all.first { $0.reference == "50200428" }?.apertures.count == 2)
        #expect(all.first { $0.reference == "50200401" }?.apertures == [HolderAperture(width: 24, height: 35),
                                                                       HolderAperture(width: 35, height: 24)],
                "24×36 / 36×24: one vertical (24 × 35) and one horizontal (35 × 24) opening")
        #expect(all.first { $0.reference == "50200416" }?.frames == 6)
        #expect(all.filter(\.mountedSlides).map(\.reference) == ["50200100", "1005377"])
        #expect(all.first { $0.reference == "50200417" }?.apertures == [HolderAperture(width: 24, height: 65)])
        #expect(all.first { $0.reference == "50200418" }?.apertures == [HolderAperture(width: 57, height: 88)])
        let withoutOpening = all.filter { $0.apertures.isEmpty }
        let onlySlides = withoutOpening.allSatisfy { $0.mountedSlides }
        #expect(onlySlides && withoutOpening.count == 2, "only mounted slides have no opening")
    }

    /// Inches as the holder sheet gives them, one per opening; patent and
    /// maker on every default; the codes read on 2026-11-18 (protocol.md §13).
    @Test func inchesPatentAndCodes() {
        let all = DefaultHolders.all
        #expect(all.filter { !$0.apertures.isEmpty }.allSatisfy { $0.aperturesInches.count == $0.apertures.count })
        #expect(all.first { $0.reference == "50200428" }?.inches == [HolderInches(width: "2¼", height: "2¼"),
                                                                     HolderInches(width: "2¼", height: "1⅔")])
        #expect(all.allSatisfy { $0.patent == "US 6,081,352" && $0.manufacturer == "Hasselblad" })
        let codes = Dictionary(uniqueKeysWithValues: all.compactMap { h in h.code.map { (h.reference!, $0) } })
        #expect(codes == ["50200401": [15], "50200402": [14], "50200428": [12, 14], "50200403": [14, 15],
                          "50200404": [13], "50200405": [7, 15], "50200411": [7, 13, 14, 15], "50200416": [7, 12, 13]])
        #expect(Set(codes.values).count == codes.count, "one code per format")
    }

    /// A custom holder: inches computed from the millimetres; maker, patent
    /// and code stay nil when saved and read back.
    @Test func customHolderInches() throws {
        let holder = Holder(reference: nil, format: "Mine", apertures: [HolderAperture(width: 57, height: 94)])
        #expect(holder.inches == [HolderInches(width: "2.24", height: "3.7")])
        let decoded = try JSONDecoder().decode(Holder.self, from: JSONEncoder().encode(holder))
        #expect(decoded == holder)
        #expect(decoded.patent == nil && decoded.manufacturer == nil && decoded.code == nil)
    }

    /// Editing a custom holder's opening drops inches saved with it, so the
    /// inches shown follow the new millimetres.
    @Test func editingClearsSavedInches() throws {
        let store = try #require(UserDefaults(suiteName: "HolderTests.inches.\(UUID().uuidString)"))
        let saved = #"{"owned":["mine"],"custom":[{"id":"mine","format":"Mine","apertures":[[57,94]],"aperturesInches":[["9","9"]]}]}"#
        store.set(Data(saved.utf8), forKey: "Holders")
        let library = HolderLibrary(defaults: [], store: store)
        #expect(library.holder(id: "mine")?.inches == [HolderInches(width: "9", height: "9")], "saved inches read back")
        library.updateCustom("mine", reference: nil, format: "Mine", aperture: HolderAperture(width: 25.4, height: 50.8), frames: 1)
        let edited = try #require(library.holder(id: "mine"))
        #expect(edited.aperturesInches.isEmpty)
        #expect(edited.inches == [HolderInches(width: "1", height: "2")])
    }

    @Test func ownedCustomAndPersistence() {
        withTemporaryDefaults { store in
            let library = HolderLibrary(store: store)
            #expect(library.ownedHolders.map(\.id) == ["50200401", "50200402", "50200428"], "standard set owned at first")
            library.setOwned("50200403", true)
            library.setOwned("50200401", false)
            let custom = library.addCustom(reference: "  ", format: " Glass 6×6 ", aperture: HolderAperture(width: 56, height: 56),
                                           frames: 0)
            #expect(custom.reference == nil && custom.format == "Glass 6×6" && custom.frames == 1 && custom.isCustom)
            #expect(library.ownedHolders.map(\.id) == ["50200402", "50200428", "50200403", custom.id], "defaults, then custom")
            library.updateCustom(custom.id, reference: "X-1", format: "Glass", aperture: nil, frames: 2)
            library.updateCustom("50200403", reference: "Z", format: "Z", aperture: nil, frames: 9)
            #expect(library.holder(id: "50200403")?.format == "6×7", "defaults cannot be changed")
            let reloaded = HolderLibrary(store: store)
            #expect(reloaded.ownedHolders.map(\.id) == library.ownedHolders.map(\.id))
            #expect(reloaded.holder(id: custom.id)?.reference == "X-1" && reloaded.holder(id: custom.id)?.frames == 2)
            reloaded.deleteCustom("50200402")
            #expect(reloaded.holder(id: "50200402") != nil, "defaults cannot be deleted")
            reloaded.deleteCustom(custom.id)
            #expect(reloaded.holder(id: custom.id) == nil && !reloaded.isOwned(custom.id))

            store.set(Data("garbage".utf8), forKey: "Holders")
            _ = HolderLibrary(store: store)
            #expect(store.data(forKey: "Holders.unreadable") == Data("garbage".utf8), "kept aside")
        }
    }

    @Test func panelSelectionAndStep3Migration() {
        withTemporaryDefaults { store in
            // Step 3 saved the holder as free text.
            store.set(Data(#"{"filmType":"positive","holder":"My glass carrier","resolution":2000,"scalePercent":100}"#.utf8),
                      forKey: "ScanSettings")
            let model = AppModel(virtualScanner: { throw TimeoutError() }, inspector: ScannerInspector {
                FakeConnection(responses: [:], openError: TransportError.deviceBusy)
            }, defaults: store)
            #expect(model.selectedHolder?.format == "My glass carrier" && model.selectedHolder?.isCustom == true)
            let again = AppModel(virtualScanner: { throw TimeoutError() }, inspector: ScannerInspector {
                FakeConnection(responses: [:], openError: TransportError.deviceBusy)
            }, defaults: store)
            #expect(again.holders.custom.count == 1, "converted once")
            again.scanSettings.holderID = "50200403"
            #expect(again.selectedHolder == nil, "not owned: shown as not specified")
            again.holders.setOwned("50200403", true)
            #expect(again.selectedHolder?.reference == "50200403")
            again.scanSettings.holderID = nil
            #expect(again.selectedHolder == nil)
        }
    }
}

struct HolderDecimalsTests {
    @Test func dotsBetweenDigitsFollowTheLocale() {
        let fr = Locale(identifier: "fr_FR"), en = Locale(identifier: "en_US")
        #expect(Holder.localizedDecimals("6×6 / 6×4.5", locale: fr) == "6×6 / 6×4,5")
        #expect(Holder.localizedDecimals("4.5×6", locale: fr) == "4,5×6")
        #expect(Holder.localizedDecimals("4.5×6", locale: en) == "4.5×6")
        #expect(Holder.localizedDecimals(".5 x 5.", locale: fr) == ".5 x 5.", "a dot not between digits stays")
        #expect(Holder.localizedDecimals("Reflex 4×6″", locale: fr) == "Reflex 4×6″")
    }
}
