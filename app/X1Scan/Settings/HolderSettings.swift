// SPDX-License-Identifier: MIT
import SwiftUI
import X1ScanCore

/// Settings > Holders: tick the holders you own (only those appear in the
/// panel's menu); add, edit or delete custom holders. Default holders can be
/// hidden (unticked), not deleted.
struct HolderSettings: View {
    @Bindable var model: AppModel
    @State private var editing: HolderDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tick the holders you own: only those appear in the panel.", comment: "Settings > Holders note")
                .font(.callout)
                .foregroundStyle(.secondary)
            List {
                ForEach([Holder.Series.standard, .common, .custom], id: \.self) { series in
                    let holders = model.holders.all.filter { $0.series == series }
                    if !holders.isEmpty || series == .custom {
                        Section(Strings.holderSeries(series)) {
                            ForEach(holders) { holder in row(holder) }
                            if series == .custom {
                                Button(String(localized: "Add Holder…", comment: "Settings > Holders button")) {
                                    editing = HolderDraft()
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
        .padding(16)
        .controlSize(.small)
        .sheet(item: $editing) { draft in
            HolderEditor(draft: draft) { result in
                if let result { save(result) }
                editing = nil
            }
        }
    }

    private func row(_ holder: Holder) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding { model.holders.isOwned(holder.id) } set: { model.holders.setOwned(holder.id, $0) }) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel(Strings.holderName(holder))
            Text(Strings.holderName(holder)).frame(minWidth: 120, alignment: .leading)
            Text(holder.reference ?? "—").monospacedDigit().foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
            Text(Strings.holderApertures(holder)).foregroundStyle(.secondary)
            if holder.frames > 1 {
                // Only shown above 1 frame, so no singular form is needed.
                Text("\(holder.frames) frames", comment: "Holder: number of frames, always 2 or more").foregroundStyle(.secondary)
            }
            Spacer()
            if holder.isCustom {
                Button(String(localized: "Edit…", comment: "Panel button: opens Settings > Export")) {
                    editing = HolderDraft(holder)
                }
                Button(role: .destructive) {
                    model.holders.deleteCustom(holder.id)
                } label: {
                    Text("Delete", comment: "Settings > Holders button")
                }
            }
        }
    }

    private func save(_ draft: HolderDraft) {
        let aperture: HolderAperture? = (draft.width > 0 && draft.height > 0)
            ? HolderAperture(width: draft.width, height: draft.height) : nil
        if let id = draft.id {
            model.holders.updateCustom(id, reference: draft.reference, format: draft.name, aperture: aperture, frames: draft.frames)
        } else {
            model.holders.addCustom(reference: draft.reference, format: draft.name, aperture: aperture, frames: draft.frames)
        }
    }
}

/// The values of the holder editor.
struct HolderDraft: Identifiable {
    let id: String?
    var name = ""
    var reference = ""
    var width: Double = 0
    var height: Double = 0
    var frames = 1

    init() { id = nil }

    init(_ holder: Holder) {
        id = holder.id
        name = holder.format
        reference = holder.reference ?? ""
        width = holder.apertures.first?.width ?? 0
        height = holder.apertures.first?.height ?? 0
        frames = holder.frames
    }

    var identity: String { id ?? "new" }
}

extension HolderDraft: Hashable {
    static func == (a: HolderDraft, b: HolderDraft) -> Bool { a.identity == b.identity }
    func hash(into hasher: inout Hasher) { hasher.combine(identity) }
}

/// Sheet to add or edit a custom holder.
private struct HolderEditor: View {
    @State var draft: HolderDraft
    let done: (HolderDraft?) -> Void

    var body: some View {
        Form {
            TextField(String(localized: "Name", comment: "Panel label: file name template"), text: $draft.name)
            TextField(String(localized: "Reference (optional)", comment: "Holder editor field"), text: $draft.reference)
            LabeledContent(String(localized: "Opening (mm)", comment: "Holder editor field")) {
                HStack {
                    TextField(value: $draft.width, format: .number) { EmptyView() }.frame(width: 60)
                    Text(verbatim: "×")
                    TextField(value: $draft.height, format: .number) { EmptyView() }.frame(width: 60)
                }
            }
            Stepper(value: $draft.frames, in: 1...12) {
                Text("Frames: \(draft.frames)", comment: "Holder editor: number of frames")
            }
            HStack {
                Spacer()
                Button(String(localized: "Cancel", comment: "Button")) { done(nil) }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Save", comment: "Button")) { done(draft) }
                    .keyboardShortcut(.defaultAction)
                    // Both sides of the opening, or neither.
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || (draft.width > 0) != (draft.height > 0))
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .padding()
    }
}
