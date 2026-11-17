// SPDX-License-Identifier: MIT
import Synchronization

/// Lets through only FlexColor's captured sequences, command after command.
///
/// Built from the captures themselves (tests/fixtures files; the app uses
/// preview-sequence-cold.json and preview-sequence.json), not from
/// `PreviewScript`: the script must agree with an independent source.
/// Rules (docs/decisions.md, "Application, step 4" and "Real X1: cold or
/// warm sequence"):
/// - every command other than a poll must be, in order, the next command of
///   one of the captured sequences (`alternatives`): same CDB, direction,
///   length and data out, byte for byte. Where the alternatives differ, the
///   first command sent decides which one is followed from then on;
/// - commands listed in `excluding` are left out of the captures (the
///   cold capture's page 0x28 read);
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
        case noSequence

        public var description: String {
            switch self {
            case .unreadableExchange(let seq): "captured exchange \(seq) cannot be turned into a command"
            case .noScan: "the capture has no SCAN command"
            case .noSequence: "no captured sequence"
            }
        }
    }

    /// The captured sequences, polls and excluded commands left out.
    public let alternatives: [[SCSICommand]]
    private let scanIndices: [Int]
    private let state: Mutex<State>

    private struct State {
        var next = 0
        var stopped = false
        /// Indices of the alternatives that match every command let through so far.
        var candidates: [Int]
    }

    static let stop = SCSICommand.noData([0xDB, 0x00, 0x00, 0x00, 0x00, 0x00])
    static let statusRead = SCSICommand.read([0x5A, 0x00, 0x20, 0x01, 0x00, 0x00, 0x00, 0x00, 0x22, 0x00], length: 34)

    /// One captured sequence.
    public convenience init(fixture: CaptureFixture) throws(SetupError) {
        try self.init(alternatives: [fixture])
    }

    /// Several captured sequences; `excluding` lists commands (CDB and
    /// length) to leave out of every capture.
    public init(alternatives fixtures: [CaptureFixture], excluding: [SCSICommand] = []) throws(SetupError) {
        guard !fixtures.isEmpty else { throw .noSequence }
        var sequences: [[SCSICommand]] = []
        var scans: [Int] = []
        for fixture in fixtures {
            var commands: [SCSICommand] = []
            for exchange in fixture.exchanges {
                let command = try Self.command(for: exchange)
                guard let command, !excluding.contains(command) else { continue }
                commands.append(command)
            }
            guard let scan = commands.firstIndex(where: { $0.opcode == 0x1B }) else { throw .noScan }
            sequences.append(commands)
            scans.append(scan)
        }
        alternatives = sequences
        scanIndices = scans
        state = Mutex(State(candidates: Array(sequences.indices)))
    }

    /// The command of a captured exchange; nil for a poll.
    private static func command(for exchange: CaptureExchange) throws(SetupError) -> SCSICommand? {
        let cdb = exchange.cdbBytes
        guard let opcode = cdb.first, exchange.length >= 0 else { throw .unreadableExchange(seq: exchange.seq) }
        if isPoll(opcode) { return nil }
        switch exchange.commandDirection {
        case .fromDevice?:
            return .read(cdb, length: exchange.length)
        case .toDevice?:
            guard let data = exchange.dataOutBytes, data.count == exchange.length else {
                throw .unreadableExchange(seq: exchange.seq)
            }
            return .write(cdb, data: data)
        case .none?:
            guard exchange.length == 0 else { throw .unreadableExchange(seq: exchange.seq) }
            return .noData(cdb)
        case nil:
            throw .unreadableExchange(seq: exchange.seq)
        }
    }

    /// The commands of the first alternative still possible.
    public var expected: [SCSICommand] { state.withLock { alternatives[$0.candidates[0]] } }

    /// Captured commands already let through.
    public var position: Int { state.withLock { $0.next } }

    /// True once every command of the followed sequence has been let through.
    public var isComplete: Bool {
        state.withLock { state in state.candidates.contains { state.next == alternatives[$0].count } }
    }

    /// Throws `TransportError.refusedByPolicy` if `command` may not be sent now.
    public func check(_ command: SCSICommand) throws(TransportError) {
        let alternatives = self.alternatives
        let scanIndices = self.scanIndices
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
            let matching = state.candidates.filter {
                state.next < alternatives[$0].count && command == alternatives[$0][state.next]
            }
            if !matching.isEmpty {
                state.candidates = matching
                state.next += 1
                return nil
            }
            let followed = state.candidates[0]
            let expected = alternatives[followed]
            // Every alternative still possible has had its SCAN let through.
            let scanSent = state.candidates.allSatisfy { state.next > scanIndices[$0] }
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
