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
    /// FlexColor's preview right after power-on (2026-11-16). With `fixture`,
    /// one of the two captures the real X1's guard is built from (page 0x28
    /// read left out; `PreviewScript.plan`). The virtual X1 itself replays
    /// `fixture`.
    public let coldFixture: CaptureFixture
    public let profile: CalibrationProfile
    public let pacing: Pacing
    /// FlexColor's preview then 2 000 ppi scan (2026-11-17): the virtual X1
    /// replays its scan session, and the real X1's scan guard is built from
    /// it (`ScanScript.flexColor4813Scan2000ppi`). Nil if not bundled: no scan.
    public let scanFixture: CaptureFixture?

    /// Identity, counters and state as recorded in the capture.
    public let info: ScannerInfo
    /// Tests only: wraps the transport of every preview (e.g. to pause the
    /// virtual X1 at a chosen command until the test lets it go on).
    var transportWrapper: (@Sendable (any SCSITransport) -> any SCSITransport)?

    public init(fixture: CaptureFixture, coldFixture: CaptureFixture, profile: CalibrationProfile,
                scanFixture: CaptureFixture? = nil, pacing: Pacing = .display) throws {
        self.fixture = fixture
        self.coldFixture = coldFixture
        self.scanFixture = scanFixture
        self.profile = profile
        self.pacing = pacing
        info = try Self.recordedInfo(in: fixture)
    }

    /// Loads `preview-sequence.json`, `preview-sequence-cold.json`,
    /// `preview-calibration-profile.json` and, if present,
    /// `scan-sequence-2000ppi.json` from `directory`.
    public static func load(fixturesDirectory directory: URL, pacing: Pacing = .display) throws -> VirtualScanner {
        let scanURL = directory.appending(path: "scan-sequence-2000ppi.json")
        let scan = FileManager.default.fileExists(atPath: scanURL.path) ? try CaptureFixture.load(from: scanURL) : nil
        return try VirtualScanner(
            fixture: CaptureFixture.load(from: directory.appending(path: "preview-sequence.json")),
            coldFixture: CaptureFixture.load(from: directory.appending(path: "preview-sequence-cold.json")),
            profile: CalibrationProfile.load(from: directory.appending(path: "preview-calibration-profile.json")),
            scanFixture: scan, pacing: pacing)
    }

    /// First exchange of the scan session in `scanFixture` (its last `CF 00 01 80`).
    var scanSessionSeq: Int? {
        scanFixture?.exchanges.last { $0.cdb == "cf 00 01 80 00 00" }?.seq
    }

    /// A fresh replay of the scan session, for one scan.
    func makeScanTransport() -> (transport: any SCSITransport, simulator: SimulatedX1)? {
        guard let scanFixture, let start = scanSessionSeq else { return nil }
        let simulator = SimulatedX1(fixture: scanFixture, profile: profile, fromSeq: start)
        let paced: any SCSITransport = pacing == .none ? simulator : PacedTransport(inner: simulator, pacing: pacing)
        return (transportWrapper.map { $0(paced) } ?? paced, simulator)
    }

    /// A fresh replay, from the start of the capture. One per preview.
    /// Also returns the simulator itself, whose log the tests read.
    func makeTransport() -> (transport: any SCSITransport, simulator: SimulatedX1) {
        let simulator = SimulatedX1(fixture: fixture, profile: profile, film: Self.film)
        let paced: any SCSITransport = pacing == .none ? simulator : PacedTransport(inner: simulator, pacing: pacing)
        return (transportWrapper.map { $0(paced) } ?? paced, simulator)
    }

    /// The film of the virtual X1's previews: the test pattern with a
    /// clipped and a dense patch (user's request of 2026-11-20), so that the
    /// exposure indicator and its overlay can be tried. With them the range
    /// used always reads 100 % on the virtual X1 (both ends reached). Scans
    /// keep the plain test pattern: the overlay is shown on the preview only.
    static let film = SyntheticFilm.exposurePatches

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
