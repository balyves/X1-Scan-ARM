// SPDX-License-Identifier: MIT
import SwiftUI
import X1ScanCore

/// The file name builder, in the Export palette and in Settings > Export:
/// template field, token buttons inserted at the cursor, roll, frame and
/// counter, and the real name of the next file (sanitised).
struct ExportNameBuilder: View {
    @Bindable var model: AppModel
    @State private var selection: TextSelection?
    @FocusState private var rollFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(String(localized: "File name", comment: "Export palette label"),
                      text: $model.exportSettings.nameTemplate, selection: $selection)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .monospaced()

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

    /// Inserts the token's placeholder at the cursor (replacing a selection), or at the end.
    private func insert(_ token: ExportToken) {
        var text = model.exportSettings.nameTemplate
        let placeholder = token.placeholder
        if case .selection(let range) = selection?.indices,
           range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex {
            text.replaceSubrange(range, with: placeholder)
            let caret = text.index(range.lowerBound, offsetBy: placeholder.count)
            model.exportSettings.nameTemplate = text
            selection = TextSelection(insertionPoint: caret)
        } else {
            model.exportSettings.nameTemplate = text + placeholder
            selection = nil
        }
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
