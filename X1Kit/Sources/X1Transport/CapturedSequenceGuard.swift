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
/// - after the last captured command, only polls;
/// - one substitution, for a scan only (`scan(fixture:allowedPositions:)`):
///   the target position (bytes 50-51) of the window right before
///   `1b 00 08 06 01 00` may differ from the captured one, within the
///   allowed positions; every other byte of that window must be the captured one
///   (docs/decisions.md, "Real X1: scan").
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
    /// Per alternative: command index → accepted target positions (bytes 50-51).
    private let positionSubstitutions: [[Int: ClosedRange<Int>]]
    private let state: Mutex<State>

    private struct State {
        var next = 0
        var stopped = false
        /// Indices of the alternatives that match every command let through so far.
        var candidates: [Int]
    }

    static let stop = SCSICommand.noData([0xDB, 0x00, 0x00, 0x00, 0x00, 0x00])
    static let focusSweep: [UInt8] = [0x1B, 0x00, 0x08, 0x06, 0x01, 0x00]

    /// `command` is `expected`, or (where a substitution is allowed) the same
    /// window with another target position within `range`.
    private static func matches(_ command: SCSICommand, _ expected: SCSICommand, substitution range: ClosedRange<Int>?) -> Bool {
        if command == expected { return true }
        guard let range, command.cdb == expected.cdb, command.direction == expected.direction,
              command.transferLength == expected.transferLength,
              command.dataOut.count == expected.dataOut.count, command.dataOut.count >= 54 else { return false }
        for index in command.dataOut.indices where index != 50 && index != 51 {
            guard command.dataOut[index] == expected.dataOut[index] else { return false }
        }
        return range.contains(Int(command.dataOut[50]) | Int(command.dataOut[51]) << 8)
    }
    static let statusRead = SCSICommand.read([0x5A, 0x00, 0x20, 0x01, 0x00, 0x00, 0x00, 0x00, 0x22, 0x00], length: 34)

    /// One captured sequence.
    public convenience init(fixture: CaptureFixture) throws(SetupError) {
        try self.init(alternatives: [fixture])
    }

    /// Several captured sequences; `excluding` lists commands (CDB and
    /// length) to leave out of every capture.
    public convenience init(alternatives fixtures: [CaptureFixture], excluding: [SCSICommand] = []) throws(SetupError) {
        try self.init(alternatives: fixtures.map(\.exchanges), excluding: excluding, allowedPositions: nil)
    }

    /// The scan session of a scan capture (from its last `CF 00 01 80`), with
    /// the one substitution allowed: the target position of the window right
    /// before `1b 00 08 06 01 00`, within `allowedPositions`, which must contain
    /// the captured one.
    public static func scan(fixture: CaptureFixture, allowedPositions: ClosedRange<Int>) throws(SetupError) -> CapturedSequenceGuard {
        guard allowedPositions.lowerBound >= 0, allowedPositions.upperBound <= 0xFFFF else { throw .noSequence }
        guard let start = fixture.exchanges.lastIndex(where: { $0.cdb == "cf 00 01 80 00 00" }) else { throw .noSequence }
        return try CapturedSequenceGuard(alternatives: [Array(fixture.exchanges[start...])], excluding: [],
                                         allowedPositions: allowedPositions)
    }

    private init(alternatives exchangeLists: [[CaptureExchange]], excluding: [SCSICommand],
                 allowedPositions: ClosedRange<Int>?) throws(SetupError) {
        guard !exchangeLists.isEmpty else { throw .noSequence }
        var sequences: [[SCSICommand]] = []
        var scans: [Int] = []
        var substitutions: [[Int: ClosedRange<Int>]] = []
        for exchanges in exchangeLists {
            var commands: [SCSICommand] = []
            for exchange in exchanges {
                let command = try Self.command(for: exchange)
                guard let command, !excluding.contains(command) else { continue }
                commands.append(command)
            }
            guard let scan = commands.firstIndex(where: { $0.opcode == 0x1B }) else { throw .noScan }
            var substitution: [Int: ClosedRange<Int>] = [:]
            if let allowed = allowedPositions {
                guard let sweep = commands.firstIndex(where: { $0.cdb == Self.focusSweep }), sweep > 0,
                      commands[sweep - 1].opcode == 0x24, commands[sweep - 1].dataOut.count >= 54 else { throw .noScan }
                let data = commands[sweep - 1].dataOut
                let captured = Int(data[50]) | Int(data[51]) << 8
                guard allowed.contains(captured) else { throw .noScan }
                substitution[sweep - 1] = allowed
            }
            sequences.append(commands)
            scans.append(scan)
            substitutions.append(substitution)
        }
        alternatives = sequences
        scanIndices = scans
        positionSubstitutions = substitutions
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
            let substitutions = self.positionSubstitutions
            let matching = state.candidates.filter {
                state.next < alternatives[$0].count
                    && Self.matches(command, alternatives[$0][state.next], substitution: substitutions[$0][state.next])
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
