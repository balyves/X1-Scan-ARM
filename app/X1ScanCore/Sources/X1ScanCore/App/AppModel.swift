// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import Observation
import X1Image
import X1Preview
import X1Transport

/// State of the read-only access to the real X1.
public enum RealScannerStatus: Sendable, Hashable {
    case notRead
    case reading
    case read(ScannerInfo)
    case failed(ScannerInspector.Failure)
}

/// The bottom bar's reminder of the source and its state ("Virtual X1 · Ready").
public struct ScannerStatusLine: Sendable, Hashable {
    public enum Detail: Sendable, Hashable {
        /// Virtual X1: the preview session's status.
        case session
        /// Virtual X1: the fixtures could not be loaded.
        case unavailable
        case notRead
        case reading
        case read
        case failed
    }

    public var source: ScannerSourceKind
    public var detail: Detail

    public init(source: ScannerSourceKind, detail: Detail) {
        self.source = source
        self.detail = detail
    }
}

/// The checks the user confirms before every scan on the real X1.
public struct RealScanConfirmation: Sendable, Hashable {
    /// Same holder as the capture (6x7, 50200403), film in place, nothing moved since the preview.
    public var sameHolderNothingMoved = false
    /// The capture's frame and resolution are used, not the panel's.
    public var captureFrameUnderstood = false

    public init(sameHolderNothingMoved: Bool = false, captureFrameUnderstood: Bool = false) {
        self.sameHolderNothingMoved = sameHolderNothingMoved
        self.captureFrameUnderstood = captureFrameUnderstood
    }

    public var isComplete: Bool { sameHolderNothingMoved && captureFrameUnderstood }
}

/// The checks the user confirms before every preview on the real X1.
public struct RealPreviewConfirmation: Sendable, Hashable {
    public var scannerOn = false
    public var holderInPlace = false
    public var flexColorClosed = false
    /// The X1 was switched off and on since the last real preview, asked only
    /// after a real preview that did not complete: a cold run stopped during
    /// calibration still shows the power-on values on page 0x20, so the
    /// automatic choice would start the cold sequence again on a scanner left
    /// half calibrated, which no capture shows (docs/decisions.md).
    public var powerCycledSinceLastRealPreview = false

    public init(scannerOn: Bool = false, holderInPlace: Bool = false, flexColorClosed: Bool = false,
                powerCycledSinceLastRealPreview: Bool = false) {
        self.scannerOn = scannerOn
        self.holderInPlace = holderInPlace
        self.flexColorClosed = flexColorClosed
        self.powerCycledSinceLastRealPreview = powerCycledSinceLastRealPreview
    }

    /// Every box asked is ticked; the fourth only when `powerCycleRequired`.
    public func isComplete(powerCycleRequired: Bool) -> Bool {
        scannerOn && holderInPlace && flexColorClosed && (!powerCycleRequired || powerCycledSinceLastRealPreview)
    }
}

public enum RealPreviewError: Error, Hashable, CustomStringConvertible {
    /// Hidden setting off, wrong source, busy, or confirmation incomplete.
    case notAllowed
    /// The capture (fixtures) needed for the guard is missing or unreadable.
    case noCapturedSequence(String)
    /// The log files could not be created; nothing was sent.
    case log(String)

    public var description: String {
        switch self {
        case .notAllowed: "preview on the real X1 not allowed now"
        case .noCapturedSequence(let detail): "captured sequence unavailable: \(detail)"
        case .log(let detail): "the log could not be created: \(detail)"
        }
    }
}

/// Everything the main window shows and does, without any view.
@MainActor
@Observable
public final class AppModel {
    // MARK: Scanner

    public var source: ScannerSourceKind {
        didSet {
            guard source != oldValue else { return }
            defaults.set(source.rawValue, forKey: Keys.source)
            session.stop()  // a preview never goes on with another source
            realPreviewActive = false
        }
    }
    public let virtualScanner: VirtualScanner?
    /// Why the virtual X1 is unavailable, when it is.
    public let virtualScannerError: String?
    public let session: PreviewSession
    public private(set) var realStatus: RealScannerStatus = .notRead
    private let inspector: ScannerInspector

    // MARK: Settings

    public let settings: AppSettings

    // MARK: Panel and viewing

    /// The settings panel on the right.
    public let panel: PanelController
    /// Settings > Holders: the holders owned (shown in the panel) and the custom ones.
    public let holders: HolderLibrary
    /// Original and scan settings of the panel (saved, not sent to the scanner yet).
    public var scanSettings: ScanSettings {
        didSet { if let data = try? JSONEncoder().encode(scanSettings) { defaults.set(data, forKey: Keys.scanSettings) } }
    }
    public var tools = ToolState()
    /// The grid over the image (lot 1): display only, saved between launches.
    public var grid: GridSettings {
        didSet { if grid != oldValue, let data = try? JSONEncoder().encode(grid) { defaults.set(data, forKey: Keys.grid) } }
    }
    public private(set) var viewport: Viewport
    /// Size of the visible image area, reported by the canvas.
    public var viewSize: CGSize { viewport.viewSize }
    /// The recipe of the image shown (lot 1): orientation for now. Kept from
    /// one image to the next (a preview, then the scan of the same frame).
    public private(set) var recipe = Recipe() {
        didSet { viewport.orientation = recipe.orientation }
    }
    /// Framing rectangle drawn with the crop tool. Not exported at this stage;
    /// the histogram counts its pixels only.
    public var cropRect: PixelRect? {
        didSet { if Self.histogramRegion(of: cropRect) != Self.histogramRegion(of: oldValue) { refreshHistogram() } }
    }
    /// Pixel under the pointer, reported by the canvas.
    public var pointer: PixelCoordinate?
    public private(set) var displayImage: CGImage?
    public private(set) var histogram = Histogram.empty
    /// Exposure indicator (lot 1): measured read-only on the raw samples of
    /// the last complete preview; kept while a scan is shown.
    public private(set) var exposure: ExposureReading?
    /// Clipped (red) and near-noise (blue) pixels of that preview, for the overlay.
    public private(set) var exposureZones: CGImage?
    /// Size of the preview `exposureZones` was made from.
    public private(set) var exposureZonesSize: (width: Int, height: Int)?
    /// The overlay of the zones is shown on the preview (saved).
    public var showsExposureZones: Bool {
        didSet { defaults.set(showsExposureZones, forKey: Keys.showsExposureZones) }
    }
    private var exposureTask: Task<Void, Never>?
    private var measuredRevision = -1
    private var histogramTask: Task<Void, Never>?
    private var renderedRevision = -1
    /// Set by startPreview: the next image gets the zoom of Settings > Display.
    private var startupZoomPending = true
    private var renderTask: Task<Void, Never>?

    // MARK: Export

    public var exportSettings: ExportSettings {
        didSet { saveExportSettings() }
    }
    public private(set) var lastExport: Result<URL, ExportError>?
    /// The scan shown was saved as this master (raw TIFF and its recipe):
    /// Export then writes `<master>_v1.tif`, `_v2`… next to it.
    public private(set) var scanMaster: URL?

    private let defaults: UserDefaults
    private enum Keys {
        static let source = "ScannerSource"
        static let exportSettings = "ExportSettings"
        static let scanSettings = "ScanSettings"
        static let grid = "GridSettings"
        static let showsExposureZones = "ShowExposureZones"
        /// Hidden setting, no interface: `defaults write org.x1scanarm.X1Scan EnableRealPreview -bool YES`.
        static let enableRealPreview = "EnableRealPreview"
        /// Set when a real preview starts, cleared when it completes: true
        /// after a stop, an anomaly or a quit during a real preview.
        static let realPreviewInterrupted = "RealPreviewInterrupted"
        /// Hidden setting, no interface: `defaults write org.x1scanarm.X1Scan EnableRealScan -bool YES`.
        static let enableRealScan = "EnableRealScan"
    }

    /// A real preview completed (scanner side) since launch, with no real run
    /// interrupted since: the X1 is in the state the scan needs. Not kept
    /// between launches.
    public private(set) var realPreviewCompletedThisLaunch = false
    /// The TIFF saved after the last scan, or why it could not be.
    public private(set) var lastScanSave: Result<URL, ExportError>?

    /// The last real preview did not complete (stopped, anomaly, app quit or
    /// crashed while it ran): the next one asks for the X1 to be switched off
    /// and on. Kept between launches.
    public var realPreviewNeedsPowerCycle: Bool { defaults.bool(forKey: Keys.realPreviewInterrupted) }

    /// Opens the real X1 for the captured preview; replaced in tests.
    private let realConnection: @Sendable (CapturedSequenceGuard) -> any ScannerConnection
    /// Where preview logs on the real X1 are written (outside the repository).
    private let captureFolder: URL
    /// The text log of the last preview on the real X1.
    public private(set) var lastPreviewLog: URL?
    private var previewLog: CaptureLog?
    /// The log of the last real preview missed writes (disk full…).
    public var lastPreviewLogIsIncomplete: Bool { previewLog?.isIncomplete ?? false }
    /// The session shows a preview on the real X1 (until the source changes).
    public private(set) var realPreviewActive = false
    /// The last preview started was on the real X1. Kept when the source
    /// changes, so that the end of a stopped real preview is still reported.
    public private(set) var lastPreviewWasReal = false

    public init(virtualScanner: () throws -> VirtualScanner,
                inspector: ScannerInspector = .realScanner,
                defaults: UserDefaults = .standard,
                realConnection: @escaping @Sendable (CapturedSequenceGuard) -> any ScannerConnection = {
                    IOKitTransport(capturedSequence: $0)
                },
                captureFolder: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "X1-captures")) {
        self.defaults = defaults
        self.inspector = inspector
        self.realConnection = realConnection
        self.captureFolder = captureFolder
        do {
            self.virtualScanner = try virtualScanner()
            virtualScannerError = nil
        } catch {
            self.virtualScanner = nil
            virtualScannerError = String(describing: error)
        }
        session = PreviewSession()
        panel = PanelController(defaults: defaults)
        holders = HolderLibrary(store: defaults)
        var scan = defaults.data(forKey: Keys.scanSettings)
            .flatMap { try? JSONDecoder().decode(ScanSettings.self, from: $0) } ?? ScanSettings()
        // Step 3 typed the holder as free text: keep it as a custom holder, chosen.
        let migratedHolder = scan.legacyHolderName != nil
        if let name = scan.legacyHolderName {
            let holder = holders.addCustom(reference: nil, format: name, aperture: nil, frames: 1)
            scan.holderID = holder.id
            scan.clearLegacyHolder()
        }
        scanSettings = scan
        let settings = AppSettings(defaults: defaults)
        self.settings = settings
        switch settings.startupSource {
        case .virtual: source = .virtual
        case .real: source = .real
        case .last: source = defaults.string(forKey: Keys.source).flatMap(ScannerSourceKind.init) ?? .virtual
        }
        viewport = Viewport(imageWidth: 0, imageHeight: 0, mode: settings.startupZoom == .fit ? .fit : .fixed)
        showsExposureZones = defaults.bool(forKey: Keys.showsExposureZones)
        grid = defaults.data(forKey: Keys.grid)
            .flatMap { try? JSONDecoder().decode(GridSettings.self, from: $0) } ?? GridSettings()
        exportSettings = defaults.data(forKey: Keys.exportSettings)
            .flatMap { try? JSONDecoder().decode(ExportSettings.self, from: $0) } ?? ExportSettings()
        // Not saved here: "last chosen" is the last source chosen in the interface
        // (`source.didSet`), never one imposed at launch (startup setting or
        // the -StartupSource argument).
        if migratedHolder, let data = try? JSONEncoder().encode(scanSettings) {
            defaults.set(data, forKey: Keys.scanSettings)  // converted once, not at every launch
        }
    }

    // MARK: Derived state

    public var toolbar: ToolbarState {
        ToolbarState(source: source, session: session.state, virtualAvailable: virtualScanner != nil,
                     hasImage: (session.image?.height ?? 0) > 0, hasExportFolder: exportSettings.folder != nil,
                     realPreviewEnabled: realPreviewEnabled, scanAvailable: virtualScanner?.scanFixture != nil,
                     scanHasExportFolder: exportSettings.folder != nil,
                     realScanEnabled: realScanEnabled,
                     realScanReady: realPreviewCompletedThisLaunch && !realPreviewNeedsPowerCycle)
    }

    /// The hidden setting (off by default): scan on the real X1 allowed, with a confirmation.
    public var realScanEnabled: Bool { defaults.bool(forKey: Keys.enableRealScan) }

    /// The hidden setting (off by default): preview on the real X1 allowed, with a confirmation.
    public var realPreviewEnabled: Bool { defaults.bool(forKey: Keys.enableRealPreview) }

    public var statusLine: ScannerStatusLine {
        switch source {
        case .virtual:
            ScannerStatusLine(source: .virtual, detail: virtualScanner == nil ? .unavailable : .session)
        case .real where realPreviewActive:
            ScannerStatusLine(source: .real, detail: .session)
        case .real:
            switch realStatus {
            case .notRead: ScannerStatusLine(source: .real, detail: .notRead)
            case .reading: ScannerStatusLine(source: .real, detail: .reading)
            case .read: ScannerStatusLine(source: .real, detail: .read)
            case .failed: ScannerStatusLine(source: .real, detail: .failed)
            }
        }
    }

    /// What the Scanner Information window shows for the current source.
    public var scannerInfo: ScannerInfo? {
        switch source {
        case .virtual: virtualScanner?.info
        case .real: if case .read(let info) = realStatus { info } else { nil }
        }
    }

    public var pixelReading: PixelReading? {
        guard let pointer, let image = session.image else { return nil }
        return PixelProbe.reading(at: pointer, in: image)
    }

    // MARK: Actions

    /// Preview on the virtual X1. On the real X1 use `startRealPreview(_:)`.
    public func startPreview() {
        guard source == .virtual, toolbar.canPreview, let virtualScanner else { return }
        prepareNewPreview()
        realPreviewActive = false
        lastPreviewWasReal = false
        previewLog = nil
        session.start(on: virtualScanner)
    }

    /// FlexColor's captured preview on the real X1 (step 4): only with the
    /// hidden setting, the real source, nothing running, and every check asked
    /// confirmed (`RealPreviewConfirmation`). The transport lets through only the captured sequence; every
    /// command and response is logged under `captureFolder`. Returns the log.
    @discardableResult
    public func startRealPreview(_ confirmation: RealPreviewConfirmation) -> Result<URL, RealPreviewError> {
        guard source == .real, realPreviewEnabled,
              confirmation.isComplete(powerCycleRequired: realPreviewNeedsPowerCycle), toolbar.canPreview,
              realStatus != .reading else { return .failure(.notAllowed) }
        guard let cold = virtualScanner?.coldFixture, let warm = virtualScanner?.fixture else {
            return .failure(.noCapturedSequence(virtualScannerError ?? "no fixtures"))
        }
        let sequence: CapturedSequenceGuard
        do {
            // Both captured sequences, without the cold capture's page 0x28 read
            // (docs/decisions.md, "Real X1: cold or warm sequence").
            sequence = try CapturedSequenceGuard(alternatives: [cold, warm],
                                                 excluding: [.read(SimulatedX1.page28Read, length: 30)])
        } catch {
            return .failure(.noCapturedSequence(error.description))
        }
        let log: CaptureLog
        do {
            log = try makePreviewLog(Date())
        } catch {
            return .failure(.log(String(describing: error)))
        }
        prepareNewPreview()
        lastPreviewLog = log.textURL
        realPreviewActive = true
        lastPreviewWasReal = true
        previewLog = log
        realPreviewCompletedThisLaunch = false
        let interrupted = beginRealRun()
        session.start(onRealScanner: realConnection(sequence), log: log) { [weak self] state in
            guard let self else { return }
            self.realPreviewCompletedThisLaunch = self.endRealRun(state, interruptedBefore: interrupted)
        }
        return .success(log.textURL)
    }

    /// Marks a real run as started (interrupted until it completes); returns
    /// the flag as it was.
    private func beginRealRun() -> Bool {
        let before = realPreviewNeedsPowerCycle
        defaults.set(true, forKey: Keys.realPreviewInterrupted)
        return before
    }

    /// Updates the interrupted flag at the end of a real run. True when the
    /// scanner side completed (end of session sent), even if decoding failed:
    /// no power cycle is needed then.
    @discardableResult
    private func endRealRun(_ state: PreviewSession.State, interruptedBefore: Bool) -> Bool {
        if state == .finished {
            defaults.set(false, forKey: Keys.realPreviewInterrupted)
            return true
        }
        if case .failed(let failure) = state {
            switch failure.cause {
            case .decoding:
                defaults.set(false, forKey: Keys.realPreviewInterrupted)
                return true
            case .anomaly(.couldNotOpen):
                // Nothing was sent: back to the state before this run.
                defaults.set(interruptedBefore, forKey: Keys.realPreviewInterrupted)
            case .anomaly:
                break
            }
        }
        return false
    }

    /// FlexColor's captured 2 000 ppi scan on the virtual X1; the TIFF is
    /// saved in the export folder at the end.
    public func startScan() {
        guard source == .virtual, toolbar.canScan, let virtualScanner else { return }
        prepareNewPreview(forScan: true)
        realPreviewActive = false
        lastPreviewWasReal = false
        previewLog = nil
        lastScanSave = nil
        session.startScan(on: virtualScanner) { [weak self] state in
            if state == .finished { self?.saveScan(Date()) }
        }
    }

    /// FlexColor's captured 2 000 ppi scan on the real X1 (docs/decisions.md,
    /// "Real X1: scan"): only with `EnableRealScan`, the real source, a real
    /// preview completed since launch with nothing interrupted since, and both
    /// checks confirmed. The guard lets through only the scan session with its
    /// one substitution; every command is logged. The TIFF is saved at the end.
    @discardableResult
    public func startRealScan(_ confirmation: RealScanConfirmation) -> Result<URL, RealPreviewError> {
        guard source == .real, confirmation.isComplete, toolbar.canScan, realStatus != .reading else {
            return .failure(.notAllowed)
        }
        guard let fixture = virtualScanner?.scanFixture else {
            return .failure(.noCapturedSequence(virtualScannerError ?? "no scan capture"))
        }
        let sequence: CapturedSequenceGuard
        do {
            sequence = try CapturedSequenceGuard.scan(fixture: fixture, allowedPositions: ScanScript.focusPositionRange)
        } catch {
            return .failure(.noCapturedSequence(error.description))
        }
        let date = Date()
        let tolerance = PreviewConfiguration.defaultPositionTolerance
        let log: CaptureLog
        do {
            log = try makeLog(date, prefix: "x1scan-scan", header: [
                "X1 Scan: FlexColor 4.8.13's captured 2 000 ppi scan replayed on the real X1, \(date.ISO8601Format())",
                "Sequence: scan session of scan-sequence-2000ppi.json (frame 609 x 614 px at 2 000 ppi).",
                "One substitution: the target position of the 400-line step's window is the position read",
                "just before, accepted from \(ScanScript.focusPositionRange.lowerBound) to "
                    + "\(ScanScript.focusPositionRange.upperBound) (captured 16 651); later positions are compared with",
                "the target sent (within \(tolerance)). Every position that differs is noted below.",
            ])
        } catch {
            return .failure(.log(String(describing: error)))
        }
        prepareNewPreview(forScan: true)
        lastPreviewLog = log.textURL
        realPreviewActive = true
        lastPreviewWasReal = true
        previewLog = log
        lastScanSave = nil
        let interrupted = beginRealRun()
        session.startScan(onRealScanner: realConnection(sequence), log: log) { [weak self] state in
            guard let self else { return }
            self.endRealRun(state, interruptedBefore: interrupted)
            // Every real scan needs a complete real preview just before it, as in the
            // captures (each is one preview, then one scan); scan after scan was never captured.
            self.realPreviewCompletedThisLaunch = false
            guard state == .finished else { return }
            self.saveScan(Date())
            switch self.lastScanSave {
            case .success(let url)?:
                let size = "\(self.session.image?.width ?? 0) x \(self.session.image?.height ?? 0) px"
                log.note("saved: \(url.path(percentEncoded: false)) (\(size))")
            case .failure(let error)?:
                log.note("not saved: \(error)")
            case nil:
                break
            }
        }
        return .success(log.textURL)
    }

    /// Saves the scan as a 16-bit RGB TIFF (linear, no profile) in the export
    /// folder, named by the export template, with the scan's resolution.
    /// Nothing else goes into the file: no serial number, no description.
    /// The same name rules as Export (roll name validated, frame number moved on).
    private func saveScan(_ date: Date) {
        if exportSettings.needsRollValidation { exportSettings.validateRoll() }
        var settings = exportSettings
        settings.format = .rgb16
        // The master: the scanner's pixels, never turned or cropped, and the recipe beside them.
        let recipe = recipe
        let result = Result { () throws(ExportError) -> URL in
            try ExportService.export(session.image, settings: settings, date: date, resolution: ScanScript.resolution,
                                     recipe: recipe)
        }
        lastScanSave = result
        if case .success(let url) = result { scanMaster = url }
        if case .success = result, exportSettings.incrementsFrame { exportSettings.frame += 1 }
    }

    /// `forScan`: the exposure measured on the preview stays shown during and after the scan.
    private func prepareNewPreview(forScan: Bool = false) {
        lastExport = nil
        measuredRevision = -1
        if !forScan {
            // A new preview: no measure of the previous one over its rows.
            exposureTask?.cancel()
            exposure = nil
            exposureZones = nil
            exposureZonesSize = nil
        }
        scanMaster = nil
        // Every new preview gets the zoom of Settings > Display when its first
        // rows arrive (refreshImage). The crop rectangle is kept if the size is the same.
        startupZoomPending = true
        // The session counts image revisions from 0 again: the next one must be rendered.
        renderedRevision = -1
    }

    private func makePreviewLog(_ date: Date) throws -> CaptureLog {
        try makeLog(date, prefix: "x1scan-apercu", header: [
            "X1 Scan: FlexColor 4.8.13's captured preview replayed on the real X1, \(date.ISO8601Format())",
            "Sequences: right after power-on (preview-sequence-cold.json, without its page 0x28",
            "read) or after earlier use (preview-sequence.json), chosen by the first page 0x20 read.",
            "Position tolerance \(PreviewConfiguration.defaultPositionTolerance); every position",
            "that differs from the capture is noted below.",
        ])
    }

    /// `<captureFolder>/<yyyy-MM-dd>/<prefix>-<HHmmss>.txt` and `.raw`; `-2`,
    /// `-3`… are added when a log of that second already exists. The header
    /// lines are followed by the format and the serial-number warning.
    private func makeLog(_ date: Date, prefix: String, header: [String]) throws -> CaptureLog {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let time = String(format: "%02d%02d%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
        let folder = captureFolder.appending(path: day)
        var base = "\(prefix)-\(time)"
        var suffix = 2
        while FileManager.default.fileExists(atPath: folder.appending(path: base + ".txt").path)
                || FileManager.default.fileExists(atPath: folder.appending(path: base + ".raw").path) {
            base = "\(prefix)-\(time)-\(suffix)"
            suffix += 1
        }
        let lines = header + [
            "Format of tools/capture/cap3.py; image data in \(base).raw.",
            "Contains the scanner's serial number: keep outside the repository.",
        ]
        return try CaptureLog(textURL: folder.appending(path: base + ".txt"), rawURL: folder.appending(path: base + ".raw"),
                              header: lines.joined(separator: "\n"))
    }

    public func stop() {
        session.stop()
    }

    /// Reads the real X1 (reads only, device closed afterwards).
    public func readRealScanner() async {
        // Never while a preview runs: the preview has the scanner open.
        guard source == .real, realStatus != .reading, !session.isBusy else { return }
        realStatus = .reading
        do {
            realStatus = .read(try await inspector.read())
        } catch {
            realStatus = .failed(error)
        }
    }

    @discardableResult
    public func export(date: Date = Date()) -> Result<URL, ExportError> {
        // Exporting right after typing a new roll name counts as validating it.
        if exportSettings.needsRollValidation { exportSettings.validateRoll() }
        // The recipe applied to the image shown, written as a new file with its recipe:
        // a version of the scan's master, or a preview named by the template.
        let master = session.kind == .scan ? scanMaster : nil
        let isScan = session.kind == .scan
        let result = Result { () throws(ExportError) -> URL in
            try ExportService.export(session.image, settings: exportSettings, date: date,
                                     resolution: isScan ? ScanScript.resolution : 72,
                                     recipe: recipe, applyRecipe: true,
                                     pixelAspectRatio: viewport.pixelAspectRatio, versionOf: master)
        }
        lastExport = result
        // A version of a master is the same frame: the frame number does not move.
        if case .success = result, master == nil, exportSettings.incrementsFrame { exportSettings.frame += 1 }
        return result
    }

    // MARK: Orientation (lot 1)

    public func rotateClockwise() { recipe.orientation.rotateClockwise() }
    public func rotateCounterclockwise() { recipe.orientation.rotateCounterclockwise() }
    public func mirrorHorizontally() { recipe.orientation.mirrorHorizontally() }
    public func toggleGrid() { grid.isVisible.toggle() }

    /// Choosing a kind of grid shows it.
    public func showGrid(_ kind: GridKind) {
        grid.kind = kind
        grid.isVisible = true
    }

    /// A preview runs or stops, or the real X1 is being read.
    public var isBusy: Bool { session.isBusy || realStatus == .reading }

    /// For quitting: stops a running preview and returns once the stop
    /// sequence is over and any read of the real X1 has finished.
    public func stopAndWait() async {
        session.stop()
        await session.waitUntilIdle()
        while realStatus == .reading {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// The holder shown in the panel: the chosen one if it is still owned, else none.
    public var selectedHolder: Holder? {
        guard let holder = holders.holder(id: scanSettings.holderID), holders.isOwned(holder.id) else { return nil }
        return holder
    }

    /// Uncompressed size of the file an export would write now (bottom bar).
    public var estimatedExportBytes: Int? {
        ExportService.estimatedBytes(for: session.image, settings: exportSettings)
    }

    /// Input size of the panel: the crop rectangle, or the whole preview, in pixels.
    public var inputPixelSize: (width: Int, height: Int)? {
        if let cropRect { return (cropRect.width, cropRect.height) }
        guard let image = session.image else { return nil }
        return (image.width, image.expectedHeight)
    }

    /// The name the next export would get.
    public func nextExportFileName(date: Date = Date()) -> String {
        // As the export will write it: with the roll name validated, a version of the
        // scan's master when a saved scan is shown, a recipe beside it.
        ExportService.nextFileName(settings: exportSettings.validated, date: date,
                                   versionOf: session.kind == .scan ? scanMaster : nil, withRecipe: true)
    }

    // MARK: Viewport

    /// The image area changed size: window, full screen, settings panel shown or hidden.
    public func viewSizeChanged(_ size: CGSize) { viewport.viewSizeChanged(size) }

    public func zoomToFit() { viewport.fit() }
    public func zoomToFill() { viewport.fill() }
    public func zoomToActualSize() { viewport.actualSize() }
    public func zoomIn() { viewport.zoomIn() }
    public func zoomOut() { viewport.zoomOut() }
    public func zoom(to magnification: Double) { viewport.setMagnification(magnification) }
    /// A value typed in the bottom bar. Returns false (nothing changed) if it is not a number.
    @discardableResult
    public func zoom(typed text: String) -> Bool {
        guard let value = Viewport.magnification(fromTyped: text) else { return false }
        viewport.setMagnification(value)
        return true
    }
    /// Pinch or zoom tool: the canvas reports the magnification it applied.
    public func magnificationChanged(_ value: Double) { viewport.setMagnification(value) }

    // MARK: Image updates

    /// Called by the view layer when `session.imageRevision` changes: builds
    /// the display image and the histogram off the main actor, keeping only
    /// the latest result.
    public func refreshImage() {
        let revision = session.imageRevision
        guard revision != renderedRevision else { return }
        renderedRevision = revision
        guard let image = session.image else {
            displayImage = nil
            histogram = .empty
            renderTask?.cancel()
            return
        }
        // Preview pixels are 3 times taller than wide; a scan's are square
        // (2 000 ppi both ways, docs/protocol.md §10).
        let aspect = session.kind == .scan ? ScanDecoding.pixelAspectRatio : PreviewGeometry.pixelAspectRatio
        if viewport.imageWidth != image.width || viewport.imageHeight != image.expectedHeight
            || viewport.pixelAspectRatio != aspect {
            viewport.setImage(width: image.width, height: image.expectedHeight, pixelAspectRatio: aspect)
            cropRect = nil
        }
        if startupZoomPending {
            // A new preview: the zoom of Settings > Display, Fit by default.
            startupZoomPending = false
            if settings.startupZoom == .fit { viewport.fit() } else { viewport.actualSize() }
        }
        measureExposure(image, revision: revision)
        renderTask?.cancel()
        histogramTask?.cancel()
        let region = histogramRegion
        renderTask = Task {
            let rendered = await Task.detached(priority: .userInitiated) {
                (DisplayImage.make(from: image).map(SendableImage.init),
                 Histogram(samples: image.corrected, width: image.width, region: region))
            }.value
            guard !Task.isCancelled, revision == self.session.imageRevision else { return }
            self.displayImage = rendered.0?.image
            if region == self.histogramRegion { self.histogram = rendered.1 }
        }
    }

    /// Once a preview is complete: the exposure reading and the zone overlay,
    /// off the main actor. Read-only: nothing is changed in the image.
    private func measureExposure(_ image: PreviewImage, revision: Int) {
        guard session.kind == .preview, image.isComplete, revision != measuredRevision else { return }
        measuredRevision = revision
        exposureTask?.cancel()
        exposureTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                (ExposureMeter.measure(raw: image.raw),
                 Self.zoneImage(ExposureMeter.zoneMask(raw: image.raw), width: image.width, height: image.height)
                    .map(SendableImage.init))
            }.value
            guard !Task.isCancelled else { return }
            self.exposure = result.0
            self.exposureZones = result.1?.image
            self.exposureZonesSize = (image.width, image.height)
        }
    }

    /// RGBA premultiplied, 8 bits, sRGB.
    nonisolated static func zoneImage(_ mask: [UInt8], width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, mask.count == width * height * 4,
              let provider = CGDataProvider(data: Data(mask) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// The crop the histogram counts: none below 2 × 2 pixels (a click with the
    /// crop tool draws a 1 × 1 rectangle, which would leave a one-pixel histogram).
    var histogramRegion: PixelRect? { Self.histogramRegion(of: cropRect) }

    static func histogramRegion(of crop: PixelRect?) -> PixelRect? {
        guard let crop, crop.width >= 2, crop.height >= 2 else { return nil }
        return crop
    }

    /// The histogram of the crop (or of the whole image without one), after the
    /// crop changed; the display image does not change.
    private func refreshHistogram() {
        histogramTask?.cancel()
        guard let image = session.image else {
            histogram = .empty
            return
        }
        let region = histogramRegion
        histogramTask = Task {
            // While the crop is being dragged, only the position it rests at is counted:
            // each mouse move cancels the previous task during this pause.
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            let histogram = await Task.detached(priority: .userInitiated) {
                Histogram(samples: image.corrected, width: image.width, region: region)
            }.value
            guard !Task.isCancelled, region == self.histogramRegion else { return }
            self.histogram = histogram
        }
    }

    /// Waits for the latest `refreshImage` / histogram work (tests).
    public func waitForRendering() async {
        await renderTask?.value
        await exposureTask?.value
        await histogramTask?.value
    }

    private func saveExportSettings() {
        if let data = try? JSONEncoder().encode(exportSettings) {
            defaults.set(data, forKey: Keys.exportSettings)
        }
    }
}

/// CGImage is immutable and thread-safe; it is not marked Sendable.
private struct SendableImage: @unchecked Sendable {
    let image: CGImage
}
