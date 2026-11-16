// SPDX-License-Identifier: MIT
import Foundation
import SwiftUI
import Testing
@testable import X1ScanCore

struct CompactValueFormatTests {
    private let english = Locale(identifier: "en_US")
    /// Comma as decimal separator, space for thousands.
    private let french = Locale(identifier: "fr_FR")
    /// Full stop as decimal separator, apostrophe for thousands.
    private let swissFrench = Locale(identifier: "fr_CH")

    @Test func clampsToRangeAndStep() {
        let format = CompactValueFormat(range: 0...10, defaultValue: 5, step: 0.5, fractionDigits: 1)
        #expect(format.clamped(-3) == 0)
        #expect(format.clamped(42) == 10)
        #expect(format.clamped(3.3) == 3.5)
        #expect(format.clamped(3.2) == 3)
        #expect(format.clamped(.nan) == 5, "not a number: the default value")
        #expect(format.clamped(.infinity) == 5)
    }

    @Test func stepNeverPushesAboveTheUpperBound() {
        // 0...10 with step 3: 9 is the last step inside the range.
        let format = CompactValueFormat(range: 0...10, defaultValue: 0, step: 3)
        #expect(format.clamped(10) == 9)
        #expect(format.clamped(9.6) == 9)
    }

    @Test func roundsToTheDigitsShown() {
        let format = CompactValueFormat(range: 0...1, defaultValue: 0.5, fractionDigits: 2)
        #expect(format.clamped(0.123_4) == 0.12)
        #expect(format.text(for: 0.123_4, locale: english) == "0.12")
        #expect(format.text(for: 0.123_4, locale: french) == "0,12")
        #expect(format.text(for: 0.123_4, locale: swissFrench) == "0.12")
    }

    @Test func textHasNoGrouping() {
        let format = CompactValueFormat(integers: ScanSettings.resolutionRange, defaultValue: ScanSettings.defaultResolution)
        #expect(format.text(for: 10_000, locale: english) == "10000")
        #expect(format.text(for: 10_000, locale: french) == "10000")
        #expect(format.text(for: 10_000, locale: swissFrench) == "10000")
        #expect(format.text(for: 1_999.6, locale: english) == "2000")
    }

    @Test func parsesTypedText() {
        let format = CompactValueFormat(range: 0...100, defaultValue: 50, fractionDigits: 1)
        #expect(format.value(parsing: "12,5") == 12.5, "comma, as in fr_FR")
        #expect(format.value(parsing: "12.5") == 12.5, "full stop, as in fr_CH and en_US")
        #expect(format.value(parsing: " 1 000 ") == 100, "spaces ignored, then clamped")
        #expect(format.value(parsing: "1'000") == 100, "apostrophe ignored (fr_CH thousands)")
        #expect(format.value(parsing: "1\u{2019}000") == 100)
        #expect(format.value(parsing: "-4") == 0)
        #expect(format.value(parsing: "") == nil)
        #expect(format.value(parsing: "abc") == nil)
        #expect(format.value(parsing: "1,2,3") == nil)
        #expect(format.value(parsing: "nan") == nil)
        #expect(format.value(parsing: "inf") == nil)
    }

    @Test func integerFormatMatchesTheScanSettings() {
        let resolution = CompactValueFormat(integers: ScanSettings.resolutionRange, defaultValue: ScanSettings.defaultResolution)
        #expect(resolution.range == 50...10_000 && resolution.defaultValue == 2_000 && resolution.step == 1)
        #expect(resolution.value(parsing: "2400,7") == 2_401)
        let scale = CompactValueFormat(integers: ScanSettings.scaleRange, defaultValue: ScanSettings.defaultScalePercent)
        #expect(scale.defaultValue == Double(ScanSettings().scalePercent))
        #expect(resolution.defaultValue == Double(ScanSettings().resolution))
    }
}

@MainActor
struct CompactPanelBindingTests {
    @Test func roundingBindingWritesIntegers() {
        var stored = 7
        let source = Binding(get: { stored }, set: { stored = $0 })
        let double = Binding(rounding: source)
        #expect(double.wrappedValue == 7)
        double.wrappedValue = 41.6
        #expect(stored == 42)
        double.wrappedValue = .nan
        #expect(stored == 42, "not a number: unchanged")
    }

    @Test func sectionFoldingIsSetExplicitly() {
        var layout = InspectorLayout()
        layout.setFolded(.settings, true)
        #expect(layout.isFolded(.settings))
        layout.setFolded(.settings, true)
        #expect(layout.isFolded(.settings), "idempotent")
        layout.setFolded(.settings, false)
        #expect(!layout.isFolded(.settings))
    }
}

struct CompactFieldStateTests {
    private let format = CompactValueFormat(integers: ScanSettings.resolutionRange,
                                            defaultValue: ScanSettings.defaultResolution)
    private let locale = Locale(identifier: "en_US")

    @Test func untouchedFieldKeepsTheSliderValue() {
        // Click into the field, move the slider to 4000, leave the field: 4000 stays.
        var field = CompactFieldState(showing: "2000")
        field.show(format.text(for: 4_000, locale: locale))
        #expect(!field.isEdited)
        #expect(field.commit(format: format, current: 4_000, locale: locale) == nil)
        #expect(field.text == "4000")
    }

    @Test func typedTextIsApplied() {
        var field = CompactFieldState(showing: "2000")
        field.edit("2400,6")
        #expect(field.isEdited)
        #expect(field.commit(format: format, current: 2_000, locale: locale) == 2_401)
        #expect(field.text == "2401" && !field.isEdited)
    }

    @Test func textThatIsNotANumberShowsTheValueAgain() {
        var field = CompactFieldState(showing: "2000")
        field.edit("abc")
        #expect(field.commit(format: format, current: 2_000, locale: locale) == nil)
        #expect(field.text == "2000" && !field.isEdited)
    }

    @Test func showDropsTypingInProgress() {
        var field = CompactFieldState(showing: "2000")
        field.edit("31")
        field.show("2000")
        #expect(!field.isEdited && field.text == "2000")
    }
}

@MainActor
struct CompactPanelExpansionTests {
    @Test func expansionBindingFoldsAndSaves() throws {
        let suite = "CompactPanelExpansionTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let panel = PanelController(defaults: defaults)
        let expansion = panel.expansion(of: .settings)
        #expect(expansion.wrappedValue, "open at first launch")
        expansion.wrappedValue = false
        #expect(panel.layout.isFolded(.settings))
        let saved = try #require(defaults.data(forKey: "InspectorLayout"))
        #expect(try JSONDecoder().decode(InspectorLayout.self, from: saved).isFolded(.settings))
        expansion.wrappedValue = true
        #expect(!panel.layout.isFolded(.settings))
    }

    @Test func roundingBindingWritesOnlyChanges() {
        var stored = 7
        var writes = 0
        let source = Binding(get: { stored }, set: { stored = $0; writes += 1 })
        let double = Binding(rounding: source)
        double.wrappedValue = 7.2
        double.wrappedValue = 6.8
        #expect(writes == 0, "same integer: nothing written")
        double.wrappedValue = 8.4
        #expect(stored == 8 && writes == 1)
    }
}

struct CompactSliderScaleTests {
    @Test func linearSliderSpreadsTheRangeEvenly() {
        let format = CompactValueFormat(integers: ScanSettings.scaleRange, defaultValue: 100)
        #expect(format.sliderPosition(for: 1) == 0 && format.sliderPosition(for: 1_000) == 1)
        #expect(format.value(forSliderPosition: 0.5) == 501)
    }

    @Test func logarithmicSliderGivesEqualRatiosEqualLengths() {
        let format = CompactValueFormat(integers: ScanSettings.resolutionRange,
                                        defaultValue: ScanSettings.defaultResolution, sliderScale: .logarithmic)
        #expect(format.sliderPosition(for: 50) == 0 && format.sliderPosition(for: 10_000) == 1)
        // 50 → 10 000 is a ratio of 200; 2 000 is 40 × 50: log 40 / log 200 ≈ 0.696.
        #expect(abs(format.sliderPosition(for: 2_000) - log(40) / log(200)) < 1e-12)
        #expect(abs(format.sliderPosition(for: 1_000) - format.sliderPosition(for: 500)
                    - (format.sliderPosition(for: 2_000) - format.sliderPosition(for: 1_000))) < 1e-12,
                "each doubling takes the same length")
        #expect(format.value(forSliderPosition: 0) == 50 && format.value(forSliderPosition: 1) == 10_000)
        #expect(format.value(forSliderPosition: 0.5) == 707, "geometric middle, rounded to the step")
        for value in [50.0, 51, 300, 2_000, 4_000, 9_999, 10_000] {
            #expect(format.value(forSliderPosition: format.sliderPosition(for: value)) == value, "round trip \(value)")
        }
    }

    @Test func sliderPositionsAreClamped() {
        let format = CompactValueFormat(integers: ScanSettings.resolutionRange,
                                        defaultValue: ScanSettings.defaultResolution, sliderScale: .logarithmic)
        #expect(format.value(forSliderPosition: -1) == 50 && format.value(forSliderPosition: 2) == 10_000)
        #expect(format.value(forSliderPosition: .nan) == 2_000)
        #expect(format.sliderPosition(for: 1) == 0 && format.sliderPosition(for: 1e9) == 1)
        #expect(format.sliderPosition(for: .nan) == format.sliderPosition(for: 2_000), "not a number: the default")
    }

    @Test func continuousLogarithmicSlider() {
        let format = CompactValueFormat(range: 0.1...10, defaultValue: 1, fractionDigits: 2, sliderScale: .logarithmic)
        #expect(format.sliderPosition(for: 1) == 0.5, "1 is the geometric middle of 0.1...10")
        #expect(format.value(forSliderPosition: 0.5) == 1)
        #expect(format.value(forSliderPosition: 0.25) == 0.32, "√(0.1 × 1) ≈ 0.316, two digits")
    }
}
