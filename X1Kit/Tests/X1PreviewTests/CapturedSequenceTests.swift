// SPDX-License-Identifier: MIT
import Foundation
import Testing
import X1Preview
import X1Protocol
import X1TestSupport
import X1Transport

struct CapturedSequenceGuardTests {
    private func makeGuard() throws -> CapturedSequenceGuard {
        try CapturedSequenceGuard(fixture: Fixtures.sequence())
    }

    private static let script = PreviewScript.flexColor4813.map(\.command)
    private static let scanIndex = script.firstIndex { $0.opcode == 0x1B }!

    /// Two independent sources agree: the script and the capture itself.
    @Test func scriptIsExactlyTheCapturedSequence() throws {
        #expect(try makeGuard().expected == Self.script)
    }

    @Test func wholePreviewGoesThroughTheGuard() async throws {
        let sequence = try makeGuard()
        let runner = PreviewRunner(transport: GuardedTransport(inner: try Fixtures.simulator(), sequence: sequence),
                                   configuration: .simulator)
        let capture = try await runner.run()
        #expect(capture.image.count == 41)
        #expect(sequence.isComplete)
    }

    /// Plays the script up to (not including) `index`.
    private func advanced(to index: Int) throws -> CapturedSequenceGuard {
        let sequence = try makeGuard()
        for command in Self.script.prefix(index) { try sequence.check(command) }
        return sequence
    }

    private func refused(_ sequence: CapturedSequenceGuard, _ command: SCSICommand) -> Bool {
        do { try sequence.check(command); return false } catch { return true }
    }

    @Test func refusesAnyByteDifferent() throws {
        let sequence = try makeGuard()
        let windowIndex = Self.script.firstIndex { $0.opcode == 0x24 }!
        for command in Self.script.prefix(windowIndex) { try sequence.check(command) }
        let window = Self.script[windowIndex]
        var data = window.dataOut
        data[50] ^= 0x01
        #expect(refused(sequence, .write(window.cdb, data: data)), "one bit of the window")
        var cdb = window.cdb
        cdb[9] = 0x01
        #expect(refused(sequence, SCSICommand(cdb: cdb, direction: .toDevice, transferLength: 68, dataOut: window.dataOut)))
        #expect(sequence.position == windowIndex, "a refusal does not move the sequence")
        try sequence.check(window)
        #expect(sequence.position == windowIndex + 1)
    }

    @Test func refusesAnotherOrderOrAnExtraCommand() throws {
        let sequence = try makeGuard()
        #expect(refused(sequence, Self.script[1]), "skipping the first command")
        #expect(refused(sequence, X1Command.startupD2()), "a captured command, but not now")
        #expect(refused(sequence, X1Command.modeSense(page: 0x26, length: 12)), "a read of another length")
        #expect(refused(sequence, X1Command.stop()), "stop before SCAN")
        #expect(refused(sequence, X1Command.modeSense(page: 0x20, length: 34)), "page 0x20 again before SCAN")
        try sequence.check(Self.script[0])
    }

    @Test func pollsAreAllowedAndDoNotMoveTheSequence() throws {
        let sequence = try advanced(to: 5)
        try sequence.check(X1Command.scannerState())
        try sequence.check(X1Command.sensors())
        try sequence.check(X1Command.readRegister(0x10))
        #expect(sequence.position == 5)
        #expect(refused(sequence, .read([0xEE, 0, 0, 0, 0x02, 0x10, 0, 0, 1, 0], length: 1)),
                "a poll outside the read-only list")
    }

    @Test func afterScanStatusMayBeReadAgainAndStopIsAccepted() throws {
        let sequence = try advanced(to: Self.scanIndex + 1)
        let position = sequence.position
        try sequence.check(X1Command.modeSense(page: 0x20, length: 34))
        try sequence.check(X1Command.modeSense(page: 0x20, length: 34))
        #expect(sequence.position == position, "page 0x20 again: the sequence does not move")
        try sequence.check(X1Command.stop())
        try sequence.check(X1Command.scannerState())
        #expect(refused(sequence, X1Command.modeSense(page: 0x20, length: 34)), "after the stop: only 0xDF")
        #expect(refused(sequence, X1Command.sensors()))
        #expect(refused(sequence, X1Command.session(.end)))
        #expect(refused(sequence, X1Command.stop()))
    }

    @Test func nothingButPollsAfterTheEnd() throws {
        let sequence = try advanced(to: Self.script.count)
        #expect(sequence.isComplete)
        try sequence.check(X1Command.scannerState())
        #expect(refused(sequence, X1Command.inquiry()))
        #expect(refused(sequence, X1Command.scan()))
    }

    /// An anomaly after SCAN: the runner's stop goes through the guard.
    @Test func emergencyStopPassesTheGuard() async throws {
        let sequence = try makeGuard()
        let faulty = FaultInjectingTransport(inner: try Fixtures.simulator(),
                                             faultAtNonPollingCommand: Self.scanIndex + 10, fault: .checkCondition)
        let runner = PreviewRunner(transport: GuardedTransport(inner: faulty, sequence: sequence),
                                   configuration: .simulator)
        do {
            _ = try await runner.run()
            Issue.record("the preview should have stopped")
        } catch {
            #expect(error.emergencyStop == .stoppedAndReady)
        }
        #expect(await faulty.commandsAfterFault.first == X1Command.stop())
    }

    /// A READ that times out at the IOKit level after SCAN: the run stops with
    /// DB, which the guard lets through, then only 0xDF.
    @Test func transportErrorAfterScanStopsThroughTheGuard() async throws {
        let sequence = try makeGuard()
        let faulty = FaultInjectingTransport(inner: try Fixtures.simulator(),
                                             faultAtNonPollingCommand: Self.scanIndex + 12, fault: .transportError)
        let runner = PreviewRunner(transport: GuardedTransport(inner: faulty, sequence: sequence),
                                   configuration: .simulator)
        do {
            _ = try await runner.run()
            Issue.record("the preview should have stopped")
        } catch {
            if case .transport(let text) = error.anomaly {
                #expect(text.contains("timed out"), "a timeout is reported as such, not as a scanner status")
            } else {
                Issue.record("transport anomaly expected, got \(error.anomaly)")
            }
            #expect(error.emergencyStop == .stoppedAndReady)
        }
        let after = await faulty.commandsAfterFault
        #expect(after.first == X1Command.stop())
        #expect(after.dropFirst().allSatisfy { $0 == X1Command.scannerState() })
    }

    @Test func iokitTransportUsesTheGuardBeforeTheDevice() async throws {
        let transport = IOKitTransport(capturedSequence: try makeGuard())
        #expect(!transport.isReadOnly)
        #expect(IOKitTransport().isReadOnly)
        // Never opened: a refused command must fail on the guard, before the open check.
        await #expect(throws: TransportError.self) { try await transport.execute(X1Command.scan()) }
        do {
            _ = try await transport.execute(X1Command.scan())
        } catch let error as TransportError {
            if case .refusedByPolicy = error {} else { Issue.record("refused by the guard expected, got \(error)") }
        }
        // The first captured command passes the guard and only then meets the closed device.
        await #expect(throws: TransportError.notOpen) { try await transport.execute(Self.script[0]) }
    }
}

struct CaptureLogTests {
    @Test func logFollowsTheFormatOfCap3() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "X1KitTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = try CaptureLog(textURL: folder.appending(path: "p.txt"), rawURL: folder.appending(path: "p.raw"),
                                 header: "test run\nsecond line")
        let sequence = try CapturedSequenceGuard(fixture: Fixtures.sequence())
        let transport = LoggingTransport(inner: GuardedTransport(inner: try Fixtures.simulator(), sequence: sequence),
                                         log: log)
        _ = try await PreviewRunner(transport: transport, configuration: .simulator).run()
        // A refused command is logged too.
        await #expect(throws: TransportError.self) { try await transport.execute(X1Command.scan()) }
        log.close()

        let text = try String(contentsOf: log.textURL, encoding: .utf8)
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines.prefix(2) == ["# test run", "# second line"])
        let cdbLines = lines.filter { $0.range(of: #"^\d{4} CDB "#, options: .regularExpression) != nil }
        #expect(cdbLines.first == "0001 CDB 12 00 00 00 60 00")
        #expect(lines.contains("   FIN statut=0x00 recus=96"))
        #expect(lines.last?.hasPrefix("   ERREUR command 0x1b refused by policy") == true)
        #expect(lines[lines.count - 3].hasSuffix(" CDB 1b 00 00 01 01 00"), "the CDB line, written before sending")
        #expect(!log.isIncomplete)
        // RAW offsets follow each other and match the raw file, as decode_preview.py reads them.
        var expectedOffset = 0
        for line in lines.map({ $0.trimmingCharacters(in: .whitespaces) }) where line.hasPrefix("RAW offset=") {
            let parts = line.dropFirst("RAW offset=".count).split(separator: " ")
            #expect(Int(parts[0]) == expectedOffset)
            expectedOffset += Int(parts[1].dropFirst("taille=".count)) ?? 0
        }
        let rawSize = try FileManager.default.attributesOfItem(atPath: log.rawURL.path)[.size] as? Int
        #expect(rawSize == expectedOffset && expectedOffset > 0)
        // Never replaces an existing log.
        #expect(throws: (any Error).self) {
            try CaptureLog(textURL: log.textURL, rawURL: folder.appending(path: "other.raw"), header: "")
        }
    }
}

/// The guard built from the cold capture (2026-11-16) alone, page 0x28 left out.
struct ColdCapturedSequenceGuardTests {
    private func makeGuard() throws -> CapturedSequenceGuard {
        try CapturedSequenceGuard(alternatives: [Fixtures.coldSequence()],
                                  excluding: [.read(SimulatedX1.page28Read, length: 30)])
    }

    private static let cold = PreviewScript.flexColor4813Cold.map(\.command)
    private static let warm = PreviewScript.flexColor4813.map(\.command)
    private static let scanIndex = cold.firstIndex { $0.opcode == 0x1B }!

    @Test func coldScriptIsExactlyTheColdCapture() throws {
        #expect(try makeGuard().expected == Self.cold)
    }

    @Test func wholeColdPreviewGoesThroughTheGuard() async throws {
        let sequence = try makeGuard()
        let runner = PreviewRunner(transport: GuardedTransport(inner: try Fixtures.coldSimulator(), sequence: sequence),
                                   configuration: .simulator, script: PreviewScript.flexColor4813Cold)
        let capture = try await runner.run()
        #expect(capture.image.count == 41)
        #expect(sequence.isComplete)
    }

    /// The warm sequence cannot run through the cold guard alone: it is
    /// refused at its first difference, right after the first page 0x20 read.
    @Test func theWarmSequenceIsRefused() async throws {
        let sequence = try makeGuard()
        let firstDifference = Self.cold.indices.first { Self.warm[$0] != Self.cold[$0] }!
        let choice = PreviewScript.flexColor4813Cold.firstIndex { $0.kind == .sequenceChoice }!
        #expect(firstDifference == choice + 1)
        #expect(Self.warm[firstDifference] == X1Command.setMode(0, 0, 1, 1))
        let transport = GuardedTransport(inner: try Fixtures.simulator(), sequence: sequence)
        do {
            _ = try await PreviewRunner(transport: transport, configuration: .simulator).run()
            Issue.record("the warm sequence should have been refused")
        } catch {
            #expect(error.stepIndex == firstDifference)
            #expect(error.emergencyStop == nil)
        }
        #expect(sequence.position == firstDifference)
    }

    /// After the power-on check, the next warm command (F0) is refused.
    @Test func noWarmCommandAfterThePowerOnCheck() throws {
        let sequence = try makeGuard()
        let check = PreviewScript.flexColor4813Cold.firstIndex { $0.kind == .sequenceChoice }!
        for command in Self.cold.prefix(check + 1) { try sequence.check(command) }
        let warmCheck = Self.warm.firstIndex { $0.cdb.prefix(3) == [0x5A, 0x00, 0x20] }!
        #expect(throws: TransportError.self) { try sequence.check(Self.warm[warmCheck + 1]) }
        try sequence.check(Self.cold[check + 1])
    }

    /// The emergency stop after SCAN goes through the cold guard too.
    @Test func emergencyStopPassesTheColdGuard() async throws {
        let sequence = try makeGuard()
        let faulty = FaultInjectingTransport(inner: try Fixtures.coldSimulator(),
                                             faultAtNonPollingCommand: Self.scanIndex + 10, fault: .checkCondition)
        let runner = PreviewRunner(transport: GuardedTransport(inner: faulty, sequence: sequence),
                                   configuration: .simulator, script: PreviewScript.flexColor4813Cold)
        do {
            _ = try await runner.run()
            Issue.record("the preview should have stopped")
        } catch {
            #expect(error.emergencyStop == .stoppedAndReady)
        }
        let after = await faulty.commandsAfterFault
        #expect(after.first == X1Command.stop())
        #expect(after.dropFirst().allSatisfy { $0 == X1Command.scannerState() })
    }

    /// A stop before SCAN (here: not just switched on) sends nothing more.
    @Test func powerOnCheckFailureSendsNothingMore() async throws {
        let check = PreviewScript.flexColor4813Cold.firstIndex { $0.kind == .sequenceChoice }!
        let sequence = try makeGuard()
        let faulty = FaultInjectingTransport(inner: try Fixtures.coldSimulator(), faultAtNonPollingCommand: check,
                                             fault: .setChannelValues([1928, 1843, 1882]))
        let runner = PreviewRunner(transport: GuardedTransport(inner: faulty, sequence: sequence),
                                   configuration: .simulator, script: PreviewScript.flexColor4813Cold)
        do {
            _ = try await runner.run()
            Issue.record("the preview should have stopped")
        } catch {
            #expect(error.anomaly == .notJustSwitchedOn(channelValues: [1928, 1843, 1882]))
        }
        #expect(await faulty.commandsAfterFault.isEmpty)
        #expect(sequence.position == check + 1)
    }
}

/// The guard the app builds: both captures, page 0x28 left out.
struct TwoSequenceGuardTests {
    private static let cold = PreviewScript.plan.steps(for: .cold).map(\.command)
    private static let warm = PreviewScript.plan.steps(for: .warm).map(\.command)
    private static let choice = PreviewScript.plan.common.count - 1

    /// After the choice, the first command of one sequence locks it: the
    /// other one's commands are refused from then on.
    @Test(arguments: [false, true])
    func theFirstDifferentCommandLocksTheSequence(chooseWarm: Bool) throws {
        let sequence = try Fixtures.previewGuard()
        let (chosen, other) = chooseWarm ? (Self.warm, Self.cold) : (Self.cold, Self.warm)
        for command in chosen.prefix(Self.choice + 2) { try sequence.check(command) }
        #expect(throws: TransportError.self) { try sequence.check(other[Self.choice + 1]) }
        #expect(sequence.expected == chosen)
        for command in chosen.dropFirst(Self.choice + 2) { try sequence.check(command) }
        #expect(sequence.isComplete)
    }

    /// Not complete while the commands of neither sequence have all gone through.
    @Test func notCompleteHalfWay() throws {
        let sequence = try Fixtures.previewGuard()
        for command in Self.warm.prefix(Self.warm.count - 1) { try sequence.check(command) }
        #expect(!sequence.isComplete)
    }

    /// The emergency stop after SCAN goes through the two-sequence guard, on either sequence.
    @Test(arguments: [false, true])
    func emergencyStopPassesAfterScan(cold: Bool) async throws {
        let sequence = try Fixtures.previewGuard()
        let commands = cold ? Self.cold : Self.warm
        let scan = commands.firstIndex { $0.opcode == 0x1B }!
        let faulty = FaultInjectingTransport(inner: cold ? try Fixtures.coldSimulator() : try Fixtures.simulator(),
                                             faultAtNonPollingCommand: scan + 10, fault: .checkCondition)
        let runner = PreviewRunner(transport: GuardedTransport(inner: faulty, sequence: sequence),
                                   configuration: .simulator, plan: PreviewScript.plan)
        do {
            _ = try await runner.run()
            Issue.record("the preview should have stopped")
        } catch {
            #expect(error.emergencyStop == .stoppedAndReady)
        }
        #expect(await faulty.commandsAfterFault.first == X1Command.stop())
    }

    /// Two alternatives identical up to after SCAN (the warm capture twice):
    /// the stop is still accepted after SCAN.
    @Test func stopAfterScanWithIdenticalAlternatives() throws {
        let sequence = try CapturedSequenceGuard(alternatives: [Fixtures.sequence(), Fixtures.sequence()])
        let scan = Self.warm.firstIndex { $0.opcode == 0x1B }!
        for command in PreviewScript.flexColor4813.map(\.command).prefix(scan + 1) { try sequence.check(command) }
        try sequence.check(X1Command.stop())
    }
}
