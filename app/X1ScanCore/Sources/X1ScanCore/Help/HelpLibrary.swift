// SPDX-License-Identifier: MIT
import Foundation

/// A page of the built-in help: `docs/help/<language>/<id>.md`.
public struct HelpPage: Sendable, Hashable {
    public let id: String
    /// The text of its first heading.
    public let title: String
    /// Its Markdown, the shortcuts table inserted (`HelpLibrary.shortcutsPlaceholder`).
    public let markdown: String
}

/// A place in the help that matches a search: a page, or a section of it.
public struct HelpSearchResult: Sendable, Hashable {
    public let pageID: String
    /// Nil: the top of the page.
    public let anchor: String?
    /// The section's heading (the page's title for its top).
    public let title: String
    public let pageTitle: String
}

/// The pages of the built-in help in one language, from the Markdown files
/// copied into the application unchanged (docs/help, the only source of the
/// help text; docs/decisions.md, "Built-in help").
public struct HelpLibrary: Sendable {
    /// Every page, in both languages, with the same file name (tests check it).
    /// The first one is the home page.
    public static let pageIDs: [String] = [
        "index", "first-scan", "hardware", "prepare", "scan", "output", "information",
        "tool-hand", "tool-zoom", "tool-crop", "tool-rule", "tool-grid", "tool-exposure-zones",
        "shortcuts", "troubleshooting", "discovery", "about",
    ]
    /// Languages of the help; any other system language gets English, as the rest of the app.
    public static let languages = ["en", "fr"]
    /// Line of `shortcuts.md` replaced by the table of `AppShortcut.helpTable`.
    public static let shortcutsPlaceholder = "<!-- shortcuts -->"

    public let language: String
    public let pages: [HelpPage]

    /// Loads `<directory>/<language>/<id>.md` for every page of `pageIDs`.
    /// `shortcuts`: the Markdown table that replaces the placeholder.
    public init(directory: URL, language: String, shortcuts: String) throws {
        self.language = language
        pages = try Self.pageIDs.map { id in
            let url = directory.appending(path: language).appending(path: "\(id).md")
            let markdown = try String(contentsOf: url, encoding: .utf8)
                .replacingOccurrences(of: Self.shortcutsPlaceholder, with: shortcuts)
            let title = HelpMarkdown.blocks(markdown).lazy.compactMap { block -> String? in
                if case .heading(_, let text, _) = block { text } else { nil }
            }.first ?? id
            return HelpPage(id: id, title: HelpMarkdown.plainText(title), markdown: markdown)
        }
    }

    /// French for a French system, English otherwise (`preferred`: the
    /// application's localizations in order, `Bundle.preferredLocalizations`).
    public static func language(for preferred: [String]) -> String {
        preferred.first.map { $0.hasPrefix("fr") ? "fr" : "en" } ?? "en"
    }

    public func page(_ id: String) -> HelpPage? { pages.first { $0.id == id } }

    // MARK: Links

    /// The page and anchor a link leads to, seen from page `from`:
    /// `crop.md`, `crop.md#frame`, `#frame`. Nil for anything else (a web
    /// address, a missing `.md`).
    public static func resolve(_ target: String, from pageID: String) -> (page: String, anchor: String?)? {
        let parts = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let file = parts[0]
        let anchor = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
        if file.isEmpty { return anchor.map { (pageID, $0) } }
        guard file.hasSuffix(".md"), !file.contains("/"), !file.contains(":") else { return nil }
        return (String(file.dropLast(3)), anchor)
    }

    // MARK: Search

    /// The sections (`##`, and `###` with an anchor) whose heading or text contains every word of `query`,
    /// ignoring case and accents ("recadrage", "Echap"); headings first.
    public func search(_ query: String, limit: Int = 30) -> [HelpSearchResult] {
        let words = Self.fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return [] }
        var scored: [(score: Int, order: Int, result: HelpSearchResult)] = []
        for section in sections {
            let title = Self.fold(section.result.title)
            let all = title + " " + Self.fold(section.text)
            guard words.allSatisfy({ all.contains($0) }) else { continue }
            let score = words.allSatisfy { title.contains($0) } ? 2 : 1
            scored.append((score, scored.count, section.result))
        }
        return scored.sorted { ($0.score, -$0.order) > ($1.score, -$1.order) }.prefix(limit).map(\.result)
    }

    private var sections: [(result: HelpSearchResult, text: String)] {
        var out: [(result: HelpSearchResult, text: String)] = []
        for page in pages {
            var title = page.title
            var anchor: String?
            var text: [String] = []
            func close() {
                out.append((HelpSearchResult(pageID: page.id, anchor: anchor, title: title, pageTitle: page.title),
                            text.joined(separator: " ")))
            }
            for block in HelpMarkdown.blocks(page.markdown) {
                // A `##` section, or a `###` one with an anchor (a place the index links to).
                if case .heading(let level, let heading, let id) = block, level == 2 || (level == 3 && id != nil) {
                    close()
                    title = HelpMarkdown.plainText(heading)
                    anchor = id
                    text = []
                } else if case .heading(1, _, _) = block {
                    continue
                } else {
                    text += HelpMarkdown.texts(of: block).map(HelpMarkdown.plainText)
                }
            }
            close()
        }
        return out
    }

    static func fold(_ text: String) -> String {
        // The pages use the typographic apostrophe, the keyboard types the straight one.
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "\u{2019}", with: "'")
    }

    // MARK: HTML

    /// The whole HTML document of a page, in the system's light or dark
    /// appearance (CSS `prefers-color-scheme`).
    public func html(for pageID: String, iconURL: (AppIcon) -> String? = { _ in nil }) -> String? {
        guard let page = page(pageID) else { return nil }
        return """
        <!doctype html>
        <html lang="\(language)"><head><meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <title>\(HelpMarkdown.escape(page.title))</title>
        <style>\(Self.stylesheet)</style></head>
        <body>\(HelpMarkdown.html(page.markdown, iconURL: iconURL))</body></html>
        """
    }

    /// Semantic colours of the system (text, links, separators, background), so
    /// that the page follows the appearance, the accent colour and Increase Contrast.
    static let stylesheet = """
    :root { color-scheme: light dark; }
    html { background: -apple-system-text-background; }
    body { font: 13px/1.5 -apple-system, system-ui, sans-serif; color: -apple-system-label; margin: 20px 24px 40px; max-width: 680px; }
    h1 { font-size: 22px; margin: 0 0 12px; }
    h2 { font-size: 16px; margin: 22px 0 6px; padding-top: 8px; border-top: 1px solid -apple-system-separator; }
    h3 { font-size: 13px; margin: 16px 0 4px; }
    p, ul, ol { margin: 6px 0; }
    ul, ol { padding-left: 22px; }
    li { margin: 2px 0; }
    a { color: -webkit-link; text-decoration: none; }
    a:hover { text-decoration: underline; }
    code { font: 12px ui-monospace, Menlo, monospace; background: -apple-system-quaternary-label; padding: 1px 4px; border-radius: 4px; }
    blockquote { margin: 10px 0; padding: 4px 12px; border-left: 3px solid -apple-system-separator; color: -apple-system-secondary-label; }
    :target { scroll-margin-top: 12px; }
    .icon { display: inline-block; width: 1.15em; height: 1.15em; vertical-align: -0.2em; margin: 0 0.15em;
            background-color: currentColor; -webkit-mask-repeat: no-repeat; -webkit-mask-position: center;
            -webkit-mask-size: contain; }
    .icon[data-icon="swap-proportions"] { width: 2.4em; }
    """
}

/// The page of keyboard shortcuts, made from the same table as the menus
/// and the tooltips (`AppShortcut.helpTable`): never written by hand.
public enum HelpShortcuts {
    /// One `##` heading per group, then one line per shortcut: `- **⌘R** — Preview`.
    public static func markdown(groupTitle: (AppShortcut.HelpGroup) -> String,
                                label: (AppShortcut) -> String,
                                names: KeyShortcut.KeyNames) -> String {
        AppShortcut.HelpGroup.allCases.compactMap { group -> String? in
            let lines: [String] = AppShortcut.helpTable.filter { $0.helpGroup == group }.compactMap { shortcut in
                guard let keys = shortcut.shortcut?.display(names: names) else { return nil }
                return "- **\(keys)** — \(label(shortcut))"
            }
            return lines.isEmpty ? nil : "## \(groupTitle(group))\n\n" + lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}
