// SPDX-License-Identifier: MIT

public enum ResponseError: Error, Hashable, CustomStringConvertible {
    case tooShort(what: String, expected: Int, received: Int)
    case wrongPage(expected: UInt8, received: UInt8)

    public var description: String {
        switch self {
        case .tooShort(let what, let expected, let received):
            "\(what): \(received) bytes, at least \(expected) expected"
        case .wrongPage(let expected, let received):
            "page 0x\(String(received, radix: 16)) instead of 0x\(String(expected, radix: 16))"
        }
    }
}

func requireLength(_ bytes: [UInt8], _ minimum: Int, _ what: String) throws {
    guard bytes.count >= minimum else {
        throw ResponseError.tooShort(what: what, expected: minimum, received: bytes.count)
    }
}

func littleEndian16(_ bytes: [UInt8], at offset: Int) -> Int {
    Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
}

func littleEndian32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
    (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * UInt32($1)) }
}

/// ASCII text with trailing spaces and NULs removed.
func ascii<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
    var trimmed = Array(bytes)
    while let last = trimmed.last, last == 0x20 || last == 0x00 { trimmed.removeLast() }
    return String(decoding: trimmed, as: UTF8.self)
}

/// INQUIRY response. On the X1: type 6, `Imacon` / `Flextight X1` / `R185`. [confirmed]
public struct InquiryResponse: Sendable, Hashable {
    public let peripheralDeviceType: UInt8
    public let vendor: String
    public let product: String
    public let revision: String

    public init(_ bytes: [UInt8]) throws {
        try requireLength(bytes, 36, "INQUIRY")
        peripheralDeviceType = bytes[0] & 0x1F
        vendor = ascii(bytes[8..<16])
        product = ascii(bytes[16..<32])
        revision = ascii(bytes[32..<36])
    }

    public var isFlextightX1: Bool { vendor == "Imacon" && product == "Flextight X1" }
}

/// Vendor mode page 0x20, scan status (34 bytes). Offsets from the start of the response.
public struct ScanStatusPage: Sendable, Hashable {
    public static let page: UInt8 = 0x20
    public static let length = 34

    /// Bytes 27-28, LE16. A measured position, compared by FlexColor with
    /// the target of the scan window. Value [confirmed], meaning [hypothesis].
    public let measuredPosition: Int
    /// Bytes 31-32, LE16: lines acquired since SCAN. [confirmed]
    public let linesAcquired: Int
    public let bytes: [UInt8]

    public init(_ bytes: [UInt8]) throws {
        try requireLength(bytes, 33, "page 0x20")
        guard bytes[8] == Self.page else { throw ResponseError.wrongPage(expected: Self.page, received: bytes[8]) }
        measuredPosition = littleEndian16(bytes, at: 27)
        linesAcquired = littleEndian16(bytes, at: 31)
        self.bytes = bytes
    }
}

/// Vendor mode page 0x26, identity (56 bytes requested). [confirmed]
/// A 10-byte field (dashes when unset), then the serial number in ASCII.
public struct IdentityPage: Sendable, Hashable {
    public static let page: UInt8 = 0x26
    public static let length = 56

    /// Bytes 11-20. Dashes when unset.
    public let field: String
    /// From byte 22 up to the first NUL (`FX1…`).
    public let serialNumber: String

    public init(_ bytes: [UInt8]) throws {
        try requireLength(bytes, 32, "page 0x26")
        guard bytes[8] == Self.page else { throw ResponseError.wrongPage(expected: Self.page, received: bytes[8]) }
        field = ascii(bytes[11..<21])
        serialNumber = ascii(bytes[22...].prefix { $0 != 0 })
    }

    public var isFieldUnset: Bool { !field.isEmpty && field.allSatisfy { $0 == "-" } }
}

/// LOG SENSE page 0x30: seven LE32 counters after a 4-byte header.
/// One of them increases by 1 per preview; meanings are [hypothesis].
public struct UsageLog: Sendable, Hashable {
    public static let page: UInt8 = 0x30
    public static let length = 52

    public let counters: [UInt32]

    public init(_ bytes: [UInt8]) throws {
        try requireLength(bytes, 32, "log page 0x30")
        guard bytes[0] == Self.page else { throw ResponseError.wrongPage(expected: Self.page, received: bytes[0]) }
        counters = (0..<7).map { littleEndian32(bytes, at: 4 + 4 * $0) }
    }
}

/// Scanner state returned by 0xDF (docs/protocol.md §7).
public struct ScannerState: Sendable, Hashable, CustomStringConvertible {
    public let rawValue: UInt16

    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public init(_ bytes: [UInt8]) throws {
        try requireLength(bytes, 2, "0xDF state")
        rawValue = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
    }

    /// `00 00` ready. [confirmed]
    public static let ready = ScannerState(rawValue: 0x0000)
    /// `08 01` busy, after F0, SCAN, stop. [hypothesis: mechanical movement]
    public static let busy = ScannerState(rawValue: 0x0801)
    /// `08 40` busy, other phase, often after `08 01`.
    public static let busyOtherPhase = ScannerState(rawValue: 0x0840)
    /// `00 01` seen once, right after SCAN; FlexColor then starts reading image lines. [confirmed]
    public static let afterScan = ScannerState(rawValue: 0x0001)

    public var isBusy: Bool { self == .busy || self == .busyOtherPhase }

    public var description: String { [UInt8(rawValue >> 8), UInt8(rawValue & 0xFF)].hexString }
}
