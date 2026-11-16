// SPDX-License-Identifier: MIT
import SwiftUI
import X1ScanCore

/// RGB histogram of the corrected values (what is exported). Linear scale by
/// default, logarithmic as an option. Drawn straight on the panel
/// background, without a box. Channels add up in dark mode (overlaps turn
/// white) and multiply in light mode (overlaps turn neutral grey), so that
/// the drawing order does not tint the result and a neutral image reads as
/// neutral in both appearances.
struct HistogramView: View {
    @Bindable var model: AppModel
    @AppStorage("HistogramLogarithmic") private var logarithmic = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: CompactPanelMetrics.rowSpacing) {
            let bins = model.histogram.normalized(scale: logarithmic ? .logarithmic : .linear)
            let dark = colorScheme == .dark
            Canvas { context, size in
                context.blendMode = dark ? .plusLighter : .multiply
                for (channel, color) in Self.channelColors.enumerated() {
                    context.fill(path(bins[channel], in: size), with: .color(color.opacity(dark ? 0.75 : 0.45)))
                }
            }
            .frame(height: 90)
            .accessibilityLabel(Text("RGB histogram", comment: "Accessibility"))

            HStack {
                Toggle(String(localized: "Logarithmic", comment: "Histogram option"), isOn: $logarithmic)
                    .toggleStyle(.checkbox)
                Spacer()
                if model.histogram.pixelCount > 0 {
                    Text("\(model.histogram.pixelCount) pixels", comment: "Histogram pixel count")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .font(.caption)
        }
    }

    /// Pure sRGB primaries (data colours, not interface colours): the system
    /// red, green and blue are not primaries, so their overlaps would not add
    /// up to white nor multiply to grey.
    private static let channelColors = [Color(.sRGB, red: 1, green: 0, blue: 0),
                                        Color(.sRGB, red: 0, green: 1, blue: 0),
                                        Color(.sRGB, red: 0, green: 0, blue: 1)]

    private func path(_ values: [Double], in size: CGSize) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let step = size.width / CGFloat(values.count - 1)
        path.move(to: CGPoint(x: 0, y: size.height))
        for (index, value) in values.enumerated() {
            path.addLine(to: CGPoint(x: CGFloat(index) * step, y: size.height * (1 - CGFloat(value))))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }
}
