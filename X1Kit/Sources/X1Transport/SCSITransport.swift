// SPDX-License-Identifier: MIT

/// Anything that can execute a SCSI command on an X1: the real scanner
/// (`IOKitTransport`) or a replay of a capture (`SimulatedX1`).
public protocol SCSITransport: Sendable {
    func execute(_ command: SCSICommand) async throws -> SCSIResult
}

public enum TransportError: Error, Hashable, CustomStringConvertible {
    /// The command policy refused the command; nothing was sent.
    case refusedByPolicy(opcode: UInt8, reason: String)
    /// `execute` was called before `open`.
    case notOpen
    /// No Imacon / Hasselblad SCSI device is visible to IOKit.
    case deviceNotFound
    /// IOCreatePlugInInterfaceForService returned 0xE00002BE (kIOReturnNoResources):
    /// another program, usually FlexColor, already has the scanner open.
    /// FlexColor shows the reverse case as an alert with an empty reason.
    case deviceBusy
    /// IOKit returned an error.
    case ioKit(code: Int32, operation: String)

    public var description: String {
        switch self {
        case .refusedByPolicy(let opcode, let reason):
            "command 0x\([opcode].hexString) refused by policy: \(reason)"
        case .notOpen:
            "transport is not open"
        case .deviceNotFound:
            "no Imacon / Hasselblad scanner found"
        case .deviceBusy:
            "the scanner is already open in another program (probably FlexColor, or x1probe): "
                + "quit it and try again (IOKit 0xE00002BE, kIOReturnNoResources)"
        case .ioKit(let code, let operation):
            "IOKit error 0x\(String(UInt32(bitPattern: code), radix: 16)) during \(operation)"
        }
    }
}

/// CDB layout used by FlexColor (docs/protocol.md §3).
public enum CDBLayout {
    /// 6 bytes for groups 0 and 6 (0x00-0x1F, 0xC0-0xDF), 10 bytes otherwise.
    public static func length(forOpcode opcode: UInt8) -> Int {
        opcode < 0x20 || (0xC0...0xDF).contains(opcode) ? 6 : 10
    }

    /// The transfer length written in the CDB: byte 4 for 6-byte CDBs,
    /// bytes 6-8 (big-endian) for 10-byte CDBs. `nil` if the CDB size is wrong.
    public static func allocationLength(of cdb: [UInt8]) -> Int? {
        guard let opcode = cdb.first, cdb.count == length(forOpcode: opcode) else { return nil }
        if cdb.count == 6 { return Int(cdb[4]) }
        return Int(cdb[6]) << 16 | Int(cdb[7]) << 8 | Int(cdb[8])
    }
}

extension Array where Element == UInt8 {
    /// Parses hex bytes such as "5a 00 26" or "5a0026". Returns nil on invalid input.
    public init?(hex: String) {
        let digits = hex.filter { !$0.isWhitespace }
        guard digits.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(digits.count / 2)
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            guard let byte = UInt8(digits[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = bytes
    }

    /// Lower-case hex bytes separated by spaces, as in the docs and fixtures.
    public var hexString: String {
        let symbols: [Character] = Array<Character>("0123456789abcdef")
        return map { String([symbols[Int($0 >> 4)], symbols[Int($0 & 0x0F)]]) }.joined(separator: " ")
    }
}
