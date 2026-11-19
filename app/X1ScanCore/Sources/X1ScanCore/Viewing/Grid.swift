// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation

/// The grid drawn over the image (lot 1). Display only: never in the scan
/// nor in an exported file.
public enum GridKind: String, Sendable, Hashable, CaseIterable, Codable {
    /// Two lines each way, at a third and two thirds.
    case thirds
    /// Lines at a regular spacing, `GridSettings.fineDivisions` across the longer side.
    case fine
    /// One horizontal and one vertical line through the centre.
    case centre
}

/// Grid shown or not, its kind and the fine grid's spacing; saved between launches.
public struct GridSettings: Sendable, Hashable, Codable {
    public static let divisionChoices = [4, 6, 8, 10, 12, 16, 20, 24]
    public static let defaultDivisions = 12

    public var isVisible = false
    public var kind: GridKind = .thirds
    /// Squares across the longer side of the area for the fine grid.
    public var fineDivisions: Int = GridSettings.defaultDivisions {
        didSet { fineDivisions = Self.clampedDivisions(fineDivisions) }
    }
    public static let divisionRange = 2...64

    static func clampedDivisions(_ value: Int) -> Int {
        min(max(value, divisionRange.lowerBound), divisionRange.upperBound)
    }

    public init() {}

    private enum CodingKeys: String, CodingKey { case isVisible, kind, fineDivisions }

    /// Unknown values (another version) fall back to the defaults.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isVisible = (try? container.decodeIfPresent(Bool.self, forKey: .isVisible)) ?? false
        kind = (try? container.decodeIfPresent(String.self, forKey: .kind)).flatMap(GridKind.init(rawValue:)) ?? .thirds
        // didSet does not run in an initialiser: bounded here.
        fineDivisions = Self.clampedDivisions((try? container.decodeIfPresent(Int.self, forKey: .fineDivisions))
                                              ?? Self.defaultDivisions)
    }

    /// The lines of `kind` over `rect` (display coordinates), as segments.
    public static func lines(_ kind: GridKind, in rect: CGRect, fineDivisions: Int = defaultDivisions)
        -> [(CGPoint, CGPoint)] {
        guard rect.width > 0, rect.height > 0 else { return [] }
        func vertical(_ x: Double) -> (CGPoint, CGPoint) { (CGPoint(x: x, y: rect.minY), CGPoint(x: x, y: rect.maxY)) }
        func horizontal(_ y: Double) -> (CGPoint, CGPoint) { (CGPoint(x: rect.minX, y: y), CGPoint(x: rect.maxX, y: y)) }
        switch kind {
        case .thirds:
            var segments: [(CGPoint, CGPoint)] = []
            for fraction in [1.0 / 3, 2.0 / 3] {
                segments.append(vertical(rect.minX + rect.width * fraction))
                segments.append(horizontal(rect.minY + rect.height * fraction))
            }
            return segments
        case .centre:
            return [vertical(rect.midX), horizontal(rect.midY)]
        case .fine:
            // Square cells: the spacing comes from the longer side; lines from the centre out.
            let spacing = max(rect.width, rect.height) / Double(clampedDivisions(fineDivisions))
            var segments: [(CGPoint, CGPoint)] = []
            var offset = 0.0
            while offset < rect.width / 2 {
                segments.append(vertical(rect.midX + offset))
                if offset > 0 { segments.append(vertical(rect.midX - offset)) }
                offset += spacing
            }
            offset = 0
            while offset < rect.height / 2 {
                segments.append(horizontal(rect.midY + offset))
                if offset > 0 { segments.append(horizontal(rect.midY - offset)) }
                offset += spacing
            }
            return segments
        }
    }
}
