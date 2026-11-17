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
    public private(set) var viewport: Viewport
    /// Size of the visible image area, reported by the canvas.
    public var viewSize: CGSize { viewport.viewSize }
    /// Framing rectangle drawn with the crop tool. Not exported at this stage;
    /// the histogram counts its pixels only.
    public var cropRect: PixelRect? {
        didSet { if Self.histogramRegion(of: cropRect) != Self.histogramRegion(of: oldValue) { refreshHistogram() } }
    }
    /// Pixel under the pointer, reported by the canvas.
    public var pointer: PixelCoordinate?
    public private(set) var displayImage: CGImage?
    public private(set) var histogram = Histogram.empty
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

    private let defaults: UserDefaults
    private enum Keys {
        static let source = "ScannerSource"
        static let exportSettings = "ExportSettings"
        static let scanSettings = "ScanSettings"
        /// Hidden setting, no interface: `defaults write org.x1scanarm.X1Scan EnableRealPreview -bool YES`.
        static let enableRealPreview = "EnableRealPreview"
        /// Set when a real preview starts, cleared when it completes: true
        /// after a stop, an anomaly or a quit during a real preview.
        static let realPreviewInterrupted = "RealPreviewInterrupted"
    }

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
                     realPreviewEnabled: realPreviewEnabled)
    }

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
        let interruptedBefore = realPreviewNeedsPowerCycle
        defaults.set(true, forKey: Keys.realPreviewInterrupted)
        session.start(onRealScanner: realConnection(sequence), log: log) { [defaults] state in
            // The scanner side completed (end of session sent): no power cycle needed,
            // even if decoding the image failed.
            if state == .finished {
                defaults.set(false, forKey: Keys.realPreviewInterrupted)
            } else if case .failed(let failure) = state {
                switch failure.cause {
                case .decoding: defaults.set(false, forKey: Keys.realPreviewInterrupted)
                // Nothing was sent: back to the state before this run.
                case .anomaly(.couldNotOpen):
                    defaults.set(interruptedBefore, forKey: Keys.realPreviewInterrupted)
                case .anomaly: break
                }
            }
        }
        return .success(log.textURL)
    }

    private func prepareNewPreview() {
        lastExport = nil
        // Every new preview gets the zoom of Settings > Display when its first
        // rows arrive (refreshImage). The crop rectangle is kept if the size is the same.
        startupZoomPending = true
        // The session counts image revisions from 0 again: the next one must be rendered.
        renderedRevision = -1
    }

    /// `<captureFolder>/<yyyy-MM-dd>/x1scan-apercu-<HHmmss>.txt` and `.raw`;
    /// `-2`, `-3`… are added when a log of that second already exists.
    private func makePreviewLog(_ date: Date) throws -> CaptureLog {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let time = String(format: "%02d%02d%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
        let folder = captureFolder.appending(path: day)
        var base = "x1scan-apercu-\(time)"
        var suffix = 2
        while FileManager.default.fileExists(atPath: folder.appending(path: base + ".txt").path)
                || FileManager.default.fileExists(atPath: folder.appending(path: base + ".raw").path) {
            base = "x1scan-apercu-\(time)-\(suffix)"
            suffix += 1
        }
        return try CaptureLog(textURL: folder.appending(path: base + ".txt"), rawURL: folder.appending(path: base + ".raw"),
                              header: """
                                X1 Scan: FlexColor 4.8.13's captured preview replayed on the real X1, \(date.ISO8601Format())
                                Sequences: right after power-on (preview-sequence-cold.json, without its page 0x28
                                read) or after earlier use (preview-sequence.json), chosen by the first page 0x20 read.
                                Position tolerance \(PreviewConfiguration.defaultPositionTolerance); every position
                                that differs from the capture is noted below.
                                Format of tools/capture/cap3.py; image data in \(base).raw.
                                Contains the scanner's serial number: keep outside the repository.
                                """)
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
        let result = Result { () throws(ExportError) -> URL in
            try ExportService.export(session.image, settings: exportSettings, date: date)
        }
        lastExport = result
        if case .success = result, exportSettings.incrementsFrame { exportSettings.frame += 1 }
        return result
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
        // As the export will write it: with the roll name validated.
        ExportService.nextFileName(settings: exportSettings.validated, date: date)
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
        if viewport.imageWidth != image.width || viewport.imageHeight != image.expectedHeight {
            viewport.setImageSize(width: image.width, height: image.expectedHeight)
            cropRect = nil
        }
        if startupZoomPending {
            // A new preview: the zoom of Settings > Display, Fit by default.
            startupZoomPending = false
            if settings.startupZoom == .fit { viewport.fit() } else { viewport.actualSize() }
        }
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
