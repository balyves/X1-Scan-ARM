// SPDX-License-Identifier: MIT
import X1Protocol
import X1Transport

public struct PreviewConfiguration: Sendable {
    /// Delay between two 0xDF polls.
    public var pollInterval: Duration
    /// Longest wait for a 0xDF state.
    public var stateTimeout: Duration
    /// Largest accepted difference between a measured position (page 0x20)
    /// and the captured one, checked only after a window that requests a
    /// position (`requestsPosition`). 256 (docs/decisions.md, "Position
    /// tolerance"): the check is for gross anomalies (thousands); the largest
    /// difference seen on a checked read is 192, in one capture, and
    /// differences come in steps of 64.
    public var positionTolerance: Int

    public static let defaultPositionTolerance = 256

    public init(pollInterval: Duration = .milliseconds(100),
                stateTimeout: Duration = .seconds(120),
                positionTolerance: Int = defaultPositionTolerance) {
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
    /// A fixed script, or a plan whose first page 0x20 read chooses the rest.
    private let plan: PreviewPlan?
    private let fixedScript: [PreviewStep]

    public init(transport: any SCSITransport,
                configuration: PreviewConfiguration = PreviewConfiguration(),
                script: [PreviewStep] = PreviewScript.flexColor4813) {
        self.transport = transport
        self.configuration = configuration
        self.plan = nil
        self.fixedScript = script
    }

    /// Runs `plan`: the common part, then the cold or warm sequence according
    /// to the first page 0x20 read of the session (`.sequenceChoice`).
    public init(transport: any SCSITransport,
                configuration: PreviewConfiguration = PreviewConfiguration(),
                plan: PreviewPlan) {
        self.transport = transport
        self.configuration = configuration
        self.plan = plan
        self.fixedScript = []
    }

    /// The steps known before the run: the fixed script, or the longer of
    /// the plan's two sequences (the cold one).
    public var script: [PreviewStep] {
        guard let plan else { return fixedScript }
        let cold = plan.steps(for: .cold), warm = plan.steps(for: .warm)
        return cold.count >= warm.count ? cold : warm
    }

    /// Runs the script. `progress`, if given, receives a `PreviewEvent` for
    /// every step, accepted page 0x20 and accepted READ; it never changes what
    /// is sent. Cancelling the task is handled like an anomaly
    /// (`PreviewAnomaly.cancelled`): nothing more before SCAN, the stop
    /// sequence after it.
    public func run(progress: PreviewEventHandler? = nil) async throws(PreviewError) -> PreviewCapture {
        var capture = PreviewCapture()
        var scanSent = false
        var lastLineCount: Int?
        // Page 0x20 reads before any window that requests a position show the
        // state left by earlier use (defaults after power-on, or the last
        // scan), not a measurement: no tolerance check until one has been sent.
        var positionRequested = false
        var steps = plan?.common ?? fixedScript
        var phases = PreviewPhase.phases(for: script)
        var index = 0

        while index < steps.count {
            let step = steps[index]
            do {
                if Task.isCancelled { throw PreviewAnomaly.cancelled }
                progress?(.step(index: index, count: phases.count, phase: phases[min(index, phases.count - 1)]))
                if step.kind == .scan { scanSent = true }  // set before sending: the scanner may have started
                let result = try await transport.execute(step.command)
                try verify(result, of: step.command)
                try handle(result, of: step, scanSent: scanSent, positionRequested: positionRequested,
                           lastLineCount: &lastLineCount, capture: &capture, progress: progress)
                if step.kind == .sequenceChoice, let plan, let choice = capture.choice {
                    steps = plan.steps(for: choice)
                    phases = PreviewPhase.phases(for: steps)
                    progress?(.sequenceChosen(choice))
                }
                if Self.requestsPosition(step.command) { positionRequested = true }
                if let state = steps[index].waitUntil {
                    try await waitForState(state, honouringCancellation: true)
                }
            } catch {
                // A cancelled Task.sleep (0xDF wait, or a transport delay) is a cancellation too.
                let anomaly: PreviewAnomaly = switch error {
                case let anomaly as PreviewAnomaly: anomaly
                case is CancellationError: .cancelled
                default: .transport(String(describing: error))
                }
                var stop: EmergencyStopOutcome?
                if scanSent {
                    progress?(.stopping)
                    stop = await emergencyStop()
                }
                throw PreviewError(stepIndex: index, command: step.command, anomaly: anomaly, emergencyStop: stop)
            }
            index += 1
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

    /// SET WINDOW whose target position (offset 50, LE16 followed by two zero bytes in every captured window, docs/protocol.md §9) is not 0.
    public static func requestsPosition(_ command: SCSICommand) -> Bool {
        command.opcode == 0x24 && command.dataOut.count >= 54 && command.dataOut[50..<54].contains { $0 != 0 }
    }

    private func handle(_ result: SCSIResult, of step: PreviewStep, scanSent: Bool, positionRequested: Bool,
                        lastLineCount: inout Int?, capture: inout PreviewCapture,
                        progress: PreviewEventHandler?) throws {
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
        case .sequenceChoice:
            let status = try parse { try ScanStatusPage(result.data) }
            let choice: PreviewPlan.Choice
            if status.showsPowerOnValues {
                choice = .cold
            } else if status.showsValuesLeftByEarlierUse {
                choice = .warm
            } else {
                throw PreviewAnomaly.unrecognisedStartState(channelValues: status.channelValues)
            }
            // A fixed script must get the state it was written for.
            if plan == nil, choice != .cold {
                throw PreviewAnomaly.notJustSwitchedOn(channelValues: status.channelValues)
            }
            capture.choice = choice
            capture.scanStatuses.append(status)
            progress?(.scanStatus(status))
        case .positionGate(let captured):
            let status = try parse { try ScanStatusPage(result.data) }
            if status.measuredPosition != captured {
                progress?(.positionDifference(captured: captured, measured: status.measuredPosition, checked: true))
            }
            guard abs(status.measuredPosition - captured) <= configuration.positionTolerance else {
                throw PreviewAnomaly.unexpectedCarriagePosition(captured: captured, measured: status.measuredPosition,
                                                                tolerance: configuration.positionTolerance)
            }
            capture.scanStatuses.append(status)
            progress?(.scanStatus(status))
        case .scanStatus(let captured):
            let status = try parse { try ScanStatusPage(result.data) }
            if status.measuredPosition != captured {
                progress?(.positionDifference(captured: captured, measured: status.measuredPosition,
                                              checked: positionRequested))
            }
            guard !positionRequested || abs(status.measuredPosition - captured) <= configuration.positionTolerance else {
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
            progress?(.scanStatus(status))
        case .read(let purpose):
            capture.append(result.data, for: purpose)
            progress?(.data(result.data, purpose: purpose))
        }
    }

    private func parse<T>(_ body: () throws -> T) throws -> T {
        do { return try body() } catch { throw PreviewAnomaly.malformedResponse(String(describing: error)) }
    }

    // MARK: Waiting on 0xDF

    /// Polls 0xDF until `target`. Only the observed busy states
    /// (`ScannerState.observedBusyStates`) are accepted meanwhile.
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
    /// The read before the warm sequence's window with target 25 000 is too far
    /// from the capture: stopped before that window.
    case unexpectedCarriagePosition(captured: Int, measured: Int, tolerance: Int)
    /// A fixed cold script was run and the first page 0x20 read does not show the power-on values.
    case notJustSwitchedOn(channelValues: [Int])
    /// The first page 0x20 read shows neither the power-on values nor values left by earlier use.
    case unrecognisedStartState(channelValues: [Int])
    case lineCounterWentBack(previous: Int, current: Int)
    case unexpectedState(ScannerState, waitingFor: ScannerState)
    case stateTimeout(waitingFor: ScannerState, last: ScannerState)
    case malformedResponse(String)
    case transport(String)
    /// The real scanner could not be opened: nothing was sent.
    case couldNotOpen(String)
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
        case .notJustSwitchedOn(let values):
            "the X1 is not in its power-on state (page 0x20 bytes 19-24: "
                + values.map(String.init).joined(separator: " / ")
                + ", expected 2048 / 2048 / 2048): switch it off and on again, then start the preview again"
        case .unrecognisedStartState(let values):
            "unexpected scanner state at session start (page 0x20 bytes 19-24: "
                + values.map(String.init).joined(separator: " / ")
                + "): neither the power-on values nor values left by earlier use"
        case .unexpectedCarriagePosition(let captured, let measured, let tolerance):
            "unexpected carriage position: read \(measured), expected \(captured), difference \(measured - captured) "
                + "(tolerance \(tolerance)); stopped before the window with target 25 000"
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
        case .couldNotOpen(let detail):
            "the scanner could not be opened (nothing was sent): \(detail)"
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

    public init(stepIndex: Int, command: SCSICommand, anomaly: PreviewAnomaly, emergencyStop: EmergencyStopOutcome?) {
        self.stepIndex = stepIndex
        self.command = command
        self.anomaly = anomaly
        self.emergencyStop = emergencyStop
    }

    public var description: String {
        var text = "preview stopped at step \(stepIndex) (\(command)): \(anomaly)"
        if let emergencyStop { text += "; stop sequence: \(emergencyStop)" }
        return text
    }
}
