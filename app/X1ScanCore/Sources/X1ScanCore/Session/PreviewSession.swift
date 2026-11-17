// SPDX-License-Identifier: MIT
import Foundation
import Observation
import X1Image
import X1Preview
import X1Transport

/// Progress of a running preview.
public struct PreviewProgress: Sendable, Hashable {
    public var phase: PreviewPhase?
    public var stepIndex = 0
    public var stepCount = 0
    /// Image lines received (READ with flag 00; in a preview without the
    /// lead-in lines, in a scan with the priming lines).
    public var linesReceived = 0
    public var linesExpected = 0
    /// Scan only: lines of the 400-line step received, and expected.
    public var focusLinesReceived = 0
    public var focusLinesExpected = 0

    public init() {}

    /// 0...1, over the whole sequence.
    public var fraction: Double {
        stepCount > 0 ? Double(stepIndex + 1) / Double(stepCount) : 0
    }
}

/// Why a preview ended without completing.
public struct PreviewFailure: Sendable, Hashable, CustomStringConvertible {
    public enum Cause: Sendable, Hashable {
        /// The scanner (here, the virtual one) did something unexpected.
        case anomaly(PreviewAnomaly)
        /// The image lines could not be decoded. The scanner side completed.
        case decoding(String)
    }

    public let cause: Cause
    /// Index of the failing step in the script, for anomalies.
    public let stepIndex: Int?
    /// Outcome of the stop sequence; nil when SCAN had not been sent.
    public let emergencyStop: EmergencyStopOutcome?
    /// Full text for the details area and the log.
    public let description: String
}

/// Runs the preview on the virtual X1 and builds the image as lines arrive.
///
/// Stop (decisions.md, "Scanner safety"): `stop()` cancels the run. Before
/// SCAN the runner sends nothing more; after SCAN it sends only `DB` and
/// waits for 0xDF = 00 00, and that wait cannot be cancelled. Until it is
/// over the session stays `.stopping`, and `waitUntilIdle()` lets the app
/// delay quitting.
@MainActor
@Observable
public final class PreviewSession {
    public enum State: Sendable, Hashable {
        case idle
        case running
        /// Stop requested, or stop sequence in progress after an anomaly.
        case stopping
        case finished
        /// Stopped by the user. The outcome of the stop sequence, if SCAN had been sent.
        case stopped(EmergencyStopOutcome?)
        case failed(PreviewFailure)
    }

    public enum Kind: Sendable, Hashable {
        case preview
        /// FlexColor's captured scan (`ScanScript`); the image is decoded at the end.
        case scan
    }

    public private(set) var state: State = .idle
    /// What the current or last run is.
    public private(set) var kind: Kind = .preview
    public private(set) var progress = PreviewProgress()
    public private(set) var image: PreviewImage?
    /// Increases every time `image` gains rows.
    public private(set) var imageRevision = 0

    public let script: [PreviewStep]
    private var runTask: Task<Result<PreviewCapture, PreviewError>, Never>?
    private var consumer: Task<Void, Never>?
    /// Called once with the final state of a run on the real X1 (or of a scan
    /// on the virtual X1), before anyone waiting on `waitUntilIdle` resumes.
    private var realRunFinished: (@MainActor (State) -> Void)?
    /// The log of the run on the real X1, closed once `realRunFinished` has
    /// run (it may note the saved file).
    private var runLog: CaptureLog?
    private var white: [[UInt8]] = []
    private var dark: [[UInt8]] = []
    private var decoder: IncrementalPreviewDecoder?
    private var decodingError: String?
    /// Scan: the full-width white and dark reads, and the image reads
    /// (priming lines first) kept until the end.
    private var scanReference: [[UInt8]] = []
    private var scanImage: [[UInt8]] = []
    private var scanPriming = 0
    /// The simulator of the last run, for tests.
    private(set) var simulator: SimulatedX1?

    public init(script: [PreviewStep] = PreviewScript.flexColor4813) {
        self.script = script
    }

    /// What the real X1 receives: FlexColor's cold or warm preview, chosen by
    /// the first page 0x20 read; anything else stops there, before any window,
    /// mode, exposure or READ (docs/decisions.md, "Real X1: cold or warm
    /// sequence"). Both have the same image reads.
    public static let realScannerPlan = PreviewScript.plan

    /// Image lines the script reads (819 for FlexColor 4.8.13's preview).
    public var expectedImageLines: Int { Self.imageLines(in: script) }

    private static func imageLines(in script: [PreviewStep], kind: Kind = .preview) -> Int {
        script.reduce(0) { total, step in
            step.kind == .read(.image) || (kind == .scan && step.kind == .read(.leadIn))
                ? total + Int(step.command.cdb[4]) : total
        }
    }

    /// The scan the app runs: FlexColor's 2 000 ppi scan session.
    public static let scanScript = ScanScript.flexColor4813Scan2000ppi

    /// Starts FlexColor's captured scan on the virtual X1 (replay of its scan
    /// session). Does nothing if a run is going on or the scan capture is missing.
    public func startScan(on scanner: VirtualScanner, finished: (@MainActor (State) -> Void)? = nil) {
        guard !isBusy, let made = scanner.makeScanTransport() else { return }
        realRunFinished = finished
        simulator = made.simulator
        let runner = PreviewRunner(transport: made.transport, configuration: scanner.configuration,
                                   script: Self.scanScript)
        launch(script: Self.scanScript, kind: .scan) { continuation in
            do throws(PreviewError) {
                return .success(try await runner.run { continuation.yield($0) })
            } catch {
                return .failure(error)
            }
        }
    }

    /// Starts FlexColor's captured scan on the real X1, as
    /// `start(onRealScanner:log:finished:)` does for the preview: `connection`
    /// lets through only the scan session with its one substitution.
    public func startScan(onRealScanner connection: any ScannerConnection, log: CaptureLog,
                          finished: (@MainActor (State) -> Void)? = nil) {
        guard !isBusy else { return }
        let runner = PreviewRunner(transport: LoggingTransport(inner: connection, log: log),
                                   configuration: PreviewConfiguration(), script: Self.scanScript)
        startReal(runner: runner, kind: .scan, connection: connection, log: log, finished: finished)
    }

    public var isBusy: Bool { state == .running || state == .stopping }

    /// Starts a preview on the virtual X1. Does nothing if one is running.
    public func start(on scanner: VirtualScanner) {
        guard !isBusy else { return }
        let made = scanner.makeTransport()
        simulator = made.simulator
        let runner = PreviewRunner(transport: made.transport, configuration: scanner.configuration,
                                   script: script)
        launch(script: script) { continuation in
            do throws(PreviewError) {
                return .success(try await runner.run { continuation.yield($0) })
            } catch {
                return .failure(error)
            }
        }
    }

    /// Starts FlexColor's captured preview on the real X1 (step 4). `connection`
    /// is an `IOKitTransport` in captured-sequence mode: it refuses anything that is
    /// not the captured sequence. It is opened here and always closed at the
    /// end. Every command and response goes to `log`. Does nothing if a
    /// preview is running.
    public func start(onRealScanner connection: any ScannerConnection, log: CaptureLog,
                      finished: (@MainActor (State) -> Void)? = nil) {
        guard !isBusy else { return }
        let runner = PreviewRunner(transport: LoggingTransport(inner: connection, log: log),
                                   configuration: PreviewConfiguration(), plan: Self.realScannerPlan)
        startReal(runner: runner, kind: .preview, connection: connection, log: log, finished: finished)
    }

    /// Common part of both runs on the real X1: open, run, log, always close.
    private func startReal(runner: PreviewRunner, kind: Kind, connection: any ScannerConnection, log: CaptureLog,
                           finished: (@MainActor (State) -> Void)?) {
        realRunFinished = finished
        runLog = log
        simulator = nil
        let script = runner.script
        let firstCommand = script[0].command
        let name = kind == .scan ? "scan" : "preview"
        launch(script: script, kind: kind) { continuation in
            do {
                try await connection.open()
            } catch {
                log.note("could not open the scanner: \(error)")
                return .failure(PreviewError(stepIndex: 0, command: firstCommand,
                                             anomaly: .couldNotOpen(String(describing: error)), emergencyStop: nil))
            }
            let result: Result<PreviewCapture, PreviewError>
            do throws(PreviewError) {
                result = .success(try await runner.run { event in
                    Self.note(event, in: log)
                    continuation.yield(event)
                })
            } catch {
                result = .failure(error)
            }
            await connection.close()
            switch result {
            case .success: log.note("\(name) complete")
            case .failure(let error): log.note(error.description)
            }
            return result
        }
    }

    /// The choice of sequence, and every position that differs from the
    /// capture (to revise the tolerance with later sessions; docs/decisions.md).
    nonisolated static func note(_ event: PreviewEvent, in log: CaptureLog) {
        switch event {
        case .sequenceChosen(let choice):
            log.note("sequence chosen by the first page 0x20 read: \(choice == .cold ? "cold" : "warm")")
        case .positionDifference(let expected, let measured, let checked):
            log.note("position: expected \(expected), measured \(measured), difference \(measured - expected)"
                     + (checked ? "" : " (not checked)"))
        default:
            break
        }
    }

    /// Common part of both starts: the run task, its events and the end.
    private func launch(script: [PreviewStep], kind: Kind = .preview,
                        _ body: @escaping @Sendable (AsyncStream<PreviewEvent>.Continuation) async
                            -> Result<PreviewCapture, PreviewError>) {
        reset()
        self.kind = kind
        state = .running
        progress.stepCount = script.count
        progress.linesExpected = Self.imageLines(in: script, kind: kind)
        if kind == .scan {
            progress.focusLinesExpected = script.filter { $0.kind == .read(.focusLine) }.count
        }

        let (events, continuation) = AsyncStream.makeStream(of: PreviewEvent.self, bufferingPolicy: .unbounded)
        let runTask = Task.detached { () -> Result<PreviewCapture, PreviewError> in
            defer { continuation.finish() }
            return await body(continuation)
        }
        self.runTask = runTask
        consumer = Task { [weak self] in
            for await event in events { self?.handle(event) }
            let result = await runTask.value
            self?.finish(result)
        }
    }

    /// Requests a stop. The session goes to `.stopping` until the runner returns.
    public func stop() {
        guard state == .running else { return }
        state = .stopping
        runTask?.cancel()
    }

    /// Returns once no preview is running or stopping.
    public func waitUntilIdle() async {
        await consumer?.value
    }

    private func reset() {
        progress = PreviewProgress()
        image = nil
        imageRevision = 0
        white = []
        dark = []
        decoder = nil
        decodingError = nil
        scanReference = []
        scanImage = []
        scanPriming = 0
    }

    private func handle(_ event: PreviewEvent) {
        switch event {
        case .step(let index, let count, let phase):
            progress.stepIndex = index
            progress.stepCount = count
            progress.phase = phase
        case .scanStatus, .sequenceChosen, .positionDifference:
            break
        case .stopping:
            state = .stopping
        case .data(let bytes, let purpose) where kind == .scan:
            switch purpose {
            case .focusLine: progress.focusLinesReceived += 1
            case .scanReference: scanReference.append(bytes)
            case .leadIn, .image:
                if purpose == .leadIn { scanPriming += 1 }
                scanImage.append(bytes)
                progress.linesReceived += bytes.count / (ScanScript.pixelsPerLine * PreviewScript.bytesPerPixel)
            case .calibrationLine, .whiteReference, .darkReference: break
            }
        case .data(let bytes, let purpose):
            switch purpose {
            case .whiteReference: white.append(bytes)
            case .darkReference: dark.append(bytes)
            case .image: appendImage(bytes)
            case .calibrationLine, .leadIn, .scanReference, .focusLine: break
            }
        }
    }

    private func appendImage(_ bytes: [UInt8]) {
        let width = PreviewScript.previewPixelsPerLine
        progress.linesReceived += bytes.count / (width * PreviewScript.bytesPerPixel)
        guard decodingError == nil else { return }
        do {
            if decoder == nil {
                let created = try IncrementalPreviewDecoder(white: white, dark: dark, width: width)
                decoder = created
                // The line gap costs `lineGap` rows at the top and at the bottom.
                image = PreviewImage(width: width, expectedHeight: max(expectedImageLines - 2 * created.lineGap, 0))
            }
            guard var decoder, var image else { return }
            let rows = try decoder.append(bytes)
            image.append(rows: rows, from: decoder)
            self.decoder = decoder
            self.image = image
            if !rows.isEmpty { imageRevision += 1 }
        } catch {
            decodingError = String(describing: error)
        }
    }

    /// The scan, decoded (docs/protocol.md §10): linear, flat field, lines
    /// realigned and resampled. The screen and the TIFF show the same values.
    private func decodeScan() throws -> PreviewImage {
        let scan = try Self.scanGeometry()
        let linear = try ScanDecoding.decode(calibration: scanReference,
                                             calibrationWidth: ScanScript.calibrationPixelsPerLine,
                                             image: scanImage, geometry: scan, primingLines: scanPriming)
        let samples = linear.toRGB16().samples
        return PreviewImage(width: linear.width, corrected: samples, raw: samples)
    }

    private func finish(_ result: Result<PreviewCapture, PreviewError>) {
        runTask = nil
        switch result {
        case .success where kind == .scan:
            do {
                image = try decodeScan()
                imageRevision += 1
                state = .finished
            } catch {
                state = .failed(PreviewFailure(cause: .decoding(String(describing: error)), stepIndex: nil,
                                               emergencyStop: nil, description: "scan decoding: \(error)"))
            }
        case .success:
            if let decodingError {
                state = .failed(PreviewFailure(cause: .decoding(decodingError), stepIndex: nil, emergencyStop: nil,
                                               description: "image decoding: \(decodingError)"))
            } else {
                state = .finished
            }
        case .failure(let error) where error.anomaly == .cancelled:
            state = .stopped(error.emergencyStop)
        case .failure(let error):
            state = .failed(PreviewFailure(cause: .anomaly(error.anomaly), stepIndex: error.stepIndex,
                                           emergencyStop: error.emergencyStop, description: error.description))
        }
        let finished = realRunFinished
        realRunFinished = nil
        finished?(state)
        runLog?.close()
        runLog = nil
    }
}

extension PreviewSession {
    /// Geometry of the scan's image window (the last window before its SCAN).
    static func scanGeometry() throws -> ScanGeometry {
        guard let scan = scanScript.lastIndex(where: { $0.kind == .scan }),
              let window = scanScript[..<scan].last(where: { $0.command.opcode == 0x24 }),
              let geometry = ScanGeometry(windowData: window.command.dataOut) else {
            throw ImageError.noLines
        }
        return geometry
    }
}

