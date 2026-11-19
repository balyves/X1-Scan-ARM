// SPDX-License-Identifier: MIT
import SwiftUI
import X1ScanCore

/// Exposure section (lot 1): how much of the CCD's range the last preview
/// uses, measured read-only on its raw samples. The thresholds are
/// provisional (`ExposureThresholds.provisional`).
struct ExposureSection: View {
    @Bindable var model: AppModel

    /// The advice ("try a quality mode") points to modes that do not exist yet: hidden in lot 1.
    static let showsAdvice = false

    var body: some View {
        if let reading = model.exposure {
            ExposureGauge(reading: reading, thresholds: .provisional)
                .frame(height: CompactPanelMetrics.gaugeHeight)
                .help(Strings.exposureHelp)
                .accessibilityElement()
                .accessibilityLabel(Strings.exposureGaugeLabel)
                .accessibilityValue(Strings.exposureSummary(reading))
            Text(Strings.exposureLine(reading))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(Strings.exposureHelp)
                .accessibilityHidden(true)  // already the gauge's value
            if Self.showsAdvice, let advice = Strings.exposureAdvice(reading) {
                Label(advice, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(Strings.exposureEmpty)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Toggle(Strings.exposureZonesToggle, isOn: $model.showsExposureZones)
            .toggleStyle(.checkbox)
            .disabled(model.exposure == nil)
            .help(Strings.exposureZonesHelp)
    }
}

/// The bar: the full raw scale, left to right. Hatched: below the noise
/// floor; green: the levels the preview uses; red: above the clipping
/// level, solid when pixels are clipped.
private struct ExposureGauge: View {
    /// Between hatch lines; also the narrowest noise zone drawn, so that it stays visible.
    static let hatchSpacing: CGFloat = 3
    let reading: ExposureReading
    let thresholds: ExposureThresholds

    var body: some View {
        Canvas { context, size in
            let full = CGRect(origin: .zero, size: size)
            let rounded = Path(roundedRect: full, cornerRadius: size.height / 5)
            context.clip(to: rounded)
            context.fill(rounded, with: .color(.secondary.opacity(0.18)))
            func x(_ fraction: Double) -> Double { size.width * min(max(fraction, 0), 1) }
            let floor = Double(thresholds.noiseFloor) / thresholds.fullScale
            let ceiling = Double(thresholds.clipLevel) / thresholds.fullScale
            // Noise zone: hatched.
            let noise = CGRect(x: 0, y: 0, width: max(x(floor), Self.hatchSpacing), height: size.height)
            var hatch = Path()
            var offset = -size.height
            while offset < noise.width {
                hatch.move(to: CGPoint(x: offset, y: size.height))
                hatch.addLine(to: CGPoint(x: offset + size.height, y: 0))
                offset += Self.hatchSpacing
            }
            context.drawLayer { layer in
                layer.clip(to: Path(noise))
                layer.stroke(hatch, with: .color(.secondary.opacity(0.7)), lineWidth: 1)
            }
            // Levels used.
            let low = max(reading.low, floor), high = min(reading.high, ceiling)
            if high > low {
                context.fill(Path(CGRect(x: x(low), y: 0, width: x(high) - x(low), height: size.height)),
                             with: .color(.green))
            }
            // Clipping zone.
            let clip = CGRect(x: x(ceiling), y: 0, width: size.width - x(ceiling), height: size.height)
            // Solid red as soon as the text shows clipping (0.1 % and more, as rounded).
            let shown = reading.clippedFraction >= Strings.clippedShownFrom
            context.fill(Path(clip), with: .color(.red.opacity(shown ? 1 : 0.25)))
        }
    }
}
