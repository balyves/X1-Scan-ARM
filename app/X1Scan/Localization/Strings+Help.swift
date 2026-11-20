// SPDX-License-Identifier: MIT
import Foundation
import X1ScanCore

/// Texts of the built-in help that come from the application, not from
/// docs/help: the Keyboard Shortcuts table (`HelpShortcuts`), made from the
/// shortcuts' own source.
extension Strings {
    /// The table that replaces `<!-- shortcuts -->` in shortcuts.md, in the application's language.
    static var helpShortcutsTable: String {
        HelpShortcuts.markdown(groupTitle: helpGroup, label: shortcutLabel, names: keyNames)
    }

    static func helpGroup(_ group: AppShortcut.HelpGroup) -> String {
        switch group {
        case .tools: String(localized: "help.group.tools", defaultValue: "Tools", comment: "Help, Keyboard Shortcuts page: heading of the tools' shortcuts")
        case .framing: String(localized: "help.group.framing", defaultValue: "Framing", comment: "Help, Keyboard Shortcuts page: heading of the crop mode's shortcuts")
        case .image: String(localized: "help.group.image", defaultValue: "Image", comment: "Help, Keyboard Shortcuts page: heading of orientation and grid shortcuts (the Image menu)")
        case .view: String(localized: "help.group.view", defaultValue: "Zoom", comment: "Help, Keyboard Shortcuts page: heading of the zoom shortcuts")
        case .panel: String(localized: "help.group.panel", defaultValue: "Settings Panel", comment: "Help, Keyboard Shortcuts page: heading of the panel's shortcuts")
        case .scanner: String(localized: "help.group.scanner", defaultValue: "Scanner", comment: "Help, Keyboard Shortcuts page: heading of Preview and Stop")
        case .application: String(localized: "help.group.application", defaultValue: "Application", comment: "Help, Keyboard Shortcuts page: heading of Export, Settings, Help…")
        }
    }

    /// What a shortcut does, as the menus and the panel name it.
    static func shortcutLabel(_ shortcut: AppShortcut) -> String {
        switch shortcut {
        case .tool(let tool): toolName(tool)
        case .temporaryHand: String(localized: "help.shortcut.temporaryHand", defaultValue: "Hand, while the key is held", comment: "Help, Keyboard Shortcuts page: the space bar")
        case .swapProportions: cropSwap
        case .done: String(localized: "help.shortcut.done", defaultValue: "Done: leave crop mode and keep the changes", comment: "Help, Keyboard Shortcuts page: Return in crop mode")
        case .escape: String(localized: "help.shortcut.escape", defaultValue: "Stop a preview or a scan; in crop mode, cancel the changes", comment: "Help, Keyboard Shortcuts page: Esc")
        case .angle: String(localized: "help.shortcut.angle", defaultValue: "Fine rotation, to the next whole degree (Crop or Rule)", comment: "Help, Keyboard Shortcuts page: left and right arrows")
        case .angleLarge: String(localized: "help.shortcut.angleLarge", defaultValue: "Fine rotation, to the next multiple of 5° (Crop or Rule)", comment: "Help, Keyboard Shortcuts page: Shift with the arrows")
        case .panelTab(let tab): panelTabMenuItem(tab)
        case .rotateCounterclockwise: rotateCounterclockwise
        case .rotateClockwise: rotateClockwise
        case .toggleGrid: String(localized: "help.shortcut.grid", defaultValue: "Show or hide the grid", comment: "Help, Keyboard Shortcuts page")
        case .preview: String(localized: "Preview", comment: "Menu item and toolbar button")
        case .stop: String(localized: "Stop", comment: "Menu item and toolbar button")
        case .export: String(localized: "Export…", comment: "Menu item")
        case .undo: String(localized: "Undo", comment: "Menu item")
        case .redo: String(localized: "Redo", comment: "Menu item")
        case .zoomToFit: zoomMode(.fit)
        case .zoomToFill: zoomMode(.fill)
        case .actualSize: String(localized: "Actual Size", comment: "Menu item")
        case .zoomIn: String(localized: "Zoom In", comment: "Menu item")
        case .zoomOut: String(localized: "Zoom Out", comment: "Menu item")
        case .toggleSettingsPanel: String(localized: "help.shortcut.panel", defaultValue: "Show or hide the settings panel", comment: "Help, Keyboard Shortcuts page")
        case .scannerInformation: String(localized: "Scanner Information…", comment: "Menu item")
        case .settings: String(localized: "Settings…", comment: "Menu item")
        case .help: String(localized: "X1 Scan Help", comment: "Menu item: opens the built-in help (Help menu); also its line on the help's Keyboard Shortcuts page")
        }
    }
}
