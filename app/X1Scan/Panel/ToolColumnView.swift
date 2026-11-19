// SPDX-License-Identifier: MIT
import SwiftUI
import X1ScanCore

/// The narrow tool bar between the image and the settings panel: only tools
/// that act on the preview (lot 1).
struct ToolColumnView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 6) {
            tool(.hand, "hand.raised")
            tool(.zoom, "plus.magnifyingglass")
            tool(.crop, "crop")
            tool(.straighten, "ruler")
            gridButton
            Spacer()
        }
        .padding(.top, 10)
        .frame(width: 36)
        .frame(maxHeight: .infinity)
    }

    private func tool(_ tool: Tool, _ symbol: String) -> some View {
        let selected = model.tools.effective == tool
        return Button {
            model.tools.selected = tool
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.accentColor : Color.primary)
        .background { if selected { RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.18)) } }
        .help("\(Strings.toolName(tool)) (\(tool.key.uppercased()))")
        .accessibilityLabel(Strings.toolName(tool))
    }

    /// Shows or hides the grid (⌘'); the kind is chosen in its menu (right click) or in Image > Grid.
    private var gridButton: some View {
        let shown = model.grid.isVisible
        return Button {
            model.toggleGrid()
        } label: {
            Image(systemName: "grid")
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(shown ? Color.accentColor : Color.primary)
        .background { if shown { RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.18)) } }
        .help(Strings.withShortcut(Strings.gridTool, "⌘'"))
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
            Button(model.grid.isVisible ? Strings.hideGrid : Strings.showGrid) { model.toggleGrid() }
        }
    }
}
