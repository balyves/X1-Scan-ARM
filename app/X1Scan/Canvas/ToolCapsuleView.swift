// SPDX-License-Identifier: MIT
import SwiftUI
import X1ScanCore

/// The vertical tool bar: a glass capsule floating over the left of the image.
/// (PaletteLayout.toolBarPlacement can later dock it as a fixed column.)
struct ToolCapsuleView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Tool.allCases, id: \.self) { tool in
                Button {
                    model.tools.selected = tool
                } label: {
                    Image(systemName: symbol(tool))
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.tools.effective == tool ? Color.accentColor : Color.primary)
                .background {
                    if model.tools.effective == tool {
                        Circle().fill(Color.accentColor.opacity(0.18))
                    }
                }
                .help(Text("\(Strings.toolName(tool)) (\(String(tool.key).uppercased()))",
                           comment: "Tool tooltip: name and key"))
                .accessibilityLabel(Strings.toolName(tool))
                .accessibilityAddTraits(model.tools.selected == tool ? .isSelected : [])
            }
        }
        .padding(6)
        .glassEffect(.regular, in: .capsule)
    }

    private func symbol(_ tool: Tool) -> String {
        switch tool {
        case .hand: "hand.raised"
        case .zoom: "plus.magnifyingglass"
        case .crop: "crop"
        }
    }
}
