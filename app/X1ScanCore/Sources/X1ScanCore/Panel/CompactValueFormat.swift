// SPDX-License-Identifier: MIT
import Foundation

/// How a number is edited in a compact slider row: its range, its default
/// value (restored by a double-click on the label), its step and the digits
/// shown. No interface here, so that it can be tested.
public struct CompactValueFormat: Sendable, Hashable {
    /// How the slider spreads the range. The field always shows and accepts
    /// the exact value.
    public enum SliderScale: Sendable, Hashable {
        case linear
        /// Equal ratios take equal lengths: for wide ranges (50 to 10 000 ppi),
        /// where a linear slider would crowd the usual values at one end.
        case logarithmic
    }

    public let range: ClosedRange<Double>
    public let defaultValue: Double
    /// Values are multiples of `step` from the lower bound; nil: continuous.
    public let step: Double?
    public let fractionDigits: Int
    public let sliderScale: SliderScale

    public init(range: ClosedRange<Double>, defaultValue: Double, step: Double? = nil, fractionDigits: Int = 0,
                sliderScale: SliderScale = .linear) {
        precondition(range.lowerBound.isFinite && range.upperBound.isFinite, "the range must be finite")
        precondition(range.contains(defaultValue), "default value outside the range")
        precondition(step.map { $0 > 0 } ?? true, "step must be positive")
        precondition(fractionDigits >= 0)
        precondition(sliderScale == .linear || range.lowerBound > 0, "a logarithmic slider needs a positive range")
        if let step {
            // The step must be shown exactly with these digits (0.25 needs two).
            let scaled = step * pow(10, Double(fractionDigits))
            precondition(abs(scaled - scaled.rounded()) < 1e-9, "step needs more fraction digits")
        }
        self.range = range
        self.defaultValue = defaultValue
        self.step = step
        self.fractionDigits = fractionDigits
        self.sliderScale = sliderScale
    }

    /// An integer setting: step 1, no decimals.
    public init(integers range: ClosedRange<Int>, defaultValue: Int, sliderScale: SliderScale = .linear) {
        self.init(range: Double(range.lowerBound)...Double(range.upperBound),
                  defaultValue: Double(defaultValue), step: 1, fractionDigits: 0, sliderScale: sliderScale)
    }

    /// Where `value` sits on the slider, 0...1.
    public func sliderPosition(for value: Double) -> Double {
        let value = clamped(value)
        let span: Double
        let offset: Double
        switch sliderScale {
        case .linear:
            span = range.upperBound - range.lowerBound
            offset = value - range.lowerBound
        case .logarithmic:
            span = log(range.upperBound / range.lowerBound)
            offset = log(value / range.lowerBound)
        }
        return span > 0 ? min(max(offset / span, 0), 1) : 0
    }

    /// The value at a slider position (0...1), clamped to the range and the step.
    public func value(forSliderPosition position: Double) -> Double {
        guard position.isFinite else { return defaultValue }
        let position = min(max(position, 0), 1)
        return switch sliderScale {
        case .linear: clamped(range.lowerBound + position * (range.upperBound - range.lowerBound))
        case .logarithmic: clamped(range.lowerBound * pow(range.upperBound / range.lowerBound, position))
        }
    }

    /// `value` inside the range, on the step, rounded to the digits shown.
    /// Not a number: the default value.
    public func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return defaultValue }
        var result = min(max(value, range.lowerBound), range.upperBound)
        if let step {
            result = range.lowerBound + ((result - range.lowerBound) / step).rounded() * step
            if result > range.upperBound { result -= step }
        }
        let scale = pow(10, Double(fractionDigits))
        result = (result * scale).rounded() / scale
        return min(max(result, range.lowerBound), range.upperBound)
    }

    /// The value as shown in the field: the locale's decimal separator, no grouping.
    public func text(for value: Double, locale: Locale) -> String {
        clamped(value).formatted(.number
            .precision(.fractionLength(fractionDigits))
            .grouping(.never)
            .locale(locale))
    }

    /// The value typed in the field, clamped; nil if it is not a number (the
    /// field then shows the current value again). Same rule as the zoom field
    /// (`Viewport.magnification(fromTyped:)`): comma and full stop are both the
    /// decimal separator, whatever the locale ("12,5" in a locale that writes
    /// 12.5); spaces and apostrophes (thousands in some locales) are ignored.
    public func value(parsing text: String) -> Double? {
        let cleaned = text
            .filter { !$0.isWhitespace && $0 != "'" && $0 != "\u{2019}" }
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let number = Double(cleaned), number.isFinite else { return nil }
        return clamped(number)
    }
}
