// SPDX-License-Identifier: MIT
import SwiftUI
import X1ScanCore

/// The narrow tool bar between the image and the settings panel (lot 1b),
/// in groups separated by a thin line: Navigate (hand, zoom), Frame (crop,
/// rule; they open Prepare > Framing), then at the bottom Show (grid,
/// exposure zones). Only tools that work are shown (the pipettes and the
/// densitometer come with lot 3).
struct ToolColumnView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 6) {
            tool(.hand, "hand.raised")
            tool(.zoom, "plus.magnifyingglass")
            separator
            tool(.crop, "crop")
            tool(.straighten, "ruler")
            Spacer()
            separator
            gridButton
            zonesButton
        }
        .padding(.vertical, 10)
        .frame(width: 36)
        .frame(maxHeight: .infinity)
    }

    /// Between two groups.
    private var separator: some View {
        Divider()
            .frame(width: 22)
            .padding(.vertical, 2)
            .accessibilityHidden(true)
    }

    private func tool(_ tool: Tool, _ symbol: String) -> some View {
        let selected = model.tools.effective == tool
        return Button {
            model.tools.selected = tool
        } label: {
            ToolIcon(symbol: symbol, highlighted: selected)
        }
        .buttonStyle(.plain)
        .help(Strings.toolHelp(tool))
        .accessibilityLabel(Strings.toolName(tool))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Exposure zones over the preview: the same setting as the checkbox of
    /// the Exposure section; available once a preview has been measured.
    private var zonesButton: some View {
        // What is drawn, not only the saved setting: no measured preview, no zones.
        let shown = model.showsExposureZones && model.exposure != nil
        return Button {
            model.showsExposureZones.toggle()
        } label: {
            ToolIcon(symbol: "exclamationmark.triangle", highlighted: shown)
        }
        .buttonStyle(.plain)
        .disabled(model.exposure == nil)
        .help(Strings.exposureZonesHelp)
        .accessibilityLabel(Strings.exposureZonesTool)
        .accessibilityValue(shown ? Strings.exposureZonesShown : Strings.exposureZonesHidden)
        .accessibilityAddTraits(shown ? .isSelected : [])
    }

    /// Shows or hides the grid (⌘'); the kind is chosen in its menu (right click) or in Image > Grid.
    private var gridButton: some View {
        let shown = model.grid.isVisible
        return Button {
            model.toggleGrid()
        } label: {
            ToolIcon(symbol: "grid", highlighted: shown)
        }
        .buttonStyle(.plain)
        .help(Strings.gridButtonHelp)
        .accessibilityLabel(Strings.gridTool)
        .accessibilityValue(shown ? Strings.gridKind(model.grid.kind) : Strings.gridHidden)
        .accessibilityAddTraits(shown ? .isSelected : [])
        .contextMenu {
            ForEach(GridKind.allCases, id: \.self) { kind in
                Toggle(Strings.gridKind(kind), isOn: Binding {
                    model.grid.isVisible && model.grid.kind == kind
                } set: { _ in
                    model.showGrid(kind)
                })
            }
            Divider()
            Menu(Strings.gridColorMenu) {
                ForEach(GridColor.allCases, id: \.self) { color in
                    Toggle(Strings.gridColor(color), isOn: Binding { model.grid.color == color } set: { _ in
                        model.grid.color = color
                    })
                }
            }
            Menu(Strings.gridOpacityMenu) {
                ForEach(GridSettings.opacityChoices, id: \.self) { opacity in
                    Toggle(Strings.gridOpacity(opacity), isOn: Binding { abs(model.grid.opacity - opacity) < 1e-9 } set: { _ in
                        model.grid.opacity = opacity
                    })
                }
            }
            Divider()
            Button(model.grid.isVisible ? Strings.hideGrid : Strings.showGrid) { model.toggleGrid() }
        }
    }
}

/// A button of the column: its symbol, tinted with a light background when
/// the tool is selected or the display it shows is on; dimmed when disabled.
private struct ToolIcon: View {
    let symbol: String
    let highlighted: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14))
            .frame(width: 28, height: 28)
            .contentShape(.rect)
            .foregroundStyle(highlighted ? Color.accentColor : Color.primary)
            .opacity(isEnabled ? 1 : 0.35)
            .background { if highlighted { RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.18)) } }
    }
}
