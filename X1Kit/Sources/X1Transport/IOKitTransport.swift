// SPDX-License-Identifier: MIT
import CX1IOKit

/// The real scanner, through Apple's SCSITaskUserClient.
///
/// Every command goes through `policy.check` before anything touches IOKit.
/// The default policy is `.readOnly`. Creating an `IOKitTransport` does not
/// talk to IOKit; only `open()` does.
public actor IOKitTransport: SCSITransport {
    public nonisolated let policy: CommandPolicy
    private let timeoutMilliseconds: UInt32
    private let handle = DeviceHandle()
    public private(set) var deviceDescription: String?

    public init(policy: CommandPolicy = .readOnly, timeoutMilliseconds: UInt32 = 10_000) {
        self.policy = policy
        self.timeoutMilliseconds = timeoutMilliseconds
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
        try policy.check(command)  // first, before any IOKit call
        guard let device = handle.pointer else { throw TransportError.notOpen }

        var buffer = command.direction == .toDevice
            ? command.dataOut
            : [UInt8](repeating: 0, count: command.transferLength)
        var sense = [UInt8](repeating: 0, count: 18)
        var status: UInt8 = 0
        var transferred: UInt64 = 0
        let direction: Int32 = switch command.direction {
        case .none: CX1_DIRECTION_NONE
        case .toDevice: CX1_DIRECTION_TO_DEVICE
        case .fromDevice: CX1_DIRECTION_FROM_DEVICE
        }
        let timeout = timeoutMilliseconds

        let code = command.cdb.withUnsafeBufferPointer { cdb in
            buffer.withUnsafeMutableBufferPointer { data in
                sense.withUnsafeMutableBufferPointer { senseBytes in
                    cx1_execute(device, cdb.baseAddress!, UInt8(cdb.count),
                                data.baseAddress, UInt32(data.count), direction, timeout,
                                &status, &transferred, senseBytes.baseAddress, UInt32(senseBytes.count))
                }
            }
        }
        guard code == 0 else { throw TransportError.ioKit(code: code, operation: "execute \(command)") }

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
