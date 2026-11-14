// SPDX-License-Identifier: MIT
import SwiftUI
import X1ScanCore

/// The narrow tool bar between the image and the settings panel. Tools that
/// do not work yet are disabled, with a tooltip.
struct ToolColumnView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 6) {
            tool(.hand, "hand.raised")
            tool(.zoom, "plus.magnifyingglass")
            tool(.crop, "crop")
            Divider().frame(width: 22)
            unavailable("rotate.right", String(localized: "Rotate", comment: "Tool, not available yet"))
            unavailable("plus.rectangle.on.rectangle", String(localized: "Add Frame", comment: "Tool, not available yet"))
            unavailable("wand.and.stars", String(localized: "Auto Adjust", comment: "Tool, not available yet"))
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

    private func unavailable(_ symbol: String, _ name: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14))
            .frame(width: 28, height: 28)
            .foregroundStyle(.tertiary)
            .help(String(localized: "\(name): not available yet", comment: "Tooltip of a disabled tool"))
            .accessibilityLabel(name)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(Text("Not available yet", comment: "Accessibility: disabled tool"))
    }
}
