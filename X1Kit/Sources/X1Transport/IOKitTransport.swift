// SPDX-License-Identifier: MIT
import CX1IOKit

/// The real scanner, through Apple's SCSITaskUserClient.
///
/// Every command is checked before anything touches IOKit: by `policy`
/// (`.readOnly` by default), or, for the captured preview of step 4, by
/// `capturedSequence` instead. Creating an `IOKitTransport` does not
/// talk to IOKit; only `open()` does.
public actor IOKitTransport: SCSITransport {
    /// Ignored when `capturedSequence` is set: see `isReadOnly`.
    public nonisolated let policy: CommandPolicy
    /// When set, it decides instead of `policy`: only the captured preview (step 4).
    public nonisolated let capturedSequence: CapturedSequenceGuard?
    private let timeoutMilliseconds: UInt32
    /// READ (0x28) timeout in captured-sequence mode.
    private let readTimeoutMilliseconds: UInt32

    /// True when nothing but the reads of `CommandPolicy.readOnly` can be sent.
    public nonisolated var isReadOnly: Bool { capturedSequence == nil && policy == .readOnly }
    private let handle = DeviceHandle()
    public private(set) var deviceDescription: String?

    public init(policy: CommandPolicy = .readOnly, timeoutMilliseconds: UInt32 = 10_000) {
        self.policy = policy
        capturedSequence = nil
        self.timeoutMilliseconds = timeoutMilliseconds
        readTimeoutMilliseconds = timeoutMilliseconds
    }

    /// The real X1 for FlexColor's captured preview only: every command is
    /// checked by `sequence` (CapturedSequenceGuard) before any IOKit call.
    /// A READ may wait for its lines up to `readTimeoutMilliseconds` (30 s:
    /// the user's limit without new lines; then the run stops with DB);
    /// every other command keeps the usual 10 s.
    public init(capturedSequence sequence: CapturedSequenceGuard, timeoutMilliseconds: UInt32 = 10_000,
                readTimeoutMilliseconds: UInt32 = 30_000) {
        policy = .readOnly
        capturedSequence = sequence
        self.timeoutMilliseconds = timeoutMilliseconds
        self.readTimeoutMilliseconds = readTimeoutMilliseconds
    }

    public var isOpen: Bool { handle.pointer != nil }

    /// Opens the first Imacon / Hasselblad scanner with exclusive access.
    public func open() throws {
        guard handle.pointer == nil else { return }
        var pointer: OpaquePointer?
        var description = [CChar](repeating: 0, count: 160)
        let code = cx1_open(&pointer, &description, description.count)
        guard code == 0, let pointer else {
            switch UInt32(bitPattern: code) {
            case 0xE000_02F0: throw TransportError.deviceNotFound  // kIOReturnNotFound
            case 0xE000_02BE: throw TransportError.deviceBusy      // kIOReturnNoResources
            default: throw TransportError.ioKit(code: code, operation: "open")
            }
        }
        handle.pointer = pointer
        deviceDescription = String(decoding: description.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
                                   as: UTF8.self)
    }

    public func close() {
        handle.close()
        deviceDescription = nil
    }

    public func execute(_ command: SCSICommand) throws -> SCSIResult {
        // First, before any IOKit call.
        if let capturedSequence { try capturedSequence.check(command) } else { try policy.check(command) }
        guard let device = handle.pointer else { throw TransportError.notOpen }

        var buffer = command.direction == .toDevice
            ? command.dataOut
            : [UInt8](repeating: 0, count: command.transferLength)
        var sense = [UInt8](repeating: 0, count: 18)
        var status: UInt8 = 0
        var transferred: UInt64 = 0
        var serviceResponse: UInt8 = 0
        let direction: Int32 = switch command.direction {
        case .none: CX1_DIRECTION_NONE
        case .toDevice: CX1_DIRECTION_TO_DEVICE
        case .fromDevice: CX1_DIRECTION_FROM_DEVICE
        }
        let timeout = command.opcode == 0x28 ? readTimeoutMilliseconds : timeoutMilliseconds

        let code = command.cdb.withUnsafeBufferPointer { cdb in
            buffer.withUnsafeMutableBufferPointer { data in
                sense.withUnsafeMutableBufferPointer { senseBytes in
                    cx1_execute(device, cdb.baseAddress!, UInt8(cdb.count),
                                data.baseAddress, UInt32(data.count), direction, timeout,
                                &status, &transferred, senseBytes.baseAddress, UInt32(senseBytes.count),
                                &serviceResponse)
                }
            }
        }
        guard code == 0 else { throw TransportError.ioKit(code: code, operation: "execute \(command)") }
        // `status` is a SCSI status only with kSCSIServiceResponse_TASK_COMPLETE (2).
        // SERVICE_DELIVERY_OR_TARGET_FAILURE (1): `status` gives the cause (timeout…).
        // Anything else, or a response that could not be read (0): not a status either.
        switch serviceResponse {
        case 2: break
        case 1: throw TransportError.deliveryFailure(.init(taskStatus: status))
        default: throw TransportError.deliveryFailure(.serviceResponse(serviceResponse))
        }

        let received = command.direction == .fromDevice ? Array(buffer.prefix(Int(transferred))) : []
        return SCSIResult(status: status, data: received,
                          sense: status == SCSIResult.checkCondition ? sense : [])
    }
}

/// Owns the C handle so it is closed when the transport goes away.
private final class DeviceHandle: @unchecked Sendable {
    // Only touched from the owning actor (and from deinit, when no one else can).
    var pointer: OpaquePointer?

    func close() {
        if let pointer { cx1_close(pointer) }
        pointer = nil
    }

    deinit { close() }
}
