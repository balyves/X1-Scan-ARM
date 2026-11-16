// SPDX-License-Identifier: MIT
import SwiftUI

// Reusable views of the compact settings panel (conventions in
// .claude/skills/compact-settings-panel/SKILL.md). They hold no setting of
// their own and produce no interface text: every label comes already
// translated from the application's String Catalog.

/// Shared grid of the compact panel, in points.
public enum CompactPanelMetrics {
    /// Label column, the same in every row so that controls line up.
    public static let labelWidth: CGFloat = 78
    /// Numeric field of a slider row.
    public static let fieldWidth: CGFloat = 52
    /// Unit after the field.
    public static let unitWidth: CGFloat = 24
    /// Between the columns of a row.
    public static let columnSpacing: CGFloat = 6
    /// Between rows.
    public static let rowSpacing: CGFloat = 4
    /// Between groups inside a section (tabs and their rows, a sub-group).
    public static let groupSpacing: CGFloat = 8
    /// Between a disclosure title and its content.
    public static let contentTopInset: CGFloat = 4
    /// Inside a section, around its rows.
    public static let sectionInsets = EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12)
}

/// VoiceOver values of a foldable title, already translated.
public struct CompactFoldTexts: Sendable, Hashable {
    public var expanded: String
    public var collapsed: String

    public init(expanded: String, collapsed: String) {
        self.expanded = expanded
        self.collapsed = collapsed
    }
}

/// Disclosure style of the panel: the whole title row is one button (chevron
/// and title), content without indentation, so that rows keep the panel grid.
public struct CompactDisclosureStyle: DisclosureGroupStyle {
    let texts: CompactFoldTexts
    let isHeader: Bool

    public init(texts: CompactFoldTexts, isHeader: Bool = false) {
        self.texts = texts
        self.isHeader = isHeader
    }

    public func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.15)) { configuration.$isExpanded.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                    configuration.label
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? texts.expanded : texts.collapsed)
            .accessibilityAddTraits(isHeader ? .isHeader : [])
            if configuration.isExpanded {
                configuration.content
                    .padding(.top, CompactPanelMetrics.contentTopInset)
            }
        }
    }
}

/// A foldable section: short title, thin separator below, folded state kept
/// by the caller (the panel layout, saved between launches).
public struct CompactSection<Content: View>: View {
    let title: String
    let foldTexts: CompactFoldTexts
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    public init(_ title: String, foldTexts: CompactFoldTexts, isExpanded: Binding<Bool>,
                @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.foldTexts = foldTexts
        _isExpanded = isExpanded
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: CompactPanelMetrics.rowSpacing) {
                    content()
                }
                // Sub-groups inside the section: the same style, without the header trait.
                .disclosureGroupStyle(CompactDisclosureStyle(texts: foldTexts))
            } label: {
                Text(title).font(.callout.weight(.semibold))
            }
            .disclosureGroupStyle(CompactDisclosureStyle(texts: foldTexts, isHeader: true))
            .padding(CompactPanelMetrics.sectionInsets)
            Divider()
        }
    }
}

/// A read-only value on one row: label column, then the value.
public struct CompactInfoRow: View {
    let label: String
    let value: String

    public init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CompactPanelMetrics.columnSpacing) {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: CompactPanelMetrics.labelWidth, alignment: .leading)
            Text(value)
                .monospacedDigit()
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A number on one row: label, slider, editable field, unit. A double-click
/// on the label, or the VoiceOver action, restores the default value.
public struct CompactSliderRow: View {
    /// Already translated texts.
    public struct Texts: Sendable, Hashable {
        public var label: String
        public var unit: String
        /// Name of the VoiceOver action that restores the default value.
        public var resetAction: String
        /// Tooltip of the label; it says what the double-click restores.
        public var resetHelp: String

        public init(label: String, unit: String, resetAction: String, resetHelp: String) {
            self.label = label
            self.unit = unit
            self.resetAction = resetAction
            self.resetHelp = resetHelp
        }
    }

    @Binding var value: Double
    let format: CompactValueFormat
    let texts: Texts

    @State private var field = CompactFieldState()
    @FocusState private var isEditing: Bool
    @Environment(\.locale) private var locale

    public init(value: Binding<Double>, format: CompactValueFormat, texts: Texts) {
        _value = value
        self.format = format
        self.texts = texts
    }

    public var body: some View {
        HStack(alignment: .center, spacing: CompactPanelMetrics.columnSpacing) {
            Text(texts.label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: CompactPanelMetrics.labelWidth, alignment: .leading)
                .contentShape(.rect)
                .onTapGesture(count: 2, perform: reset)
                .help(texts.resetHelp)
                .accessibilityHidden(true)  // the slider and the field carry the label
            Slider(value: Binding(get: { value }, set: { value = format.clamped($0) }), in: format.range) {
                Text(texts.label)
            }
            .labelsHidden()
            .accessibilityValue(spokenValue)
            .accessibilityAction(named: texts.resetAction, reset)
            TextField(text: Binding(get: { field.text }, set: { field.edit($0) }), prompt: nil) {
                Text(texts.label)
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: CompactPanelMetrics.fieldWidth)
            .focused($isEditing)
            .onSubmit(commit)
            .accessibilityValue(spokenValue)
            .accessibilityAction(named: texts.resetAction, reset)
            Text(texts.unit)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: CompactPanelMetrics.unitWidth, alignment: .leading)
                .accessibilityHidden(true)
        }
        .onAppear { field.show(format.text(for: value, locale: locale)) }
        .onChange(of: value) { field.show(format.text(for: value, locale: locale)) }
        .onChange(of: isEditing) { _, editing in if !editing { commit() } }
        .onDisappear(perform: commit)  // section folded or tab changed while typing
    }

    private var spokenValue: String {
        let number = format.text(for: value, locale: locale)
        return texts.unit.isEmpty ? number : number + " " + texts.unit
    }

    private func commit() {
        if let typed = field.commit(format: format, current: value, locale: locale) { value = typed }
    }

    private func reset() {
        value = format.defaultValue
        field.show(format.text(for: value, locale: locale))
    }
}

extension Binding where Value == Double {
    /// An integer setting seen as a Double by a slider row; written back
    /// rounded, and only when the integer changes (a slider sends many values).
    public init(rounding source: Binding<Int>) {
        self.init(
            get: { Double(source.wrappedValue) },
            set: { newValue in
                guard newValue.isFinite, let rounded = Int(exactly: newValue.rounded()),
                      rounded != source.wrappedValue else { return }
                source.wrappedValue = rounded
            })
    }
}

extension PanelController {
    /// Expanded state of a section or sub-group, for a DisclosureGroup; saved
    /// with the panel layout.
    public func expansion(of section: PanelSection) -> Binding<Bool> {
        Binding(get: { !self.layout.isFolded(section) }, set: { self.setFolded(section, !$0) })
    }
}
