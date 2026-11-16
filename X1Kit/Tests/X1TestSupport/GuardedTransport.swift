// SPDX-License-Identifier: MIT
import X1Transport

/// `CapturedSequenceGuard` in front of another transport, as `IOKitTransport`
/// uses it, so that the guard can be tested against the simulator.
public struct GuardedTransport: SCSITransport {
    public let inner: any SCSITransport
    public let sequence: CapturedSequenceGuard

    public init(inner: any SCSITransport, sequence: CapturedSequenceGuard) {
        self.inner = inner
        self.sequence = sequence
    }

    public func execute(_ command: SCSICommand) async throws -> SCSIResult {
        try sequence.check(command)
        return try await inner.execute(command)
    }
}
