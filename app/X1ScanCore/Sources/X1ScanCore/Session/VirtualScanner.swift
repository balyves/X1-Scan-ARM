// SPDX-License-Identifier: MIT
import Foundation
import X1Preview
import X1Protocol
import X1Transport

/// The virtual X1: a replay of tests/fixtures (`SimulatedX1`).
///
/// This is the only scanner the preview can run on at this stage:
/// `PreviewSession.start(on:)` takes a `VirtualScanner`, and a
/// `VirtualScanner` can only be made from capture fixtures. The real scanner
/// is reached through `ScannerInspector`, which only sends reads.
public struct VirtualScanner: Sendable {
    public let fixture: CaptureFixture
    public let profile: CalibrationProfile
    public let pacing: Pacing

    /// Identity, counters and state as recorded in the capture.
    public let info: ScannerInfo

    public init(fixture: CaptureFixture, profile: CalibrationProfile, pacing: Pacing = .display) throws {
        self.fixture = fixture
        self.profile = profile
        self.pacing = pacing
        info = try Self.recordedInfo(in: fixture)
    }

    /// Loads `preview-sequence.json` and `preview-calibration-profile.json` from `directory`.
    public static func load(fixturesDirectory directory: URL, pacing: Pacing = .display) throws -> VirtualScanner {
        try VirtualScanner(
            fixture: CaptureFixture.load(from: directory.appending(path: "preview-sequence.json")),
            profile: CalibrationProfile.load(from: directory.appending(path: "preview-calibration-profile.json")),
            pacing: pacing)
    }

    /// A fresh replay, from the start of the capture. One per preview.
    /// Also returns the simulator itself, whose log the tests read.
    func makeTransport() -> (transport: any SCSITransport, simulator: SimulatedX1) {
        let simulator = SimulatedX1(fixture: fixture, profile: profile)
        return (pacing == .none ? simulator : PacedTransport(inner: simulator, pacing: pacing), simulator)
    }

    /// The simulator answers at once: no delay between 0xDF polls.
    var configuration: PreviewConfiguration { .simulator }

    private static func recordedInfo(in fixture: CaptureFixture) throws -> ScannerInfo {
        func firstResponse(to command: SCSICommand) -> [UInt8]? {
            fixture.exchanges.first { $0.cdbBytes == command.cdb }?.responseBytes
        }
        guard let inquiryBytes = firstResponse(to: X1Command.inquiry()) else {
            throw ScannerInspector.Failure.missingResponse("INQUIRY")
        }
        let inquiry = try InquiryResponse(inquiryBytes)
        let identity = try firstResponse(to: X1Command.modeSense(page: IdentityPage.page, length: IdentityPage.length))
            .map(IdentityPage.init)
        let usage = try firstResponse(to: X1Command.usageLog()).map(UsageLog.init)
        let stateCDB = X1Command.scannerState().cdb
        let state = try fixture.exchanges.last { $0.cdbBytes == stateCDB }?.responseBytes.map(ScannerState.init)
        return ScannerInfo(inquiry: inquiry, identity: identity, usage: usage, state: state)
    }
}

/// Delays added in front of the virtual X1 so that the image can be seen
/// building up. **Not a measurement of the real X1**: the capture's timing is
/// not reproduced, these are display choices.
public struct Pacing: Sendable, Hashable {
    /// Before every non-polling command.
    public var perCommand: Duration
    /// Before every image READ (20 lines in the preview).
    public var perImageRead: Duration

    public init(perCommand: Duration, perImageRead: Duration) {
        self.perCommand = perCommand
        self.perImageRead = perImageRead
    }

    /// About 4 s for a whole preview.
    public static let display = Pacing(perCommand: .milliseconds(3), perImageRead: .milliseconds(70))
    public static let none = Pacing(perCommand: .zero, perImageRead: .zero)
}

/// Forwards to another transport after a delay. The delay ignores task
/// cancellation (it just ends early), so that the stop sequence the runner
/// sends after a cancellation is never lost to a `CancellationError`. A
/// command already handed over when Stop is pressed is still forwarded, as
/// it would be by the real transport; the runner sends nothing after it
/// except the stop sequence.
actor PacedTransport: SCSITransport {
    private let inner: any SCSITransport
    private let pacing: Pacing

    init(inner: any SCSITransport, pacing: Pacing) {
        self.inner = inner
        self.pacing = pacing
    }

    func execute(_ command: SCSICommand) async throws -> SCSIResult {
        if !SimulatedX1.pollingOpcodes.contains(command.opcode) {
            let isImageRead = command.opcode == 0x28 && command.cdb.count > 5 && command.cdb[5] == 0x00
            let delay = isImageRead ? pacing.perImageRead : pacing.perCommand
            if delay > .zero { try? await Task.sleep(for: delay) }
        }
        return try await inner.execute(command)
    }
}
