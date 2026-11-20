// SPDX-License-Identifier: MIT
import SwiftUI
import X1ScanCore

/// Above the image while discovery mode is on (lot A, step C): always
/// visible, with the way out. Nothing (no height) otherwise.
struct DiscoveryBanner: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.discoveryMode {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                // One line, truncated in a narrow image area: the way out stays visible.
                Text(Strings.discoveryBanner)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(-1)
                Spacer(minLength: 8)
                Button(Strings.leaveDiscovery) { model.leaveDiscovery() }
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(model.isBusy)
                    .help(Strings.leaveDiscoveryHelp)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            // An opaque window background under a light tint: readable in light and dark mode.
            .background {
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    // The system's adaptive yellow, lightly: a warning tint (lot A decision).
                    Color(nsColor: .systemYellow).opacity(0.18)
                }
            }
            .overlay(alignment: .bottom) { Divider() }
            .accessibilityElement(children: .contain)
        }
    }
}
