// SPDX-License-Identifier: MIT

/// One SCSI command: its CDB and the size and direction of its data phase.
public struct SCSICommand: Sendable, Hashable, CustomStringConvertible {
    public enum Direction: String, Sendable, Hashable {
        /// No data phase.
        case none
        /// Scanner to host (a read).
        case fromDevice
        /// Host to scanner.
        case toDevice
    }

    public let cdb: [UInt8]
    public let direction: Direction
    /// Bytes requested from the scanner, or sent to it.
    public let transferLength: Int
    /// Bytes sent to the scanner. Empty unless `direction == .toDevice`.
    public let dataOut: [UInt8]

    public init(cdb: [UInt8], direction: Direction, transferLength: Int, dataOut: [UInt8] = []) {
        precondition(!cdb.isEmpty, "empty CDB")
        precondition(transferLength >= 0)
        precondition(direction != .none || transferLength == 0, "no data phase but a transfer length")
        precondition(direction == .toDevice || dataOut.isEmpty, "dataOut is only for .toDevice")
        precondition(direction != .toDevice || dataOut.count == transferLength, "dataOut size differs from transferLength")
        self.cdb = cdb
        self.direction = direction
        self.transferLength = transferLength
        self.dataOut = dataOut
    }

    public static func noData(_ cdb: [UInt8]) -> SCSICommand {
        SCSICommand(cdb: cdb, direction: .none, transferLength: 0)
    }

    public static func read(_ cdb: [UInt8], length: Int) -> SCSICommand {
        SCSICommand(cdb: cdb, direction: .fromDevice, transferLength: length)
    }

    public static func write(_ cdb: [UInt8], data: [UInt8]) -> SCSICommand {
        SCSICommand(cdb: cdb, direction: .toDevice, transferLength: data.count, dataOut: data)
    }

    public var opcode: UInt8 { cdb[0] }

    public var description: String {
        var text = cdb.hexString
        switch direction {
        case .none: break
        case .fromDevice: text += " <- \(transferLength) bytes"
        case .toDevice: text += " -> \(dataOut.hexString)"
        }
        return text
    }
}

/// Result of one command.
public struct SCSIResult: Sendable, Hashable {
    public static let good: UInt8 = 0x00
    public static let checkCondition: UInt8 = 0x02

    /// SCSI status byte.
    public let status: UInt8
    /// Bytes received from the scanner (empty for commands without a read phase).
    public let data: [UInt8]
    /// Fixed-format sense data, when the status is CHECK CONDITION.
    public let sense: [UInt8]

    public init(status: UInt8 = SCSIResult.good, data: [UInt8] = [], sense: [UInt8] = []) {
        self.status = status
        self.data = data
        self.sense = sense
    }

    public var isGood: Bool { status == Self.good }

    /// Sense key (fixed-format sense, byte 2, low nibble).
    public var senseKey: UInt8? { sense.count > 2 ? sense[2] & 0x0F : nil }
}
