// SPDX-License-Identifier: MIT
import AppKit
import X1ScanCore

extension KeyPress {
    /// A key event as X1ScanCore compares it with the shortcuts (`AppShortcut.matches`).
    init(_ event: NSEvent) {
        var modifiers: KeyShortcut.Modifiers = []
        let flags = event.modifierFlags
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        self.init(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "", modifiers: modifiers)
    }
}
