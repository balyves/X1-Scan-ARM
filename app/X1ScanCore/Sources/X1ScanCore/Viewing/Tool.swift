// SPDX-License-Identifier: MIT

/// Tools of the vertical tool bar.
public enum Tool: String, Sendable, Hashable, CaseIterable, Codable {
    /// Move the image (hand).
    case hand
    /// Click to zoom in, Option-click to zoom out.
    case zoom
    /// Draw, move and resize the crop frame (lot 1). Never sent to the scanner:
    /// applied to the exported file.
    case crop
    /// The straightening rule (lot 1): a line along what should be horizontal or vertical.
    case straighten

    /// Single-key shortcut, as in image editors.
    public var key: Character {
        switch self {
        case .hand: "h"
        case .zoom: "z"
        case .crop: "c"
        case .straighten: "r"
        }
    }

    public static func forKey(_ key: Character) -> Tool? {
        allCases.first { $0.key == Character(key.lowercased()) }
    }

    /// Only these work at this stage.
    public var isImplemented: Bool { true }
}

/// The selected tool, and the hand that Space gives while it is held.
public struct ToolState: Sendable, Hashable {
    public var selected: Tool = .hand
    public var spaceHeld = false

    public init() {}

    /// The tool that handles the mouse right now.
    public var effective: Tool { spaceHeld ? .hand : selected }

    /// The crop options are shown at the top of the panel.
    public var showsCropOptions: Bool { selected == .crop || selected == .straighten }
}
