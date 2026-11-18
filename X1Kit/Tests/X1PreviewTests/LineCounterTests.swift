// SPDX-License-Identifier: MIT
import Testing
import X1Preview
import X1Protocol
import X1TestSupport
import X1Transport

/// Page 0x20's line counter (bytes 31-32) must not go back in the image
/// phase only, between `1b 00 00 01 01 00` and the next DB (real X1,
/// 2026-11-18; docs/protocol.md §5).
struct LineCounterTests {
    private static let script = ScanRunTests.script
    private static let imageScan = script.lastIndex { $0.command == X1Command.scan() }!
    private static let focusStop = script.firstIndex { $0.command == X1Command.stop() }!

    /// Page 0x20 reads of the white and black references (between the
    /// 400-line step and the image at 2 000 ppi; at 1 000 and 3 200 ppi
    /// FlexColor reads the references before the 400-line step, so this
    /// filter is specific to this script).
    private static let referenceStatusReads = script.indices.filter { index in
        index > focusStop && index < imageScan && script[index].command.cdb.prefix(3) == [0x5A, 0x00, 0x20]
    }

    /// The case of 2026-11-18 (x1scan-scan log, step 458): 0b, then 0a
    /// during the references. The scan now goes on to the end.
    @Test func theReferencesOfTheScanDoNotCheckIt() async throws {
        #expect(Self.referenceStatusReads.count == 2)
        #expect(Self.referenceStatusReads.last == 458, "the step of the log")
        let transport = LineCounterOverride(inner: try ScanRunTests.simulator(),
                                            values: [Self.referenceStatusReads[0]: 11, Self.referenceStatusReads[1]: 10])
        let sequence = try ScanRunTests.scanGuard()
        let capture = try await ScanRunTests.runner(GuardedTransport(inner: transport, sequence: sequence)).run()
        #expect(sequence.isComplete)
        #expect(await transport.overridden == 2)
        #expect(capture.image.reduce(0) { $0 + $1.count } == 1023 * ScanScript.pixelsPerLine * 6)
    }

    /// In the image phase, a counter that goes back still stops the scan,
    /// with the emergency DB.
    @Test func theImagePhaseStillChecksIt() async throws {
        let reads = Self.script.indices.filter {
            $0 > Self.imageScan && Self.script[$0].command.cdb.prefix(3) == [0x5A, 0x00, 0x20]
        }
        let transport = LineCounterOverride(inner: try ScanRunTests.simulator(),
                                            values: [reads[2]: 200, reads[3]: 199])
        do {
            _ = try await ScanRunTests.runner(transport).run()
            Issue.record("the scan should have stopped")
        } catch {
            #expect(error.anomaly == .lineCounterWentBack(previous: 200, current: 199))
            #expect(error.stepIndex == reads[3])
            #expect(error.emergencyStop == .stoppedAndReady)
        }
    }

    /// The preview: the check starts at its SCAN too (no page 0x20 read with
    /// a smaller counter in its image phase), and the captured preview runs.
    @Test func thePreviewImagePhaseIsChecked() async throws {
        let plan = PreviewScript.plan
        let steps = plan.steps(for: .warm)
        let scan = try #require(steps.lastIndex { $0.command == X1Command.scan() })
        let reads = steps.indices.filter { $0 > scan && steps[$0].command.cdb.prefix(3) == [0x5A, 0x00, 0x20] }
        let transport = LineCounterOverride(inner: try Fixtures.simulator(), values: [reads[0]: 500, reads[1]: 400])
        do {
            _ = try await PreviewRunner(transport: transport, configuration: .simulator, plan: plan).run()
            Issue.record("the preview should have stopped")
        } catch {
            #expect(error.anomaly == .lineCounterWentBack(previous: 500, current: 400))
        }
    }
}

/// Sets page 0x20's line counter (bytes 31-32, LE) in the response to given
/// non-polling commands (0-based), forwarding everything else to `inner`.
private actor LineCounterOverride: SCSITransport {
    private let inner: any SCSITransport
    private let values: [Int: Int]
    private var nonPolling = -1
    private(set) var overridden = 0

    init(inner: any SCSITransport, values: [Int: Int]) {
        self.inner = inner
        self.values = values
    }

    func execute(_ command: SCSICommand) async throws -> SCSIResult {
        if ![0xDF, 0xEE, 0xD3].contains(command.opcode) { nonPolling += 1 }
        let result = try await inner.execute(command)
        guard command.opcode != 0xDF, let value = values[nonPolling], result.data.count > 32 else { return result }
        var data = result.data
        data[31] = UInt8(value & 0xFF)
        data[32] = UInt8(value >> 8)
        overridden += 1
        return SCSIResult(status: result.status, data: data, sense: result.sense)
    }
}
