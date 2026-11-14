// SPDX-License-Identifier: MIT
import Foundation

/// A window frame, stored for floating palettes (later stage).
public struct StoredFrame: Sendable, Hashable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Where a palette lives.
public enum PalettePlacement: Sendable, Hashable, Codable {
    /// In the column on the right. The only placement implemented at this stage.
    case docked
    /// In its own floating window. Modelled and saved, not implemented yet.
    case floating(StoredFrame)
}

/// How the right column is shown.
public enum ColumnMode: String, Sendable, Hashable, Codable {
    /// Palettes with their content.
    case expanded
    /// A narrow bar of icons; a click shows a palette over the image.
    case iconBar
}

/// Where the tool bar (hand, zoom, crop) lives.
public enum ToolBarPlacement: String, Sendable, Hashable, Codable {
    /// A glass capsule floating over the left of the image. Implemented.
    case floating
    /// A fixed column on the left. Modelled, not implemented yet.
    case dockedColumn
}

/// The arrangement of palettes and tool bar, saved between launches and
/// stored in workspaces. Every change goes through a mutating method, so
/// that the layout stays consistent (each palette of the registry exactly
/// once in `order`).
public struct PaletteLayout: Sendable, Hashable, Codable {
    /// 2: `hidden` added (step 2b). Version 1 layouts decode with nothing hidden.
    public static let currentVersion = 2
    public static let minimumColumnWidth: Double = 220
    public static let maximumColumnWidth: Double = 480
    public static let defaultColumnWidth: Double = 270

    public var version = PaletteLayout.currentVersion
    public private(set) var order: [PaletteID]
    public private(set) var collapsed: Set<PaletteID>
    /// Palettes hidden from the Window menu; they keep their place in `order`.
    public private(set) var hidden: Set<PaletteID> = []
    public var columnMode: ColumnMode = .expanded
    public private(set) var columnWidth: Double = PaletteLayout.defaultColumnWidth
    /// Placement of each palette; a missing entry means `.docked`.
    public private(set) var placements: [PaletteID: PalettePlacement] = [:]
    public var toolBarPlacement: ToolBarPlacement = .floating

    private enum CodingKeys: String, CodingKey {
        case version, order, collapsed, hidden, columnMode, columnWidth, placements, toolBarPlacement
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        order = try container.decode([PaletteID].self, forKey: .order)
        collapsed = try container.decode(Set<PaletteID>.self, forKey: .collapsed)
        hidden = try container.decodeIfPresent(Set<PaletteID>.self, forKey: .hidden) ?? []
        columnMode = try container.decode(ColumnMode.self, forKey: .columnMode)
        columnWidth = try container.decode(Double.self, forKey: .columnWidth)
        placements = try container.decode([PaletteID: PalettePlacement].self, forKey: .placements)
        toolBarPlacement = try container.decode(ToolBarPlacement.self, forKey: .toolBarPlacement)
    }

    public init(registry: PaletteRegistry = .standard) {
        order = registry.ids
        collapsed = Set(registry.descriptors.filter(\.collapsedByDefault).map(\.id))
    }

    // MARK: Queries

    public func isCollapsed(_ id: PaletteID) -> Bool { collapsed.contains(id) }

    public func placement(of id: PaletteID) -> PalettePlacement { placements[id] ?? .docked }

    public func isHidden(_ id: PaletteID) -> Bool { hidden.contains(id) }

    /// Palettes placed in the column, in order, hidden ones included.
    public var dockedPalettes: [PaletteID] { order.filter { placement(of: $0) == .docked } }

    /// Palettes shown in the column, in order.
    public var visibleDockedPalettes: [PaletteID] { dockedPalettes.filter { !isHidden($0) } }

    /// True when every palette is hidden: the column is collapsed.
    public var allHidden: Bool { order.allSatisfy(isHidden) }

    // MARK: Changes

    public mutating func toggleCollapsed(_ id: PaletteID) {
        setCollapsed(id, !isCollapsed(id))
    }

    public mutating func setCollapsed(_ id: PaletteID, _ value: Bool) {
        guard order.contains(id) else { return }
        if value { collapsed.insert(id) } else { collapsed.remove(id) }
    }

    public mutating func setHidden(_ id: PaletteID, _ value: Bool) {
        guard order.contains(id) else { return }
        if value { hidden.insert(id) } else { hidden.remove(id) }
    }

    public mutating func toggleHidden(_ id: PaletteID) {
        setHidden(id, !isHidden(id))
    }

    /// Show/Hide All Palettes: hides them all if any is shown, else shows them all.
    public mutating func toggleAllHidden() {
        hidden = allHidden ? [] : Set(order)
    }

    /// Moves `id` to `index` in the order (clamped).
    public mutating func move(_ id: PaletteID, to index: Int) {
        guard let from = order.firstIndex(of: id) else { return }
        order.remove(at: from)
        order.insert(id, at: min(max(index, 0), order.count))
    }

    public mutating func setColumnWidth(_ width: Double) {
        columnWidth = min(max(width, Self.minimumColumnWidth), Self.maximumColumnWidth)
    }

    public mutating func toggleColumnMode() {
        columnMode = columnMode == .expanded ? .iconBar : .expanded
    }

    /// Floating palettes are a later stage; this only records the placement.
    public mutating func setPlacement(_ placement: PalettePlacement, for id: PaletteID) {
        guard order.contains(id) else { return }
        placements[id] = placement == .docked ? nil : placement
    }

    /// The same layout, made consistent with `registry`: unknown palettes
    /// dropped, new ones appended in registry order with their default state.
    public func reconciled(with registry: PaletteRegistry) -> PaletteLayout {
        var result = self
        result.version = Self.currentVersion
        var seen = Set<PaletteID>()
        result.order = order.filter { registry.contains($0) && seen.insert($0).inserted }
        for descriptor in registry.descriptors where !seen.contains(descriptor.id) {
            result.order.append(descriptor.id)
            if descriptor.collapsedByDefault { result.collapsed.insert(descriptor.id) }
        }
        result.collapsed = result.collapsed.filter(registry.contains)
        result.hidden = result.hidden.filter(registry.contains)
        result.placements = result.placements.filter { registry.contains($0.key) }
        result.columnWidth = min(max(columnWidth, Self.minimumColumnWidth), Self.maximumColumnWidth)
        return result
    }
}
