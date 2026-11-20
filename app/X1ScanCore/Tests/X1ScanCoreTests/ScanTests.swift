// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import X1ScanCore
import X1Preview
import X1Transport

/// FlexColor's captured 2 000 ppi scan in the app, on the virtual X1 and on a
/// simulated real X1 behind the scan guard (docs/decisions.md, "Real X1: scan").
@MainActor
final class ScanTests {
    private var suites: [String] = []
    private var folders: [URL] = []
    private let box = ScanConnectionBox()

    deinit {
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
    }

    private func model(realScan: Bool = false, realPreview: Bool = false) throws -> AppModel {
        let suite = "X1ScanCoreTests-\(UUID().uuidString)"
        suites.append(suite)
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(realPreview, forKey: "EnableRealPreview")
        defaults.set(realScan, forKey: "EnableRealScan")
        let scanner = try TestFixtures.scanner()
        let captures = try temporaryDirectory()
        let export = try temporaryDirectory()
        folders += [captures, export]
        let box = self.box
        let model = AppModel(virtualScanner: { scanner }, inspector: ScannerInspector {
            FakeConnection(responses: [:], openError: TransportError.deviceBusy)
        }, defaults: defaults, realConnection: { sequence in
            // The scan guard contains the focus sweep; the preview guard does not.
            if sequence.expected.contains(where: { $0.cdb == [0x1B, 0x00, 0x08, 0x06, 0x01, 0x00] }) {
                let connection = GuardedScanConnection(sequence: sequence, scanner: scanner, openError: box.openError)
                box.scan = connection
                return connection
            }
            return GuardedSimulatedConnection(sequence: sequence, scanner: scanner)
        }, captureFolder: captures)
        model.exportSettings = ExportSettings(folder: export, nameTemplate: "Scan-{n}")
        return model
    }

    private static let confirmed = RealScanConfirmation(sameHolderNothingMoved: true, captureFrameUnderstood: true)
    private static let previewChecks = RealPreviewConfirmation(scannerOn: true, holderInPlace: true, flexColorClosed: true)

    /// Crop mode entered on the preview, then a scan (another area): Esc
    /// cannot bring back the preview's frame on the scan.
    @Test func escapeAfterAScanDoesNotBringBackThePreviewFrame() async throws {
        let model = try model()
        model.startPreview()
        await model.session.waitUntilIdle()
        model.refreshImage()
        model.setCropFrame(documentRect: CGRect(x: 100, y: 100, width: 300, height: 200))
        model.tools.selected = .crop
        model.startScan()
        await model.session.waitUntilIdle()
        model.refreshImage()
        #expect(model.session.kind == .scan && model.recipe.crop.frame == nil)
        model.escape()
        #expect(model.recipe.crop.frame == nil && model.tools.selected == .hand)
    }

    @Test func virtualScanDecodesAndSavesTheTIFF() async throws {
        let model = try model()
        #expect(model.toolbar.canScan && !model.toolbar.scanNeedsConfirmation)
        model.startScan()
        await model.session.waitUntilIdle()
        #expect(model.session.kind == .scan && model.session.state == .finished)
        #expect(model.session.image?.width == 609 && model.session.image?.height == 614)
        #expect(model.session.progress.focusLinesReceived == 400)
        #expect(model.session.progress.linesReceived == 1064)
        let url = try #require(try? model.lastScanSave?.get())
        let data = try Data(contentsOf: url)
        #expect(url.lastPathComponent == "Scan-001.tif")
        #expect(Self.resolution(of: data) == 2000)
        #expect(data.range(of: Data("FX1".utf8)) == nil, "no serial number in the file")
    }

    /// Lot 1: the scan is saved as a master (pixels as decoded, with its
    /// recipe); Export writes versions next to it, never replacing it, and the
    /// frame number does not move; the preview's exposure stays shown.
    @Test func scanMasterThenVersions() async throws {
        let model = try model()
        model.startPreview()
        await model.session.waitUntilIdle()
        model.refreshImage()
        await model.waitForRendering()
        let exposure = try #require(model.exposure)
        model.rotateClockwise()
        model.startScan()
        await model.session.waitUntilIdle()
        model.refreshImage()
        await model.waitForRendering()
        #expect(model.exposure == exposure, "the preview's measure is kept during and after the scan")
        let master = try #require(try? model.lastScanSave?.get())
        #expect(model.scanMaster == master)
        let recipeURL = Recipe.fileURL(forImage: master)
        #expect(try Recipe.decode(from: Data(contentsOf: recipeURL)).orientation == Orientation(quarterTurns: 1))
        let frame = model.exportSettings.frame
        model.setCropAngle(1.5)
        #expect(model.nextExportFileName() == master.deletingPathExtension().lastPathComponent + "_v1.tif")
        let v1 = try await model.export().get()
        let v2 = try await model.export().get()
        #expect(v1.lastPathComponent == master.deletingPathExtension().lastPathComponent + "_v1.tif")
        #expect(v2.lastPathComponent == master.deletingPathExtension().lastPathComponent + "_v2.tif")
        #expect(v1.deletingLastPathComponent() == master.deletingLastPathComponent())
        #expect(model.exportSettings.frame == frame, "a version is the same frame")
        #expect(try Recipe.decode(from: Data(contentsOf: Recipe.fileURL(forImage: v1))).crop.angle == 1.5)
        #expect(FileManager.default.fileExists(atPath: master.path), "the master is still there")
    }

    /// A scan is shown with square pixels (609 × 614 points at 100 %), a
    /// preview with pixels 3 times taller than wide; a preview after a scan
    /// goes back to 3.
    @Test func scanPixelsAreShownSquare() async throws {
        let model = try model()
        model.startPreview()
        await model.session.waitUntilIdle()
        model.refreshImage()
        #expect(model.viewport.pixelAspectRatio == 3)

        model.startScan()
        await model.session.waitUntilIdle()
        model.refreshImage()
        #expect(model.viewport.pixelAspectRatio == 1)
        #expect(model.viewport.documentSize == CGSize(width: 609, height: 614))

        model.startPreview()
        await model.session.waitUntilIdle()
        model.refreshImage()
        #expect(model.viewport.pixelAspectRatio == 3)
    }

    @Test func scanButtonConditionsOnTheRealX1() async throws {
        let disabled = try model(realScan: false, realPreview: true)
        disabled.source = .real
        #expect(disabled.toolbar.scanBlock == .realScanDisabled)

        let model = try model(realScan: true, realPreview: true)
        model.source = .real
        #expect(model.toolbar.scanBlock == .needsCompletePreview && model.toolbar.scanNeedsConfirmation)
        #expect(model.startRealScan(Self.confirmed) == .failure(.notAllowed))
        _ = try model.startRealPreview(Self.previewChecks).get()
        #expect(model.toolbar.scanBlock == .busy)
        await model.session.waitUntilIdle()
        #expect(model.session.state == .finished)
        #expect(model.toolbar.canScan, "after a complete real preview")
        #expect(model.startRealScan(RealScanConfirmation(sameHolderNothingMoved: true)) == .failure(.notAllowed))
    }

    @Test func realScanGoesThroughTheGuardAndIsLogged() async throws {
        let model = try model(realScan: true, realPreview: true)
        model.source = .real
        _ = try model.startRealPreview(Self.previewChecks).get()
        await model.session.waitUntilIdle()
        let log = try model.startRealScan(Self.confirmed).get()
        await model.session.waitUntilIdle()
        #expect(model.session.state == .finished)
        let connection = try #require(box.scan)
        #expect(connection.sequence.isComplete)
        let opened = await connection.opened, closed = await connection.closed
        #expect(opened && closed)
        #expect(log.lastPathComponent.hasPrefix("x1scan-scan-"))
        let text = try String(contentsOf: log, encoding: .utf8)
        #expect(text.contains("# scan complete"))
        #expect(text.contains("# saved: "))
        let url = try #require(try? model.lastScanSave?.get())
        #expect(Self.resolution(of: try Data(contentsOf: url)) == 2000)
        #expect(model.toolbar.scanBlock == .needsCompletePreview, "a new complete preview before every scan")
    }

    /// No export folder: Scan is disabled (the scan would not be saved).
    @Test func scanNeedsAnExportFolder() throws {
        let model = try model()
        model.exportSettings = ExportSettings()
        #expect(model.toolbar.scanBlock == .noExportFolder)
    }

    /// The scanner could not be opened for the scan: nothing sent, the flag as before,
    /// and still a new preview first.
    @Test func realScanThatCouldNotOpen() async throws {
        let model = try model(realScan: true, realPreview: true)
        model.source = .real
        _ = try model.startRealPreview(Self.previewChecks).get()
        await model.session.waitUntilIdle()
        box.openError = TransportError.deviceBusy
        _ = try model.startRealScan(Self.confirmed).get()
        await model.session.waitUntilIdle()
        guard case .failed(let failure) = model.session.state, case .anomaly(.couldNotOpen) = failure.cause else {
            Issue.record("couldNotOpen expected, got \(model.session.state)")
            return
        }
        #expect(!model.realPreviewNeedsPowerCycle)
        #expect(model.toolbar.scanBlock == .needsCompletePreview)
        #expect(await box.scan?.sent.isEmpty == true)
    }

    /// A real preview that stops after a complete one: Scan is disabled again.
    @Test func aFailedPreviewDisablesScanAgain() async throws {
        let model = try model(realScan: true, realPreview: true)
        model.source = .real
        _ = try model.startRealPreview(Self.previewChecks).get()
        await model.session.waitUntilIdle()
        #expect(model.toolbar.canScan)
        _ = try model.startRealPreview(Self.previewChecks).get()
        model.stop()
        await model.session.waitUntilIdle()
        #expect(model.toolbar.scanBlock == .needsCompletePreview)
    }

    /// A scan stopped by the user: the next preview asks for the power cycle,
    /// and Scan stays disabled until a new complete preview.
    @Test func aStoppedScanNeedsANewPreview() async throws {
        let model = try model(realScan: true, realPreview: true)
        model.source = .real
        _ = try model.startRealPreview(Self.previewChecks).get()
        await model.session.waitUntilIdle()
        _ = try model.startRealScan(Self.confirmed).get()
        model.stop()
        await model.session.waitUntilIdle()
        #expect(model.realPreviewNeedsPowerCycle)
        #expect(model.toolbar.scanBlock == .needsCompletePreview)
        #expect(model.lastScanSave == nil, "nothing saved")
    }

    /// XResolution of a little-endian TIFF written by TIFFWriter (tag 282, RATIONAL).
    private static func resolution(of data: Data) -> Int? {
        let bytes = [UInt8](data)
        func le16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
        func le32(_ o: Int) -> Int { le16(o) | le16(o + 2) << 16 }
        let ifd = le32(4)
        for entry in 0..<le16(ifd) {
            let base = ifd + 2 + entry * 12
            guard le16(base) == 282 else { continue }
            let offset = le32(base + 8)
            return le32(offset) / max(le32(offset + 4), 1)
        }
        return nil
    }
}

/// The scan guard in front of the simulator replaying the capture's scan session.
actor GuardedScanConnection: ScannerConnection {
    nonisolated let sequence: CapturedSequenceGuard
    private let simulator: SimulatedX1
    private let openError: (any Error)?
    private(set) var opened = false
    private(set) var closed = false
    private(set) var sent: [SCSICommand] = []

    init(sequence: CapturedSequenceGuard, scanner: VirtualScanner, openError: (any Error)? = nil) {
        self.sequence = sequence
        self.openError = openError
        let fixture = scanner.scanFixture!
        let start = fixture.exchanges.last { $0.cdb == "cf 00 01 80 00 00" }!.seq
        simulator = SimulatedX1(fixture: fixture, profile: scanner.profile, fromSeq: start)
    }

    func open() throws {
        if let openError { throw openError }
        opened = true
    }
    func close() { closed = true }

    func execute(_ command: SCSICommand) async throws -> SCSIResult {
        guard opened, !closed else { throw TransportError.notOpen }
        try sequence.check(command)  // as IOKitTransport does, before the device
        sent.append(command)
        return try await simulator.execute(command)
    }
}

final class ScanConnectionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: GuardedScanConnection?
    private var error: (any Error)?
    var scan: GuardedScanConnection? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
    /// Error the next scan connection's open() throws.
    var openError: (any Error)? {
        get { lock.withLock { error } }
        set { lock.withLock { error = newValue } }
    }
}
