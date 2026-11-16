// SPDX-License-Identifier: MIT
import Darwin
import Foundation
import Synchronization

/// A log of every command and response, in the format of
/// tools/capture/cap3.py, so that a preview on the real X1 can be compared
/// with a FlexColor capture and decoded by tools/decode/decode_preview.py.
/// READ data goes to a separate raw file. Both files hold the scanner's
/// serial number (page 0x26): they are written outside the repository.
public final class CaptureLog: Sendable {
    public let textURL: URL
    public let rawURL: URL
    private let state: Mutex<State>

    private struct State {
        var text: FileHandle
        var raw: FileHandle
        var count = 0
        var rawOffset = 0
        var writeFailed = false
    }

    /// True if a write failed (e.g. disk full): the log is incomplete.
    public var isIncomplete: Bool { state.withLock { $0.writeFailed } }

    /// Creates both files (never replacing existing ones) and writes a header.
    public init(textURL: URL, rawURL: URL, header: String) throws {
        try FileManager.default.createDirectory(at: textURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        self.textURL = textURL
        self.rawURL = rawURL
        let text = try Self.createExclusively(textURL)
        let raw: FileHandle
        do {
            raw = try Self.createExclusively(rawURL)
        } catch {
            try? text.close()
            try? FileManager.default.removeItem(at: textURL)  // the empty text file just created
            throw error
        }
        state = Mutex(State(text: text, raw: raw))
        write(header.split(separator: "\n").map { "# " + $0 }.joined(separator: "\n") + "\n")
    }

    /// Never replaces a file: fails if it exists (O_EXCL).
    private static func createExclusively(_ url: URL) throws -> FileHandle {
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: url.path]) }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    /// Written before the command is sent, so that a command that never
    /// returns (READ held, scanner switched off, app killed) is in the log.
    func begin(_ command: SCSICommand) {
        state.withLock { state in
            state.count += 1
            var lines = [String(format: "%04d CDB ", state.count % 10_000) + command.cdb.hexString]
            switch command.direction {
            case .fromDevice: lines.append("     <-X1 \(command.transferLength) octets")
            case .toDevice:
                lines.append("     ->X1 \(command.transferLength) octets")
                lines.append("   ENV " + Array(command.dataOut.prefix(128)).hexString)
            case .none: break
            }
            Self.append(lines, to: &state)
        }
    }

    /// What came back for the command of the last `begin` (or the error).
    func end(_ command: SCSICommand, result: Result<SCSIResult, any Error>) {
        state.withLock { state in
            var lines: [String] = []
            switch result {
            case .success(let response):
                lines.append(String(format: "   FIN statut=0x%02x recus=%d", response.status, response.data.count))
                if command.opcode == 0x28, !response.data.isEmpty {
                    // A failed write (disk full) must not stop the run: the log is a record only.
                    do { try state.raw.write(contentsOf: Data(response.data)) } catch { state.writeFailed = true }
                    lines.append("   RAW offset=\(state.rawOffset) taille=\(response.data.count)")
                    state.rawOffset += response.data.count
                }
                if !response.data.isEmpty { lines.append("   REP " + Array(response.data.prefix(64)).hexString) }
                if !response.sense.isEmpty { lines.append("   SENSE " + response.sense.hexString) }
            case .failure(let error):
                lines.append("   ERREUR \(error)")
            }
            Self.append(lines, to: &state)
        }
    }

    private static func append(_ lines: [String], to state: inout State) {
        do {
            try state.text.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8))
        } catch {
            state.writeFailed = true
        }
    }

    /// A free comment line (`# …`), e.g. the outcome of the run.
    public func note(_ text: String) {
        write(text.split(separator: "\n").map { "# " + $0 }.joined(separator: "\n") + "\n")
    }

    public func close() {
        state.withLock { state in
            try? state.text.close()
            try? state.raw.close()
        }
    }

    private func write(_ text: String) {
        state.withLock { Self.append([String(text.dropLast())], to: &$0) }
    }
}

/// Logs every command that goes through `inner` to a `CaptureLog`, including
/// those refused by the transport's guard (nothing was sent then).
public struct LoggingTransport: SCSITransport {
    public let inner: any SCSITransport
    public let log: CaptureLog

    public init(inner: any SCSITransport, log: CaptureLog) {
        self.inner = inner
        self.log = log
    }

    public func execute(_ command: SCSICommand) async throws -> SCSIResult {
        log.begin(command)
        do {
            let result = try await inner.execute(command)
            log.end(command, result: .success(result))
            return result
        } catch {
            log.end(command, result: .failure(error))
            throw error
        }
    }
}
