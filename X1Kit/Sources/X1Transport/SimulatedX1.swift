// SPDX-License-Identifier: MIT
import Foundation

/// A virtual X1 that replays a capture of FlexColor.
///
/// - Non-polling commands must arrive in the captured order, with the same
///   CDB, direction, transfer length and data_out; otherwise the simulator
///   throws `SimulatorError.unexpectedCommand`. Each one gets its recorded
///   response.
/// - Polling commands (0xEE, 0xD3, 0xDF) are answered with the responses
///   recorded between the previous and the next non-polling exchange, in
///   order; when they run out, the last one is repeated.
/// - READ (0x28) data is synthesised: white and dark references from the
///   calibration profile, image lines from `SyntheticFilm` with the CCD line
///   gap applied, and a constant level for full-width calibration lines
///   (the capture has no reference for those).
/// - A stop (`DB 00 00 00 00 00`) received after SCAN but before its captured
///   place (an emergency stop) is accepted: the replay jumps to the captured
///   `DB`, so the following 0xDF polls get the states FlexColor saw after its
///   own **end-of-scan** stop. **Not captured**: how a real X1 answers a `DB`
///   sent while lines are still being read is unknown, so a clean stop on the
///   simulator proves nothing for the real scanner. Before SCAN, an early `DB`
///   is refused like any other command.
public actor SimulatedX1: SCSITransport {
    public static let pollingOpcodes: Set<UInt8> = [0xEE, 0xD3, 0xDF]

    public enum SimulatorError: Error, Hashable, CustomStringConvertible {
        case unexpectedCommand(seq: Int, expected: String, received: String)
        case endOfCapture(received: String)
        case noRecordedResponse(received: String)

        public var description: String {
            switch self {
            case .unexpectedCommand(let seq, let expected, let received):
                "capture seq \(seq) expects \(expected), received \(received)"
            case .endOfCapture(let received):
                "capture ended, received \(received)"
            case .noRecordedResponse(let received):
                "no recorded response for \(received)"
            }
        }
    }

    /// Level returned for full-CCD calibration lines (no reference recorded).
    public static let constantLevel: UInt16 = 20_000

    private struct Recorded: Sendable {
        let seq: Int
        let cdb: [UInt8]
        let direction: SCSICommand.Direction?
        let length: Int
        let dataOut: [UInt8]?
        let status: UInt8
        let response: [UInt8]?

        var summary: String {
            var text = cdb.hexString + " (\(length) bytes)"
            if let dataOut { text += " -> \(dataOut.hexString)" }
            return text
        }
    }

    private let exchanges: [Recorded]
    private let nonPolling: [Int]
    private let profile: CalibrationProfile
    public nonisolated let film: SyntheticFilm

    private var next = 0
    private var pollCursor: [[UInt8]: Int] = [:]
    private var lastMode: [UInt8] = []
    private var imageRow = 0
    /// Every command received, in order.
    public private(set) var log: [SCSICommand] = []

    public init(fixture: CaptureFixture, profile: CalibrationProfile, film: SyntheticFilm = .testPattern) {
        let recorded = fixture.exchanges.map { exchange in
            Recorded(seq: exchange.seq, cdb: exchange.cdbBytes, direction: exchange.commandDirection,
                     length: exchange.length, dataOut: exchange.dataOutBytes,
                     status: UInt8(exchange.status ?? 0), response: exchange.responseBytes)
        }
        exchanges = recorded
        nonPolling = recorded.indices.filter { !Self.pollingOpcodes.contains(recorded[$0].cdb.first ?? 0) }
        self.profile = profile
        self.film = film
    }

    public init(sequenceURL: URL, calibrationProfileURL: URL, film: SyntheticFilm = .testPattern) throws {
        self.init(fixture: try CaptureFixture.load(from: sequenceURL),
                  profile: try CalibrationProfile.load(from: calibrationProfileURL),
                  film: film)
    }

    /// Number of image lines (READ with flag 00) served so far.
    public var imageLinesServed: Int { imageRow }

    public func execute(_ command: SCSICommand) throws -> SCSIResult {
        log.append(command)
        if Self.pollingOpcodes.contains(command.opcode) {
            return try pollResponse(for: command)
        }
        guard next < nonPolling.count else {
            throw SimulatorError.endOfCapture(received: command.description)
        }
        var expected = exchanges[nonPolling[next]]
        if !matches(command, expected), let stop = earlyStopTarget(for: command) {
            next = stop
            expected = exchanges[nonPolling[next]]
        }
        guard matches(command, expected) else {
            throw SimulatorError.unexpectedCommand(seq: expected.seq, expected: expected.summary,
                                                   received: command.description)
        }
        next += 1
        pollCursor.removeAll()
        if command.opcode == 0xF0 { lastMode = Array(command.cdb[2...5]) }

        guard command.direction == .fromDevice else { return SCSIResult(status: expected.status) }
        let data = command.opcode == 0x28 ? synthesizeRead(command) : (expected.response ?? [])
        guard data.count == command.transferLength else {
            throw SimulatorError.noRecordedResponse(received: command.description)
        }
        return SCSIResult(status: expected.status, data: data)
    }

    private static let stopCDB: [UInt8] = [0xDB, 0, 0, 0, 0, 0]
    private static let scanOpcode: UInt8 = 0x1B

    /// Index in `nonPolling` of the captured stop, if `command` is an early
    /// stop after SCAN has been replayed.
    private func earlyStopTarget(for command: SCSICommand) -> Int? {
        guard command.cdb == Self.stopCDB,
              nonPolling[..<next].contains(where: { exchanges[$0].cdb.first == Self.scanOpcode }) else { return nil }
        return (next..<nonPolling.count).first { exchanges[nonPolling[$0]].cdb == Self.stopCDB }
    }

    private func matches(_ command: SCSICommand, _ expected: Recorded) -> Bool {
        guard command.cdb == expected.cdb,
              command.direction == expected.direction,
              command.transferLength == expected.length else { return false }
        guard let recorded = expected.dataOut else { return command.dataOut.isEmpty }
        // The capture keeps at most the first 128 bytes of data_out.
        if recorded.count == 128 { return command.dataOut.starts(with: recorded) }
        return command.dataOut == recorded
    }

    private func pollResponse(for command: SCSICommand) throws -> SCSIResult {
        let lower = next == 0 ? 0 : nonPolling[next - 1] + 1
        let upper = next < nonPolling.count ? nonPolling[next] : exchanges.count
        let candidates = (lower..<upper).filter { exchanges[$0].cdb == command.cdb }
        let chosen: Recorded
        if !candidates.isEmpty {
            let position = pollCursor[command.cdb, default: 0]
            pollCursor[command.cdb] = position + 1
            chosen = exchanges[candidates[min(position, candidates.count - 1)]]
        } else if let previous = exchanges[..<upper].last(where: { $0.cdb == command.cdb }) {
            chosen = previous
        } else {
            throw SimulatorError.noRecordedResponse(received: command.description)
        }
        guard let response = chosen.response, response.count == command.transferLength else {
            throw SimulatorError.noRecordedResponse(received: command.description)
        }
        return SCSIResult(status: chosen.status, data: response)
    }

    // MARK: Image data

    private func synthesizeRead(_ command: SCSICommand) -> [UInt8] {
        let lines = Int(command.cdb[4])
        let isCalibration = command.cdb[5] == 0x01
        let bytesPerLine = command.transferLength / max(lines, 1)
        let pixels = bytesPerLine / 6
        var samples: [UInt16] = []
        samples.reserveCapacity(command.transferLength / 2)

        for _ in 0..<lines {
            if isCalibration {
                // In the capture, white lines follow F0 01 01 00 01 and dark lines F0 01 00 00 01.
                if pixels == profile.width && lastMode == [1, 1, 0, 1] {
                    for column in 0..<pixels { for channel in 0..<3 { samples.append(UInt16(profile.white[column][channel])) } }
                } else if pixels == profile.width && lastMode == [1, 0, 0, 1] {
                    for column in 0..<pixels { for channel in 0..<3 { samples.append(UInt16(profile.dark[column][channel])) } }
                } else {
                    samples.append(contentsOf: repeatElement(Self.constantLevel, count: pixels * 3))
                }
            } else {
                let row = imageRow
                imageRow += 1
                guard pixels == profile.width else {
                    samples.append(contentsOf: repeatElement(Self.constantLevel, count: pixels * 3))
                    continue
                }
                for column in 0..<pixels {
                    for channel in 0..<3 {
                        // CCD line gap (protocol.md §10): red leads green by one line, blue trails by one.
                        let filmRow = row + (channel == 0 ? -1 : channel == 2 ? 1 : 0)
                        let t = film.transmission(row: filmRow, column: column, channel: channel, width: pixels)
                        let dark = Double(profile.dark[column][channel])
                        let white = Double(profile.white[column][channel])
                        let value = (dark + t * (white - dark)).rounded()
                        samples.append(UInt16(min(max(value, 0), 65_535)))
                    }
                }
            }
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(samples.count * 2)
        for sample in samples {
            bytes.append(UInt8(sample & 0xFF))
            bytes.append(UInt8(sample >> 8))
        }
        return bytes
    }
}

/// Transmission of an imaginary film, used to synthesise image lines.
/// Each channel has its own pattern so that channel swaps and line-gap
/// errors show up in tests.
public struct SyntheticFilm: Sendable {
    public static let testPattern = SyntheticFilm()

    public init() {}

    /// Transmission in 0...1 at a scan row (counted from SCAN), column and channel (0 R, 1 G, 2 B).
    public func transmission(row: Int, column: Int, channel: Int, width: Int) -> Double {
        let row = max(row, 0)
        switch channel {
        case 0:  // horizontal ramp plus 5-line bands
            return 0.1 + 0.4 * Double(column) / Double(max(width - 1, 1)) + ((row / 5).isMultiple(of: 2) ? 0 : 0.4)
        case 1:  // vertical sawtooth
            return 0.1 + 0.8 * Double(row % 400) / 399
        default:  // 7-line bands
            return (row / 7).isMultiple(of: 2) ? 0.2 : 0.8
        }
    }
}
