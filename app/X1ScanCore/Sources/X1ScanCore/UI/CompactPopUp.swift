// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// A menu (pop-up button) that fills the control column of a compact row.
/// A SwiftUI `Picker` keeps the width of its longest item on macOS, even in a
/// wider frame; this native pop-up button stretches to the width it is
/// offered and truncates long titles in the middle. Titles come already
/// translated; `label` is what VoiceOver reads; `help` is the tooltip and the
/// VoiceOver help of the menu itself (a SwiftUI `.help` around a native view
/// does not reach it). The selection must be one of the items' values;
/// otherwise the menu shows no title.
public struct CompactPopUp<Value: Hashable>: NSViewRepresentable {
    public struct Item {
        public var title: String
        public var value: Value

        public init(_ title: String, _ value: Value) {
            self.title = title
            self.value = value
        }
    }

    let label: String
    let help: String?
    /// Groups of items, separated in the menu.
    let sections: [[Item]]
    @Binding var selection: Value

    public init(_ label: String, help: String? = nil, selection: Binding<Value>, sections: [[Item]]) {
        self.label = label
        self.help = help
        self.sections = sections
        _selection = selection
    }

    public init(_ label: String, help: String? = nil, selection: Binding<Value>, items: [Item]) {
        self.init(label, help: help, selection: selection, sections: [items])
    }

    /// The menu as shown: items in order, `nil` for a separator. A separator
    /// goes between two non-empty sections only (never first or last).
    nonisolated static func menu(of sections: [[Item]]) -> [Item?] {
        var entries: [Item?] = []
        for section in sections where !section.isEmpty {
            if !entries.isEmpty { entries.append(nil) }
            entries.append(contentsOf: section.map { Optional($0) })
        }
        return entries
    }

    /// Index of `value` in the menu; nil when no item has that value.
    nonisolated static func menuIndex(of value: Value, in sections: [[Item]]) -> Int? {
        menu(of: sections).firstIndex { $0?.value == value }
    }

    /// The value at a menu index; nil for a separator or an index out of range.
    nonisolated static func value(atMenuIndex index: Int, in sections: [[Item]]) -> Value? {
        let entries = menu(of: sections)
        guard entries.indices.contains(index) else { return nil }
        return entries[index]?.value
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        (button.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingMiddle
        return button
    }

    public func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        // The title follows the control size, like the system's own menus.
        let size: NSControl.ControlSize = switch context.environment.controlSize {
        case .mini: .mini
        case .small: .small
        case .large: .large
        case .extraLarge: .extraLarge
        default: .regular
        }
        button.controlSize = size
        button.font = .systemFont(ofSize: NSFont.systemFontSize(for: size))
        button.isEnabled = context.environment.isEnabled
        button.setAccessibilityLabel(label)
        button.toolTip = help
        button.setAccessibilityHelp(help)

        let entries = Self.menu(of: sections)
        let titles = entries.map { $0?.title }
        if context.coordinator.shownTitles != titles {
            button.removeAllItems()
            for entry in entries {
                button.menu?.addItem(entry.map { NSMenuItem(title: $0.title, action: nil, keyEquivalent: "") }
                                     ?? .separator())
            }
            context.coordinator.shownTitles = titles
        }
        if let index = Self.menuIndex(of: selection, in: sections) {
            button.selectItem(at: index)
        } else {
            button.select(nil)
        }
    }

    /// As wide as offered (the control column); as tall as the button.
    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        let natural = nsView.intrinsicContentSize
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? natural.width
        return CGSize(width: width, height: natural.height)
    }

    @MainActor
    public final class Coordinator: NSObject {
        var parent: CompactPopUp
        var shownTitles: [String?] = []

        init(_ parent: CompactPopUp) { self.parent = parent }

        @objc func changed(_ sender: NSPopUpButton) {
            if let value = CompactPopUp.value(atMenuIndex: sender.indexOfSelectedItem, in: parent.sections) {
                parent.selection = value
            }
        }
    }
}
