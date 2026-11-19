// SPDX-License-Identifier: MIT
import Foundation

/// The 31 scans of tests/fixtures/scan-windows-2026-11-18.json and -19.json
/// (FlexColor, original calibration), with the windows of each scan session:
/// read by `ScanWindowRulesTests` and `ScanWindowCalculatorTests`.
public enum ScanWindowFixtures {
    public struct Scan: Decodable, Sendable {
        public let ppi: Int
        public let tiff_width: Int
        public let tiff_height: Int
    }

    public struct ScanCase: Sendable {
        public let capture: String
        public let session: Int
        public let scan: Scan
        /// The image window as sent last, right before `1b 00 00 01 01 00`
        /// (offsets 54 / 58 moved by FlexColor's focus correction).
        public let image: [UInt8]
        /// The 400-line window (ratio 21 674 665).
        public let focus: [UInt8]
        /// The page 0x20 position read last before the 400-line window.
        public let focusTarget: Int?
        /// The window right before the 400-line window (54 / 58 before the
        /// focus correction).
        public let base: [UInt8]
        /// Whether the white and black references came before the 400-line
        /// step; nil when FlexColor skipped the calibration and references.
        public let referencesFirst: Bool?

        public var label: String { "\(capture) session \(session)" }
    }

    /// The holder FlexColor showed for each capture with a scan.
    public static let holders: [String: String] = [
        "essai-I": "6×7", "essai-L": "6×7", "essai-N": "6×7",
        "essai-J3": "24×36×4", "essai-J3-2": "24×36", "essai-J4": "4×5",
    ]

    private struct File: Decodable {
        struct Capture: Decodable {
            let capture: String
            let sessions: [Session]
        }
        struct Session: Decodable {
            let session: Int
            let events: [Event]
            let scan: Scan?
        }
        struct Event: Decodable {
            let window: String?
            let position: Int?
            let cdb: String?
        }
        let captures: [Capture]
    }

    public enum LoadError: Error, CustomStringConvertible {
        case missing(String)
        public var description: String {
            switch self { case .missing(let what): "scan-windows fixtures: \(what)" }
        }
    }

    static func bytes(_ hex: String) -> [UInt8] {
        hex.split(separator: " ").map { UInt8($0, radix: 16)! }
    }

    private static func le32(_ b: [UInt8], _ offset: Int) -> Int {
        (0..<4).reduce(0) { $0 | Int(b[offset + $1]) << (8 * $1) }
    }

    public static func load() throws -> [ScanCase] {
        var captures: [File.Capture] = []
        for name in ["scan-windows-2026-11-18.json", "scan-windows-2026-11-19.json"] {
            let url = Fixtures.directory.appending(path: name)
            captures += try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).captures
        }
        var result: [ScanCase] = []
        for capture in captures {
            for session in capture.sessions {
                guard let scan = session.scan else { continue }
                var windows: [([UInt8], Int?)] = []
                var position: Int?
                var image: [UInt8]?
                var focusIndex: Int?
                var referencesIndex: Int?
                for event in session.events {
                    if let p = event.position { position = p }
                    if let hex = event.window {
                        let window = bytes(hex)
                        if le32(window, 10) == 21_674_665 { focusIndex = windows.count }
                        windows.append((window, position))
                    }
                    if event.cdb == "1b 00 00 01 01 00" { image = windows.last?.0 }
                    if event.cdb?.hasPrefix("f0 00 01 01 00 01") == true { referencesIndex = windows.count }
                }
                let label = "\(capture.capture) session \(session.session)"
                guard let focus = focusIndex else { throw LoadError.missing("\(label): no 400-line window") }
                guard focus > 0 else { throw LoadError.missing("\(label): no window before the 400-line window") }
                guard let image else { throw LoadError.missing("\(label): no image window") }
                result.append(ScanCase(capture: capture.capture, session: session.session, scan: scan,
                                       image: image, focus: windows[focus].0, focusTarget: windows[focus].1,
                                       base: windows[focus - 1].0,
                                       referencesFirst: referencesIndex.map { $0 <= focus }))
            }
        }
        return result
    }
}
