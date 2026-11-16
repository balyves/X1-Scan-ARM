// SPDX-License-Identifier: MIT
import SwiftUI
import X1ScanCore

/// RGB histogram of the corrected values (what is exported). Linear scale by
/// default, logarithmic as an option. Drawn straight on the panel
/// background, without a box: each channel is a light translucent fill with a
/// thin outline in its colour, the same in light and dark mode. Channels are
/// not blended into each other (blending turned overlaps mustard or khaki).
/// Where the three outlines coincide (a neutral image), they are drawn once
/// in a neutral colour: otherwise the last one drawn, blue, would hide the
/// others and suggest a blue cast. Known limit: where only two channels
/// coincide, the one drawn later hides the other (green over red).
struct HistogramView: View {
    @Bindable var model: AppModel
    @AppStorage("HistogramLogarithmic") private var logarithmic = false

    var body: some View {
        VStack(alignment: .leading, spacing: CompactPanelMetrics.rowSpacing) {
            // Linear: the top of the scale is the 99.5th percentile of the bins, so that a
            // few isolated peaks are cut instead of flattening the rest of the distribution.
            let bins = logarithmic ? model.histogram.normalized(scale: .logarithmic)
                : model.histogram.normalized(scale: .linear, peakPercentile: 0.995)
            Canvas { context, size in
                for (channel, color) in Self.channelColors.enumerated() {
                    context.fill(area(bins[channel], in: size), with: .color(color.opacity(0.12)))
                }
                let outlines = outlines(bins, in: size)
                let style = StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
                for (channel, color) in Self.channelColors.enumerated() {
                    context.stroke(outlines.channels[channel], with: .color(color), style: style)
                }
                context.stroke(outlines.shared, with: .color(.primary.opacity(0.7)), style: style)
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

    /// System red, green and blue: they adapt to light and dark mode, so the
    /// outlines keep their contrast on both backgrounds.
    private static let channelColors: [Color] = [.red, .green, .blue]

    /// The top of the bins as points, half a line inside the frame on every
    /// side, so that a 1 pt outline is never cut (full bins, empty bins, the
    /// first and the last bin).
    private func points(_ values: [Double], in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let step = (size.width - 1) / CGFloat(values.count - 1)
        let height = size.height - 1
        return values.enumerated().map { index, value in
            CGPoint(x: 0.5 + CGFloat(index) * step, y: 0.5 + height * (1 - CGFloat(value)))
        }
    }

    /// Outlines split by segment: where the three channels are within 1 pt of
    /// each other at both ends of a segment, it goes to `shared` (drawn once,
    /// neutral); elsewhere each channel draws its own segment.
    private func outlines(_ bins: [[Double]], in size: CGSize) -> (channels: [Path], shared: Path) {
        let all = bins.map { points($0, in: size) }
        var channels = [Path](repeating: Path(), count: all.count)
        var shared = Path()
        guard let count = all.first?.count, count > 1, all.allSatisfy({ $0.count == count }) else {
            return (channels, shared)
        }
        func together(_ index: Int) -> Bool {
            let ys = all.map { $0[index].y }
            return (ys.max() ?? 0) - (ys.min() ?? 0) <= 1
        }
        for index in 0..<(count - 1) {
            if together(index) && together(index + 1) {
                shared.move(to: all[0][index])
                shared.addLine(to: all[0][index + 1])
            } else {
                for channel in all.indices {
                    channels[channel].move(to: all[channel][index])
                    channels[channel].addLine(to: all[channel][index + 1])
                }
            }
        }
        return (channels, shared)
    }

    /// The area under a channel's outline, for the fill.
    private func area(_ values: [Double], in size: CGSize) -> Path {
        let points = points(values, in: size)
        guard let first = points.first, let last = points.last else { return Path() }
        var path = Path()
        path.move(to: CGPoint(x: first.x, y: size.height))
        for point in points { path.addLine(to: point) }
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.closeSubpath()
        return path
    }
}
