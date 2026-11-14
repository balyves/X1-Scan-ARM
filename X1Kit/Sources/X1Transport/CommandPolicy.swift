// SPDX-License-Identifier: MIT

/// Decides which commands may reach a real scanner.
///
/// By default (`.readOnly`) only these reads are allowed: those FlexColor
/// sends at start-up and while polling, plus TEST UNIT READY and REQUEST
/// SENSE as sent by tools/x1probe. Each CDB must match its template byte for
/// byte, with its direction: only the MODE SENSE page and per-page length and
/// the register address vary, within the values seen. Everything else is
/// refused before any IOKit call. `.unrestricted` lets every command through
/// and must only be used for runs the user has explicitly approved
/// (CLAUDE.md, rule 4).
public struct CommandPolicy: Sendable, Hashable {
    public struct ReadRule: Sendable, Hashable {
        public let name: String
        public let direction: SCSICommand.Direction
        public let maximumLength: Int
    }

    /// Read-only commands allowed by default, by opcode.
    public static let readOnlyCommands: [UInt8: ReadRule] = [
        0x00: ReadRule(name: "TEST UNIT READY", direction: .none, maximumLength: 0),
        0x03: ReadRule(name: "REQUEST SENSE", direction: .fromDevice, maximumLength: 18),
        0x12: ReadRule(name: "INQUIRY", direction: .fromDevice, maximumLength: 96),
        0x4D: ReadRule(name: "LOG SENSE", direction: .fromDevice, maximumLength: 52),
        0x5A: ReadRule(name: "MODE SENSE", direction: .fromDevice, maximumLength: 100),
        0xD3: ReadRule(name: "status / sensors", direction: .fromDevice, maximumLength: 2),
        0xDF: ReadRule(name: "scanner state", direction: .fromDevice, maximumLength: 2),
        0xEE: ReadRule(name: "read register", direction: .fromDevice, maximumLength: 1),
    ]

    /// Exact CDBs of the fixed read-only commands. INQUIRY, LOG SENSE, 0xD3
    /// and 0xDF as captured from FlexColor; TEST UNIT READY and REQUEST SENSE
    /// as sent by tools/x1probe and answered by a real X1.
    public static let capturedCDBs: [UInt8: [UInt8]] = [
        0x00: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
        0x03: [0x03, 0x00, 0x00, 0x00, 0x12, 0x00],
        0x12: [0x12, 0x00, 0x00, 0x00, 0x60, 0x00],
        0x4D: [0x4D, 0x00, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x34, 0x00],
        0xD3: [0xD3, 0x00, 0x00, 0x00, 0x02, 0x00],
        0xDF: [0xDF, 0x00, 0x00, 0x00, 0x02, 0x00],
    ]

    /// MODE SENSE `5a 00 PP 01 00 00 00 LL LL 00`: the pages seen in the
    /// captures and, for each, the lengths read (page control 0, subpage 01).
    public static let modeSenseLengths: [UInt8: Set<Int>] = [
        0x20: [34],
        0x21: [12, 100],
        0x23: [12, 60],
        0x25: [24],
        0x26: [56],
        0x27: [20],
        0x29: [14],
    ]

    /// Register read `ee 00 00 00 01 AA 00 00 01 00`: this bank, these addresses.
    public static let registerBank: UInt8 = 0x01
    public static let registerAddresses: ClosedRange<UInt8> = 0x04...0x19

    public static let readOnly = CommandPolicy(allowsStateChangingCommands: false)
    /// Lets every command through. Only for runs the user has explicitly approved.
    public static let unrestricted = CommandPolicy(allowsStateChangingCommands: true)

    public let allowsStateChangingCommands: Bool

    public init(allowsStateChangingCommands: Bool) {
        self.allowsStateChangingCommands = allowsStateChangingCommands
    }

    /// Throws `TransportError.refusedByPolicy` if the command may not be sent.
    public func check(_ command: SCSICommand) throws {
        if allowsStateChangingCommands { return }
        let opcode = command.opcode
        func refuse(_ reason: String) -> TransportError {
            .refusedByPolicy(opcode: opcode, reason: reason)
        }
        guard let rule = Self.readOnlyCommands[opcode] else {
            throw refuse("not one of the allowed read commands")
        }
        guard command.direction == rule.direction, command.dataOut.isEmpty else {
            throw refuse("\(rule.name) must be \(rule.direction.rawValue)")
        }
        guard command.transferLength <= rule.maximumLength else {
            throw refuse("\(rule.name) longer than \(rule.maximumLength) bytes")
        }
        guard CDBLayout.allocationLength(of: command.cdb) == command.transferLength else {
            throw refuse("CDB size or length field does not match the transfer length")
        }
        // The length check above guarantees the CDB size for the opcode.
        let cdb = command.cdb
        switch opcode {
        case 0x5A:
            let page = cdb[2]
            guard let lengths = Self.modeSenseLengths[page] else {
                throw refuse("MODE SENSE page \(Self.hex(page)) not seen in the captures")
            }
            guard cdb[1] == 0, cdb[3...6] == [0x01, 0, 0, 0], cdb[9] == 0 else {
                throw refuse("MODE SENSE CDB \(cdb.hexString) differs from the captured form 5a 00 PP 01 00 00 00 LL LL 00")
            }
            guard lengths.contains(command.transferLength) else {
                let seen = lengths.sorted().map(String.init).joined(separator: ", ")
                throw refuse("MODE SENSE page \(Self.hex(page)) read with \(command.transferLength) bytes, captured: \(seen)")
            }
        case 0xEE:
            guard cdb[1...3] == [0, 0, 0], cdb[6...9] == [0, 0, 0x01, 0] else {
                throw refuse("register read CDB \(cdb.hexString) differs from the captured form ee 00 00 00 01 AA 00 00 01 00")
            }
            guard cdb[4] == Self.registerBank, Self.registerAddresses.contains(cdb[5]) else {
                let allowed = "bank \(Self.hex(Self.registerBank)), "
                    + "\(Self.hex(Self.registerAddresses.lowerBound))-\(Self.hex(Self.registerAddresses.upperBound))"
                throw refuse("register \(Self.hex(cdb[4])).\(Self.hex(cdb[5])) outside \(allowed)")
            }
        default:
            guard let captured = Self.capturedCDBs[opcode], cdb == captured else {
                throw refuse("\(rule.name) CDB \(cdb.hexString) differs from the captured \((Self.capturedCDBs[opcode] ?? []).hexString)")
            }
        }
    }

    /// `0x05`, two uppercase digits.
    static func hex(_ byte: UInt8) -> String {
        let digits = String(byte, radix: 16, uppercase: true)
        return "0x" + (digits.count == 1 ? "0" + digits : digits)
    }
}
