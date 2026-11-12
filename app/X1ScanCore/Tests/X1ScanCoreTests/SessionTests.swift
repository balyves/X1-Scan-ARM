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

    @Test func stopBeforeScanSendsNothingMore() async throws {
        let session = PreviewSession()
        session.start(on: try TestFixtures.scanner(pacing: TestFixtures.slow))
        try await waitUntil { session.progress.phase == .calibration }
        let simulator = try #require(session.simulator)
        let sentBeforeStop = await simulator.log.count
        session.stop()
        #expect(session.state == .stopping)
        await session.waitUntilIdle()
        #expect(session.state == .stopped(nil))
        #expect(session.image == nil)
        let log = await simulator.log
        #expect(!log.contains { $0.opcode == 0x1B || $0.opcode == 0xDB }, "no SCAN, no stop")
        // The count is read just before stop(), across an actor hop: the runner may
        // send one more command in between, plus the one already handed to the
        // transport when stop() is called. Polls of 0xDF are not counted.
        let after = log.dropFirst(sentBeforeStop).filter { $0.opcode != 0xDF }
        #expect(after.count <= 2)
    }

    @Test func stopAfterScanRunsTheStopSequence() async throws {
        let session = PreviewSession()
        session.start(on: try TestFixtures.scanner(pacing: TestFixtures.slow))
        try await waitUntil { (session.image?.height ?? 0) > 0 }
        session.stop()
        await session.waitUntilIdle()
        #expect(session.state == .stopped(.stoppedAndReady))
        let image = try #require(session.image)
        #expect(image.height > 0 && !image.isComplete, "the partial image is kept")

        // After the stop: one DB, then only 0xDF until 00 00; no end of session.
        let log = try await #require(session.simulator).log
        let stopIndex = try #require(log.firstIndex { $0.opcode == 0xDB })
        #expect(log.filter { $0.opcode == 0xDB }.count == 1)
        #expect(log[(stopIndex + 1)...].allSatisfy { $0.opcode == 0xDF })
        #expect(!log.contains { $0.opcode == 0xCF && $0.cdb[2] == 0x02 })
    }

    @Test func startIsIgnoredWhileBusyAndStopWhileIdle() async throws {
        let session = PreviewSession()
        session.stop()
        #expect(session.state == .idle)
        let scanner = try TestFixtures.scanner(pacing: TestFixtures.slow)
        session.start(on: scanner)
        try await waitUntil { session.progress.stepIndex > 3 }
        let step = session.progress.stepIndex
        session.start(on: scanner)  // ignored: no reset
        #expect(session.progress.stepIndex >= step)
        session.stop()
        session.stop()
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
                                    calibrationProfileURL: TestFixtures.directory.appending(path: "preview-calibration-profile.json"))
    }
}
