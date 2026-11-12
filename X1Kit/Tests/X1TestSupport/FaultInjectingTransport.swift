// SPDX-License-Identifier: MIT
import X1Transport

/// Wraps a transport and corrupts one non-polling command, to test how the
/// preview stops.
public actor FaultInjectingTransport: SCSITransport {
    public enum Fault: Sendable {
        /// The command fails with CHECK CONDITION. From then on this transport
        /// plays the scanner alone: DB is accepted and 0xDF answers 08 01, then 00 00.
        case checkCondition
        /// The command is forwarded, and the measured position (page 0x20,
        /// bytes 27-28) in its response is shifted.
        case shiftMeasuredPosition(by: Int)
    }

    private let inner: any SCSITransport
    private let faultIndex: Int
    private let fault: Fault
    private var nonPollingCount = 0
    private var playingAlone = false
    private var statesAfterFault: [[UInt8]] = [[0x08, 0x01], [0x00, 0x00]]

    /// Every command received, in order.
    public private(set) var log: [SCSICommand] = []
    /// Position in `log` of the corrupted command.
    public private(set) var faultLogIndex: Int?

    /// `index`: 0-based position of the command to corrupt among non-polling commands.
    public init(inner: any SCSITransport, faultAtNonPollingCommand index: Int, fault: Fault) {
        self.inner = inner
        self.faultIndex = index
        self.fault = fault
    }

    /// Commands received after the corrupted one.
    public var commandsAfterFault: [SCSICommand] {
        guard let faultLogIndex else { return [] }
        return Array(log[(faultLogIndex + 1)...])
    }

    public func execute(_ command: SCSICommand) async throws -> SCSIResult {
        log.append(command)
        if playingAlone {
            if command.opcode == 0xDF {
                let state = statesAfterFault.count > 1 ? statesAfterFault.removeFirst() : statesAfterFault[0]
                return SCSIResult(data: state)
            }
            return SCSIResult()
        }
        guard !SimulatedX1.pollingOpcodes.contains(command.opcode) else {
            return try await inner.execute(command)
        }
        let index = nonPollingCount
        nonPollingCount += 1
        guard index == faultIndex else { return try await inner.execute(command) }

        faultLogIndex = log.count - 1
        switch fault {
        case .checkCondition:
            playingAlone = true
            var sense = [UInt8](repeating: 0, count: 18)
            sense[0] = 0x70
            sense[2] = 0x04  // hardware error
            return SCSIResult(status: SCSIResult.checkCondition, sense: sense)
        case .shiftMeasuredPosition(let delta):
            let result = try await inner.execute(command)
            var data = result.data
            let position = Int(data[27]) | Int(data[28]) << 8
            let shifted = UInt16(clamping: position + delta)
            data[27] = UInt8(shifted & 0xFF)
            data[28] = UInt8(shifted >> 8)
            return SCSIResult(status: result.status, data: data, sense: result.sense)
        }
    }
}
