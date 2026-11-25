// SPDX-License-Identifier: MIT
import Foundation

/// The text of the numeric field of a compact slider row. Only text the user
/// actually typed is applied: clicking into the field, moving the slider and
/// leaving the field keeps the slider's value. No interface here, so that it
/// can be tested.
public struct CompactFieldState: Sendable, Hashable {
    public private(set) var text: String
    /// The text last shown for the current value.
    private var shown: String

    public init(showing text: String = "") {
        self.text = text
        shown = text
    }

    /// The user changed the text since it was last shown.
    public var isEdited: Bool { text != shown }

    /// The user typed.
    public mutating func edit(_ newText: String) {
        text = newText
    }

    /// The value changed elsewhere (slider, reset, model): show it. Typing in
    /// progress is dropped.
    public mutating func show(_ formatted: String) {
        text = formatted
        shown = formatted
    }

    /// Return or focus lost. Returns the typed number, clamped, or nil when
    /// nothing was typed or the text is not a number. Either way the field then
    /// shows the value that applies.
    /// `unit`: the row's unit, accepted after the number.
    public mutating func commit(format: CompactValueFormat, current: Double, locale: Locale, unit: String = "") -> Double? {
        let typed = isEdited ? format.value(parsing: text, unit: unit) : nil
        show(format.text(for: typed ?? current, locale: locale))
        return typed
    }
}
