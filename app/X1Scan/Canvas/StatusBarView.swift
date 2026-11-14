// SPDX-License-Identifier: MIT
import SwiftUI
import X1ScanCore

/// Bottom bar: source and state ("Virtual X1 · Ready"), preview progress,
/// image size, zoom menu.
struct StatusBarView: View {
    @Bindable var model: AppModel

    var body: some View {
        let session = model.session
        HStack(spacing: 12) {
            if session.state == .stopping {
                ProgressView().controlSize(.small)
            }
            Text(Strings.statusLine(model.statusLine, session: session))
                .lineLimit(1)
                .foregroundStyle(statusColor(session.state))
            if session.state == .running {
                ProgressView(value: session.progress.fraction)
                    .frame(maxWidth: 220)
            }
            Spacer(minLength: 8)
            if let image = session.image {
                Text("\(image.width) × \(image.expectedHeight) px", comment: "Image size in the status bar")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ZoomComboBox(model: model, magnification: model.viewport.magnification, enabled: session.image != nil)
                .frame(width: 128)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(.bar)
    }

    private func statusColor(_ state: PreviewSession.State) -> Color {
        if model.statusLine.detail == .failed || model.statusLine.detail == .unavailable { return .red }
        guard model.statusLine.detail == .session else { return .primary }
        switch state {
        case .failed: return .red
        case .stopped(let outcome?) where outcome != .stoppedAndReady: return .red
        default: return .primary
        }
    }
}
