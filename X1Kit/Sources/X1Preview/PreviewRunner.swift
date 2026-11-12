// SPDX-License-Identifier: MIT
import X1Protocol
import X1Transport

public struct PreviewConfiguration: Sendable {
    /// Delay between two 0xDF polls.
    public var pollInterval: Duration
    /// Longest wait for a 0xDF state.
    public var stateTimeout: Duration
    /// Largest accepted difference between a measured position (page 0x20)
    /// and the captured one. Two captures differed by 64; to be revised.
    public var positionTolerance: Int

    public init(pollInterval: Duration = .milliseconds(100),
                stateTimeout: Duration = .seconds(120),
                positionTolerance: Int = 100) {
        self.pollInterval = pollInterval
        self.stateTimeout = stateTimeout
        self.positionTolerance = positionTolerance
    }

    /// For `SimulatedX1`: no delay between polls.
    public static let simulator = PreviewConfiguration(pollInterval: .zero, stateTimeout: .seconds(5))
}

/// Runs the preview sequence and stops at the first unexpected response.
///
/// If the anomaly happens after SCAN (0x1B) was sent, the runner sends only
/// `DB 00 00 00 00 00`, waits for 0xDF to return `00 00`, and sends nothing
/// else. Before SCAN, it sends nothing more.
public struct PreviewRunner: Sendable {
    public let transport: any SCSITransport
    public let configuration: PreviewConfiguration
    public let script: [PreviewStep]

    public init(transport: any SCSITransport,
                configuration: PreviewConfiguration = PreviewConfiguration(),
                script: [PreviewStep] = PreviewScript.flexColor4813) {
        self.transport = transport
        self.configuration = configuration
        self.script = script
    }

    public func run() async throws(PreviewError) -> PreviewCapture {
        var capture = PreviewCapture()
        var scanSent = false
        var lastLineCount: Int?

        for (index, step) in script.enumerated() {
            do {
                if Task.isCancelled { throw PreviewAnomaly.cancelled }
                if step.kind == .scan { scanSent = true }  // set before sending: the scanner may have started
                let result = try await transport.execute(step.command)
                try verify(result, of: step.command)
                try handle(result, of: step, scanSent: scanSent, lastLineCount: &lastLineCount, capture: &capture)
                if let state = step.waitUntil {
                    try await waitForState(state, honouringCancellation: true)
                }
            } catch {
                let anomaly = error as? PreviewAnomaly ?? .transport(String(describing: error))
                let stop = scanSent ? await emergencyStop() : nil
                throw PreviewError(stepIndex: index, command: step.command, anomaly: anomaly, emergencyStop: stop)
            }
        }
        return capture
    }

    // MARK: Checks

    private func verify(_ result: SCSIResult, of command: SCSICommand) throws {
        guard result.isGood else {
            throw PreviewAnomaly.badStatus(status: result.status, senseKey: result.senseKey)
        }
        if command.direction == .fromDevice, result.data.count != command.transferLength {
            throw PreviewAnomaly.wrongLength(expected: command.transferLength, received: result.data.count)
        }
    }

    private func handle(_ result: SCSIResult, of step: PreviewStep, scanSent: Bool,
                        lastLineCount: inout Int?, capture: inout PreviewCapture) throws {
        switch step.kind {
        case .command:
            break
        case .inquiry:
            let inquiry = try parse { try InquiryResponse(result.data) }
            guard inquiry.isFlextightX1 else {
                throw PreviewAnomaly.unexpectedIdentity(vendor: inquiry.vendor, product: inquiry.product)
            }
        case .scan:
            guard result.data == [0x00, 0x00] else { throw PreviewAnomaly.unexpectedScanResponse(result.data) }
        case .scanStatus(let captured):
            let status = try parse { try ScanStatusPage(result.data) }
            guard abs(status.measuredPosition - captured) <= configuration.positionTolerance else {
                throw PreviewAnomaly.positionOutOfTolerance(captured: captured, measured: status.measuredPosition,
                                                            tolerance: configuration.positionTolerance)
            }
            if scanSent {
                if let previous = lastLineCount, status.linesAcquired < previous {
                    throw PreviewAnomaly.lineCounterWentBack(previous: previous, current: status.linesAcquired)
                }
                lastLineCount = status.linesAcquired
            }
            capture.scanStatuses.append(status)
        case .read(let purpose):
            capture.append(result.data, for: purpose)
        }
    }

    private func parse<T>(_ body: () throws -> T) throws -> T {
        do { return try body() } catch { throw PreviewAnomaly.malformedResponse(String(describing: error)) }
    }

    // MARK: Waiting on 0xDF

    /// Polls 0xDF until `target`. Only the busy states (08 01, 08 40) are accepted meanwhile.
    private func waitForState(_ target: ScannerState, honouringCancellation: Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + configuration.stateTimeout
        let command = X1Command.scannerState()
        while true {
            let result = try await transport.execute(command)
            try verify(result, of: command)
            let state = try parse { try ScannerState(result.data) }
            if state == target { return }
            guard state.isBusy else { throw PreviewAnomaly.unexpectedState(state, waitingFor: target) }
            guard clock.now < deadline else { throw PreviewAnomaly.stateTimeout(waitingFor: target, last: state) }
            if configuration.pollInterval > .zero {
                if honouringCancellation {
                    try await Task.sleep(for: configuration.pollInterval)
                } else {
                    try? await Task.sleep(for: configuration.pollInterval)
                }
            }
        }
    }

    /// After SCAN: send only DB, then wait for 0xDF = 00 00. Nothing else.
    private func emergencyStop() async -> EmergencyStopOutcome {
        let result: SCSIResult
        do {
            result = try await transport.execute(X1Command.stop())
        } catch {
            return .stopNotSent(String(describing: error))
        }
        guard result.isGood else {
            return .stopRefused(status: result.status, senseKey: result.senseKey)
        }
        do {
            // Keep waiting even if the task was cancelled: the scanner is moving.
            try await waitForState(.ready, honouringCancellation: false)
            return .stoppedAndReady
        } catch {
            return .notReadyAfterStop(String(describing: error))
        }
    }
}

// MARK: Errors

public enum PreviewAnomaly: Error, Hashable, CustomStringConvertible {
    case badStatus(status: UInt8, senseKey: UInt8?)
    case wrongLength(expected: Int, received: Int)
    case unexpectedIdentity(vendor: String, product: String)
    case unexpectedScanResponse([UInt8])
    case positionOutOfTolerance(captured: Int, measured: Int, tolerance: Int)
    case lineCounterWentBack(previous: Int, current: Int)
    case unexpectedState(ScannerState, waitingFor: ScannerState)
    case stateTimeout(waitingFor: ScannerState, last: ScannerState)
    case malformedResponse(String)
    case transport(String)
    case cancelled

    public var description: String {
        switch self {
        case .badStatus(let status, let senseKey):
            "SCSI status 0x\(String(status, radix: 16))" + (senseKey.map { ", sense key 0x\(String($0, radix: 16))" } ?? "")
        case .wrongLength(let expected, let received):
            "\(received) bytes received, \(expected) expected"
        case .unexpectedIdentity(let vendor, let product):
            "unexpected scanner '\(vendor)' '\(product)'"
        case .unexpectedScanResponse(let bytes):
            "SCAN returned \(bytes.hexString), 00 00 expected"
        case .positionOutOfTolerance(let captured, let measured, let tolerance):
            "measured position \(measured), captured \(captured) (tolerance \(tolerance))"
        case .lineCounterWentBack(let previous, let current):
            "line counter went back from \(previous) to \(current)"
        case .unexpectedState(let state, let target):
            "0xDF state \(state) while waiting for \(target)"
        case .stateTimeout(let target, let last):
            "timed out waiting for 0xDF \(target) (last \(last))"
        case .malformedResponse(let detail):
            "malformed response: \(detail)"
        case .transport(let detail):
            detail
        case .cancelled:
            "cancelled"
        }
    }
}

public enum EmergencyStopOutcome: Sendable, Hashable {
    /// DB accepted and 0xDF back to 00 00.
    case stoppedAndReady
    /// DB could not be delivered.
    case stopNotSent(String)
    /// DB delivered but not accepted.
    case stopRefused(status: UInt8, senseKey: UInt8?)
    /// DB accepted but 0xDF did not return to 00 00.
    case notReadyAfterStop(String)
}

public struct PreviewError: Error, CustomStringConvertible {
    /// Index in the script of the step that failed.
    public let stepIndex: Int
    public let command: SCSICommand
    public let anomaly: PreviewAnomaly
    /// Outcome of the stop sequence; nil when SCAN had not been sent.
    public let emergencyStop: EmergencyStopOutcome?

    public var description: String {
        var text = "preview stopped at step \(stepIndex) (\(command)): \(anomaly)"
        if let emergencyStop { text += "; stop sequence: \(emergencyStop)" }
        return text
    }
}
