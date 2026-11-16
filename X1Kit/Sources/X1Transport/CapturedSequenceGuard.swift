// SPDX-License-Identifier: MIT
import Synchronization

/// Lets through only FlexColor's captured preview, command after command.
///
/// Built from the capture itself (tests/fixtures/preview-sequence.json), not
/// from `PreviewScript`: the script must agree with an independent source.
/// Rules (docs/decisions.md, "Application, step 4"):
/// - every command other than a poll must be, in order, the next captured
///   exchange: same CDB, direction, length and data out, byte for byte;
/// - polls (0xEE, 0xD3, 0xDF reads of `CommandPolicy.readOnly`) are allowed
///   between steps and do not move the sequence on;
/// - after SCAN, the captured page 0x20 read may be repeated, and
///   `DB 00 00 00 00 00` (stop) is accepted out of order; after that stop
///   only 0xDF is allowed;
/// - after the last captured command, only polls.
/// Anything else is refused before it reaches the scanner.
public final class CapturedSequenceGuard: Sendable {
    public enum SetupError: Error, Hashable, CustomStringConvertible {
        case unreadableExchange(seq: Int)
        case noScan

        public var description: String {
            switch self {
            case .unreadableExchange(let seq): "captured exchange \(seq) cannot be turned into a command"
            case .noScan: "the capture has no SCAN command"
            }
        }
    }

    /// The captured commands, polls left out, in order.
    public let expected: [SCSICommand]
    private let scanIndex: Int
    private let state = Mutex(State())

    private struct State {
        var next = 0
        var stopped = false
    }

    static let stop = SCSICommand.noData([0xDB, 0x00, 0x00, 0x00, 0x00, 0x00])
    static let statusRead = SCSICommand.read([0x5A, 0x00, 0x20, 0x01, 0x00, 0x00, 0x00, 0x00, 0x22, 0x00], length: 34)

    public init(fixture: CaptureFixture) throws(SetupError) {
        var commands: [SCSICommand] = []
        for exchange in fixture.exchanges {
            let cdb = exchange.cdbBytes
            guard let opcode = cdb.first, exchange.length >= 0 else { throw .unreadableExchange(seq: exchange.seq) }
            if Self.isPoll(opcode) { continue }
            let command: SCSICommand
            switch exchange.commandDirection {
            case .fromDevice?:
                command = .read(cdb, length: exchange.length)
            case .toDevice?:
                guard let data = exchange.dataOutBytes, data.count == exchange.length else {
                    throw .unreadableExchange(seq: exchange.seq)
                }
                command = .write(cdb, data: data)
            case .none?:
                guard exchange.length == 0 else { throw .unreadableExchange(seq: exchange.seq) }
                command = .noData(cdb)
            case nil:
                throw .unreadableExchange(seq: exchange.seq)
            }
            commands.append(command)
        }
        guard let scan = commands.firstIndex(where: { $0.opcode == 0x1B }) else { throw .noScan }
        expected = commands
        scanIndex = scan
    }

    /// Captured commands already let through.
    public var position: Int { state.withLock { $0.next } }

    /// True once every captured command has been let through.
    public var isComplete: Bool { state.withLock { $0.next == expected.count } }

    /// Throws `TransportError.refusedByPolicy` if `command` may not be sent now.
    public func check(_ command: SCSICommand) throws(TransportError) {
        let expected = self.expected
        let scanIndex = self.scanIndex
        let outcome: String? = state.withLock { state in
            let opcode = command.opcode
            if state.stopped {
                guard opcode == 0xDF, (try? CommandPolicy.readOnly.check(command)) != nil else {
                    return ("after the stop command only 0xDF is allowed")
                }
                return nil
            }
            if Self.isPoll(opcode) {
                return (try? CommandPolicy.readOnly.check(command)) != nil ? nil : ("poll outside the read-only list")
            }
            if state.next < expected.count, command == expected[state.next] {
                state.next += 1
                return nil
            }
            let scanSent = state.next > scanIndex
            if scanSent, command == Self.stop {
                state.stopped = true
                return nil
            }
            if scanSent, state.next < expected.count, command == Self.statusRead {
                return nil  // page 0x20 read again: does not move the sequence on
            }
            if state.next < expected.count {
                return ("not the next captured command (\(state.next + 1) of \(expected.count): "
                               + "\(expected[state.next]))")
            }
            return ("the captured sequence is over")
        }
        if let outcome { throw .refusedByPolicy(opcode: command.opcode, reason: outcome) }
    }

    /// Reads FlexColor repeats at its own pace (0xEE registers, 0xD3, 0xDF state).
    public static let pollOpcodes: Set<UInt8> = [0xEE, 0xD3, 0xDF]

    private static func isPoll(_ opcode: UInt8) -> Bool {
        pollOpcodes.contains(opcode)
    }
}
