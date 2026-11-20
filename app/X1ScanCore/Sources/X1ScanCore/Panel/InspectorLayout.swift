// SPDX-License-Identifier: MIT
import Foundation
import Observation

/// A section of the settings panel, folded or not, in the panel's order.
public enum PanelSection: String, Sendable, Hashable, CaseIterable, Codable {
    case original
    /// Framing (lot 1b): orientation, proportions, angle, straightening, grid.
    case framing
    case scan
    case exposure
    case histogram
    case output

    /// Names saved by earlier versions: `settings` (Main / Advanced tabs,
    /// before lot 1) became `scan`.
    static func decoded(_ name: String) -> PanelSection? {
        name == "settings" ? .scan : PanelSection(rawValue: name)
    }
}

/// A tab of the settings panel (lot 1b), in the tab bar's order. Develop
/// (corrections, lot 3) has its place between Scan and Output but is not
/// shown yet: only `visible` tabs reach the tab bar, the menu and the
/// saved layout.
public enum PanelTab: String, Sendable, Hashable, CaseIterable, Codable {
    case prepare
    case scan
    case develop
    case output

    /// The tabs shown, in order (lot 1b: no Develop).
    public static let visible: [PanelTab] = [.prepare, .scan, .output]

    public var isVisible: Bool { Self.visible.contains(self) }

    /// The sections of the tab, top to bottom. Histogram and Exposure are
    /// in the Information area, common to every tab.
    public var sections: [PanelSection] {
        switch self {
        case .prepare: [.original, .framing]
        case .scan: [.scan]
        case .develop: []
        case .output: [.output]
        }
    }
}

/// The settings panel on the right (step 3): width, hidden or shown, the
/// tab shown (lot 1b), folded sections. Replaces the palettes
/// (PaletteLayout) of step 2. The Main / Advanced tab of step 3 is gone
/// (lot 1); its saved value ("main", "advanced") is read as Prepare.
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
    /// The tab shown; Prepare at first launch, then remembered. Always a visible tab.
    public private(set) var tab: PanelTab = .prepare
    /// At first launch every section is open except the histogram (lot 1);
    /// then remembered.
    public private(set) var folded: Set<PanelSection> = InspectorLayout.defaultFolded
    public static let defaultFolded: Set<PanelSection> = [.histogram]

    public init() {}

    public mutating func setWidth(_ value: Double) {
        width = min(max(value.isFinite ? value : Self.defaultWidth, Self.minimumWidth), Self.maximumWidth)
    }

    /// A hidden tab (Develop, lot 3) is not selected: the tab stays as it was.
    public mutating func select(_ tab: PanelTab) {
        if tab.isVisible { self.tab = tab }
    }

    public func isFolded(_ section: PanelSection) -> Bool { folded.contains(section) }

    public mutating func toggleFolded(_ section: PanelSection) {
        if folded.contains(section) { folded.remove(section) } else { folded.insert(section) }
    }

    public mutating func setFolded(_ section: PanelSection, _ isFolded: Bool) {
        if isFolded { folded.insert(section) } else { folded.remove(section) }
    }

    private enum CodingKeys: String, CodingKey { case width, isHidden, tab, folded }

    /// Unknown sections (another version) are dropped, not fatal; an
    /// unknown or hidden tab gives Prepare.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        setWidth(try container.decodeIfPresent(Double.self, forKey: .width) ?? Self.defaultWidth)
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        if let name = try container.decodeIfPresent(String.self, forKey: .tab), let saved = PanelTab(rawValue: name) {
            select(saved)
        }
        if let names = try container.decodeIfPresent([String].self, forKey: .folded) {
            folded = Set(names.compactMap(PanelSection.decoded))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(width, forKey: .width)
        try container.encode(isHidden, forKey: .isHidden)
        try container.encode(tab, forKey: .tab)
        try container.encode(folded.map(\.rawValue).sorted(), forKey: .folded)
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
    public func select(_ tab: PanelTab) { layout.select(tab) }

    /// The Crop tool or the rule chosen (lot 1b): the Prepare tab, with Framing unfolded.
    public func showFraming() {
        layout.select(.prepare)
        layout.setFolded(.framing, false)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(layout) { defaults.set(data, forKey: Self.key) }
    }
}
