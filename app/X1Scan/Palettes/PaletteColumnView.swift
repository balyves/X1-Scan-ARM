// SPDX-License-Identifier: MIT
import SwiftUI
import X1ScanCore

/// The right column: palettes in full, or an icon bar whose icons show a
/// palette over the image.
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
                    Divider()
                }
            }
        }
        .scrollIndicators(.automatic)
    }

    private var iconBar: some View {
        VStack(spacing: 6) {
            ForEach(model.layout.layout.visibleDockedPalettes, id: \.self) { id in
                PaletteIconButton(model: model, id: id)
            }
            Spacer()
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity)
    }
}

/// One palette in the expanded column: a header that folds it, and its content.
private struct PaletteSection: View {
    @Bindable var model: AppModel
    let id: PaletteID

    var body: some View {
        let layout = model.layout.layout
        let collapsed = layout.isCollapsed(id)
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

/// Context menu of a palette header.
private struct PaletteMenu: View {
    @Bindable var model: AppModel
    let id: PaletteID

    var body: some View {
        let order = model.layout.layout.order
        let index = order.firstIndex(of: id) ?? 0
        Button(String(localized: "Move Up", comment: "Palette menu")) { model.layout.move(id, to: index - 1) }
            .disabled(index == 0)
        Button(String(localized: "Move Down", comment: "Palette menu")) { model.layout.move(id, to: index + 1) }
            .disabled(index == order.count - 1)
        Button(String(localized: "Hide", comment: "Palette menu")) { model.layout.toggleHidden(id) }
        Divider()
        // Floating palettes are modelled (PalettePlacement.floating) but come later.
        Button(String(localized: "Open in Separate Window", comment: "Palette menu, not available yet")) {}
            .disabled(true)
    }
}

/// Icon of the icon bar; a click shows the palette over the image.
private struct PaletteIconButton: View {
    @Bindable var model: AppModel
    let id: PaletteID

    var body: some View {
        let shown = model.layout.overlayPalette == id
        Button {
            model.layout.toggleOverlay(id)
        } label: {
            Image(systemName: model.layout.registry.descriptor(for: id)?.symbolName ?? "square")
                .font(.system(size: 16))
                .frame(width: 34, height: 34)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(shown ? Color.accentColor : Color.primary)
        .background {
            if shown { RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.18)) }
        }
        .help(Strings.paletteTitle(id))
        .accessibilityLabel(Strings.paletteTitle(id))
        .popover(isPresented: Binding(get: { model.layout.overlayPalette == id },
                                      set: { if !$0, model.layout.overlayPalette == id { model.layout.closeOverlay() } }),
                 arrowEdge: .leading) {
            VStack(alignment: .leading, spacing: 10) {
                Text(Strings.paletteTitle(id)).font(.headline)
                PaletteContent(model: model, id: id)
            }
            .padding(14)
            .frame(width: 280)
        }
    }
}

/// The content of a palette, wherever it is hosted: the column, the overlay
/// from the icon bar, and later a floating window.
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
