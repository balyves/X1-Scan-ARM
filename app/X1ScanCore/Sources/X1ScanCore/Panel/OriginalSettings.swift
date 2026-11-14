// SPDX-License-Identifier: MIT
import Foundation

/// The film in the scanner.
public enum FilmType: String, Sendable, Hashable, CaseIterable, Codable {
    case positive
    case colorNegative
    case blackAndWhiteNegative
}

/// Original and scan settings of the panel. Saved, but **not sent to the
/// scanner yet**: they take effect with real scans (a later step).
public struct ScanSettings: Sendable, Hashable, Codable {
    public static let resolutionRange = 50...10_000
    public static let scaleRange = 1...1_000

    public var filmType: FilmType = .positive
    /// Free text; empty means "not specified".
    public var holder: String = ""
    /// Pixels per inch, for the scan (stored only).
    public var resolution: Int = 2_000 {
        didSet { resolution = min(max(resolution, Self.resolutionRange.lowerBound), Self.resolutionRange.upperBound) }
    }
    /// Output scale in percent (stored only).
    public var scalePercent: Int = 100 {
        didSet { scalePercent = min(max(scalePercent, Self.scaleRange.lowerBound), Self.scaleRange.upperBound) }
    }

    public init() {}

    private enum CodingKeys: String, CodingKey { case filmType, holder, resolution, scalePercent }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filmType = (try container.decodeIfPresent(String.self, forKey: .filmType)).flatMap(FilmType.init(rawValue:)) ?? .positive
        holder = try container.decodeIfPresent(String.self, forKey: .holder) ?? ""
        let resolution = try container.decodeIfPresent(Int.self, forKey: .resolution) ?? 2_000
        let scale = try container.decodeIfPresent(Int.self, forKey: .scalePercent) ?? 100
        self.resolution = min(max(resolution, Self.resolutionRange.lowerBound), Self.resolutionRange.upperBound)
        scalePercent = min(max(scale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(filmType.rawValue, forKey: .filmType)
        try container.encode(holder, forKey: .holder)
        try container.encode(resolution, forKey: .resolution)
        try container.encode(scalePercent, forKey: .scalePercent)
    }
}

/// How RGB values are shown in the bottom bar.
public enum RGBUnit: String, Sendable, Hashable, CaseIterable {
    /// 0-255. Default.
    case eightBit
    case percent
    /// 0-65535, the stored values.
    case sixteenBit

    /// `value` (0-65535) in this unit.
    public func value(_ sample: UInt16) -> Double {
        switch self {
        case .eightBit: (Double(sample) * 255 / 65_535).rounded()
        case .percent: Double(sample) * 100 / 65_535
        case .sixteenBit: Double(sample)
        }
    }
}

/// The zoom menu of the bottom bar: Fit, Fill, then the steps. A choice is
/// applied only when confirmed (click, Return), never while the list is browsed.
public enum ZoomMenuEntry: Sendable, Hashable {
    case fit
    case fill
    case step(Double)

    public static let all: [ZoomMenuEntry] = [.fit, .fill] + Viewport.steps.map(ZoomMenuEntry.step)

    /// The entry whose title is `text`, if any.
    public static func entry(titled text: String, title: (ZoomMenuEntry) -> String) -> ZoomMenuEntry? {
        all.first { title($0) == text }
    }
}
