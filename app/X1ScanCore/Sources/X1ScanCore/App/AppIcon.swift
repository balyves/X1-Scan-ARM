// SPDX-License-Identifier: MIT
import Foundation

/// The icons of the tools and of the panel's icon buttons, in one table used
/// both by the interface and by the built-in help (`{icon:<key>}` in a help
/// page shows the same icon next to its name). The help renders them when a
/// page is shown: no image of a system symbol is stored in the repository
/// (docs/decisions.md, "Built-in help").
public enum AppIcon: String, CaseIterable, Sendable {
    // Tool column.
    case hand
    case zoom
    case crop
    case rule
    case grid
    case exposureZones = "exposure-zones"
    // Settings panel.
    case rotateLeft = "rotate-left"
    case rotateRight = "rotate-right"
    case mirror
    case swapProportions = "swap-proportions"
    case lockOpen = "lock-open"
    case lockClosed = "lock-closed"
    case reset
    case more

    /// Where the picture comes from.
    public enum Source: Sendable, Hashable {
        /// A system symbol (SF Symbols), by name.
        case symbol(String)
        /// Drawn by the application itself (`SwapDimensionsIcon`).
        case drawn
    }

    public var source: Source {
        switch self {
        case .hand: .symbol("hand.raised")
        case .zoom: .symbol("plus.magnifyingglass")
        case .crop: .symbol("crop")
        case .rule: .symbol("ruler")
        case .grid: .symbol("grid")
        // Half hatched, echoing the hatched noise zone of the exposure gauge: a display, not a warning.
        case .exposureZones: .symbol("circle.lefthalf.striped.horizontal")
        case .rotateLeft: .symbol("rotate.left")
        case .rotateRight: .symbol("rotate.right")
        case .mirror: .symbol("arrow.left.and.right.righttriangle.left.righttriangle.right")
        case .swapProportions: .drawn
        case .lockOpen: .symbol("lock.open")
        case .lockClosed: .symbol("lock.fill")
        case .reset: .symbol("arrow.counterclockwise")
        case .more: .symbol("ellipsis.circle")
        }
    }

    /// The system symbol's name; nil for an icon the application draws.
    public var symbolName: String? {
        if case .symbol(let name) = source { name } else { nil }
    }

    /// The icon of a tool of the column.
    public static func tool(_ tool: Tool) -> AppIcon {
        switch tool {
        case .hand: .hand
        case .zoom: .zoom
        case .crop: .crop
        case .straighten: .rule
        }
    }
}
