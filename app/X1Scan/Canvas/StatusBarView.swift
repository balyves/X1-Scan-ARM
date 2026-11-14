// SPDX-License-Identifier: MIT
import SwiftUI
import X1ScanCore

/// Bottom bar: scanner state ("Virtual X1 · Ready"), preview progress,
/// estimated size of the exported file, R G B under the pointer, zoom menu.
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
                    .frame(maxWidth: 160)
            }
            Spacer(minLength: 8)
            if let bytes = model.estimatedExportBytes {
                Text(Strings.estimatedSize(bytes))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .help(Text("Uncompressed size of the file an export would write now", comment: "Tooltip"))
            }
            RGBReadout(model: model)
            ZoomComboBox(model: model, magnification: model.viewport.magnification, enabled: session.image != nil)
                .frame(width: 118)
        }
        .font(.callout)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .frame(height: 26)
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

/// R G B of the pixel under the pointer, in the unit of Settings > Display;
/// the raw sensor values in the tooltip. Replaces the Info palette.
private struct RGBReadout: View {
    @Bindable var model: AppModel

    var body: some View {
        let unit = model.settings.rgbUnit
        HStack(spacing: 6) {
            if let reading = model.pixelReading {
                ForEach(0..<3, id: \.self) { channel in
                    HStack(spacing: 2) {
                        Text(verbatim: ["R", "G", "B"][channel])
                            .foregroundStyle([Color.red, .green, .blue][channel])
                            .font(.caption.weight(.semibold))
                        Text(Strings.rgbValue(reading.corrected[channel], unit: unit))
                            .monospacedDigit()
                            .frame(minWidth: unit == .sixteenBit ? 40 : 30, alignment: .trailing)
                    }
                }
            } else {
                Text(verbatim: "R – G – B –").foregroundStyle(.tertiary)
            }
        }
        .help(model.pixelReading.map {
            let shown = unit.isSRGBEncoded
                ? String(localized: "Values encoded in sRGB, as in an 8-bit export.", comment: "Tooltip of the RGB values")
                : String(localized: "Linear corrected values, as exported in 16 bits.", comment: "Tooltip of the RGB values")
            return String(localized: "x \($0.coordinate.x), y \($0.coordinate.y). \(shown) Raw sensor values: \($0.raw[0]), \($0.raw[1]), \($0.raw[2])",
                          comment: "Tooltip of the RGB values; %@ says which values are shown")
        } ?? "")
    }
}
