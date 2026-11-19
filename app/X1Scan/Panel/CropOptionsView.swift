// SPDX-License-Identifier: MIT
import SwiftUI
import X1ScanCore

/// Crop and straighten options (lot 1): shown at the top of the panel while
/// the Crop or Straightening Rule tool is selected, on a lightly tinted
/// background (the user's brief: a mode, visibly apart from the settings).
/// Done goes back to the hand.
struct CropOptionsSection: View {
    @Bindable var model: AppModel
    @State private var customShown = false
    @State private var customWidth = ""
    @State private var customHeight = ""

    private static let angleFormat = CompactValueFormat(
        range: CropSettings.angleRange, defaultValue: 0, step: CropSettings.angleStep, fractionDigits: 1)

    var body: some View {
        VStack(alignment: .leading, spacing: CompactPanelMetrics.rowSpacing) {
            HStack(spacing: CompactPanelMetrics.columnSpacing) {
                Text(Strings.cropTitle)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button(Strings.cropDone) { model.tools.selected = .hand }
                    .buttonStyle(.borderedProminent)
                    .help(Strings.withShortcut(Strings.cropDone, "↩"))
            }
            proportionsRow
            CompactSliderRow(value: Binding { model.recipe.crop.angle } set: { model.setCropAngle($0) },
                             format: Self.angleFormat,
                             texts: Strings.sliderRow(label: Strings.cropAngle, unit: "°", format: Self.angleFormat))
            straightenRow
            let grid = Strings.gridTool
            CompactControlRow(grid) {
                CompactPopUp(grid, help: Strings.cropGridHelp,
                             selection: Binding { model.cropGridKind } set: { model.cropGridKind = $0 },
                             sections: [[.init(Strings.cropGridNone, nil)],
                                        GridKind.allCases.map { .init(Strings.gridKind($0), Optional($0)) }])
            }
            CompactDetailRow {
                Toggle(Strings.cropConstrain,
                       isOn: Binding { model.recipe.crop.constrained } set: { model.setCropConstrained($0) })
                    .toggleStyle(.checkbox)
                    .help(Strings.cropConstrainHelp)
            }
        }
        .padding(CompactPanelMetrics.sectionInsets)
        .background(Color.accentColor.opacity(0.07))
    }

    // MARK: Proportions

    private enum Choice: Hashable {
        case free, original, ratio(Double, Double), custom
    }

    private var choice: Choice {
        switch model.recipe.crop.aspect {
        case .free: .free
        case .original: .original
        case .ratio(let width, let height): .ratio(width, height)
        }
    }

    private var proportionsRow: some View {
        let label = Strings.cropProportions
        var presets = CropAspect.presets.compactMap { aspect -> CompactPopUp<Choice>.Item? in
            guard case .ratio(let width, let height) = aspect else { return nil }
            return .init(Strings.ratio(width, height), .ratio(width, height))
        }
        if case .ratio(let width, let height) = choice, !presets.contains(where: { $0.value == choice }) {
            presets.append(.init(Strings.ratio(width, height), .ratio(width, height)))  // a custom ratio in use
        }
        return CompactControlRow(label) {
            HStack(spacing: CompactPanelMetrics.columnSpacing) {
                CompactPopUp(label, help: Strings.cropProportionsHelp,
                             selection: Binding { choice } set: { choose($0) },
                             sections: [[.init(Strings.cropFree, .free), .init(Strings.cropOriginal, .original)],
                                        presets, [.init(Strings.cropCustom, .custom)]])
                    .popover(isPresented: $customShown, arrowEdge: .bottom) { customRatio }
                Button { model.toggleCropPortrait() } label: {
                    // The frame's real direction (portrait means "exchanged", not "upright").
                    Image(systemName: (model.cropRatio ?? model.cropFrameInDocument.map { $0.width / $0.height } ?? 1) < 1
                          ? "rectangle.portrait" : "rectangle")
                }
                .buttonStyle(.borderless)
                .help(Strings.withShortcut(Strings.cropSwap, "X"))
                .accessibilityLabel(Strings.cropSwap)
                .accessibilityValue(model.recipe.crop.portrait ? Strings.cropSwapped : Strings.cropAsNamed)
                Toggle(isOn: Binding { model.recipe.crop.locked } set: { model.setCropLocked($0) }) {
                    Image(systemName: model.recipe.crop.locked ? "lock.fill" : "lock.open")
                }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .help(Strings.cropLockHelp)
                .accessibilityLabel(Strings.cropLock)
            }
        }
    }

    private func choose(_ choice: Choice) {
        switch choice {
        case .free: model.setCropAspect(.free)
        case .original: model.setCropAspect(.original)
        case .ratio(let width, let height): model.setCropAspect(.ratio(width: width, height: height))
        case .custom: customShown = true
        }
    }

    /// Custom…: two numbers, width and height (13 × 18, 1 × 2…).
    private var customRatio: some View {
        VStack(alignment: .leading, spacing: CompactPanelMetrics.groupSpacing) {
            Text(Strings.cropCustomTitle).font(.callout.weight(.semibold))
            HStack(spacing: CompactPanelMetrics.columnSpacing) {
                TextField(Strings.cropCustomWidth, text: $customWidth)
                    .frame(width: CompactPanelMetrics.fieldWidth)
                Text(verbatim: "×")
                TextField(Strings.cropCustomHeight, text: $customHeight)
                    .frame(width: CompactPanelMetrics.fieldWidth)
            }
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            HStack {
                Spacer()
                Button(Strings.cancel) { customShown = false }
                    .keyboardShortcut(.cancelAction)
                Button(Strings.ok) {
                    if let aspect = CropAspect.custom(Self.number(customWidth) ?? 0, Self.number(customHeight) ?? 0) {
                        model.setCropAspect(aspect, asTyped: true)
                        customShown = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(CropAspect.custom(Self.number(customWidth) ?? 0, Self.number(customHeight) ?? 0) == nil)
            }
        }
        .controlSize(.small)
        .padding(CompactPanelMetrics.sectionInsets)
    }

    /// A typed number, by the panel's rule: comma or full stop, spaces and apostrophes ignored.
    private static let ratioFormat = CompactValueFormat(range: 0.01...10_000, defaultValue: 1, fractionDigits: 2)

    private static func number(_ text: String) -> Double? {
        ratioFormat.value(parsing: text)
    }

    // MARK: Straighten

    private var straightenRow: some View {
        let label = Strings.cropStraighten
        let ruleSelected = model.tools.selected == .straighten
        return CompactControlRow(label) {
            HStack(spacing: CompactPanelMetrics.columnSpacing) {
                Button(Strings.cropRule) {
                    model.tools.selected = ruleSelected ? .crop : .straighten
                }
                .tint(ruleSelected ? .accentColor : nil)
                .buttonStyle(.bordered)
                .help(Strings.withShortcut(Strings.cropRuleHelp, "R"))
                .accessibilityLabel(Strings.toolName(.straighten))
                .accessibilityAddTraits(ruleSelected ? .isSelected : [])
                // Detection of the frame's edges on the film comes in a later lot.
                Button(Strings.cropAutoEdges) {}
                    .buttonStyle(.bordered)
                    .disabled(true)
                    .help(Strings.cropAutoEdgesHelp)
            }
        }
    }
}
