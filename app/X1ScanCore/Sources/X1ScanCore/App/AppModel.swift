// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import Observation
import X1Image

/// State of the read-only access to the real X1.
public enum RealScannerStatus: Sendable, Hashable {
    case notRead
    case reading
    case read(ScannerInfo)
    case failed(ScannerInspector.Failure)
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
            if source == .real { session.stop() }
        }
    }
    public let virtualScanner: VirtualScanner?
    /// Why the virtual X1 is unavailable, when it is.
    public let virtualScannerError: String?
    public let session: PreviewSession
    public private(set) var realStatus: RealScannerStatus = .notRead
    /// Serial number shown in full. Not saved: masked again at every launch.
    public var serialRevealed = false
    private let inspector: ScannerInspector

    // MARK: Layout and viewing

    public let layout: LayoutController
    public var tools = ToolState()
    public private(set) var viewport = Viewport(imageWidth: 0, imageHeight: 0)
    /// Size of the visible image area, reported by the canvas.
    public private(set) var viewSize: CGSize = .zero
    /// Framing rectangle drawn with the crop tool. No effect at this stage.
    public var cropRect: PixelRect?
    /// Pixel under the pointer, reported by the canvas.
    public var pointer: PixelCoordinate?
    public private(set) var displayImage: CGImage?
    public private(set) var histogram = Histogram.empty
    private var renderedRevision = -1
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
    }

    public init(virtualScanner: () throws -> VirtualScanner,
                inspector: ScannerInspector = .realScanner,
                layoutStore: (any LayoutStore)? = nil,
                defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.inspector = inspector
        do {
            self.virtualScanner = try virtualScanner()
            virtualScannerError = nil
        } catch {
            self.virtualScanner = nil
            virtualScannerError = String(describing: error)
        }
        session = PreviewSession()
        layout = LayoutController(store: layoutStore ?? UserDefaultsLayoutStore(defaults: defaults))
        source = defaults.string(forKey: Keys.source).flatMap(ScannerSourceKind.init) ?? .virtual
        exportSettings = defaults.data(forKey: Keys.exportSettings)
            .flatMap { try? JSONDecoder().decode(ExportSettings.self, from: $0) } ?? ExportSettings()
    }

    // MARK: Derived state

    public var toolbar: ToolbarState {
        ToolbarState(source: source, session: session.state, virtualAvailable: virtualScanner != nil,
                     hasImage: (session.image?.height ?? 0) > 0, hasExportFolder: exportSettings.folder != nil)
    }

    /// What the Scanner palette shows for the current source.
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

    public func startPreview() {
        guard toolbar.canPreview, let virtualScanner else { return }
        lastExport = nil
        session.start(on: virtualScanner)
    }

    public func stop() {
        session.stop()
    }

    /// Reads the real X1 (reads only, device closed afterwards).
    public func readRealScanner() async {
        guard source == .real, realStatus != .reading else { return }
        realStatus = .reading
        do {
            realStatus = .read(try await inspector.read())
        } catch {
            realStatus = .failed(error)
        }
    }

    @discardableResult
    public func export(date: Date = Date()) -> Result<URL, ExportError> {
        let result = Result { () throws(ExportError) -> URL in
            try ExportService.export(session.image, settings: exportSettings, date: date)
        }
        lastExport = result
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

    // MARK: Viewport

    public func viewSizeChanged(_ size: CGSize) {
        viewSize = size
        if viewport.fitsWindow { viewport.fit(in: size) }
    }

    public func zoomToFit() { viewport.fit(in: viewSize) }
    public func zoomToActualSize() { viewport.actualSize() }
    public func zoomIn() { viewport.zoomIn() }
    public func zoomOut() { viewport.zoomOut() }
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
            let fits = viewport.fitsWindow
            let magnification = viewport.magnification
            viewport = Viewport(imageWidth: image.width, imageHeight: image.expectedHeight)
            if fits { viewport.fit(in: viewSize) } else { viewport.setMagnification(magnification) }
            cropRect = nil
        }
        renderTask?.cancel()
        renderTask = Task {
            let rendered = await Task.detached(priority: .userInitiated) {
                (DisplayImage.make(from: image).map(SendableImage.init), Histogram(samples: image.corrected))
            }.value
            guard !Task.isCancelled, revision == self.session.imageRevision else { return }
            self.displayImage = rendered.0?.image
            self.histogram = rendered.1
        }
    }

    /// Waits for the latest `refreshImage` work (tests).
    public func waitForRendering() async {
        await renderTask?.value
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
