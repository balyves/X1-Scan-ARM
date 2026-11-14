// SPDX-License-Identifier: MIT
import SwiftUI
import X1ScanCore

/// The file name builder, in Settings > Export:
/// template field, token buttons inserted at the cursor, roll, frame and
/// counter, and the real name of the next file (sanitised).
struct ExportNameBuilder: View {
    @Bindable var model: AppModel
    @State private var selection: TextSelection?
    /// Last caret position in the template field (character offset and selection
    /// length). Kept when a token button takes the focus away from the field.
    @State private var caret: (offset: Int, length: Int)?
    @FocusState private var templateFocused: Bool
    /// The template as this builder last wrote it; another value means it was
    /// changed elsewhere (the panel's Name menu) and the caret no longer applies.
    @State private var templateFromBuilder: String?
    @FocusState private var rollFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(String(localized: "File name", comment: "Export palette label"),
                      text: $model.exportSettings.nameTemplate, selection: $selection)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .monospaced()
                .focused($templateFocused)
                // Only while the field has the focus: losing it (a token button
                // clicked) may move the selection to the start.
                .onChange(of: selection) { _, newValue in if templateFocused { rememberCaret(newValue) } }
                .onChange(of: model.exportSettings.nameTemplate) { _, newValue in
                    if !templateFocused, newValue != templateFromBuilder { caret = nil }  // insert at the end
                }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(ExportToken.allCases, id: \.self) { token in
                    Button(Strings.exportToken(token)) { insert(token) }
                        .controlSize(.small)
                        .help(token.placeholder)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("Roll", comment: "File name token button: roll name").foregroundStyle(.secondary)
                    TextField(String(localized: "Roll", comment: "File name token button: roll name"),
                              text: $model.exportSettings.roll)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .focused($rollFocused)
                        // Another roll starts at frame 1, once the name is validated.
                        .onSubmit { validateRoll() }
                        .onChange(of: rollFocused) { _, focused in
                            if !focused { validateRoll() }
                        }
                }
                GridRow {
                    Text("Frame", comment: "File name token button: frame number").foregroundStyle(.secondary)
                    HStack {
                        TextField(value: frame, format: .number) { EmptyView() }
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 56)
                        Stepper(value: frame, in: ExportSettings.frameRange) { EmptyView() }.labelsHidden()
                        Toggle(String(localized: "+1 after export", comment: "Export: increment the frame number"),
                               isOn: $model.exportSettings.incrementsFrame)
                            .toggleStyle(.checkbox)
                    }
                }
                GridRow {
                    Text("Number", comment: "File name token button: counter {n}").foregroundStyle(.secondary)
                    HStack {
                        Text("From", comment: "Export counter: start value").foregroundStyle(.secondary)
                        TextField(value: $model.exportSettings.counterStart, format: .number) { EmptyView() }
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 56)
                        Text("Digits", comment: "Export counter: number of digits").foregroundStyle(.secondary)
                        Text(model.exportSettings.counterDigits, format: .number).monospacedDigit()
                        Stepper(value: $model.exportSettings.counterDigits, in: ExportSettings.counterDigitsRange) {
                            EmptyView()
                        }
                        .labelsHidden()
                    }
                }
            }
            .font(.callout)

            Text(ExportNameHelp.next(model))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    /// The frame, set by hand: a roll name typed before is validated first,
    /// so that the frame chosen for the new roll is kept.
    private var frame: Binding<Int> {
        Binding { model.exportSettings.frame } set: { model.exportSettings.setFrame($0) }
    }

    private func validateRoll() {
        if model.exportSettings.needsRollValidation { model.exportSettings.validateRoll() }
    }

    /// Inserts the token at the last caret position, with "-" separators
    /// where needed (ExportToken.insert); at the end if the field was never edited.
    private func insert(_ token: ExportToken) {
        let result = token.insert(into: model.exportSettings.nameTemplate, at: caret?.offset,
                                  selectionLength: caret?.length ?? 0)
        templateFromBuilder = result.text
        model.exportSettings.nameTemplate = result.text
        caret = (result.caret, 0)
        let text = result.text
        let index = text.index(text.startIndex, offsetBy: min(result.caret, text.count))
        selection = TextSelection(insertionPoint: index)
    }

    private func rememberCaret(_ selection: TextSelection?) {
        guard case .selection(let range) = selection?.indices else { return }
        let text = model.exportSettings.nameTemplate
        guard range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex else { return }
        caret = (text.distance(from: text.startIndex, to: range.lowerBound),
                 text.distance(from: range.lowerBound, to: range.upperBound))
    }
}

/// Text under the builder.
@MainActor
enum ExportNameHelp {
    static func next(_ model: AppModel) -> String {
        _ = model.lastExport  // recomputed after each export: the number moves on
        return String(localized: "Next file: \(model.nextExportFileName())", comment: "Export: name of the next file")
    }
}
