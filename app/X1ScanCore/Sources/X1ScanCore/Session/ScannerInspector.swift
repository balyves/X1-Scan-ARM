// SPDX-License-Identifier: MIT
import X1Protocol
import X1Transport

/// What the Scanner palette shows: identity, usage counters and state.
public struct ScannerInfo: Sendable, Hashable {
    public var vendor: String
    public var model: String
    /// INQUIRY revision (`R185` on our unit).
    public var firmware: String
    /// Page 0x26. Never logged; shown masked by default (`SerialMasking`).
    public var serialNumber: String?
    /// Log page 0x30, seven counters. Meanings are [hypothesis].
    public var counters: [UInt32]
    public var state: ScannerState?

    public init(inquiry: InquiryResponse, identity: IdentityPage?, usage: UsageLog?, state: ScannerState?) {
        vendor = inquiry.vendor
        model = inquiry.product
        firmware = inquiry.revision
        serialNumber = identity?.serialNumber
        counters = usage?.counters ?? []
        self.state = state
    }
}

/// A connection to a real scanner that can be opened and closed.
public protocol ScannerConnection: SCSITransport {
    func open() async throws
    func close() async
}

extension IOKitTransport: ScannerConnection {}

/// Reads identity, counters and state from the real X1, with read commands
/// only, then closes the device at once so that FlexColor can open it.
///
/// Two guards: the connection the app uses is an `IOKitTransport` with the
/// `.readOnly` policy, and every command is also checked here against
/// `CommandPolicy.readOnly` before it is handed to the connection.
public struct ScannerInspector: Sendable {
    public enum Failure: Error, Hashable, CustomStringConvertible {
        case transport(TransportError)
        case notAFlextightX1(vendor: String, product: String)
        case badStatus(opcode: UInt8, status: UInt8, senseKey: UInt8?)
        case wrongLength(opcode: UInt8, expected: Int, received: Int)
        case malformed(String)
        case missingResponse(String)
        case other(String)

        public var description: String {
            switch self {
            case .transport(let error): error.description
            case .notAFlextightX1(let vendor, let product): "not a Flextight X1: '\(vendor)' '\(product)'"
            case .badStatus(let opcode, let status, let senseKey):
                "command 0x\([opcode].hexString): status 0x\([status].hexString)"
                    + (senseKey.map { ", sense key 0x\([$0].hexString)" } ?? "")
            case .wrongLength(let opcode, let expected, let received):
                "command 0x\([opcode].hexString): \(received) bytes, \(expected) expected"
            case .malformed(let detail): "malformed response: \(detail)"
            case .missingResponse(let what): "no recorded response to \(what)"
            case .other(let detail): detail
            }
        }
    }

    /// The commands sent, in order. All of them are in `CommandPolicy.readOnlyCommands`.
    public static let commands: [SCSICommand] = [
        X1Command.inquiry(),
        X1Command.modeSense(page: IdentityPage.page, length: IdentityPage.length),
        X1Command.usageLog(),
        X1Command.scannerState(),
    ]

    private let makeConnection: @Sendable () -> any ScannerConnection

    public init(makeConnection: @escaping @Sendable () -> any ScannerConnection) {
        self.makeConnection = makeConnection
    }

    /// The real X1, through IOKit, read-only.
    public static let realScanner = ScannerInspector { realConnection() }

    /// The connection `realScanner` opens. Separate so that tests can check its policy without opening it.
    static func realConnection() -> IOKitTransport { IOKitTransport(policy: .readOnly) }

    public func read() async throws(Failure) -> ScannerInfo {
        let connection = makeConnection()
        do {
            try await connection.open()
        } catch {
            throw Self.failure(from: error)
        }
        do {
            let info = try await readAll(from: connection)
            await connection.close()
            return info
        } catch {
            await connection.close()
            throw Self.failure(from: error)
        }
    }

    private func readAll(from connection: any ScannerConnection) async throws -> ScannerInfo {
        let inquiry = try await parse { try InquiryResponse(try await send(Self.commands[0], to: connection)) }
        // Nothing more is sent to a device that is not an X1.
        guard inquiry.isFlextightX1 else {
            throw Failure.notAFlextightX1(vendor: inquiry.vendor, product: inquiry.product)
        }
        let identity = try await parse { try IdentityPage(try await send(Self.commands[1], to: connection)) }
        let usage = try await parse { try UsageLog(try await send(Self.commands[2], to: connection)) }
        let state = try await parse { try ScannerState(try await send(Self.commands[3], to: connection)) }
        return ScannerInfo(inquiry: inquiry, identity: identity, usage: usage, state: state)
    }

    private func send(_ command: SCSICommand, to connection: any ScannerConnection) async throws -> [UInt8] {
        try CommandPolicy.readOnly.check(command)  // second guard, before the connection's own
        let result = try await connection.execute(command)
        guard result.isGood else {
            throw Failure.badStatus(opcode: command.opcode, status: result.status, senseKey: result.senseKey)
        }
        guard result.data.count == command.transferLength else {
            throw Failure.wrongLength(opcode: command.opcode, expected: command.transferLength,
                                      received: result.data.count)
        }
        return result.data
    }

    private func parse<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as Failure {
            throw error
        } catch let error as TransportError {
            throw error
        } catch {
            throw Failure.malformed(String(describing: error))
        }
    }

    private static func failure(from error: any Error) -> Failure {
        switch error {
        case let failure as Failure: failure
        case let transport as TransportError: .transport(transport)
        default: .other(String(describing: error))
        }
    }
}
