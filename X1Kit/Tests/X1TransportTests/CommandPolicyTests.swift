// SPDX-License-Identifier: MIT
import Testing
import X1Transport
import X1TestSupport

private func read(_ hex: String, _ length: Int) -> SCSICommand {
    .read([UInt8](hex: hex)!, length: length)
}

struct CommandPolicyTests {
    /// Reads FlexColor sends (INQUIRY, MODE SENSE, LOG SENSE, 0xEE, 0xD3, 0xDF)
    /// and those of tools/x1probe (TEST UNIT READY, REQUEST SENSE).
    static let allowedReads: [SCSICommand] = [
        read("12 00 00 00 60 00", 96),                   // INQUIRY
        .noData([UInt8](hex: "00 00 00 00 00 00")!),      // TEST UNIT READY
        read("03 00 00 00 12 00", 18),                   // REQUEST SENSE
        read("5a 00 26 01 00 00 00 00 38 00", 56),       // MODE SENSE page 0x26
        read("5a 00 21 01 00 00 00 00 64 00", 100),      // MODE SENSE page 0x21 (longest)
        read("4d 00 30 00 00 00 00 00 34 00", 52),       // LOG SENSE page 0x30
        read("ee 00 00 00 01 04 00 00 01 00", 1),        // register 1.04
        read("d3 00 00 00 02 00", 2),                    // 0xD3
        read("df 00 00 00 02 00", 2),                    // 0xDF state
    ]

    /// Commands that move the scanner or change its state.
    static let stateChanging: [SCSICommand] = [
        read("1b 00 00 01 01 00", 2),                                                    // SCAN
        .noData([UInt8](hex: "db 00 00 00 00 00")!),                                    // stop
        .noData([UInt8](hex: "d2 00 00 01 00 00")!),                                    // D2
        .noData([UInt8](hex: "cf 00 01 80 00 00")!),                                    // session
        .write([UInt8](hex: "f0 00 00 00 01 01 00 00 02 00")!, data: [0, 0]),           // set mode
        .write([UInt8](hex: "24 00 00 00 00 00 00 00 44 00")!, data: Array(repeating: 0, count: 68)),
        .write([UInt8](hex: "e4 00 00 00 01 00 00 00 0c 00")!, data: Array(repeating: 0, count: 12)),
        read("28 00 01 00 01 01 00 bb 50 00", 47_952),                                  // READ(10)
        read("e1 00 00 00 00 01 00 00 04 00", 4),
        .noData([UInt8](hex: "e0 00 00 00 00 00 00 00 00 00")!),                        // motor
        .write([UInt8](hex: "55 00 00 00 00 00 00 00 02 00")!, data: [0, 0]),           // MODE SELECT
        .write([UInt8](hex: "3b 00 00 00 00 00 00 00 02 00")!, data: [0, 0]),           // WRITE BUFFER
    ]

    @Test(arguments: allowedReads)
    func readOnlyPolicyAllowsStartupReads(_ command: SCSICommand) throws {
        try CommandPolicy.readOnly.check(command)
    }

    @Test(arguments: stateChanging)
    func readOnlyPolicyRefusesStateChangingCommands(_ command: SCSICommand) {
        #expect(throws: TransportError.self) { try CommandPolicy.readOnly.check(command) }
    }

    @Test(arguments: [
        read("df 00 00 00 03 00", 3),                     // 0xDF longer than 2 bytes
        read("12 00 00 00 ff 00", 255),                   // INQUIRY longer than 96 bytes
        read("12 00 00 00 60 00", 36),                    // CDB length field ≠ transfer length
        read("ee 00 01 04 01 00", 1),                     // 6-byte CDB for a 10-byte opcode
        .write([UInt8](hex: "5a 00 26 01 00 00 00 00 02 00")!, data: [0, 0]),  // allowed opcode, wrong direction
        .noData([UInt8](hex: "12 00 00 00 00 00")!),      // INQUIRY without a data phase
    ])
    func readOnlyPolicyChecksDirectionAndLength(_ command: SCSICommand) {
        #expect(throws: TransportError.self) { try CommandPolicy.readOnly.check(command) }
    }

    /// Every read of the read-only list in preview-sequence.json passes, with
    /// its captured CDB, direction and length.
    @Test func readOnlyPolicyAllowsEveryCapturedRead() throws {
        let reads = try Fixtures.sequence().exchanges.filter {
            CommandPolicy.readOnlyCommands[$0.cdbBytes.first ?? 0xFF] != nil
        }
        #expect(reads.count > 600)
        for exchange in reads {
            #expect(exchange.direction == "in")
            #expect(exchange.dataOut == nil)
            try CommandPolicy.readOnly.check(.read(exchange.cdbBytes, length: exchange.length))
        }
        // Every MODE SENSE page and length, and every register, is covered.
        let modeSense = Set(reads.filter { $0.cdbBytes[0] == 0x5A }.map { [$0.cdbBytes[2], UInt8($0.length)] })
        let expected = Set(CommandPolicy.modeSenseLengths.flatMap { page, lengths in lengths.map { [page, UInt8($0)] } })
        #expect(modeSense == expected)
        let registers = Set(reads.filter { $0.cdbBytes[0] == 0xEE }.map { $0.cdbBytes[5] })
        #expect(registers == Set(CommandPolicy.registerAddresses))
    }

    @Test(arguments: [
        // MODE SENSE pages never captured
        read("5a 00 22 01 00 00 00 00 0c 00", 12),
        read("5a 00 24 01 00 00 00 00 0c 00", 12),
        read("5a 00 28 01 00 00 00 00 0c 00", 12),
        read("5a 00 1f 01 00 00 00 00 0c 00", 12),
        read("5a 00 2a 01 00 00 00 00 0c 00", 12),
        read("5a 00 3f 01 00 00 00 00 64 00", 100),     // all pages
        read("5a 00 66 01 00 00 00 00 38 00", 56),      // page 0x26 with page control ≠ 0
        // LOG SENSE pages never captured
        read("4d 00 00 00 00 00 00 00 34 00", 52),
        read("4d 00 31 00 00 00 00 00 34 00", 52),
        read("4d 00 70 00 00 00 00 00 34 00", 52),      // page 0x30 with page control ≠ 0
        // registers outside bank 1, 0x04-0x19
        read("ee 00 00 00 01 03 00 00 01 00", 1),
        read("ee 00 00 00 01 1a 00 00 01 00", 1),
        read("ee 00 00 00 00 04 00 00 01 00", 1),       // bank 0
        read("ee 00 00 00 02 04 00 00 01 00", 1),       // bank 2
        read("ee 00 00 01 01 04 00 00 01 00", 1),       // nonzero high address byte
        read("ee 00 01 00 01 04 00 00 01 00", 1),
        // other CDB bytes differing from the captures
        read("4d 01 30 00 00 00 00 00 34 00", 52),      // LOG SENSE with SP (save parameters)
        read("4d 02 30 00 00 00 00 00 34 00", 52),      // LOG SENSE with PPC
        read("4d 00 30 00 00 01 00 00 34 00", 52),      // LOG SENSE parameter pointer
        read("4d 00 30 00 00 00 00 00 34 01", 52),      // LOG SENSE control byte
        read("4d 00 30 00 00 00 00 00 20 00", 32),      // LOG SENSE shorter than captured
        read("5a 00 26 00 00 00 00 00 38 00", 56),      // MODE SENSE subpage 00
        read("5a 00 26 ff 00 00 00 00 38 00", 56),      // MODE SENSE subpage ff
        read("5a 08 26 01 00 00 00 00 38 00", 56),      // MODE SENSE with DBD
        read("5a 00 26 01 01 00 00 00 38 00", 56),
        read("5a 00 26 01 00 00 00 00 38 01", 56),      // MODE SENSE control byte
        read("5a 00 20 01 00 00 00 00 64 00", 100),     // page 0x20: only 34 captured
        read("5a 00 26 01 00 00 00 00 0c 00", 12),      // page 0x26: only 56 captured
        read("5a 00 21 01 00 00 00 00 38 00", 56),      // page 0x21: only 12 and 100 captured
        read("ee 01 00 00 01 04 00 00 01 00", 1),       // register read, byte 1
        read("ee 00 00 00 01 04 00 00 01 01", 1),       // register read, control byte
        read("12 01 00 00 60 00", 96),                  // INQUIRY with EVPD
        read("12 00 80 00 60 00", 96),                  // INQUIRY page code
        read("12 00 00 00 24 00", 36),                  // INQUIRY shorter than captured
        read("d3 01 00 00 02 00", 2),
        read("d3 00 00 00 01 00", 1),
        read("df 00 00 01 02 00", 2),
        read("df 00 00 00 02 80", 2),
        read("03 00 00 00 08 00", 8),                   // REQUEST SENSE shorter than captured
        read("03 01 00 00 12 00", 18),
        .noData([UInt8](hex: "00 00 00 00 00 01")!),    // TEST UNIT READY control byte
    ])
    func readOnlyPolicyRefusesUncapturedPagesAndRegisters(_ command: SCSICommand) {
        #expect(throws: TransportError.self) { try CommandPolicy.readOnly.check(command) }
    }

    @Test func refusalsNameWhatDiffers() {
        #expect(throws: TransportError.refusedByPolicy(opcode: 0x5A, reason: "MODE SENSE page 0x22 not seen in the captures")) {
            try CommandPolicy.readOnly.check(read("5a 00 22 01 00 00 00 00 0c 00", 12))
        }
        #expect(throws: TransportError.refusedByPolicy(opcode: 0x5A, reason: "MODE SENSE page 0x05 not seen in the captures")) {
            try CommandPolicy.readOnly.check(read("5a 00 05 01 00 00 00 00 0c 00", 12))
        }
        #expect(throws: TransportError.refusedByPolicy(opcode: 0x5A, reason: "MODE SENSE page 0x21 read with 56 bytes, captured: 12, 100")) {
            try CommandPolicy.readOnly.check(read("5a 00 21 01 00 00 00 00 38 00", 56))
        }
        #expect(throws: TransportError.refusedByPolicy(opcode: 0xEE, reason: "register 0x00.0x04 outside bank 0x01, 0x04-0x19")) {
            try CommandPolicy.readOnly.check(read("ee 00 00 00 00 04 00 00 01 00", 1))
        }
        #expect(throws: TransportError.refusedByPolicy(opcode: 0xEE, reason: "register 0x01.0x1A outside bank 0x01, 0x04-0x19")) {
            try CommandPolicy.readOnly.check(read("ee 00 00 00 01 1a 00 00 01 00", 1))
        }
        #expect(throws: TransportError.refusedByPolicy(opcode: 0x4D, reason: "LOG SENSE CDB 4d 01 30 00 00 00 00 00 34 00 differs from the captured 4d 00 30 00 00 00 00 00 34 00")) {
            try CommandPolicy.readOnly.check(read("4d 01 30 00 00 00 00 00 34 00", 52))
        }
    }

    @Test(arguments: stateChanging)
    func unrestrictedPolicyAllowsEverything(_ command: SCSICommand) throws {
        try CommandPolicy.unrestricted.check(command)
    }

    @Test func busyScannerErrorNamesTheLikelyCause() {
        let message = TransportError.deviceBusy.description
        #expect(message.contains("already open in another program"))
        #expect(message.contains("FlexColor"))
        #expect(message.contains("0xE00002BE"))
    }

    @Test func ioKitTransportRefusesBeforeTouchingTheDevice() async throws {
        // Never opened: no IOKit call is made in this test.
        let transport = IOKitTransport()
        #expect(transport.policy == .readOnly)
        await #expect(throws: TransportError.refusedByPolicy(opcode: 0x1B, reason: "not one of the allowed read commands")) {
            try await transport.execute(read("1b 00 00 01 01 00", 2))
        }
        await #expect(throws: TransportError.notOpen) {
            try await transport.execute(read("12 00 00 00 60 00", 96))
        }
        #expect(await transport.isOpen == false)
    }
}
