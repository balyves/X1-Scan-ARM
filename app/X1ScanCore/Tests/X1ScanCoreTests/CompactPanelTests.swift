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

    /// Lot 1b: the angle moves by whole degrees, but shows the rule's tenths.
    @Test func finerValuesSetElsewhereKeepTheirDigits() {
        let format = CompactValueFormat(range: -45...45, defaultValue: 0, step: 1, fractionDigits: 0,
                                        finerFractionDigits: 1)
        #expect(format.text(for: -1, locale: english) == "-1")
        #expect(format.text(for: -1.3, locale: french) == "-1,3", "a tenth from the rule is shown")
        #expect(format.text(for: 2.04, locale: english) == "2", "below a tenth: the whole degree")
        #expect(format.value(parsing: "-1,3") == -1, "typed values keep the step")
        #expect(format.value(forSliderPosition: 0.5) == 0 && format.value(forSliderPosition: 0.51) == 1)
        #expect(abs(format.sliderPosition(for: -1.3) - 43.7 / 90) < 1e-12, "the knob at the exact value")
        let plain = CompactValueFormat(range: -45...45, defaultValue: 0, step: 1)
        #expect(plain.text(for: -1.3, locale: english) == "-1", "without finer digits: the step")
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
        // Session of 2026-11-25: the Angle field and Return.
        let angle = CompactValueFormat(range: -45...45, defaultValue: 0, step: 1, fractionDigits: 0, finerFractionDigits: 1)
        #expect(angle.value(parsing: "-3") == -3)
        #expect(angle.value(parsing: "\u{2212}3") == -3, "typographic minus")
        #expect(angle.value(parsing: "\u{2013}3") == -3, "Option-hyphen")
        #expect(angle.value(parsing: "3°", unit: "°") == 3 && angle.value(parsing: "-3 °", unit: "°") == -3, "the row's unit")
        #expect(angle.value(parsing: "3°") == nil, "not the row's unit")
        #expect(angle.value(parsing: "3°5", unit: "°") == nil, "a unit inside the number")
        #expect(format.value(parsing: "50 %", unit: "%") == 50)
        let ppi = CompactValueFormat(range: 100...8_000, defaultValue: 2_000, fractionDigits: 0)
        #expect(ppi.value(parsing: "2400 ppi", unit: "ppi") == 2_400 && ppi.value(parsing: "2400 PPI", unit: "ppi") == 2_400)
        #expect(ppi.value(parsing: "300 %", unit: "ppi") == nil, "another unit is refused")
        var field = CompactFieldState(showing: "0")
        field.edit("-3°")
        #expect(field.commit(format: angle, current: 0, locale: Locale(identifier: "fr_CH"), unit: "°") == -3)
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
        layout.setFolded(.scan, true)
        #expect(layout.isFolded(.scan))
        layout.setFolded(.scan, true)
        #expect(layout.isFolded(.scan), "idempotent")
        layout.setFolded(.scan, false)
        #expect(!layout.isFolded(.scan))
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
        let expansion = panel.expansion(of: .scan)
        #expect(expansion.wrappedValue, "open at first launch")
        expansion.wrappedValue = false
        #expect(panel.layout.isFolded(.scan))
        let saved = try #require(defaults.data(forKey: "InspectorLayout"))
        #expect(try JSONDecoder().decode(InspectorLayout.self, from: saved).isFolded(.scan))
        expansion.wrappedValue = true
        #expect(!panel.layout.isFolded(.scan))
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

struct CompactPopUpIndexTests {
    private typealias PopUp = CompactPopUp<String?>
    private let sections: [[PopUp.Item]] = [
        [.init("Not specified", nil)],
        [.init("6×7", "a"), .init("4×5", "b")],
    ]

    @Test func separatorTakesAnIndex() {
        // Menu: 0 Not specified, 1 separator, 2 6×7, 3 4×5.
        #expect(PopUp.menuIndex(of: nil, in: sections) == 0)
        #expect(PopUp.menuIndex(of: "a", in: sections) == 2)
        #expect(PopUp.menuIndex(of: "b", in: sections) == 3)
        #expect(PopUp.menuIndex(of: "z", in: sections) == nil)
        #expect(PopUp.value(atMenuIndex: 0, in: sections) == .some(nil))
        #expect(PopUp.value(atMenuIndex: 1, in: sections) == nil, "the separator has no value")
        #expect(PopUp.value(atMenuIndex: 3, in: sections) == .some("b"))
        #expect(PopUp.value(atMenuIndex: 4, in: sections) == nil)
        #expect(PopUp.value(atMenuIndex: -1, in: sections) == nil)
    }

    @Test func emptySectionAddsNoSeparator() {
        let noHolders: [[PopUp.Item]] = [[.init("Not specified", nil)], []]
        #expect(PopUp.menuIndex(of: nil, in: noHolders) == 0)
        #expect(PopUp.value(atMenuIndex: 1, in: noHolders) == nil)
        let single: [[CompactPopUp<Int>.Item]] = [[.init("A", 1), .init("B", 2)]]
        #expect(CompactPopUp<Int>.value(atMenuIndex: 1, in: single) == 2)
    }

    @Test func noSeparatorFirstOrLast() {
        typealias Ints = CompactPopUp<Int>
        let sections: [[Ints.Item]] = [[], [.init("A", 1)], [], [.init("B", 2)], []]
        // Menu: 0 A, 1 separator, 2 B.
        #expect(Ints.menu(of: sections).map { $0?.title } == ["A", nil, "B"])
        #expect(Ints.menuIndex(of: 1, in: sections) == 0 && Ints.menuIndex(of: 2, in: sections) == 2)
        #expect(Ints.menu(of: [[], []]).isEmpty)
    }
}
