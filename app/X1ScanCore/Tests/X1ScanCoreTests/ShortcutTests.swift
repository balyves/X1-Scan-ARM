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
        #expect(KeyShortcut("c").display == "C")
        #expect(KeyShortcut("2", [.option, .command]).display == "⌥⌘2")
        #expect(KeyShortcut("e", [.command, .shift]).display == "⇧⌘E", "modifiers in the menus' order")
        #expect(KeyShortcut(.returnKey).display == "↩" && KeyShortcut(.escape).display == "⎋")
        #expect(KeyShortcut(.leftRight, .shift).display == "⇧← →")
        #expect(KeyShortcut("e", [.command, .shift]).keyEquivalent == "e" && KeyShortcut(.leftRight).keyEquivalent == nil)
    }

    @Test func toolsAndTabsComeFromTheirOwnSource() {
        for tool in Tool.allCases {
            let shortcut: KeyShortcut? = AppShortcut.tool(tool).shortcut
            #expect(shortcut == KeyShortcut(tool.key), "the tool key itself (Tool.key)")
        }
        let tabs: [String] = PanelTab.visible.compactMap { AppShortcut.panelTab($0).shortcut?.display }
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
            let displays: [String] = tooltip.shortcuts.compactMap { $0.shortcut?.display }
            #expect(!displays.isEmpty, "\(tooltip) has no shortcut")
            let text: String = tooltip.text("Sentence")
            #expect(text == "Sentence (\(displays.joined(separator: ", ")))", "\(tooltip): \(text)")
        }
        #expect(ShortcutTooltip.stopPreview.text("Stop the preview") == "Stop the preview (⌘., ⎋)")
        #expect(ShortcutTooltip.handTool.text("Hand") == "Hand (H, ␣)" && ShortcutTooltip.done.text("Done") == "Done (↩, ⎋)")
        #expect(ShortcutTooltip.tool(.crop).text("Crop") == "Crop (C)")
    }

    /// Every tooltip's sentence is in the application's String Catalog,
    /// translated into French, and neither language copies a shortcut by
    /// hand (the parentheses are added from the source).
    @Test func sentencesAreTranslatedWithoutHandCopiedShortcuts() throws {
        let strings = try Self.catalog()
        // Any shortcut copied by hand, anywhere in the sentence, except a lone letter
        // (C, R…), which a sentence may contain as a word.
        let displays: [String] = AppShortcut.all.compactMap { $0.shortcut?.display }
            .filter { display in !(display.count == 1 && display.first?.isLetter == true) }
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
            }
        }
    }

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
