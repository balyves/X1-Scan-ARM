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

    @Test func fileNameCountsUpAndIsSanitised() {
        let taken: Set = ["X1-preview-2026-11-12-001.tif", "X1-preview-2026-11-12-002.tif"]
        #expect(ExportService.fileName(base: "X1-preview", date: date, calendar: utc) { taken.contains($0) }
            == "X1-preview-2026-11-12-003.tif")
        #expect(ExportService.sanitizedBaseName(" a/b:c ") == "a-b-c")
        #expect(ExportService.sanitizedBaseName("  ") == ExportSettings.defaultBaseName)
        #expect(ExportService.sanitizedBaseName("..") == ExportSettings.defaultBaseName)
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
        #expect(model.viewport.imageHeight == 817 && model.viewport.fitsWindow)
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

    @Test func settingsPersistButNotTheRevealedSerial() {
        let defaults = temporaryDefaults()
        let first = model(defaults: defaults)
        first.source = .real
        first.exportSettings.baseName = "Test"
        first.serialRevealed = true
        let second = model(defaults: defaults)
        #expect(second.source == .real && second.exportSettings.baseName == "Test")
        #expect(!second.serialRevealed)
    }

    @Test func missingFixturesDisableTheVirtualScanner() {
        let model = AppModel(virtualScanner: { throw TimeoutError() }, inspector: Self.failingInspector,
                             layoutStore: InMemoryLayoutStore(), defaults: temporaryDefaults())
        #expect(model.virtualScannerError != nil)
        #expect(model.toolbar.previewBlock == .virtualScannerUnavailable)
    }
}
