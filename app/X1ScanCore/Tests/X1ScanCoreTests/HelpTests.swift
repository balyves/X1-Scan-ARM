// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import X1ScanCore

/// Lot A, built-in help: docs/help/fr and docs/help/en, the only source of
/// the help text (docs/decisions.md, "Built-in help").
struct HelpTests {
    /// docs/help, from this file: app/X1ScanCore/Tests/X1ScanCoreTests/HelpTests.swift.
    static let helpDirectory: URL = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "docs/help")

    static func library(_ language: String, shortcuts: String = "SHORTCUTS") throws -> HelpLibrary {
        try HelpLibrary(directory: helpDirectory, language: language, shortcuts: shortcuts)
    }

    // MARK: Pages

    /// Every page in both languages, and no page that the help does not list.
    @Test func everyPageExistsInBothLanguages() throws {
        for language in HelpLibrary.languages {
            let folder: URL = Self.helpDirectory.appending(path: language)
            let files: [String] = try FileManager.default.contentsOfDirectory(atPath: folder.path)
                .filter { $0.hasSuffix(".md") }
            let ids: Set<String> = Set(files.map { String($0.dropLast(3)) })
            #expect(ids == Set(HelpLibrary.pageIDs), "\(language): \(ids.symmetricDifference(HelpLibrary.pageIDs).sorted())")
            let library = try Self.library(language)
            for page in library.pages {
                #expect(!page.title.isEmpty && page.title != page.id, "\(language)/\(page.id): no title")
            }
        }
    }

    /// Each page has the same sections (anchors) in both languages, so that
    /// a link or a Help button leads to the same place in either.
    @Test func bothLanguagesHaveTheSameAnchors() throws {
        let english = try Self.library("en"), french = try Self.library("fr")
        for id in HelpLibrary.pageIDs {
            let en: [String] = HelpMarkdown.anchors(try #require(english.page(id)).markdown)
            let fr: [String] = HelpMarkdown.anchors(try #require(french.page(id)).markdown)
            #expect(en == fr, "\(id): en \(en), fr \(fr)")
            #expect(Set(en).count == en.count, "\(id): an anchor is used twice")
        }
    }

    /// Every link of every page leads to a page that exists, and to an anchor
    /// of it; or it is a web address in https, opened in the browser.
    @Test func everyInternalLinkLeadsToAPage() throws {
        for language in HelpLibrary.languages {
            let library = try Self.library(language)
            for page in library.pages {
                for link in HelpMarkdown.links(page.markdown) {
                    if link.target.contains(":") {
                        #expect(link.target.hasPrefix("https://"), "\(language)/\(page.id): \(link.target)")
                        continue
                    }
                    let place = HelpLibrary.resolve(link.target, from: page.id)
                    let target = try #require(place, "\(language)/\(page.id): link \(link.target) is not a help page")
                    let destination = try #require(library.page(target.page),
                                                   "\(language)/\(page.id): \(link.target) leads nowhere")
                    if let anchor = target.anchor {
                        #expect(HelpMarkdown.anchors(destination.markdown).contains(anchor),
                                "\(language)/\(page.id): no anchor \(anchor) in \(target.page)")
                    }
                }
            }
        }
    }

    /// The home page's index is in alphabetical order in its language, and
    /// reaches every page except itself.
    @Test func indexIsAlphabeticalAndComplete() throws {
        for language in HelpLibrary.languages {
            let library = try Self.library(language)
            let home = try #require(library.page("index"))
            let blocks = HelpMarkdown.blocks(home.markdown)
            let start = try #require(blocks.firstIndex { block in
                if case .heading(_, _, "functions") = block { true } else { false }
            })
            guard case .list(_, let items) = blocks[start + 1] else {
                Issue.record("\(language): the index is not a list")
                continue
            }
            let names: [String] = items.map(HelpMarkdown.plainText)
            let locale = Locale(identifier: language)
            let sorted: [String] = names.sorted {
                $0.compare($1, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) == .orderedAscending
            }
            #expect(names == sorted, "\(language): index out of order")
            let reached: Set<String> = Set(HelpMarkdown.links(home.markdown).compactMap {
                HelpLibrary.resolve($0.target, from: "index")?.page
            })
            #expect(reached.union(["index"]) == Set(HelpLibrary.pageIDs), "\(language): pages not linked from the home page")
        }
    }

    // MARK: Keyboard Shortcuts

    /// The Keyboard Shortcuts page is made from the table: every shortcut of
    /// `AppShortcut.helpTable` is on it, and nothing is written by hand.
    @Test func shortcutsPageHasEveryShortcutOfTheTable() throws {
        let names = KeyShortcut.KeyNames(returnKey: "Retour", escape: "Échap", space: "Espace")
        let table: String = HelpShortcuts.markdown(groupTitle: { "Group \($0)" }, label: { "Label \($0)" }, names: names)
        for language in HelpLibrary.languages {
            let raw: String = try String(contentsOf: Self.helpDirectory.appending(path: "\(language)/shortcuts.md"), encoding: .utf8)
            #expect(raw.contains(HelpLibrary.shortcutsPlaceholder), "\(language): no place for the table")
            // No shortcut with a symbol copied by hand into the page.
            for shortcut in AppShortcut.helpTable {
                if let display = shortcut.shortcut?.display(names: names), display.contains(where: { "⌃⌥⇧⌘←→".contains($0) }) {
                    #expect(!raw.contains(display), "\(language): \(display) written by hand")
                }
            }
            let page = try #require(try Self.library(language, shortcuts: table).page("shortcuts"))
            for shortcut in AppShortcut.helpTable {
                let display = try #require(shortcut.shortcut?.display(names: names))
                #expect(page.markdown.contains("- **\(display)** — Label \(shortcut)"), "\(language): \(shortcut) missing")
            }
            #expect(!page.markdown.contains(HelpLibrary.shortcutsPlaceholder))
        }
        for group in AppShortcut.HelpGroup.allCases {
            #expect(table.contains("## Group \(group)"), "group \(group) has no shortcut")
        }
    }

    /// The menu shortcuts moved into the table (lot A) keep the keys the menus had.
    @Test func menuShortcutsKeepTheirKeys() {
        let expected: [AppShortcut: String] = [
            .zoomToFit: "⌘0", .zoomToFill: "⌥⌘0", .actualSize: "⌘1", .zoomIn: "⌘+", .zoomOut: "⌘-",
            .toggleSettingsPanel: "⌥⌘P", .redo: "⇧⌘Z", .scannerInformation: "⌘I", .settings: "⌘,", .help: "⌘?",
        ]
        for shortcut in AppShortcut.menuOnly {
            #expect(shortcut.shortcut?.display() == expected[shortcut], "\(shortcut)")
            #expect(shortcut.shortcut?.keyEquivalent != nil, "\(shortcut): a menu item needs a key equivalent")
        }
        #expect(Set(AppShortcut.menuOnly) == Set(expected.keys))
        let displays: [String] = AppShortcut.helpTable.compactMap { $0.shortcut?.display() }
        #expect(Set(displays).count == displays.count, "two functions share a shortcut")
        // Scanner > Scan… (user's decision of 2026-11-21), next to Preview… (⌘R).
        #expect(AppShortcut.scan.shortcut?.display() == "⇧⌘R" && AppShortcut.preview.shortcut?.display() == "⌘R")
        #expect(AppShortcut.scan.helpGroup == .scanner)
        let scanTip: String = ShortcutTooltip.scanReal.text("Scan", names: .english)
        #expect(scanTip == "Scan (⇧⌘R)")
    }

    /// Shortcuts written in the other pages are those of the table, in the
    /// same glyphs: every run of ⌃⌥⇧⌘ and a key is some `display()` of
    /// `AppShortcut.helpTable`, so that a changed shortcut fails here.
    @Test func shortcutsInPagesComeFromTheTable() throws {
        let displays: Set<String> = Set(AppShortcut.helpTable.compactMap { $0.shortcut?.display() })
        let modifiers: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
        for language in HelpLibrary.languages {
            for page in try Self.library(language).pages {
                let characters: [Character] = Array(page.markdown)
                var index = 0
                while index < characters.count {
                    guard modifiers.contains(characters[index]) else { index += 1; continue }
                    var end = index
                    while end < characters.count, modifiers.contains(characters[end]) { end += 1 }
                    let key: String = end < characters.count ? String(characters[end]) : ""
                    // "⌥-click": a click with a modifier, not a shortcut.
                    if key == "-", end + 1 < characters.count, characters[end + 1].isLetter {
                        index = end + 1
                        continue
                    }
                    let shortcut: String = String(characters[index..<end]) + key.uppercased()
                    #expect(displays.contains(shortcut), "\(language)/\(page.id): \(shortcut) is not a shortcut of the table")
                    index = end + 1
                }
            }
        }
    }

    // MARK: Search

    @Test func searchIgnoresCaseAndAccents() throws {
        let french = try Self.library("fr")
        let crop: [HelpSearchResult] = french.search("recadrage")
        #expect(crop.first?.pageID == "tool-crop", "the Crop page first: its title matches")
        #expect(crop.contains { $0.pageID == "prepare" })
        #expect(french.search("RÉSOLUTION").contains { $0.pageID == "scan" && $0.anchor == "resolution" })
        #expect(french.search("resolution").contains { $0.pageID == "scan" && $0.anchor == "resolution" })
        #expect(french.search("dossier d'export").contains { $0.pageID == "output" }, "the straight apostrophe finds ’")
        #expect(french.search("angle").contains { $0.pageID == "prepare" && $0.anchor == "angle" }, "### sections with an anchor")
        #expect(french.search("   ").isEmpty)
        #expect(french.search("zzzz-nothing").isEmpty)
        let english = try Self.library("en")
        #expect(english.search("straighten rule").contains { $0.pageID == "tool-rule" }, "every word, anywhere in the section")
        #expect(english.search("crop", limit: 2).count == 2)
    }

    @Test func languageFollowsTheApplication() {
        #expect(HelpLibrary.language(for: ["fr"]) == "fr")
        #expect(HelpLibrary.language(for: ["fr-CH", "en"]) == "fr")
        #expect(HelpLibrary.language(for: ["en"]) == "en")
        #expect(HelpLibrary.language(for: ["de"]) == "en")
        #expect(HelpLibrary.language(for: []) == "en")
    }

    // MARK: Markdown

    @Test func resolvesLinks() {
        #expect(HelpLibrary.resolve("tool-crop.md", from: "index")! == ("tool-crop", nil))
        #expect(HelpLibrary.resolve("prepare.md#angle", from: "index")! == ("prepare", "angle"))
        #expect(HelpLibrary.resolve("#steps", from: "first-scan")! == ("first-scan", "steps"))
        #expect(HelpLibrary.resolve("https://example.org", from: "index") == nil)
        #expect(HelpLibrary.resolve("../secret.md", from: "index") == nil)
        #expect(HelpLibrary.resolve("crop.txt", from: "index") == nil)
    }

    @Test func markdownBlocksAndInlineMarks() {
        let markdown = """
        # Title {#top}

        First line
        second line.

        - one **bold**
        - two [link](a.md#b)

        1. step
        2. step `code`

        > A note.
        <!-- comment -->
        Last <tag> & "quote".
        """
        let blocks: [HelpMarkdown.Block] = HelpMarkdown.blocks(markdown)
        #expect(blocks == [
            .heading(level: 1, text: "Title", anchor: "top"),
            .paragraph("First line second line."),
            .list(ordered: false, items: ["one **bold**", "two [link](a.md#b)"]),
            .list(ordered: true, items: ["step", "step `code`"]),
            .note("A note."),
            .paragraph("Last <tag> & \"quote\"."),
        ])
        let html: String = HelpMarkdown.html(markdown)
        #expect(html.contains("<h1 id=\"top\">Title</h1>"))
        #expect(html.contains("<li>one <strong>bold</strong></li>"))
        #expect(html.contains("<a href=\"a.md#b\">link</a>"))
        #expect(html.contains("<code>code</code>"))
        #expect(html.contains("<blockquote><p>A note.</p></blockquote>"))
        #expect(html.contains("Last &lt;tag&gt; &amp; &quot;quote&quot;."), "the text is escaped")
        #expect(HelpMarkdown.inline("a * b") == "a * b", "a lone star stays")
        #expect(HelpMarkdown.inline("*it*") == "<em>it</em>")
        #expect(HelpMarkdown.plainText("**A** [b](c.md) `d`") == "A b d")
    }

    @Test func pageDocumentFollowsTheAppearance() throws {
        let html = try #require(try Self.library("fr").html(for: "index"))
        #expect(html.contains("color-scheme: light dark") && html.contains("-apple-system-label"))
        #expect(html.contains("<html lang=\"fr\">"))
        #expect(try Self.library("fr").html(for: "missing") == nil)
    }

    // MARK: Icons

    /// `app/X1Scan`, from this file.
    static let appSources: URL = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "X1Scan")

    /// Every `{icon:…}` of the pages names an icon of the table, and every
    /// icon of the table is shown in the help, in both languages.
    @Test func iconsOfThePagesComeFromTheTable() throws {
        for language in HelpLibrary.languages {
            let library = try Self.library(language)
            var used: Set<String> = []
            for page in library.pages {
                for key in HelpMarkdown.iconKeys(page.markdown) {
                    #expect(AppIcon(rawValue: key) != nil, "\(language)/\(page.id): unknown icon \(key)")
                    used.insert(key)
                }
            }
            let all: Set<String> = Set(AppIcon.allCases.map(\.rawValue))
            #expect(used == all, "\(language): icons not shown \(all.subtracting(used).sorted())")
        }
    }

    /// Each tool's page shows its icon in its title, next to its name; the
    /// title (window list, search) keeps the name only.
    @Test func eachToolPageShowsItsIcon() throws {
        let pages: [(id: String, icon: AppIcon)] = [
            ("tool-hand", .tool(.hand)), ("tool-zoom", .tool(.zoom)), ("tool-crop", .tool(.crop)),
            ("tool-rule", .tool(.straighten)), ("tool-grid", .grid), ("tool-exposure-zones", .exposureZones),
        ]
        for language in HelpLibrary.languages {
            let library = try Self.library(language)
            for (id, icon) in pages {
                let page = try #require(library.page(id))
                let first: String = page.markdown.components(separatedBy: .newlines).first ?? ""
                #expect(first.hasPrefix("# {icon:\(icon.rawValue)} "), "\(language)/\(id)")
                #expect(!page.title.contains("{"), "\(language)/\(id): \(page.title)")
            }
        }
    }

    /// The icon becomes a mask of the text's colour, from the picture the
    /// application draws; without a picture, or for an unknown key, nothing.
    @Test func iconsAreDrawnWhenThePageIsShown() {
        let url: (AppIcon) -> String? = { $0 == .hand ? "data:image/png;base64,AAAA" : nil }
        let html: String = HelpMarkdown.html("# {icon:hand} Hand\n\n- {icon:zoom} Zoom {icon:nothing}", iconURL: url)
        #expect(html.contains("<h1><span class=\"icon\" data-icon=\"hand\" aria-hidden=\"true\" "
            + "style=\"-webkit-mask-image: url('data:image/png;base64,AAAA')\"></span> Hand</h1>"))
        #expect(html.contains("<li> Zoom </li>"))
        #expect(!HelpMarkdown.html("{icon:hand} A").contains("span"), "no picture, no icon")
        #expect(HelpMarkdown.plainText("{icon:hand} Hand") == "Hand")
        #expect(HelpMarkdown.plainText("Total {roll}") == "Total {roll}", "other braces are text")
        #expect(HelpMarkdown.iconKeys("a {icon:hand} b {icon:grid}") == ["hand", "grid"])
    }

    /// One source for the symbols: the application names none of the
    /// table's system symbols itself, it goes through `AppIcon`.
    @Test func theApplicationUsesTheIconTable() throws {
        let names: [String] = AppIcon.allCases.compactMap(\.symbolName)
        let enumerator = try #require(FileManager.default.enumerator(at: Self.appSources, includingPropertiesForKeys: nil))
        var checked = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text: String = try String(contentsOf: url, encoding: .utf8)
            checked += 1
            for name in names {
                for call in ["systemName: \"\(name)\"", "systemSymbolName: \"\(name)\""] {
                    #expect(!text.contains(call), "\(url.lastPathComponent) names \(name) itself")
                }
            }
        }
        #expect(checked > 10)
    }
}
