// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import ImageIO
import Testing
import X1Preview
import X1Transport
@testable import X1ScanCore

/// Lot A, step C: discovery mode. The virtual X1 only; no transport to a
/// real X1 is ever opened, even with the hidden settings on and a scanner
/// connected; leaving the mode looks for the scanner again.
@MainActor
@Suite(.serialized)
final class DiscoveryTests {
    private var suites: [String] = []
    deinit { for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) } }

    /// Counts every way to the real X1: the captured-sequence transport, the
    /// read-only inspector and the presence check.
    final class Spy: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [String: Int] = [:]
        var present = true
        /// The invented registry: without controllers (no adapter) unless set.
        var controllers: [FireWireController] = []
        func hit(_ name: String) { lock.withLock { counts[name, default: 0] += 1 } }
        func count(_ name: String) -> Int { lock.withLock { counts[name, default: 0] } }
        var realAccesses: Int { count("connection") + count("inspector") }
    }

    private func model(source: StartupSource = .real, spy: Spy, folder: URL? = nil) throws -> AppModel {
        let suite = "X1ScanCoreTests-\(UUID().uuidString)"
        suites.append(suite)
        let defaults = UserDefaults(suiteName: suite)!
        // Everything that could reach the real X1 is on.
        defaults.set(true, forKey: "EnableRealPreview")
        defaults.set(true, forKey: "EnableRealScan")
        defaults.set(source.rawValue, forKey: "StartupSource")
        let scanner = try TestFixtures.scanner()
        let model = AppModel(virtualScanner: { scanner }, inspector: ScannerInspector {
            spy.hit("inspector")
            return FakeConnection(responses: [:], openError: TransportError.deviceBusy)
        }, defaults: defaults, realConnection: { _ in
            spy.hit("connection")
            return FakeConnection(responses: [:], openError: TransportError.deviceBusy)
        }, captureFolder: try temporaryDirectory(), presence: {
            spy.hit("presence")
            return spy.present
        }, installation: {
            // Invented: never this Mac's registry in tests.
            InstallationSnapshot(system: .init(major: 26, minor: 1, patch: 0), controllers: spy.controllers, scannerDescription: nil)
        })
        if let folder { model.exportSettings.folder = folder }
        return model
    }

    private let allPreview = RealPreviewConfirmation(scannerOn: true, holderInPlace: true, flexColorClosed: true,
                                                     powerCycledSinceLastRealPreview: true)
    private let allScan = RealScanConfirmation(sameHolderNothingMoved: true, captureFrameUnderstood: true)

    /// In discovery mode nothing reaches a real X1, whatever is called.
    @Test func noTransportToARealX1InDiscoveryMode() async throws {
        let spy = Spy()
        let model = try model(spy: spy)
        #expect(model.source == .real)
        model.enterDiscovery(sampleSuffix: "_sample")
        #expect(model.discoveryMode && model.source == .virtual)
        // Every action that reaches the real X1 elsewhere.
        model.source = .real
        #expect(model.source == .virtual, "the source stays virtual in discovery mode")
        #expect(model.startRealPreview(allPreview) == .failure(.notAllowed))
        #expect(model.startRealScan(allScan) == .failure(.notAllowed))
        await model.readRealScanner()
        await model.detectScanner()
        #expect(spy.realAccesses == 0, "no transport opened, no read")
        #expect(spy.count("presence") == 0, "not even the presence check")
        // Preview and scan run on the virtual X1.
        model.startPreview()
        await model.session.waitUntilIdle()
        #expect(model.session.state == .finished)
        #expect(spy.realAccesses == 0)
    }

    /// A model whose real X1 is simulated behind the guards (as in ScanTests),
    /// counting every connection, read and presence check.
    private func guardedModel(spy: Spy, gate: DispatchSemaphore? = nil) throws -> AppModel {
        let suite = "X1ScanCoreTests-\(UUID().uuidString)"
        suites.append(suite)
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "EnableRealPreview")
        defaults.set(true, forKey: "EnableRealScan")
        defaults.set(StartupSource.real.rawValue, forKey: "StartupSource")
        let scanner = try TestFixtures.scanner()
        let model = AppModel(virtualScanner: { scanner }, inspector: ScannerInspector {
            spy.hit("inspector")
            return FakeConnection(responses: [:], openError: TransportError.deviceBusy)
        }, defaults: defaults, realConnection: { sequence in
            if sequence.expected.contains(where: { $0.cdb == [0x1B, 0x00, 0x08, 0x06, 0x01, 0x00] }) {
                spy.hit("scan")
                return GuardedScanConnection(sequence: sequence, scanner: scanner)
            }
            spy.hit("preview")
            return GuardedSimulatedConnection(sequence: sequence, scanner: scanner)
        }, captureFolder: try temporaryDirectory(), presence: {
            spy.hit("presence")
            gate?.wait()
            return spy.present
        })
        model.exportSettings = ExportSettings(folder: try temporaryDirectory(), nameTemplate: "Scan-{n}")
        return model
    }

    /// Each `!discoveryMode` guard alone: the real source, every hidden setting
    /// and every check on, so that discovery mode is the only thing that
    /// refuses; and the same call, discovery mode off, does reach the
    /// (simulated) real X1, which shows the guard is what stopped it.
    @Test func eachDiscoveryGuardAlone() async throws {
        let spy = Spy()
        let model = try guardedModel(spy: spy)
        #expect(model.source == .real)

        // detectScanner, first guard.
        model.setDiscoveryModeKeepingSourceForTesting(true)
        #expect(model.discoveryMode && model.source == .real)
        await model.detectScanner()
        #expect(spy.count("presence") == 0 && model.detection == .notChecked)
        model.setDiscoveryModeKeepingSourceForTesting(false)
        await model.detectScanner()
        #expect(spy.count("presence") == 1 && model.detection == .found)

        // readRealScanner.
        model.setDiscoveryModeKeepingSourceForTesting(true)
        await model.readRealScanner()
        #expect(spy.count("inspector") == 0 && model.realStatus == .notRead)
        model.setDiscoveryModeKeepingSourceForTesting(false)
        await model.readRealScanner()
        #expect(spy.count("inspector") == 1)

        // startRealPreview.
        model.setDiscoveryModeKeepingSourceForTesting(true)
        #expect(model.startRealPreview(allPreview) == .failure(.notAllowed))
        #expect(spy.count("preview") == 0)
        model.setDiscoveryModeKeepingSourceForTesting(false)
        _ = try model.startRealPreview(allPreview).get()
        await model.session.waitUntilIdle()
        #expect(spy.count("preview") == 1 && model.session.state == .finished)
        #expect(model.toolbar.canScan, "a complete real preview: only discovery mode can refuse the scan now")

        // startRealScan.
        model.setDiscoveryModeKeepingSourceForTesting(true)
        #expect(model.startRealScan(allScan) == .failure(.notAllowed))
        #expect(spy.count("scan") == 0)
        model.setDiscoveryModeKeepingSourceForTesting(false)
        _ = try model.startRealScan(allScan).get()
        await model.session.waitUntilIdle()
        #expect(spy.count("scan") == 1 && model.session.state == .finished)
    }

    /// detectScanner's second guard: discovery mode entered while the
    /// presence check runs; its result does not apply.
    @Test func presenceResultIgnoredWhenDiscoveryStartsMeanwhile() async throws {
        for enterMeanwhile in [true, false] {
            let spy = Spy()
            let gate = DispatchSemaphore(value: 0)
            let model = try guardedModel(spy: spy, gate: gate)
            defer { gate.signal() }  // never leaves the check waiting, even if a wait below throws
            let check = Task { await model.detectScanner() }
            try await waitUntil { spy.count("presence") == 1 }
            #expect(model.detection == .checking)
            if enterMeanwhile { model.setDiscoveryModeKeepingSourceForTesting(true) }
            gate.signal()
            await check.value
            let expected: AppModel.Detection = enterMeanwhile ? .notChecked : .found
            #expect(model.detection == expected)
        }
    }

    /// The source of before comes back, without being saved; the real X1 is looked for again.
    @Test func leavingLooksForTheScannerAgain() async throws {
        let spy = Spy()
        spy.present = false
        let model = try model(spy: spy)
        await model.detectScanner()
        #expect(model.detection == .notFound && spy.count("presence") == 1)
        model.enterDiscovery(sampleSuffix: "_sample")
        #expect(model.detection == .notChecked)
        spy.present = true
        model.leaveDiscovery()
        #expect(!model.discoveryMode && model.source == .real)
        try await waitUntil { model.detection == .found }
        #expect(spy.count("presence") == 2)
        #expect(spy.realAccesses == 0, "the presence check opens nothing")
    }

    /// Leaving discovery mode without an X1 gives what the launch gives
    /// (user's decision of 2026-11-26), from the registry read again: no
    /// adapter at launch (the installation check), then adapter and driver
    /// plugged in during discovery mode (the alert).
    @Test func leavingWithoutAnX1PresentsAsAtLaunch() async throws {
        let spy = Spy()
        spy.present = false
        let model = try model(spy: spy)
        await model.detectScanner()
        #expect(model.detection == .notFound && model.launchPresentation == .assistant)
        model.enterDiscovery(sampleSuffix: "_sample")
        let driver: Driver = Driver(className: "IOUserService", userClass: "ExampleDriver")
        spy.controllers = [FireWireController(drivers: [driver])]
        model.leaveDiscovery()
        try await waitUntil { model.detection == .notFound }
        #expect(model.launchPresentation == .noScannerAlert)
        #expect(spy.count("presence") == 2)
        #expect(spy.realAccesses == 0, "the presence check opens nothing")
    }

    /// The presence check runs only for the real source, outside discovery mode.
    @Test func noPresenceCheckOnTheVirtualSource() async throws {
        let spy = Spy()
        let model = try model(source: .virtual, spy: spy)
        await model.detectScanner()
        #expect(spy.count("presence") == 0 && model.detection == .notChecked)
    }

    /// Entering and leaving never change the saved "last chosen" source.
    @Test func theSavedSourceIsKept() throws {
        let spy = Spy()
        let model = try model(source: .last, spy: spy)
        model.source = .real  // chosen in the interface: saved
        model.enterDiscovery(sampleSuffix: "_sample")
        let saved = UserDefaults(suiteName: suites.last!)!.string(forKey: "ScannerSource")
        #expect(saved == ScannerSourceKind.real.rawValue)
        model.leaveDiscovery()
        #expect(UserDefaults(suiteName: suites.last!)!.string(forKey: "ScannerSource") == ScannerSourceKind.real.rawValue)
    }

    /// The place of the future photograph: a film read from an image, and no image in the repository yet.
    @Test func sampleFilmComesFromAnImage() throws {
        // 2 × 1: black, then white (sRGB), made here; no photograph in the repository.
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 8, space: space,
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
        let image = try #require(context.makeImage())
        let film = try #require(SampleFilm.film(from: image))
        let dark: Double = film.transmission(row: 0, column: 0, channel: 1, width: 100)
        let light: Double = film.transmission(row: 0, column: 99, channel: 1, width: 100)
        let below: Double = film.transmission(row: 500, column: 99, channel: 2, width: 100)
        #expect(dark == 0 && light == 1, "stretched to the line's width")
        #expect(below == 1, "edges repeated beyond the image")
        // app/X1Scan/Sample holds only its README until the user adds a photograph.
        let folder: URL = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: "X1Scan/Sample")
        let files: [String] = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { !$0.hasPrefix(".") }
        #expect(files == ["README.md"])
    }

    /// An exported file is marked as a sample: suffix, TIFF description, recipe.
    @Test func exportsAreMarkedAsSamples() async throws {
        let spy = Spy()
        let folder = try temporaryDirectory()
        let model = try model(source: .virtual, spy: spy, folder: folder)
        model.enterDiscovery(sampleSuffix: "_sample")
        model.startPreview()
        await model.session.waitUntilIdle()
        #expect(model.nextExportFileName().hasSuffix("_sample.tif"))
        let url = try await model.export().get()
        #expect(url.lastPathComponent.hasSuffix("_sample.tif"))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let tiff = properties?[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(tiff?[kCGImagePropertyTIFFImageDescription] as? String == SampleMark.description)
        let recipe = try Recipe.decode(from: Data(contentsOf: Recipe.fileURL(forImage: url)))
        #expect(recipe.sample)
        // Outside discovery mode: no mark.
        model.leaveDiscovery()
        model.startPreview()
        await model.session.waitUntilIdle()
        let plain = try await model.export().get()
        #expect(!plain.lastPathComponent.contains("_sample"))
        #expect(try !Recipe.decode(from: Data(contentsOf: Recipe.fileURL(forImage: plain))).sample)
        let plainSource = try #require(CGImageSourceCreateWithURL(plain as CFURL, nil))
        let plainTIFF = (CGImageSourceCopyPropertiesAtIndex(plainSource, 0, nil) as? [CFString: Any])?[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(plainTIFF?[kCGImagePropertyTIFFImageDescription] == nil, "nothing else goes into a real file")
    }
}
