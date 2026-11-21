// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import X1ScanCore

/// User's decision after lot 1b: every tooltip of a function with a
/// keyboard shortcut ends with it in parentheses, in Mac symbols, taken
/// from the same source as the shortcut (`AppShortcut`), in English and
/// French.
struct ShortcutTests {
    @Test func displayInMacSymbols() {
        #expect(KeyShortcut("c").display() == "C")
        #expect(KeyShortcut("2", [.option, .command]).display() == "⌥⌘2")
        #expect(KeyShortcut("e", [.command, .shift]).display() == "⇧⌘E", "modifiers in the menus' order")
        #expect(KeyShortcut(.leftRight, .shift).display() == "⇧← →", "symbols for the arrows")
        // The keys without a letter in full, in the application's language (user's decision).
        #expect(KeyShortcut(.returnKey).display() == "Return" && KeyShortcut(.escape).display() == "Esc")
        let french = KeyShortcut.KeyNames(returnKey: "Retour", escape: "Échap", space: "Espace")
        #expect(KeyShortcut(.space).display(names: french) == "Espace" && KeyShortcut(.escape).display(names: french) == "Échap")
        #expect(KeyShortcut("e", [.command, .shift]).keyEquivalent == "e" && KeyShortcut(.leftRight).keyEquivalent == nil)
    }

    @Test func toolsAndTabsComeFromTheirOwnSource() {
        for tool in Tool.allCases {
            let shortcut: KeyShortcut? = AppShortcut.tool(tool).shortcut
            #expect(shortcut == KeyShortcut(tool.key), "the tool key itself (Tool.key)")
        }
        let tabs: [String] = PanelTab.visible.compactMap { AppShortcut.panelTab($0).shortcut?.display() }
        #expect(tabs == ["⌥⌘1", "⌥⌘2", "⌥⌘3"], "in the tab bar's order")
        #expect(AppShortcut.panelTab(.develop).shortcut == nil, "no shortcut for a tab not shown")
    }

    /// Each shortcut is mentioned in at least one tooltip, and every
    /// tooltip ends with all of its shortcuts.
    @Test func everyShortcutIsMentionedInATooltip() {
        for shortcut in AppShortcut.all {
            let mentioned: Bool = ShortcutTooltip.allCases.contains { (tooltip: ShortcutTooltip) -> Bool in
                tooltip.shortcuts.contains(shortcut) || tooltip.inlineShortcut == shortcut
            }
            #expect(mentioned, "\(shortcut) has no tooltip")
        }
        for tooltip in ShortcutTooltip.allCases {
            let displays: [String] = tooltip.shortcuts.compactMap { $0.shortcut?.display() }
            #expect(!displays.isEmpty, "\(tooltip) has no shortcut")
            let text: String = tooltip.text("Sentence", names: .english)
            #expect(text == "Sentence (\(displays.joined(separator: ", ")))", "\(tooltip): \(text)")
            // A shortcut named inside the sentence takes the place of its "%@".
            if let inline = tooltip.inlineShortcut?.shortcut?.display() {
                #expect(tooltip.text("Hold %@", names: .english).hasPrefix("Hold \(inline) ("))
            }
        }
        #expect(ShortcutTooltip.stopPreview.text("Stop the preview", names: .english) == "Stop the preview (⌘., Esc)")
        let hand: String = ShortcutTooltip.handTool.text("Hand: move the image; hold %@ to use the Hand for a moment", names: .english)
        #expect(hand == "Hand: move the image; hold Space to use the Hand for a moment (H)")
        #expect(ShortcutTooltip.done.text("Done", names: .english) == "Done (Return, Esc)")
        let french = KeyShortcut.KeyNames(returnKey: "Retour", escape: "Échap", space: "Espace")
        #expect(ShortcutTooltip.done.text("Terminé", names: french) == "Terminé (Retour, Échap)")
        #expect(ShortcutTooltip.tool(.crop).text("Crop", names: .english) == "Crop (C)")
    }

    /// The key a tooltip shows is the key really handled (user's decision
    /// after lot 1b): each shortcut the window or the canvas handles is
    /// recognised by the same matcher (`AppShortcut.matching`) from its own
    /// `KeyShortcut`, letters and keys without a letter alike. Changing a
    /// shortcut changes both, or this test fails.
    @Test func theKeyShownIsTheKeyHandled() throws {
        let handled: [AppShortcut] = AppShortcut.windowKeys(cropping: true) + AppShortcut.canvasKeys(cropping: true)
        for shortcut in handled {
            let key = try #require(shortcut.shortcut, "\(shortcut) has no shortcut")
            let press: KeyPress
            switch key.key {
            case .character(let character):
                press = KeyPress(keyCode: 0, characters: String(character), modifiers: key.modifiers)
            case .returnKey, .escape, .leftRight, .space:
                let code = try #require(key.key.keyCodes.min(), "\(shortcut): a key without a letter needs its key codes")
                press = KeyPress(keyCode: code, characters: "", modifiers: key.modifiers)
            }
            let window: AppShortcut? = AppShortcut.matching(press, among: AppShortcut.windowKeys(cropping: true))
            let canvas: AppShortcut? = AppShortcut.matching(press, among: AppShortcut.canvasKeys(cropping: true))
            #expect(window == shortcut || canvas == shortcut, "\(key.display()) shown for \(shortcut) but not handled as it")
        }
        // Every shortcut shown is handled somewhere: by the window or the canvas, or by a menu item.
        let menuItems: [AppShortcut] = [.rotateCounterclockwise, .rotateClockwise, .toggleGrid, .preview, .scan, .stop, .export, .undo]
        let tabItems: [AppShortcut] = PanelTab.visible.map(AppShortcut.panelTab)
        let menus: Set<AppShortcut> = Set(menuItems + tabItems)
        for shortcut in AppShortcut.all {
            #expect(handled.contains(shortcut) || menus.contains(shortcut), "\(shortcut) is shown but handled nowhere")
            if menus.contains(shortcut) {
                #expect(shortcut.shortcut?.keyEquivalent != nil, "\(shortcut): a menu item needs a key equivalent")
            }
        }
        // Each the other way: a key's neighbours are not taken for it.
        let canvasKeys: [AppShortcut] = AppShortcut.canvasKeys(cropping: true)
        let arrow = KeyPress(keyCode: KeyShortcut.Key.rightArrowKeyCode, characters: "", modifiers: [])
        let shiftArrow = KeyPress(keyCode: KeyShortcut.Key.rightArrowKeyCode, characters: "", modifiers: .shift)
        #expect(AppShortcut.matching(arrow, among: canvasKeys) == .angle && AppShortcut.matching(shiftArrow, among: canvasKeys) == .angleLarge)
        // Shift does not change Esc, Space or Return, as before (⇧Esc still stops a preview).
        let shiftEscape = KeyPress(keyCode: 53, characters: "", modifiers: .shift)
        let shiftSpace = KeyPress(keyCode: 49, characters: " ", modifiers: .shift)
        let shiftReturn = KeyPress(keyCode: 36, characters: "\r", modifiers: .shift)
        #expect(AppShortcut.matching(shiftEscape, among: canvasKeys) == .escape)
        #expect(AppShortcut.matching(shiftSpace, among: canvasKeys) == .temporaryHand)
        #expect(AppShortcut.matching(shiftReturn, among: canvasKeys) == .done)
        let optionEscape = KeyPress(keyCode: 53, characters: "", modifiers: .option)
        #expect(AppShortcut.matching(optionEscape, among: canvasKeys) == nil, "⌥, ⌃ and ⌘ still count")
        let commandC = KeyPress(keyCode: 8, characters: "c", modifiers: .command)
        #expect(AppShortcut.matching(commandC, among: AppShortcut.windowKeys(cropping: true)) == nil, "⌘C stays Copy")
        let shiftC = KeyPress(keyCode: 8, characters: "C", modifiers: .shift)
        #expect(AppShortcut.matching(shiftC, among: AppShortcut.windowKeys(cropping: false)) == .tool(.crop), "⇧C is C, as before")
        let x = KeyPress(keyCode: 7, characters: "x", modifiers: [])
        #expect(AppShortcut.matching(x, among: AppShortcut.windowKeys(cropping: false)) == nil, "X only in crop mode")
    }

    /// Every tooltip's sentence is in the application's String Catalog,
    /// translated into French, and neither language copies a shortcut by
    /// hand (the parentheses are added from the source).
    @Test func sentencesAreTranslatedWithoutHandCopiedShortcuts() throws {
        let strings = try Self.catalog()
        // Any shortcut with a symbol (⌘, ⌥, ⇧, the arrows) copied by hand, anywhere in the
        // sentence; a lone letter (C, R…) or a key's name (Esc, Space…) may be a word of it.
        let symbols: Set<Character> = ["⌃", "⌥", "⇧", "⌘", "←", "→"]
        let displays: [String] = AppShortcut.all.compactMap { $0.shortcut?.display() }
            .filter { display in display.contains { symbols.contains($0) } }
        for tooltip in ShortcutTooltip.allCases {
            let entry = try #require(strings[tooltip.key] as? [String: Any], "\(tooltip.key) is not in the catalog")
            let comment: String = entry["comment"] as? String ?? ""
            #expect(!comment.isEmpty, "\(tooltip.key): no comment for the translators")
            let localizations = try #require(entry["localizations"] as? [String: Any])
            for language in ["en", "fr"] {
                let unit = try #require((localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any],
                                        "\(tooltip.key): no \(language)")
                let state: String? = unit["state"] as? String
                let value: String = try #require(unit["value"] as? String)
                #expect(state == "translated", "\(tooltip.key) (\(language))")
                // The place of a key named inside the sentence: exactly once, and only there.
                let places: Int = value.components(separatedBy: "%@").count - 1
                let expected: Int = tooltip.inlineShortcut == nil ? 0 : 1
                #expect(places == expected, "\(tooltip.key) (\(language)): \(places) %@, \(expected) expected")
                for display in displays {
                    #expect(!value.contains(display), "\(language) copies \(display) by hand: \(value)")
                }
                // A key's name may be a word of the sentence, but not in parentheses.
                for name in Self.keyNames {
                    #expect(!value.contains("(\(name)") && !value.contains("\(name))"), "\(language) copies \(name) by hand: \(value)")
                }
            }
        }
    }

    /// The keys' names in English and French (the catalog's key.return, key.escape, key.space).
    private static let keyNames: [String] = ["Return", "Esc", "Space", "Retour", "Échap", "Espace"]

    /// The application's catalog: app/X1Scan/Localization/Localizable.xcstrings.
    private static func catalog() throws -> [String: Any] {
        let app: URL = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url: URL = app.appending(path: "X1Scan/Localization/Localizable.xcstrings")
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try #require(root?["strings"] as? [String: Any])
    }
}
