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
    /// Image lines received (READ with flag 00, lead-in lines excluded).
    public var linesReceived = 0
    public var linesExpected = 0

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

    public private(set) var state: State = .idle
    public private(set) var progress = PreviewProgress()
    public private(set) var image: PreviewImage?
    /// Increases every time `image` gains rows.
    public private(set) var imageRevision = 0

    public let script: [PreviewStep]
    private var runTask: Task<Result<PreviewCapture, PreviewError>, Never>?
    private var consumer: Task<Void, Never>?
    private var white: [[UInt8]] = []
    private var dark: [[UInt8]] = []
    private var decoder: IncrementalPreviewDecoder?
    private var decodingError: String?
    /// The simulator of the last run, for tests.
    private(set) var simulator: SimulatedX1?

    public init(script: [PreviewStep] = PreviewScript.flexColor4813) {
        self.script = script
    }

    /// Image lines the script reads (819 for FlexColor 4.8.13's preview).
    public var expectedImageLines: Int {
        script.reduce(0) { total, step in
            step.kind == .read(.image) ? total + Int(step.command.cdb[4]) : total
        }
    }

    public var isBusy: Bool { state == .running || state == .stopping }

    /// Starts a preview on the virtual X1. Does nothing if one is running.
    public func start(on scanner: VirtualScanner) {
        guard !isBusy else { return }
        reset()
        state = .running
        progress.stepCount = script.count
        progress.linesExpected = expectedImageLines

        let (events, continuation) = AsyncStream.makeStream(of: PreviewEvent.self, bufferingPolicy: .unbounded)
        let made = scanner.makeTransport()
        simulator = made.simulator
        let runner = PreviewRunner(transport: made.transport, configuration: scanner.configuration,
                                   script: script)
        let runTask = Task.detached { () -> Result<PreviewCapture, PreviewError> in
            defer { continuation.finish() }
            do throws(PreviewError) {
                return .success(try await runner.run { continuation.yield($0) })
            } catch {
                return .failure(error)
            }
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
    }

    private func handle(_ event: PreviewEvent) {
        switch event {
        case .step(let index, let count, let phase):
            progress.stepIndex = index
            progress.stepCount = count
            progress.phase = phase
        case .scanStatus:
            break
        case .stopping:
            state = .stopping
        case .data(let bytes, let purpose):
            switch purpose {
            case .whiteReference: white.append(bytes)
            case .darkReference: dark.append(bytes)
            case .image: appendImage(bytes)
            case .calibrationLine, .leadIn: break
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

    private func finish(_ result: Result<PreviewCapture, PreviewError>) {
        runTask = nil
        switch result {
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
    }
}
