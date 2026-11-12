// SPDX-License-Identifier: MIT
import X1Transport

/// Builds CDBs in FlexColor's layout (docs/protocol.md §3).
public enum CDB {
    /// 6 bytes `[op, p1>>16, p1>>8, p1, len, 0]` for groups 0 and 6,
    /// 10 bytes `[op, 0, p1 (BE32), len (BE24), 0]` otherwise.
    public static func make(_ opcode: UInt8, parameter: UInt32 = 0, length: UInt32 = 0) -> [UInt8] {
        func byte(_ value: UInt32, _ shift: UInt32) -> UInt8 { UInt8(truncatingIfNeeded: value >> shift) }
        if CDBLayout.length(forOpcode: opcode) == 6 {
            precondition(parameter <= 0xFF_FFFF && length <= 0xFF, "value too large for a 6-byte CDB")
            return [opcode, byte(parameter, 16), byte(parameter, 8), byte(parameter, 0), UInt8(length), 0]
        }
        precondition(length <= 0xFF_FFFF, "length too large for a 10-byte CDB")
        return [opcode, 0,
                byte(parameter, 24), byte(parameter, 16), byte(parameter, 8), byte(parameter, 0),
                byte(length, 16), byte(length, 8), byte(length, 0), 0]
    }
}

/// X1 commands, with the exact layouts seen in the captures (docs/protocol.md §4).
public enum X1Command {
    // MARK: Read-only (allowed by CommandPolicy.readOnly)

    /// 0x12 INQUIRY, 96 bytes. [confirmed]
    public static func inquiry() -> SCSICommand {
        .read(CDB.make(0x12, length: 96), length: 96)
    }

    /// 0x00 TEST UNIT READY. [confirmed]
    public static func testUnitReady() -> SCSICommand {
        .noData(CDB.make(0x00))
    }

    /// 0x03 REQUEST SENSE, 18 bytes, fixed format. [confirmed]
    public static func requestSense() -> SCSICommand {
        .read(CDB.make(0x03, length: 18), length: 18)
    }

    /// 0x5A MODE SENSE(10) of a vendor page: `5a 00 PP 01 00 00 00 LL LL 00`. [confirmed]
    public static func modeSense(page: UInt8, length: Int) -> SCSICommand {
        .read(CDB.make(0x5A, parameter: UInt32(page) << 24 | 0x01_0000, length: UInt32(length)), length: length)
    }

    /// 0x4D LOG SENSE(10) of vendor page 0x30, 52 bytes. [confirmed]
    public static func usageLog() -> SCSICommand {
        .read(CDB.make(0x4D, parameter: 0x30 << 24, length: 52), length: 52)
    }

    /// 0xEE register read: `ee 00 00 00 01 AA 00 00 01 00`. [confirmed]
    public static func readRegister(_ address: UInt8) -> SCSICommand {
        .read(CDB.make(0xEE, parameter: 0x0100 | UInt32(address), length: 1), length: 1)
    }

    /// 0xD3 status / sensors, 2 bytes. Meaning [hypothesis].
    public static func sensors() -> SCSICommand {
        .read(CDB.make(0xD3, length: 2), length: 2)
    }

    /// 0xDF scanner state, 2 bytes: `df 00 00 00 02 00`. [confirmed]
    public static func scannerState() -> SCSICommand {
        .read(CDB.make(0xDF, length: 2), length: 2)
    }

    // MARK: State-changing (refused by CommandPolicy.readOnly)

    /// 0xD2 `d2 00 00 01 00 00`, once at start-up. Effect unknown.
    public static func startupD2() -> SCSICommand {
        .noData(CDB.make(0xD2, parameter: 0x01))
    }

    public enum SessionPhase: Sendable {
        case start, end
    }

    /// 0xCF `cf 00 01 80 00 00` before a preview, `cf 00 02 80 00 00` after. [hypothesis: session]
    public static func session(_ phase: SessionPhase) -> SCSICommand {
        .noData(CDB.make(0xCF, parameter: phase == .start ? 0x0180 : 0x0280))
    }

    /// 0xF0 set mode `f0 00 A B C D 00 00 02 00`, data `00 00`.
    public static func setMode(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> SCSICommand {
        let flags = UInt32(a) << 24 | UInt32(b) << 16 | UInt32(c) << 8 | UInt32(d)
        return .write(CDB.make(0xF0, parameter: flags, length: 2), data: [0x00, 0x00])
    }

    /// 0x24 SET WINDOW, 68 bytes.
    public static func setWindow(_ descriptor: [UInt8]) -> SCSICommand {
        precondition(descriptor.count == 68, "SET WINDOW data is 68 bytes")
        return .write(CDB.make(0x24, length: 68), data: descriptor)
    }

    /// 0xE4 `e4 00 00 00 01 00 00 00 0c 00`, 12 bytes. [hypothesis: CCD exposure]
    public static func exposure(_ data: [UInt8]) -> SCSICommand {
        precondition(data.count == 12, "0xE4 data is 12 bytes")
        return .write(CDB.make(0xE4, parameter: 0x0100, length: 12), data: data)
    }

    /// 0xE1 `e1 00 00 00 00 01 00 00 04 00`, read once during calibration. Meaning unknown.
    public static func readE1() -> SCSICommand {
        .read(CDB.make(0xE1, parameter: 0x01, length: 4), length: 4)
    }

    /// 0x1B SCAN `1b 00 00 01 01 00`. The CDB says 1 but the scanner returns 2 bytes (`00 00`). [confirmed]
    public static func scan() -> SCSICommand {
        .read(CDB.make(0x1B, parameter: 0x01, length: 0x01), length: 2)
    }

    /// 0x28 READ(10) `28 00 01 00 NN FF LL LL LL 00`: NN lines, FF = 01 calibration / 00 image. [confirmed]
    public static func read(lines: UInt8, calibration: Bool, bytes: Int) -> SCSICommand {
        let parameter = 0x0100_0000 | UInt32(lines) << 8 | (calibration ? 0x01 : 0x00)
        return .read(CDB.make(0x28, parameter: parameter, length: UInt32(bytes)), length: bytes)
    }

    /// 0xDB stop `db 00 00 00 00 00`, end of scan. [confirmed]
    public static func stop() -> SCSICommand {
        .noData(CDB.make(0xDB))
    }
}
