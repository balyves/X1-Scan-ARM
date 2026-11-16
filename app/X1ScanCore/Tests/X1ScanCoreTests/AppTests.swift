// SPDX-License-Identifier: MIT
import Foundation
import ImageIO
import Testing
@testable import X1ScanCore
import X1Transport

struct ToolbarStateTests {
    @Test func virtualIdle() {
        let state = ToolbarState(source: .virtual, session: .idle, virtualAvailable: true, hasImage: false,
                                 hasExportFolder: true)
        #expect(state.canPreview && !state.canStop && !state.canExport && !state.canScan)
    }

    @Test func realScannerNeverPreviews() {
        for session: PreviewSession.State in [.idle, .finished, .stopped(nil)] {
            let state = ToolbarState(source: .real, session: session, virtualAvailable: true, hasImage: true,
                                     hasExportFolder: true)
            #expect(!state.canPreview && state.previewBlock == .realScannerReadOnly)
        }
    }

    @Test func runningAndStopping() {
        let running = ToolbarState(source: .virtual, session: .running, virtualAvailable: true, hasImage: true,
                                   hasExportFolder: true)
        #expect(!running.canPreview && running.previewBlock == .busy && running.canStop && !running.canExport)
        let stopping = ToolbarState(source: .virtual, session: .stopping, virtualAvailable: true, hasImage: true,
                                    hasExportFolder: true)
        #expect(!stopping.canStop && stopping.isStopping && !stopping.canPreview)
    }

    @Test func exportNeedsAnImageAndAFolder() {
        #expect(ToolbarState(source: .virtual, session: .finished, virtualAvailable: true, hasImage: true,
                             hasExportFolder: true).canExport)
        #expect(!ToolbarState(source: .virtual, session: .finished, virtualAvailable: true, hasImage: true,
                              hasExportFolder: false).canExport)
        #expect(!ToolbarState(source: .virtual, session: .idle, virtualAvailable: false, hasImage: false,
                              hasExportFolder: true).canPreview)
    }

    @Test func stopIsRedOnlyWhileAPreviewRuns() {
        for session: PreviewSession.State in [.idle, .stopping, .finished, .stopped(nil)] {
            #expect(!ToolbarState(source: .virtual, session: session, virtualAvailable: true, hasImage: true,
                                  hasExportFolder: true).stopIsProminent)
        }
        #expect(ToolbarState(source: .virtual, session: .running, virtualAvailable: true, hasImage: true,
                             hasExportFolder: true).stopIsProminent)
    }

    @Test func serialIsMaskedByDefault() {
        #expect(SerialMasking.masked("FX1xxxxxxx") == "FX1•••••••")
        #expect(SerialMasking.display("FX1xxxxxxx", revealed: true) == "FX1xxxxxxx")
        #expect(SerialMasking.masked("FX") == "FX")
    }
}

struct ExportTests {
    private let date = Date(timeIntervalSince1970: 1_794_441_600)  // 2026-11-12 UTC
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func name(_ template: String, taken: Set<String> = [], configure: (inout ExportSettings) -> Void = { _ in })
        -> String {
        var settings = ExportSettings(nameTemplate: template)
        configure(&settings)
        return ExportService.fileName(settings: settings, date: date.addingTimeInterval(13 * 3600 + 5 * 60 + 9),
                                      calendar: utc) { taken.contains($0) }
    }

    @Test func templateTokensAndCounter() {
        let taken: Set = ["X1-preview-2026-11-12-001.tif", "X1-preview-2026-11-12-002.tif"]
        #expect(name(ExportSettings.defaultTemplate, taken: taken) == "X1-preview-2026-11-12-003.tif")
        #expect(name("{date}_{time}_{n}") == "2026-11-12_13-05-09_001.tif")
        #expect(name("{heure}") == "{heure}.tif", "only English tokens in the template")
        #expect(name("Scan") == "Scan.tif")
        #expect(name("Scan", taken: ["Scan.tif", "Scan-002.tif"]) == "Scan-003.tif", "no {n}: added when needed")
    }

    @Test func rollFrameAndCounterSettings() {
        let roll: (inout ExportSettings) -> Void = { $0.roll = "R042"; $0.frame = 7 }
        #expect(name("{roll}_{frame}", configure: roll) == "R042_07.tif")
        #expect(name("{roll}-{n}", configure: { $0.roll = "A"; $0.counterStart = 40; $0.counterDigits = 5 })
            == "A-00040.tif")
        #expect(name("{n}", taken: ["0040.tif", "0041.tif"], configure: { $0.counterStart = 40; $0.counterDigits = 4 })
            == "0042.tif")
        #expect(name("{n}", configure: { $0.counterStart = 0; $0.counterDigits = 1 }) == "0.tif")
        #expect(name("{n}") == "001.tif", "a template made of {n} alone is a name")
        #expect(name("{roll}", configure: { $0.roll = "a/b" }) == "a-b.tif", "the roll name is sanitised too")
    }

    @Test func emptyRollTakesItsSeparatorWithIt() {
        let frame: (inout ExportSettings) -> Void = { $0.frame = 7 }
        #expect(name("X1-{roll}-{frame}", configure: frame) == "X1-07.tif", "not X1--07")
        #expect(name("{roll}-{frame}", configure: frame) == "07.tif", "first: the separator after goes")
        #expect(name("{frame}_{roll}", configure: frame) == "07.tif", "last: the separator before goes")
        #expect(name("X1-{roll}{frame}", configure: frame) == "X1-07.tif", "glued to the next token")
        #expect(name("Scan{roll}_{frame}", configure: frame) == "Scan_07.tif", "glued before: nothing welded")
        #expect(name("{frame}{roll}-{date}", configure: frame) == "07-2026-11-12.tif")
        #expect(name("X1 - {roll} - {frame}", configure: frame) == "X1 - 07.tif", "a spaced separator goes whole")
        #expect(name("{roll} - {frame}", configure: frame) == "07.tif")
        #expect(name("{roll}{roll}") == "X1-preview-2026-11-12-001.tif", "two empty rolls: default template")
        #expect(name("A-{roll}-{roll}-B") == "A-B.tif", "every occurrence")
        #expect(name("X1-{roll}-{frame}", configure: { $0.frame = 7; $0.roll = "  " }) == "X1-07.tif",
                "spaces only: empty")
        #expect(name("X1-{roll}-{frame}", configure: { $0.frame = 7; $0.roll = "R1" }) == "X1-R1-07.tif",
                "a roll name keeps both separators")
        #expect(name("{roll}", taken: []) == "X1-preview-2026-11-12-001.tif", "nothing left: default template")
        #expect(ExportToken.roll.removed(from: "X1-{roll}-{frame}") == "X1-{frame}")
        #expect(ExportToken.frame.removed(from: "{roll}") == "{roll}", "other tokens untouched")
    }

    @Test func settingsKeepTheirLimits() {
        var settings = ExportSettings()
        settings.frame = 0
        #expect(settings.frame == 1)
        settings.counterDigits = 9
        #expect(settings.counterDigits == 6)
        settings.counterDigits = 0
        #expect(settings.counterDigits == 1)
        settings.counterStart = -3
        #expect(settings.counterStart == 0)
        #expect(ExportToken.allCases.map(\.placeholder) == ["{roll}", "{frame}", "{date}", "{time}", "{n}"])
    }

    @Test func templateIsSanitised() {
        #expect(name(" a/b:c {n} ") == "a-b-c 001.tif")
        #expect(name("  ") == "X1-preview-2026-11-12-001.tif", "empty: default template")
        #expect(name("..") == "X1-preview-2026-11-12-001.tif")
        #expect(ExportService.sanitizedFileName("..") == nil)
    }

    @Test func nextFileNameLooksInTheFolder() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = ExportSettings(folder: folder, nameTemplate: "Test-{n}")
        #expect(ExportService.nextFileName(settings: settings) == "Test-001.tif")
        try Data().write(to: folder.appending(path: "Test-001.tif"))
        #expect(ExportService.nextFileName(settings: settings) == "Test-002.tif")
        #expect(ExportService.nextFileName(settings: ExportSettings(nameTemplate: "Test-{n}")) == "Test-001.tif",
                "no folder yet")
    }

    @Test func step2SettingsKeepTheirBaseName() throws {
        let json = #"{"baseName":"Studio"}"#
        let settings = try JSONDecoder().decode(ExportSettings.self, from: Data(json.utf8))
        #expect(settings.nameTemplate == "Studio-{date}-{n}" && settings.folder == nil)
        let roundTrip = try JSONDecoder().decode(ExportSettings.self, from: JSONEncoder().encode(settings))
        #expect(roundTrip == settings)
        let heure = try JSONDecoder().decode(ExportSettings.self, from: Data(#"{"nameTemplate":"S-{heure}-{n}"}"#.utf8))
        #expect(heure.nameTemplate == "S-{time}-{n}", "step 2b French token stored in English")
        #expect(heure.frame == 1 && heure.incrementsFrame && heure.counterStart == 1 && heure.counterDigits == 3)
        var full = ExportSettings(nameTemplate: "{roll}")
        full.roll = "R9"
        full.frame = 4
        full.incrementsFrame = false
        full.counterStart = 10
        full.counterDigits = 2
        #expect(try JSONDecoder().decode(ExportSettings.self, from: JSONEncoder().encode(full)) == full)
        for blank in [#"{"baseName":""}"#, #"{"baseName":"  "}"#] {
            let decoded = try JSONDecoder().decode(ExportSettings.self, from: Data(blank.utf8))
            #expect(decoded.nameTemplate == ExportSettings.defaultTemplate, "empty base: default name, as in step 2")
        }
    }

    @Test func writesA16BitTIFFAndNeverOverwrites() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = PreviewImage(width: 2, corrected: Array(repeating: 40_000, count: 12),
                                 raw: Array(repeating: 1, count: 12))
        let settings = ExportSettings(folder: folder)
        let first = try ExportService.export(image, settings: settings, date: date)
        let second = try ExportService.export(image, settings: settings, date: date)
        #expect(first != second)
        let source = try #require(CGImageSourceCreateWithURL(first as CFURL, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 2 && decoded.height == 2 && decoded.bitsPerComponent == 16)
    }

    @Test func refusesWithoutFolderOrImage() throws {
        let image = PreviewImage(width: 1, corrected: [1, 2, 3], raw: [1, 2, 3])
        #expect(throws: ExportError.noFolder) { try ExportService.export(image, settings: ExportSettings()) }
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(throws: ExportError.noImage) {
            try ExportService.export(PreviewImage(width: 1, expectedHeight: 3), settings: ExportSettings(folder: folder))
        }
        let missing = folder.appending(path: "missing")
        #expect(throws: ExportError.folderMissing(missing.path)) {
            try ExportService.export(image, settings: ExportSettings(folder: missing))
        }
    }
}

@MainActor
final class AppModelTests {
    private var suites: [String] = []

    deinit {
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    }

    private func temporaryDefaults() -> UserDefaults {
        let suite = "X1ScanCoreTests-\(UUID().uuidString)"
        suites.append(suite)
        return UserDefaults(suiteName: suite)!
    }

    private static let failingInspector = ScannerInspector {
        FakeConnection(responses: [:], openError: TransportError.deviceBusy)
    }

    private func model(defaults: UserDefaults? = nil, pacing: Pacing = .none) -> AppModel {
        let defaults = defaults ?? temporaryDefaults()
        return AppModel(virtualScanner: { try TestFixtures.scanner(pacing: pacing) },
                 inspector: Self.failingInspector,
                 defaults: defaults)
    }

    @Test func virtualByDefaultAndPreviewRuns() async {
        let model = model()
        #expect(model.source == .virtual && model.toolbar.canPreview)
        #expect(model.scannerInfo?.model == "Flextight X1")
        model.startPreview()
        await model.session.waitUntilIdle()
        #expect(model.session.state == .finished)
        model.viewSizeChanged(CGSize(width: 800, height: 600))
        model.refreshImage()
        await model.waitForRendering()
        #expect(model.displayImage?.width == 2004)
        #expect(model.histogram.pixelCount == 2004 * 817)
        #expect(model.viewport.imageHeight == 817 && model.viewport.mode == .fit)
        // A crop: the histogram counts its pixels only; removing it counts the whole image again.
        model.cropRect = PixelRect(x: 100, y: 50, width: 300, height: 200)
        await model.waitForRendering()
        #expect(model.histogram.pixelCount == 300 * 200)
        model.cropRect = nil
        await model.waitForRendering()
        #expect(model.histogram.pixelCount == 2004 * 817)
        // A click with the crop tool (1 × 1): the histogram stays on the whole image.
        model.cropRect = PixelRect(x: 10, y: 10, width: 1, height: 1)
        await model.waitForRendering()
        #expect(model.histogram.pixelCount == 2004 * 817)
        model.pointer = PixelCoordinate(x: 100, y: 100)
        #expect(model.pixelReading?.corrected.count == 3)
    }

    private func model(pausedAt index: Int, gate: PreviewGate) -> AppModel {
        AppModel(virtualScanner: { try TestFixtures.scanner(pausedAt: index, gate: gate) },
                 inspector: Self.failingInspector, defaults: temporaryDefaults())
    }

    /// While a preview runs, every new slice keeps the histogram of the crop
    /// (refreshImage computes it for the current crop), clipped to the rows received.
    @Test func histogramFollowsTheCropWhilePreviewing() async throws {
        let gate = PreviewGate()
        let model = model(pausedAt: TestFixtures.scanIndex + 20, gate: gate)
        model.startPreview()
        await gate.waitUntilPaused()
        // The session receives the reads asynchronously: wait until the first rows are published.
        for _ in 0..<10_000 where model.session.image == nil { await Task.yield() }
        model.viewSizeChanged(CGSize(width: 800, height: 600))
        model.refreshImage()
        await model.waitForRendering()
        let rows = try #require(model.session.image).height
        #expect(rows > 0 && rows < 817, "part of the image received")
        // Taller than the image received so far: clipped to the rows received.
        model.cropRect = PixelRect(x: 100, y: 0, width: 300, height: 817)
        await model.waitForRendering()
        #expect(model.histogram.pixelCount == 300 * rows)
        await gate.release()
        await model.session.waitUntilIdle()
        model.refreshImage()  // a new revision: the render path, not the crop change
        await model.waitForRendering()
        #expect(model.cropRect == PixelRect(x: 100, y: 0, width: 300, height: 817), "same image size: crop kept")
        #expect(model.histogram.pixelCount == 300 * 817)
    }

    @Test func realSourceBlocksThePreviewAndStopsARunningOne() async throws {
        let gate = PreviewGate()
        let model = model(pausedAt: 3, gate: gate)
        model.startPreview()
        await gate.waitUntilPaused()
        model.source = .real
        await gate.release()
        #expect(model.session.state == .stopping)
        await model.session.waitUntilIdle()
        #expect(model.session.state == .stopped(nil))
        #expect(!model.toolbar.canPreview)
        model.startPreview()
        #expect(model.session.state == .stopped(nil), "nothing started")
        #expect(model.scannerInfo == nil)
    }

    /// Quitting during the scan waits for the stop sequence.
    @Test func stopAndWaitReturnsOnceTheStopSequenceIsOver() async throws {
        let gate = PreviewGate()
        let model = model(pausedAt: TestFixtures.scanIndex + 10, gate: gate)
        model.startPreview()
        await gate.waitUntilPaused()
        #expect(model.isBusy)
        let stopping = Task { await model.stopAndWait() }
        while model.session.state != .stopping { await Task.yield() }  // stop requested before the release
        await gate.release()
        await stopping.value
        #expect(!model.isBusy)
        #expect(model.session.state == .stopped(.stoppedAndReady))
        // Called again while idle: returns at once.
        await model.stopAndWait()
    }

    @Test func realScannerReadFailureIsReported() async {
        let model = model()
        await model.readRealScanner()
        #expect(model.realStatus == .notRead, "only in real mode")
        model.source = .real
        await model.readRealScanner()
        #expect(model.realStatus == .failed(.transport(.deviceBusy)))
    }

    @Test func settingsPersist() {
        let defaults = temporaryDefaults()
        let first = model(defaults: defaults)
        first.source = .real
        first.exportSettings.nameTemplate = "Test-{n}"
        #expect(first.settings.hidesSerialNumber, "masked by default")
        first.settings.hidesSerialNumber = false
        let second = model(defaults: defaults)
        #expect(second.source == .real && second.exportSettings.nameTemplate == "Test-{n}")
        #expect(!second.settings.hidesSerialNumber)
    }

    @Test func startupSourceAndZoomFollowTheSettings() {
        let defaults = temporaryDefaults()
        let first = model(defaults: defaults)
        first.source = .real
        first.settings.startupSource = .virtual
        first.settings.startupZoom = .actualSize
        let second = model(defaults: defaults)
        #expect(second.source == .virtual)
        #expect(second.viewport.mode == .fixed && second.viewport.magnification == 1)
        second.settings.startupSource = .real
        #expect(model(defaults: defaults).source == .real, "never read at launch")
        #expect(model(defaults: defaults).realStatus == .notRead)
        second.settings.startupSource = .last
        #expect(model(defaults: defaults).source == .real, "the last source chosen in the interface")
        let third = model(defaults: defaults)
        third.source = .virtual
        #expect(model(defaults: defaults).source == .virtual)
    }

    /// A source imposed at launch (startup setting, or the -StartupSource
    /// argument, which UserDefaults reads the same way) is never remembered as
    /// the last chosen one; only a choice made in the interface is.
    @Test func aSourceImposedAtLaunchIsNotRemembered() {
        let defaults = temporaryDefaults()
        let first = model(defaults: defaults)
        first.source = .real  // chosen in the interface
        #expect(defaults.string(forKey: "ScannerSource") == "real")
        first.settings.startupSource = .virtual
        let imposed = model(defaults: defaults)  // e.g. tools/run-virtual.sh
        #expect(imposed.source == .virtual)
        #expect(defaults.string(forKey: "ScannerSource") == "real", "launching on an imposed source saves nothing")
        imposed.settings.startupSource = .last
        #expect(model(defaults: defaults).source == .real, "back to the source chosen in the interface")
    }

    @Test func firstLaunchWithLastSourceStartsVirtualAndSavesNothing() {
        let defaults = temporaryDefaults()
        let model = model(defaults: defaults)
        #expect(model.source == .virtual)
        #expect(defaults.string(forKey: "ScannerSource") == nil)
    }

    /// Every new preview gets the zoom of Settings > Display, whatever the
    /// viewport held before.
    @Test func everyPreviewGetsTheStartupZoom() async {
        let fit = model()
        fit.viewSizeChanged(CGSize(width: 1032, height: 832))
        fit.zoomToActualSize()
        fit.startPreview()
        await fit.session.waitUntilIdle()
        fit.refreshImage()
        #expect(fit.viewport.mode == .fit && abs(fit.viewport.magnification - 800.0 / 2451) < 1e-9)
        fit.zoom(to: 2)
        let crop = PixelRect(x: 10, y: 20, width: 300, height: 200)
        fit.cropRect = crop
        let firstRevision = fit.session.imageRevision
        fit.startPreview()
        await fit.session.waitUntilIdle()
        // Same fixture, so the same final revision: rendered only because startPreview reset it.
        #expect(fit.session.imageRevision == firstRevision)
        fit.refreshImage()
        #expect(fit.viewport.mode == .fit && abs(fit.viewport.magnification - 800.0 / 2451) < 1e-9,
                "a later preview is fitted again")
        #expect(fit.cropRect == crop, "same image size: the crop rectangle is kept")

        let defaults = temporaryDefaults()
        model(defaults: defaults).settings.startupZoom = .actualSize
        let actual = model(defaults: defaults)
        actual.zoomToFit()
        actual.startPreview()
        await actual.session.waitUntilIdle()
        actual.refreshImage()
        #expect(actual.viewport.mode == .fixed && actual.viewport.magnification == 1)
        actual.zoomToFit()
        actual.startPreview()
        await actual.session.waitUntilIdle()
        actual.refreshImage()
        #expect(actual.viewport.mode == .fixed && actual.viewport.magnification == 1, "100 % again")
    }

    @Test func statusLineNamesTheSourceAndItsState() async {
        let model = model()
        #expect(model.statusLine == ScannerStatusLine(source: .virtual, detail: .session))
        model.source = .real
        #expect(model.statusLine == ScannerStatusLine(source: .real, detail: .notRead))
        await model.readRealScanner()
        #expect(model.statusLine == ScannerStatusLine(source: .real, detail: .failed))
        let unavailable = AppModel(virtualScanner: { throw TimeoutError() }, inspector: Self.failingInspector,
                                   defaults: temporaryDefaults())
        #expect(unavailable.statusLine == ScannerStatusLine(source: .virtual, detail: .unavailable))
    }

    @Test func zoomCommandsAndTypedValues() {
        let model = model()
        model.viewSizeChanged(CGSize(width: 800, height: 600))
        model.zoomToActualSize()
        model.zoomIn()
        #expect(model.viewport.magnification == 2)
        #expect(model.zoom(typed: "12,5 %") && model.viewport.magnification == 0.125)
        #expect(!model.zoom(typed: "abc") && model.viewport.magnification == 0.125, "invalid: unchanged")
        model.zoomToFill()
        #expect(model.viewport.mode == .fill)
        model.zoom(to: 1.0 / 3)
        #expect(model.viewport.currentStep == 1.0 / 3)
        model.zoomToFit()
        #expect(model.viewport.mode == .fit)
    }

    /// The written name is computed at export time ({date}, {time}, {n}),
    /// not taken from the "Next file" shown earlier in the panel.
    @Test func exportNameIsComputedWhenExporting() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = model()
        model.startPreview()
        await model.session.waitUntilIdle()
        model.exportSettings = ExportSettings(folder: folder, nameTemplate: "{date}_{time}_{n}")
        let shownAt = Date(timeIntervalSince1970: 1_794_441_600)  // 2026-11-12 00:00 UTC
        let exportedAt = shownAt.addingTimeInterval(2 * 86_400 + 3_723)  // two days, 1 h 2 min 3 s later
        let shown = model.nextExportFileName(date: shownAt)

        func expected(_ date: Date, _ number: String) -> String {
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            return String(format: "%04d-%02d-%02d_%02d-%02d-%02d_%@.tif", parts.year!, parts.month!, parts.day!,
                          parts.hour!, parts.minute!, parts.second!, number)
        }
        let first = try model.export(date: exportedAt).get()
        #expect(first.lastPathComponent == expected(exportedAt, "001"))
        #expect(first.lastPathComponent != shown)
        // A file that appears after the name was shown moves {n} on at export time.
        try Data().write(to: folder.appending(path: expected(exportedAt.addingTimeInterval(60), "001")))
        let second = try model.export(date: exportedAt.addingTimeInterval(60)).get()
        #expect(second.lastPathComponent == expected(exportedAt.addingTimeInterval(60), "002"))
        #expect(model.nextExportFileName(date: exportedAt.addingTimeInterval(60))
            == expected(exportedAt.addingTimeInterval(60), "003"))
    }

    @Test func frameMovesOnAfterEachExport() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = model()
        model.startPreview()
        await model.session.waitUntilIdle()
        model.exportSettings = ExportSettings(folder: folder, nameTemplate: "{roll}_{frame}")
        model.exportSettings.roll = "R1"
        #expect(try model.export().get().lastPathComponent == "R1_01.tif")
        #expect(try model.export().get().lastPathComponent == "R1_02.tif")
        #expect(model.exportSettings.frame == 3)
        model.exportSettings.incrementsFrame = false
        #expect(try model.export().get().lastPathComponent == "R1_03.tif")
        #expect(model.exportSettings.frame == 3, "not incremented")
        model.exportSettings.folder = folder.appending(path: "missing")
        _ = model.export()
        #expect(model.exportSettings.frame == 3, "a failed export does not move the frame on")
    }

    @Test func missingFixturesDisableTheVirtualScanner() {
        let model = AppModel(virtualScanner: { throw TimeoutError() }, inspector: Self.failingInspector,
                             defaults: temporaryDefaults())
        #expect(model.virtualScannerError != nil)
        #expect(model.toolbar.previewBlock == .virtualScannerUnavailable)
    }
}

@MainActor
struct AppSettingsTests {
    @Test func defaultsAndPersistence() {
        withTemporaryDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            #expect(settings.language == .system && settings.hidesSerialNumber && settings.appearance == .system)
            #expect(settings.canvasBackground == .neutralGray && settings.startupZoom == .fit)
            #expect(settings.startupSource == .last)
            settings.appearance = .dark
            settings.canvasBackground = .black
            settings.startupZoom = .actualSize
            let reloaded = AppSettings(defaults: defaults)
            #expect(reloaded.appearance == .dark && reloaded.canvasBackground == .black)
            #expect(reloaded.startupZoom == .actualSize)
        }
    }

    @Test func languageWritesTheAppsAppleLanguages() {
        withTemporaryDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.language = .french
            #expect(defaults.stringArray(forKey: "AppleLanguages") == ["fr"])
            settings.language = .english
            #expect(defaults.stringArray(forKey: "AppleLanguages") == ["en"])
            settings.language = .system
            // Back to the global value, as seen by a suite that never set it.
            let global = UserDefaults(suiteName: "X1ScanCoreTests-untouched")?.stringArray(forKey: "AppleLanguages")
            #expect(defaults.stringArray(forKey: "AppleLanguages") == global)
            #expect(AppSettings(defaults: defaults).language == .system)
        }
    }

    @Test func serialMaskingFollowsTheSetting() {
        withTemporaryDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            #expect(settings.displayedSerial("FX1xxxxxxx") == "FX1•••••••")
            settings.hidesSerialNumber = false
            #expect(settings.displayedSerial("FX1xxxxxxx") == "FX1xxxxxxx")
        }
    }

    @Test func neutralGrayIsMiddleGray() {
        #expect(CanvasBackground.neutralGray.color == SRGBColor(red: 119.0 / 255, green: 119.0 / 255, blue: 119.0 / 255))
    }

    @Test func customBackgroundIsSavedAndCanGoBackToGray() {
        withTemporaryDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.canvasBackground = .custom(SRGBColor(red: 0.25, green: 0.5, blue: 2))
            let reloaded = AppSettings(defaults: defaults)
            #expect(reloaded.canvasBackground == .custom(SRGBColor(red: 0.25, green: 0.5, blue: 1)), "clamped")
            reloaded.canvasBackground = .neutralGray
            #expect(AppSettings(defaults: defaults).canvasBackground == .neutralGray)
            defaults.set("custom:1,2", forKey: "CanvasBackground")
            #expect(AppSettings(defaults: defaults).canvasBackground == .neutralGray, "garbage: default")
        }
    }
}

struct ExportLimitsTests {
    @Test func frameAndCounterAreBoundedAndPaddedWithoutOverflow() throws {
        var settings = ExportSettings(nameTemplate: "{roll}_{frame}_{n}")
        settings.frame = Int.max
        #expect(settings.frame == ExportSettings.frameRange.upperBound)
        settings.counterStart = Int.max
        #expect(settings.counterStart == ExportSettings.counterStartRange.upperBound)
        settings.counterDigits = 6
        settings.roll = "R{date}"
        settings.frame = 99_999
        settings.counterStart = 999_999
        let name = ExportService.fileName(settings: settings, date: Date(timeIntervalSince1970: 0)) { _ in false }
        #expect(name == "R{date}_99999_999999.tif", "roll kept as typed; numbers not truncated")
        let json = #"{"frame":9223372036854775807,"counterStart":-5}"#
        let decoded = try JSONDecoder().decode(ExportSettings.self, from: Data(json.utf8))
        #expect(decoded.frame == 99_999 && decoded.counterStart == 0)
    }
}

struct RollValidationTests {
    /// Passing to another roll puts the frame back to 1, once the name is
    /// validated; typing, or validating the same name, does not.
    @Test func frameResetsOnlyWhenAnotherRollIsValidated() throws {
        var settings = ExportSettings()
        settings.roll = "R1"
        settings.validateRoll()
        settings.frame = 12
        settings.roll = "R"   // typing a correction, letter by letter
        settings.roll = "R1 "
        settings.roll = "R1"
        #expect(settings.frame == 12, "typing alone changes nothing")
        settings.validateRoll()
        #expect(settings.frame == 12, "same name validated: unchanged")
        settings.roll = "R2"
        #expect(settings.frame == 12, "not validated yet")
        settings.validateRoll()
        #expect(settings.frame == 1 && settings.validatedRoll == "R2", "another roll: frame 1")
        settings.frame = 4
        settings.validateRoll()
        #expect(settings.frame == 4, "validated twice: unchanged")

        // Saved and read back; older settings take their roll as validated.
        let decoded = try JSONDecoder().decode(ExportSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        var older = try JSONDecoder().decode(ExportSettings.self, from: Data(#"{"roll":"R7","frame":9}"#.utf8))
        older.validateRoll()
        #expect(older.frame == 9)
    }

    @MainActor
    @Test func exportingRightAfterTypingValidatesTheRoll() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = AppModel(virtualScanner: { try TestFixtures.scanner() }, inspector: ScannerInspector {
            FakeConnection(responses: [:], openError: TransportError.deviceBusy)
        }, defaults: UserDefaults(suiteName: "X1ScanCoreTests-\(UUID().uuidString)")!)
        model.startPreview()
        await model.session.waitUntilIdle()
        model.exportSettings = ExportSettings(folder: folder, nameTemplate: "{roll}_{frame}")
        model.exportSettings.roll = "A"
        model.exportSettings.validateRoll()
        model.exportSettings.frame = 5
        model.exportSettings.roll = "B"   // typed, then Export clicked at once
        #expect(model.nextExportFileName() == "B_01.tif", "the preview shows what the export will write")
        #expect(try model.export().get().lastPathComponent == "B_01.tif")
        #expect(model.exportSettings.frame == 2)

        // A roll already started: name typed, frame set by hand without leaving the roll field.
        model.exportSettings.roll = "C"
        model.exportSettings.setFrame(5)
        #expect(model.nextExportFileName() == "C_05.tif")
        #expect(try model.export().get().lastPathComponent == "C_05.tif", "the frame chosen is kept")
    }
}
