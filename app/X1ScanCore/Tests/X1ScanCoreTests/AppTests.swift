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

    private func name(_ template: String, taken: Set<String> = []) -> String {
        ExportService.fileName(template: template, date: date.addingTimeInterval(13 * 3600 + 5 * 60 + 9),
                               calendar: utc) { taken.contains($0) }
    }

    @Test func templateTokensAndCounter() {
        let taken: Set = ["X1-preview-2026-11-12-001.tif", "X1-preview-2026-11-12-002.tif"]
        #expect(name(ExportSettings.defaultTemplate, taken: taken) == "X1-preview-2026-11-12-003.tif")
        #expect(name("{date}_{heure}_{n}") == "2026-11-12_13-05-09_001.tif")
        #expect(name("{time}") == "13-05-09.tif", "English token")
        #expect(name("Scan") == "Scan.tif")
        #expect(name("Scan", taken: ["Scan.tif", "Scan-002.tif"]) == "Scan-003.tif", "no {n}: added when needed")
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
                 layoutStore: InMemoryLayoutStore(), defaults: defaults)
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
        model.pointer = PixelCoordinate(x: 100, y: 100)
        #expect(model.pixelReading?.corrected.count == 3)
    }

    @Test func realSourceBlocksThePreviewAndStopsARunningOne() async throws {
        let model = model(pacing: TestFixtures.slow)
        model.startPreview()
        try await waitUntil { model.session.progress.stepIndex > 2 }
        model.source = .real
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
        let model = model(pacing: TestFixtures.slow)
        model.startPreview()
        try await waitUntil { (model.session.image?.height ?? 0) > 0 }
        #expect(model.isBusy)
        await model.stopAndWait()
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
        second.source = .virtual
        second.settings.startupSource = .real
        #expect(model(defaults: defaults).source == .real, "never read at launch")
        #expect(model(defaults: defaults).realStatus == .notRead)
        second.settings.startupSource = .last
        #expect(model(defaults: defaults).source == .real, "the source of the last session")
        let third = model(defaults: defaults)
        third.source = .virtual
        #expect(model(defaults: defaults).source == .virtual)
    }

    @Test func statusLineNamesTheSourceAndItsState() async {
        let model = model()
        #expect(model.statusLine == ScannerStatusLine(source: .virtual, detail: .session))
        model.source = .real
        #expect(model.statusLine == ScannerStatusLine(source: .real, detail: .notRead))
        await model.readRealScanner()
        #expect(model.statusLine == ScannerStatusLine(source: .real, detail: .failed))
        let unavailable = AppModel(virtualScanner: { throw TimeoutError() }, inspector: Self.failingInspector,
                                   layoutStore: InMemoryLayoutStore(), defaults: temporaryDefaults())
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

    @Test func missingFixturesDisableTheVirtualScanner() {
        let model = AppModel(virtualScanner: { throw TimeoutError() }, inspector: Self.failingInspector,
                             layoutStore: InMemoryLayoutStore(), defaults: temporaryDefaults())
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
        #expect(CanvasBackground.neutralGray.srgbLevel == 119.0 / 255)
    }
}
