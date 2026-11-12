// SPDX-License-Identifier: MIT

/// Decides which commands may reach a real scanner.
///
/// By default (`.readOnly`) only the reads FlexColor sends at start-up are
/// allowed (the list of tools/x1probe, plus the 0xDF state read), each with
/// its direction and a maximum length. Everything else is refused before any
/// IOKit call. `.unrestricted` lets every command through and must only be
/// used for runs the user has explicitly approved (CLAUDE.md, rule 4).
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
    }
}
