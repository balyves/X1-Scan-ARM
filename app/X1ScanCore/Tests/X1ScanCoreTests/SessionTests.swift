// SPDX-License-Identifier: MIT
import Foundation
import Testing
import X1Image
import X1Preview
import X1Transport
@testable import X1ScanCore

@MainActor
struct PreviewSessionTests {
    @Test func previewBuildsTheWholeImage() async throws {
        let session = PreviewSession()
        session.start(on: try TestFixtures.scanner())
        #expect(session.state == .running)
        await session.waitUntilIdle()
        #expect(session.state == .finished)
        #expect(session.progress.linesReceived == 819)
        #expect(session.progress.linesExpected == 819)
        let image = try #require(session.image)
        #expect(image.width == 2004 && image.height == 817 && image.isComplete)
        #expect(session.imageRevision > 1, "the image was built in several steps")

        // Same pixels as the batch decoding of X1Kit.
        let capture = try await PreviewRunner(transport: SimulatedX1Factory.make(), configuration: .simulator).run()
        let batch = try PreviewDecoding.decode(white: capture.whiteReference, dark: capture.darkReference,
                                               image: capture.image, width: 2004)
        #expect(image.exportImage == batch.toRGB16())
    }

    /// The virtual X1 is paused before a calibration command; the stop is
    /// requested there, then the command goes on: deterministic.
    @Test func stopBeforeScanSendsNothingMore() async throws {
        let gate = PreviewGate()
        let pausedAt = 60  // a calibration command, well before SCAN
        #expect(pausedAt < TestFixtures.scanIndex)
        let session = PreviewSession()
        session.start(on: try TestFixtures.scanner(pausedAt: pausedAt, gate: gate))
        await gate.waitUntilPaused()
        session.stop()
        #expect(session.state == .stopping)
        await gate.release()
        await session.waitUntilIdle()
        #expect(session.state == .stopped(nil))
        #expect(session.image == nil)
        let log = try await #require(session.simulator).log
        #expect(!log.contains { $0.opcode == 0x1B || $0.opcode == 0xDB }, "no SCAN, no stop")
        // Only the command already handed to the transport (and its 0xDF polls) after the pause.
        let nonPolls = log.filter { !SimulatedX1.pollingOpcodes.contains($0.opcode) }
        #expect(nonPolls.count == pausedAt + 1)
    }

    @Test func stopAfterScanRunsTheStopSequence() async throws {
        let gate = PreviewGate()
        let session = PreviewSession()
        session.start(on: try TestFixtures.scanner(pausedAt: TestFixtures.scanIndex + 10, gate: gate))
        await gate.waitUntilPaused()
        session.stop()
        await gate.release()
        await session.waitUntilIdle()
        #expect(session.state == .stopped(.stoppedAndReady))
        let image = try #require(session.image)
        #expect(image.height > 0 && !image.isComplete, "the partial image is kept")

        // After the stop: one DB, then only 0xDF until 00 00; no end of session.
        let log = try await #require(session.simulator).log
        let stopIndex = try #require(log.firstIndex { $0.opcode == 0xDB })
        #expect(log.filter { $0.opcode == 0xDB }.count == 1)
        let nonPollsBeforeStop = log[..<stopIndex].filter { !SimulatedX1.pollingOpcodes.contains($0.opcode) }
        #expect(nonPollsBeforeStop.count == TestFixtures.scanIndex + 10 + 1, "DB right after the command in progress")
        #expect(log[(stopIndex + 1)...].allSatisfy { $0.opcode == 0xDF })
        #expect(!log.contains { $0.opcode == 0xCF && $0.cdb[2] == 0x02 })
    }

    @Test func startIsIgnoredWhileBusyAndStopWhileIdle() async throws {
        let session = PreviewSession()
        session.stop()
        #expect(session.state == .idle)
        let gate = PreviewGate()
        let scanner = try TestFixtures.scanner(pausedAt: 5, gate: gate)
        session.start(on: scanner)
        await gate.waitUntilPaused()
        let step = session.progress.stepIndex
        session.start(on: scanner)  // ignored: no reset
        #expect(session.progress.stepIndex >= step)
        session.stop()
        session.stop()
        await gate.release()
        await session.waitUntilIdle()
        #expect(session.state == .stopped(nil))
    }

    @Test func virtualScannerInfoComesFromTheCapture() throws {
        let info = try TestFixtures.scanner().info
        #expect(info.vendor == "Imacon" && info.model == "Flextight X1")
        #expect(info.firmware == "R185")
        #expect(info.serialNumber?.hasPrefix("FX1") == true)
        #expect(info.counters.count == 7)
        #expect(info.state == .ready)
    }
}

enum SimulatedX1Factory {
    static func make() throws -> SimulatedX1 {
        try SimulatedX1(sequenceURL: TestFixtures.directory.appending(path: "preview-sequence.json"),
                                    calibrationProfileURL: TestFixtures.directory.appending(path: "preview-calibration-profile.json"),
                                    film: VirtualScanner.film)  // the virtual X1's film, exposure patches included
    }
}
