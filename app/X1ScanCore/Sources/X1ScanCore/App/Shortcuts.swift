// SPDX-License-Identifier: MIT
import Foundation

/// A keyboard shortcut as macOS shows it: ⌃⌥⇧⌘, then the key (user's
/// decision after lot 1b: every tooltip of a function with a shortcut ends
/// with it, from the same source as the shortcut itself).
public struct KeyShortcut: Sendable, Hashable {
    public struct Modifiers: OptionSet, Sendable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
        public static let shift = Modifiers(rawValue: 4)
        public static let command = Modifiers(rawValue: 8)
    }

    /// A key typed as a character ("c", "2", "["), or a named key.
    public enum Key: Sendable, Hashable {
        case character(Character)
        case returnKey
        case escape
        /// The left and right arrows together (the fine angle).
        case leftRight
        /// The space bar (held: the hand, for a moment).
        case space

        /// Key code of the right arrow (of `leftRight`, the one that turns clockwise).
        public static let rightArrowKeyCode: UInt16 = 124

        /// Hardware key codes of a named key (both Return keys).
        public var keyCodes: Set<UInt16> {
            switch self {
            case .character: []
            case .returnKey: [36, 76]
            case .escape: [53]
            case .leftRight: [123, 124]
            case .space: [49]
            }
        }
    }

    /// The names of the keys without a letter, written in full (user's
    /// decision after lot 1b): translated by the application; English here.
    public struct KeyNames: Sendable, Hashable {
        public var returnKey: String
        public var escape: String
        public var space: String

        public init(returnKey: String, escape: String, space: String) {
            self.returnKey = returnKey
            self.escape = escape
            self.space = space
        }

        public static let english = KeyNames(returnKey: "Return", escape: "Esc", space: "Space")
    }

    public let key: Key
    public let modifiers: Modifiers

    public init(_ key: Key, _ modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Typed character with optional modifiers: `KeyShortcut("r", .command)`.
    public init(_ character: Character, _ modifiers: Modifiers = []) {
        self.init(.character(character), modifiers)
    }

    /// Symbols for the modifiers and the arrows, as in the menus, the keys
    /// without a letter in full: "⌥⌘2", "⇧⌘E", "C", "← →", "Return", "Esc", "Space".
    public func display(names: KeyNames = .english) -> String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        switch key {
        case .character(let character): text += String(character).uppercased()
        case .returnKey: text += names.returnKey
        case .escape: text += names.escape
        case .leftRight: text += "← →"
        case .space: text += names.space
        }
        return text
    }

    /// The menu item's key equivalent (lower case), nil for the arrows.
    public var keyEquivalent: String? {
        switch key {
        case .character(let character): String(character).lowercased()
        case .returnKey: "\r"
        case .escape: "\u{1b}"
        case .leftRight: nil
        case .space: " "
        }
    }
}

/// The shortcuts of the functions that have a tooltip: the one source for
/// the menus, the window's and the canvas's key handling, and the tooltips
/// (`ShortcutTooltip`). Shortcuts of menu items without a tooltip (zoom,
/// Hide Settings Panel…) stay in the menu.
public enum AppShortcut: Sendable, Hashable {
    case tool(Tool)
    /// The hand while the space bar is held.
    case temporaryHand
    case swapProportions
    case done
    case escape
    case angle
    case angleLarge
    case panelTab(PanelTab)
    case rotateCounterclockwise
    case rotateClockwise
    case toggleGrid
    case preview
    case stop
    case export
    case undo

    /// Nil only for a panel tab not shown (Develop, lot 3).
    public var shortcut: KeyShortcut? {
        switch self {
        case .tool(let tool): KeyShortcut(tool.key)
        case .temporaryHand: KeyShortcut(.space)
        case .swapProportions: KeyShortcut("x")
        case .done: KeyShortcut(.returnKey)
        case .escape: KeyShortcut(.escape)
        case .angle: KeyShortcut(.leftRight)
        case .angleLarge: KeyShortcut(.leftRight, .shift)
        // ⌥⌘1, ⌥⌘2… in the tab bar's order (⌘0 and ⌘1 stay with the zoom).
        case .panelTab(let tab): PanelTab.visible.firstIndex(of: tab).map {
            KeyShortcut(Character(String($0 + 1)), [.option, .command])
        }
        case .rotateCounterclockwise: KeyShortcut("[", .command)
        case .rotateClockwise: KeyShortcut("]", .command)
        case .toggleGrid: KeyShortcut("'", .command)
        case .preview: KeyShortcut("r", .command)
        case .stop: KeyShortcut(".", .command)
        case .export: KeyShortcut("e", [.shift, .command])
        case .undo: KeyShortcut("z", .command)
        }
    }

    /// Every shortcut, the visible tabs only.
    public static var all: [AppShortcut] {
        Tool.allCases.map(AppShortcut.tool)
            + [.temporaryHand, .swapProportions, .done, .escape, .angle, .angleLarge]
            + PanelTab.visible.map(AppShortcut.panelTab)
            + [.rotateCounterclockwise, .rotateClockwise, .toggleGrid, .preview, .stop, .export, .undo]
    }
}

/// A tooltip of a function with a shortcut: its sentence (the String
/// Catalog's key, in English, without the shortcut) and its shortcuts,
/// added at the end in parentheses by `text(_:)`. The application
/// translates `key`; the parentheses are the same in every language.
public enum ShortcutTooltip: String, Sendable, CaseIterable {
    case handTool, zoomTool, cropTool, ruleTool
    case ruleButton, straightenRow, swapProportions, done, angle
    case prepareTab, scanTab, outputTab
    case rotateCounterclockwise, rotateClockwise, gridButton
    case previewVirtual, previewReal, stopPreview, stopScan, export, reset

    public var key: String {
        switch self {
        case .handTool: "Hand: move the image, or for a moment while the second key is held"
        case .zoomTool: "Zoom: click to zoom in, ⌥-click to zoom out"
        case .cropTool: "Crop: draw and adjust the frame, in Prepare › Framing"
        case .ruleTool: "Straightening Rule: draw a line along what should be horizontal or vertical"
        case .ruleButton: "Draw a line along what should be horizontal or vertical"
        case .straightenRow: "Straighten the image with the rule, or from the frame's edges in a later version"
        case .swapProportions: "Swap Width and Height"
        case .done: "Keep the changes and go back to the previous tool, or cancel them"
        case .angle: "Fine rotation of the image in degrees; in crop mode the arrows go to the next whole degree, to the next multiple of 5° with Shift"
        case .prepareTab: "Film, holder, orientation and framing"
        case .scanTab: "Resolution, scale and sizes of the scan"
        case .outputTab: "Format, name and folder of the exported file"
        case .rotateCounterclockwise: "Rotate 90° Counterclockwise"
        case .rotateClockwise: "Rotate 90° Clockwise"
        case .gridButton: "Click: show or hide · Right click: kind, colour, opacity"
        case .previewVirtual: "Run a preview on the virtual X1"
        case .previewReal: "Run FlexColor's captured preview on the real X1"
        case .stopPreview: "Stop the preview"
        case .stopScan: "Stop the scan"
        case .export: "Export the image shown, turned, straightened and cropped, with its recipe. A saved scan is never replaced: its versions are named _v1, _v2…"
        case .reset: "Reset the orientation, proportions, angle and frame to the original; Edit › Undo cancels it"
        }
    }

    public var shortcuts: [AppShortcut] {
        switch self {
        case .handTool: [.tool(.hand), .temporaryHand]
        case .zoomTool: [.tool(.zoom)]
        case .cropTool: [.tool(.crop)]
        case .ruleTool, .ruleButton, .straightenRow: [.tool(.straighten)]
        case .swapProportions: [.swapProportions]
        case .done: [.done, .escape]
        case .angle: [.angle, .angleLarge]
        case .prepareTab: [.panelTab(.prepare)]
        case .scanTab: [.panelTab(.scan)]
        case .outputTab: [.panelTab(.output)]
        case .rotateCounterclockwise: [.rotateCounterclockwise]
        case .rotateClockwise: [.rotateClockwise]
        case .gridButton: [.toggleGrid]
        case .previewVirtual, .previewReal: [.preview]
        case .stopPreview, .stopScan: [.stop, .escape]
        case .export: [.export]
        case .reset: [.undo]
        }
    }

    /// The tooltip of a tool of the column.
    public static func tool(_ tool: Tool) -> ShortcutTooltip {
        switch tool {
        case .hand: .handTool
        case .zoom: .zoomTool
        case .crop: .cropTool
        case .straighten: .ruleTool
        }
    }

    /// The tooltip of a panel tab.
    public static func tab(_ tab: PanelTab) -> ShortcutTooltip? {
        switch tab {
        case .prepare: .prepareTab
        case .scan: .scanTab
        case .develop: nil
        case .output: .outputTab
        }
    }

    /// The translated sentence, then its shortcuts, with the keys' names
    /// translated too: "Crop: … (C)", "Stop the preview (⌘., Esc)".
    public func text(_ translated: String, names: KeyShortcut.KeyNames) -> String {
        let keys = shortcuts.compactMap { $0.shortcut?.display(names: names) }
        return keys.isEmpty ? translated : "\(translated) (\(keys.joined(separator: ", ")))"
    }
}
