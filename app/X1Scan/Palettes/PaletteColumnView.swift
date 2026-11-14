// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import X1ScanCore

/// The right column: palettes in full, or an icon bar whose icons open
/// palettes in a stack beside it (IconBarStackView). Palettes are reordered
/// by drag and drop, and detached by dropping them on the image area.
struct PaletteColumnView: View {
    @Bindable var model: AppModel

    var body: some View {
        switch model.layout.layout.columnMode {
        case .expanded: expanded
        case .iconBar: iconBar
        }
    }

    private var expanded: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(model.layout.layout.visibleDockedPalettes, id: \.self) { id in
                    PaletteSection(model: model, id: id)
                        .paletteDropTarget(model: model, before: id)
                    Divider()
                }
                // Dropping below the last palette moves it to the end.
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .contentShape(.rect)
                    .paletteDropTarget(model: model, before: nil)
            }
        }
        .scrollIndicators(.automatic)
    }

    private var iconBar: some View {
        VStack(spacing: 6) {
            ForEach(model.layout.layout.visibleDockedPalettes, id: \.self) { id in
                PaletteIconButton(model: model, id: id)
                    .paletteDropTarget(model: model, before: id)
            }
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
                .paletteDropTarget(model: model, before: nil)
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity)
    }
}

/// What a palette drag carries: a plain string with a prefix, so that the
/// image area (AppKit) can recognise it too.
enum PaletteDrag {
    static let prefix = "x1scan-palette:"

    static func payload(_ id: PaletteID) -> String { prefix + id.rawValue }

    static func palette(from string: String) -> PaletteID? {
        guard string.hasPrefix(prefix) else { return nil }
        return PaletteID(rawValue: String(string.dropFirst(prefix.count)))
    }
}

private extension View {
    /// Accepts a dragged palette and moves it before `target` (nil: to the end).
    /// A floating palette dropped here is attached again.
    func paletteDropTarget(model: AppModel, before target: PaletteID?) -> some View {
        dropDestination(for: String.self) { items, _ in
            guard let id = items.compactMap(PaletteDrag.palette(from:)).first,
                  model.layout.registry.contains(id) else { return false }
            model.layout.attach(id)
            model.layout.move(id, before: target)
            return true
        }
    }
}

/// One palette in the expanded column: a header that folds it, and its content.
private struct PaletteSection: View {
    @Bindable var model: AppModel
    let id: PaletteID

    var body: some View {
        let collapsed = model.layout.layout.isCollapsed(id)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { model.layout.toggleCollapsed(id) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                        .foregroundStyle(.secondary)
                    Image(systemName: symbol)
                        .foregroundStyle(.secondary)
                    Text(Strings.paletteTitle(id))
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .draggable(PaletteDrag.payload(id)) { PaletteDragPreview(id: id) }
            .accessibilityValue(collapsed ? Text("Collapsed", comment: "Palette state") : Text("Expanded", comment: "Palette state"))
            .contextMenu { PaletteMenu(model: model, id: id) }

            if !collapsed {
                PaletteContent(model: model, id: id)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
    }

    private var symbol: String { model.layout.registry.descriptor(for: id)?.symbolName ?? "square" }
}

private struct PaletteDragPreview: View {
    let id: PaletteID

    var body: some View {
        Text(Strings.paletteTitle(id))
            .font(.headline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: .rect(cornerRadius: 8))
    }
}

/// Context menu of a palette header or icon.
struct PaletteMenu: View {
    @Bindable var model: AppModel
    let id: PaletteID

    var body: some View {
        let order = model.layout.layout.order
        let index = order.firstIndex(of: id) ?? 0
        Button(String(localized: "Move Up", comment: "Palette menu")) { model.layout.move(id, to: index - 1) }
            .disabled(index == 0)
        Button(String(localized: "Move Down", comment: "Palette menu")) { model.layout.move(id, to: index + 1) }
            .disabled(index == order.count - 1)
        Divider()
        Button(String(localized: "Detach", comment: "Palette menu: open in a floating panel")) {
            FloatingPalettes.detach(id, model: model)
        }
        Button(String(localized: "Hide", comment: "Palette menu")) { model.layout.toggleHidden(id) }
    }
}

/// Icon of the icon bar; a click opens or closes the palette beside the bar.
private struct PaletteIconButton: View {
    @Bindable var model: AppModel
    let id: PaletteID

    var body: some View {
        let open = model.layout.layout.openInIconBar.contains(id)
        Button {
            model.layout.toggleOverlay(id)
        } label: {
            Image(systemName: model.layout.registry.descriptor(for: id)?.symbolName ?? "square")
                .font(.system(size: 16))
                .frame(width: 34, height: 34)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(open ? Color.accentColor : Color.primary)
        .background {
            if open { RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.18)) }
        }
        .draggable(PaletteDrag.payload(id)) { PaletteDragPreview(id: id) }
        .contextMenu { PaletteMenu(model: model, id: id) }
        .help(Strings.paletteTitle(id))
        .accessibilityLabel(Strings.paletteTitle(id))
        .accessibilityValue(open ? Text("Expanded", comment: "Palette state") : Text("Collapsed", comment: "Palette state"))
    }
}

/// Icon-bar mode: the open palettes, stacked top to bottom beside the bar,
/// over the image area.
struct IconBarStackView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(model.layout.layout.iconBarStack, id: \.self) { id in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(Strings.paletteTitle(id)).font(.headline)
                            Spacer()
                            Button {
                                model.layout.toggleOverlay(id)
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.borderless)
                            .help(Text("Close", comment: "Tooltip: close a palette opened from the icon bar"))
                        }
                        .draggable(PaletteDrag.payload(id)) { PaletteDragPreview(id: id) }
                        .contextMenu { PaletteMenu(model: model, id: id) }
                        PaletteContent(model: model, id: id)
                    }
                    .padding(12)
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
                    .shadow(radius: 4, y: 1)
                }
            }
            .padding(8)
        }
        .scrollIndicators(.automatic)
        .frame(width: 296)
    }
}

/// The content of a palette, wherever it is hosted: the column, the stack
/// beside the icon bar, or a floating panel.
struct PaletteContent: View {
    @Bindable var model: AppModel
    let id: PaletteID

    var body: some View {
        switch id {
        case .histogram: HistogramPaletteView(model: model)
        case .info: InfoPaletteView(model: model)
        case .export: ExportPaletteView(model: model)
        default: EmptyView()
        }
    }
}
