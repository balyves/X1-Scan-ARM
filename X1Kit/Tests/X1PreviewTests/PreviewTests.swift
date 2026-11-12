// SPDX-License-Identifier: MIT
import Testing
import X1Preview
import X1Protocol
import X1TestSupport
import X1Transport

struct PreviewConformanceTests {
    /// Our sequence, played against the simulator, sends the same commands as
    /// FlexColor in the same order: CDB, direction, transfer length and data_out,
    /// apart from the polling commands (0xEE, 0xD3, 0xDF).
    @Test func previewMatchesTheCaptureCommandForCommand() async throws {
        let simulator = try Fixtures.simulator()
        _ = try await PreviewRunner(transport: simulator, configuration: .simulator).run()

        let sent = await simulator.log.filter { !SimulatedX1.pollingOpcodes.contains($0.opcode) }
        let captured = try Fixtures.nonPollingExchanges()
        #expect(sent.count == captured.count)
        for (command, exchange) in zip(sent, captured) {
            #expect(command.cdb == exchange.cdbBytes, "seq \(exchange.seq): CDB")
            #expect(command.direction == exchange.commandDirection, "seq \(exchange.seq): direction")
            #expect(command.transferLength == exchange.length, "seq \(exchange.seq): transfer length")
            #expect(command.dataOut == (exchange.dataOutBytes ?? []), "seq \(exchange.seq): data_out")
        }
    }

    /// We poll 0xDF after exactly the commands after which FlexColor polled it
    /// (the number of polls may differ). Not waiting would mean sending the next
    /// command while the scanner is still moving.
    @Test func waitsOnScannerStateWhereFlexColorDid() async throws {
        let simulator = try Fixtures.simulator()
        _ = try await PreviewRunner(transport: simulator, configuration: .simulator).run()

        func waitsAfterEachCommand(_ opcodes: [UInt8]) -> [Bool] {
            var waits: [Bool] = []
            for opcode in opcodes {
                if opcode == 0xDF {
                    if !waits.isEmpty { waits[waits.count - 1] = true }
                } else if !SimulatedX1.pollingOpcodes.contains(opcode) {
                    waits.append(false)
                }
            }
            return waits
        }
        let ours = waitsAfterEachCommand(await simulator.log.map(\.opcode))
        let flexColor = waitsAfterEachCommand(try Fixtures.sequence().exchanges.map { $0.cdbBytes[0] })
        let captured = try Fixtures.nonPollingExchanges()
        #expect(ours.count == flexColor.count)
        for (index, (mine, theirs)) in zip(ours, flexColor).enumerated() {
            #expect(mine == theirs, "after seq \(captured[index].seq) (\(captured[index].cdb))")
        }
    }

    @Test func onlyPollingCommandSentIsTheStateRead() async throws {
        let simulator = try Fixtures.simulator()
        _ = try await PreviewRunner(transport: simulator, configuration: .simulator).run()
        let polls = await simulator.log.filter { SimulatedX1.pollingOpcodes.contains($0.opcode) }
        #expect(!polls.isEmpty)
        #expect(polls.allSatisfy { $0 == X1Command.scannerState() })
    }

    @Test func captureContainsTheExpectedReads() async throws {
        let simulator = try Fixtures.simulator()
        let capture = try await PreviewRunner(transport: simulator, configuration: .simulator).run()
        #expect(capture.calibrationLines.count == 3)
        #expect(capture.whiteReference.count == 5)
        #expect(capture.darkReference.count == 18)
        #expect(capture.leadIn.count == 3)
        #expect(capture.image.count == 41)
        #expect(capture.image.reduce(0) { $0 + $1.count } == 819 * 2004 * 6)
    }
}

struct PreviewStopTests {
    private static let script = PreviewScript.flexColor4813
    private static let scanIndex = script.firstIndex { $0.kind == .scan }!

    private func run(faultAt index: Int, _ fault: FaultInjectingTransport.Fault)
        async throws -> (FaultInjectingTransport, Result<PreviewCapture, PreviewError>) {
        let transport = FaultInjectingTransport(inner: try Fixtures.simulator(),
                                                faultAtNonPollingCommand: index, fault: fault)
        let runner = PreviewRunner(transport: transport, configuration: .simulator)
        do {
            return (transport, .success(try await runner.run()))
        } catch {
            return (transport, .failure(error))
        }
    }

    @Test func anomalyAfterScanSendsOnlyStopThenWaitsForReady() async throws {
        let index = Self.scanIndex + 10  // an image read
        let (transport, result) = try await run(faultAt: index, .checkCondition)
        guard case .failure(let error) = result else {
            Issue.record("the preview should have stopped")
            return
        }
        #expect(error.stepIndex == index)
        #expect(error.anomaly == .badStatus(status: 0x02, senseKey: 0x04))
        #expect(error.emergencyStop == .stoppedAndReady)
        // DB, then 0xDF until 00 00 (08 01, 00 00), and nothing else.
        #expect(await transport.commandsAfterFault == [X1Command.stop(), X1Command.scannerState(), X1Command.scannerState()])
    }

    @Test func anomalyOnScanItselfAlsoStops() async throws {
        let (transport, result) = try await run(faultAt: Self.scanIndex, .checkCondition)
        guard case .failure(let error) = result else {
            Issue.record("the preview should have stopped")
            return
        }
        #expect(error.emergencyStop == .stoppedAndReady)
        #expect(await transport.commandsAfterFault.first == X1Command.stop())
    }

    @Test func anomalyBeforeScanSendsNothingMore() async throws {
        let index = Self.scanIndex - 3
        let (transport, result) = try await run(faultAt: index, .checkCondition)
        guard case .failure(let error) = result else {
            Issue.record("the preview should have stopped")
            return
        }
        #expect(error.stepIndex == index)
        #expect(error.emergencyStop == nil)
        #expect(await transport.commandsAfterFault.isEmpty)
    }

    private static let positioningIndex = script.firstIndex { $0.kind == .scanStatus(capturedPosition: 8971) }!

    @Test func positionBeyondToleranceStops() async throws {
        let (transport, result) = try await run(faultAt: Self.positioningIndex, .shiftMeasuredPosition(by: 101))
        guard case .failure(let error) = result else {
            Issue.record("the preview should have stopped")
            return
        }
        #expect(error.anomaly == .positionOutOfTolerance(captured: 8971, measured: 9072, tolerance: 100))
        #expect(error.emergencyStop == nil)
        #expect(await transport.commandsAfterFault.isEmpty)
    }

    @Test func positionWithinToleranceIsAccepted() async throws {
        // Two captures differed by 64 on the first measurement.
        let (_, result) = try await run(faultAt: Self.positioningIndex, .shiftMeasuredPosition(by: 64))
        if case .failure(let error) = result { Issue.record("unexpected stop: \(error)") }
    }
}
