// SPDX-License-Identifier: MIT
import Foundation

/// The small Markdown subset of the help pages (docs/help/fr, docs/help/en),
/// turned into HTML when a page is shown (docs/decisions.md, "Built-in
/// help"): headings `#` to `###` with an optional `{#anchor}`, paragraphs,
/// `- ` and `1. ` lists, `> ` notes, `**bold**`, `*italic*`, `` `code` ``
/// and `[text](target)` links. Anything else is shown as plain text.
public enum HelpMarkdown {
    /// One block of a page.
    public enum Block: Sendable, Hashable {
        case heading(level: Int, text: String, anchor: String?)
        case paragraph(String)
        case list(ordered: Bool, items: [String])
        case note(String)
    }

    /// The blocks of `markdown`, in order. HTML comments (`<!-- … -->`, on
    /// their own line) are dropped.
    public static func blocks(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var note: [String] = []
        var items: [String] = []
        var ordered = false

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            if !note.isEmpty { blocks.append(.note(note.joined(separator: " "))) }
            if !items.isEmpty { blocks.append(.list(ordered: ordered, items: items)) }
            paragraph = []
            note = []
            items = []
        }

        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || (line.hasPrefix("<!--") && line.hasSuffix("-->")) {
                flush()
            } else if let heading = Self.heading(line) {
                flush()
                blocks.append(heading)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if !items.isEmpty, ordered { flush() }
                if !paragraph.isEmpty || !note.isEmpty { flush() }
                ordered = false
                items.append(String(line.dropFirst(2)))
            } else if let item = Self.orderedItem(line) {
                if !items.isEmpty, !ordered { flush() }
                if !paragraph.isEmpty || !note.isEmpty { flush() }
                ordered = true
                items.append(item)
            } else if line.hasPrefix(">") {
                if !paragraph.isEmpty || !items.isEmpty { flush() }
                note.append(line.dropFirst().trimmingCharacters(in: .whitespaces))
            } else if !items.isEmpty, raw.hasPrefix("  ") {
                items[items.count - 1] += " " + line  // continuation of a list item
            } else {
                if !items.isEmpty || !note.isEmpty { flush() }
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    private static func heading(_ line: String) -> Block? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...3).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        var text = line.dropFirst(hashes + 1).trimmingCharacters(in: .whitespaces)
        var anchor: String?
        if text.hasSuffix("}"), let open = text.range(of: "{#", options: .backwards) {
            anchor = String(text[open.upperBound..<text.index(before: text.endIndex)])
            text = text[..<open.lowerBound].trimmingCharacters(in: .whitespaces)
        }
        return .heading(level: hashes, text: text, anchor: anchor)
    }

    private static func orderedItem(_ line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") else { return nil }
        return String(line.dropFirst(digits.count + 2))
    }

    // MARK: Inline

    /// A link of the page: `target` as written (`crop.md#frame`, `#steps`).
    public struct Link: Sendable, Hashable {
        public var text: String
        public var target: String
    }

    /// Every link of `markdown`, in order.
    public static func links(_ markdown: String) -> [Link] {
        var links: [Link] = []
        for block in blocks(markdown) {
            for text in texts(of: block) { links += inlineLinks(text) }
        }
        return links
    }

    /// The anchors of `markdown`'s headings.
    public static func anchors(_ markdown: String) -> [String] {
        blocks(markdown).compactMap {
            if case .heading(_, _, let anchor) = $0 { anchor } else { nil }
        }
    }

    static func texts(of block: Block) -> [String] {
        switch block {
        case .heading(_, let text, _), .paragraph(let text), .note(let text): [text]
        case .list(_, let items): items
        }
    }

    private static func inlineLinks(_ text: String) -> [Link] {
        var links: [Link] = []
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "["),
              let close = rest[open...].range(of: "]("),
              let end = rest[close.upperBound...].firstIndex(of: ")") {
            links.append(Link(text: String(rest[rest.index(after: open)..<close.lowerBound]),
                              target: String(rest[close.upperBound..<end])))
            rest = rest[rest.index(after: end)...]
        }
        return links
    }

    /// The text of an inline span without its marks, for the search index.
    public static func plainText(_ text: String) -> String {
        var out = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "["),
              let close = rest[open...].range(of: "]("),
              let end = rest[close.upperBound...].firstIndex(of: ")") {
            out += rest[..<open]
            out += rest[rest.index(after: open)..<close.lowerBound]
            rest = rest[rest.index(after: end)...]
        }
        out += rest
        return out.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "*", with: "")
    }

    // MARK: HTML

    /// The HTML of `markdown`'s blocks (no `<html>` around them). Links to
    /// another page keep their target (`crop.md#frame`): the help window
    /// opens them itself.
    public static func html(_ markdown: String) -> String {
        blocks(markdown).map { block -> String in
            switch block {
            case .heading(let level, let text, let anchor):
                let id = anchor.map { " id=\"\(escape($0))\"" } ?? ""
                return "<h\(level)\(id)>\(inline(text))</h\(level)>"
            case .paragraph(let text):
                return "<p>\(inline(text))</p>"
            case .note(let text):
                return "<blockquote><p>\(inline(text))</p></blockquote>"
            case .list(let ordered, let items):
                let tag = ordered ? "ol" : "ul"
                return "<\(tag)>" + items.map { "<li>\(inline($0))</li>" }.joined() + "</\(tag)>"
            }
        }.joined(separator: "\n")
    }

    /// Inline marks of one span, the text escaped.
    static func inline(_ text: String) -> String {
        var out = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "["),
              let close = rest[open...].range(of: "]("),
              let end = rest[close.upperBound...].firstIndex(of: ")") {
            out += emphasis(String(rest[..<open]))
            let label = String(rest[rest.index(after: open)..<close.lowerBound])
            let target = String(rest[close.upperBound..<end])
            out += "<a href=\"\(escape(target))\">\(emphasis(label))</a>"
            rest = rest[rest.index(after: end)...]
        }
        return out + emphasis(String(rest))
    }

    /// `` `code` ``, `**bold**` and `*italic*`, the text escaped.
    private static func emphasis(_ text: String) -> String {
        var out = ""
        var parts = text.components(separatedBy: "`")
        if parts.count.isMultiple(of: 2) { parts[parts.count - 2] += "`" + parts.removeLast() }  // unpaired
        for (index, part) in parts.enumerated() {
            if index.isMultiple(of: 2) {
                out += pairs(pairs(escape(part), mark: "**", tag: "strong"), mark: "*", tag: "em")
            } else {
                out += "<code>\(escape(part))</code>"
            }
        }
        return out
    }

    private static func pairs(_ text: String, mark: String, tag: String) -> String {
        let parts = text.components(separatedBy: mark)
        guard parts.count >= 3 else { return text }
        let unpaired = !(parts.count - 1).isMultiple(of: 2)
        var out = parts[0]
        for index in 1..<parts.count {
            if unpaired && index == parts.count - 1 {
                out += mark + parts[index]  // a lone last mark is kept as typed
            } else {
                out += (index.isMultiple(of: 2) ? "</\(tag)>" : "<\(tag)>") + parts[index]
            }
        }
        return out
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
