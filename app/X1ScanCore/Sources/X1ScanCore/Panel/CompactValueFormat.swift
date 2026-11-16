// SPDX-License-Identifier: MIT
import Foundation

/// How a number is edited in a compact slider row: its range, its default
/// value (restored by a double-click on the label), its step and the digits
/// shown. No interface here, so that it can be tested.
public struct CompactValueFormat: Sendable, Hashable {
    public let range: ClosedRange<Double>
    public let defaultValue: Double
    /// Values are multiples of `step` from the lower bound; nil: continuous.
    public let step: Double?
    public let fractionDigits: Int

    public init(range: ClosedRange<Double>, defaultValue: Double, step: Double? = nil, fractionDigits: Int = 0) {
        precondition(range.contains(defaultValue), "default value outside the range")
        precondition(step.map { $0 > 0 } ?? true, "step must be positive")
        precondition(fractionDigits >= 0)
        if let step {
            // The step must be shown exactly with these digits (0.25 needs two).
            let scaled = step * pow(10, Double(fractionDigits))
            precondition(abs(scaled - scaled.rounded()) < 1e-9, "step needs more fraction digits")
        }
        self.range = range
        self.defaultValue = defaultValue
        self.step = step
        self.fractionDigits = fractionDigits
    }

    /// An integer setting: step 1, no decimals.
    public init(integers range: ClosedRange<Int>, defaultValue: Int) {
        self.init(range: Double(range.lowerBound)...Double(range.upperBound),
                  defaultValue: Double(defaultValue), step: 1, fractionDigits: 0)
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
