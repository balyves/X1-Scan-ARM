// SPDX-License-Identifier: MIT
import SwiftUI
import X1ScanCore

/// RGB histogram of the corrected values (what is exported), linear.
struct HistogramPaletteView: View {
    @Bindable var model: AppModel
    @AppStorage("HistogramLogarithmic") private var logarithmic = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let bins = model.histogram.normalized(logarithmic: logarithmic)
            Canvas { context, size in
                context.blendMode = .plusLighter
                for (channel, color) in [(0, Color.red), (1, Color.green), (2, Color.blue)] {
                    context.fill(path(bins[channel], in: size), with: .color(color.opacity(0.75)))
                }
            }
            .frame(height: 110)
            .background(Color.black.opacity(0.85), in: .rect(cornerRadius: 6))
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
