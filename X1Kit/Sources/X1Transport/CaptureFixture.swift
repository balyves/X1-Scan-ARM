// SPDX-License-Identifier: MIT
import Foundation

/// tests/fixtures/preview-sequence.json: every SCSI exchange of one FlexColor preview.
public struct CaptureFixture: Decodable, Sendable {
    public let description: String
    public let notes: [String]
    public let exchanges: [CaptureExchange]

    public static func load(from url: URL) throws -> CaptureFixture {
        try JSONDecoder().decode(CaptureFixture.self, from: Data(contentsOf: url))
    }
}

public struct CaptureExchange: Decodable, Sendable {
    public let seq: Int
    public let cdb: String
    /// "in" (scanner to host), "out" (host to scanner) or "none".
    public let direction: String
    public let length: Int
    public let dataOut: String?
    /// SCSI status; nil for asynchronous image reads.
    public let status: Int?
    public let transferred: Int?
    public let response: String?
    public let responseHead: String?
    public let isAsync: Bool

    enum CodingKeys: String, CodingKey {
        case seq, cdb, direction, length, status, transferred, response
        case dataOut = "data_out"
        case responseHead = "response_head"
        case isAsync = "async"
    }

    public var cdbBytes: [UInt8] { [UInt8](hex: cdb) ?? [] }
    public var dataOutBytes: [UInt8]? { dataOut.flatMap { [UInt8](hex: $0) } }
    /// Complete response, when it was recorded.
    public var responseBytes: [UInt8]? { response.flatMap { [UInt8](hex: $0) } }

    public var commandDirection: SCSICommand.Direction? {
        switch direction {
        case "in": .fromDevice
        case "out": .toDevice
        case "none": SCSICommand.Direction.none
        default: nil
        }
    }
}

/// tests/fixtures/preview-calibration-profile.json: per-column white and dark levels.
public struct CalibrationProfile: Decodable, Sendable {
    public let description: String
    public let width: Int
    /// `width` entries of [R, G, B].
    public let white: [[Int]]
    public let dark: [[Int]]

    public static func load(from url: URL) throws -> CalibrationProfile {
        try JSONDecoder().decode(CalibrationProfile.self, from: Data(contentsOf: url))
    }
}
