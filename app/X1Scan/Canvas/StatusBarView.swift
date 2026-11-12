// SPDX-License-Identifier: MIT
import SwiftUI
import X1ScanCore

/// Bottom bar: preview status and progress, image size, zoom.
struct StatusBarView: View {
    @Bindable var model: AppModel

    var body: some View {
        let session = model.session
        HStack(spacing: 12) {
            if session.state == .stopping {
                ProgressView().controlSize(.small)
            }
            Text(Strings.sessionStatus(session))
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
            Text(Strings.zoom(model.viewport.magnification))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 44, alignment: .trailing)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(.bar)
    }

    private func statusColor(_ state: PreviewSession.State) -> Color {
        switch state {
        case .failed: .red
        case .stopped(let outcome?) where outcome != .stoppedAndReady: .red
        default: .primary
        }
    }
}
