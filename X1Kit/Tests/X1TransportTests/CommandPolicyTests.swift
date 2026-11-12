// SPDX-License-Identifier: MIT
import Testing
import X1Transport

private func read(_ hex: String, _ length: Int) -> SCSICommand {
    .read([UInt8](hex: hex)!, length: length)
}

struct CommandPolicyTests {
    /// The reads FlexColor sends at start-up (tools/x1probe) and 0xDF.
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
