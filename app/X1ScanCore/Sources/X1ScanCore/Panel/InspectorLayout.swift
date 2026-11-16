// SPDX-License-Identifier: MIT
import Foundation
import Observation

/// A section of the settings panel, folded or not.
public enum PanelSection: String, Sendable, Hashable, CaseIterable, Codable {
    case original
    case settings
    case histogram
    case output
}

/// The Main / Advanced tabs of the settings panel.
public enum PanelTab: String, Sendable, Hashable, CaseIterable, Codable {
    case main
    case advanced
}

/// The settings panel on the right (step 3): width, hidden or shown,
/// folded sections, tab. Replaces the palettes (PaletteLayout) of step 2.
public struct InspectorLayout: Sendable, Hashable, Codable {
    /// Bounds of the user-resizable panel (compact settings panel conventions):
    /// at the minimum a slider row keeps a usable slider next to a 5-digit
    /// field; beyond the maximum rows would only spread out.
    public static let minimumWidth: Double = 280
    public static let maximumWidth: Double = 480
    /// Width at first launch; then the width the user left is remembered.
    public static let defaultWidth: Double = 300

    public private(set) var width: Double = InspectorLayout.defaultWidth
    public var isHidden = false
    /// All sections open at first launch; then remembered.
    public private(set) var folded: Set<PanelSection> = []
    public var tab: PanelTab = .main

    public init() {}

    public mutating func setWidth(_ value: Double) {
        width = min(max(value.isFinite ? value : Self.defaultWidth, Self.minimumWidth), Self.maximumWidth)
    }

    public func isFolded(_ section: PanelSection) -> Bool { folded.contains(section) }

    public mutating func toggleFolded(_ section: PanelSection) {
        if folded.contains(section) { folded.remove(section) } else { folded.insert(section) }
    }

    public mutating func setFolded(_ section: PanelSection, _ isFolded: Bool) {
        if isFolded { folded.insert(section) } else { folded.remove(section) }
    }

    private enum CodingKeys: String, CodingKey { case width, isHidden, folded, tab }

    /// Unknown sections and tabs (another version) are dropped, not fatal.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        setWidth(try container.decodeIfPresent(Double.self, forKey: .width) ?? Self.defaultWidth)
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        let names = try container.decodeIfPresent([String].self, forKey: .folded) ?? []
        folded = Set(names.compactMap(PanelSection.init(rawValue:)))
        tab = (try container.decodeIfPresent(String.self, forKey: .tab)).flatMap(PanelTab.init(rawValue:)) ?? .main
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(width, forKey: .width)
        try container.encode(isHidden, forKey: .isHidden)
        try container.encode(folded.map(\.rawValue).sorted(), forKey: .folded)
        try container.encode(tab.rawValue, forKey: .tab)
    }
}

/// The panel layout, saved in UserDefaults at every change. Removes the keys
/// of the step 2 palettes once.
@MainActor
@Observable
public final class PanelController {
    public var layout: InspectorLayout {
        didSet { if layout != oldValue { save() } }
    }

    private let defaults: UserDefaults
    static let key = "InspectorLayout"
    /// Saved by the palettes of steps 2 to 2c, no longer used.
    static let obsoleteKeys = ["PaletteLayout", "Workspaces"]

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        for key in Self.obsoleteKeys { defaults.removeObject(forKey: key) }
        layout = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(InspectorLayout.self, from: $0) } ?? InspectorLayout()
    }

    public func toggleHidden() { layout.isHidden.toggle() }
    public func toggleFolded(_ section: PanelSection) { layout.toggleFolded(section) }
    public func setFolded(_ section: PanelSection, _ isFolded: Bool) { layout.setFolded(section, isFolded) }
    public func setWidth(_ width: Double) { layout.setWidth(width) }

    private func save() {
        if let data = try? JSONEncoder().encode(layout) { defaults.set(data, forKey: Self.key) }
    }
}
