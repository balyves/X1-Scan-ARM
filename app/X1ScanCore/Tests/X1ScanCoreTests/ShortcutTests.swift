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
            let mentioned: Bool = ShortcutTooltip.allCases.contains { $0.shortcuts.contains(shortcut) }
            #expect(mentioned, "\(shortcut) has no tooltip")
        }
        for tooltip in ShortcutTooltip.allCases {
            let displays: [String] = tooltip.shortcuts.compactMap { $0.shortcut?.display() }
            #expect(!displays.isEmpty, "\(tooltip) has no shortcut")
            let text: String = tooltip.text("Sentence", names: .english)
            #expect(text == "Sentence (\(displays.joined(separator: ", ")))", "\(tooltip): \(text)")
        }
        #expect(ShortcutTooltip.stopPreview.text("Stop the preview", names: .english) == "Stop the preview (⌘., Esc)")
        #expect(ShortcutTooltip.handTool.text("Hand", names: .english) == "Hand (H, Space)" && ShortcutTooltip.done.text("Done", names: .english) == "Done (Return, Esc)")
        let french = KeyShortcut.KeyNames(returnKey: "Retour", escape: "Échap", space: "Espace")
        #expect(ShortcutTooltip.done.text("Terminé", names: french) == "Terminé (Retour, Échap)")
        #expect(ShortcutTooltip.tool(.crop).text("Crop", names: .english) == "Crop (C)")
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
