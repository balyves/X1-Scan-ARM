// SPDX-License-Identifier: MIT
import SwiftUI
import X1ScanCore

/// The Framing section (lot 1b), always in the Prepare tab: orientation,
/// proportions, fine angle, straightening, the crop grid and its tint, the
/// constraint. Before lot 1b these options appeared at the top of the panel
/// only while cropping. While the Crop or Straightening Rule tool is
/// selected (crop mode), the section is lightly tinted and its title row
/// carries Done and Reset (`FramingModeButtons`).
struct FramingSection: View {
    @Bindable var model: AppModel
    @State private var customShown = false
    @State private var customWidth = ""
    @State private var customHeight = ""

    private static let angleFormat = CompactValueFormat(
        range: CropSettings.angleRange, defaultValue: 0, step: CropSettings.angleStep, fractionDigits: 0,
        finerFractionDigits: 1)  // whole degrees; the rule's tenths are shown, not typed (lot 1b)

    var body: some View {
        OrientationRow(model: model)
        proportionsRow
        CompactSliderRow(value: Binding { model.recipe.crop.angle } set: { model.setCropAngle($0) },
                         format: Self.angleFormat,
                         texts: Strings.sliderRow(label: Strings.cropAngle, unit: "°", format: Self.angleFormat))
            // An angle typed and confirmed with Return: back to the image, so that X, ← → and
            // Return act on the frame again at once (as after the zoom field).
            .onSubmit { if model.tools.showsCropOptions { NSApp.keyWindow?.focusImageCanvas() } }
        straightenRow
        let grid = Strings.gridTool
        CompactControlRow(grid) {
            CompactPopUp(grid, help: Strings.cropGridHelp,
                         selection: Binding { model.cropGridKind } set: { model.cropGridKind = $0 },
                         sections: [[.init(Strings.cropGridNone, nil)],
                                    GridKind.allCases.map { .init(Strings.gridKind($0), Optional($0)) }])
        }
        tintRow
        CompactDetailRow {
            Toggle(Strings.cropConstrain,
                   isOn: Binding { model.recipe.crop.constrained } set: { model.setCropConstrained($0) })
                .toggleStyle(.checkbox)
                .help(Strings.cropConstrainHelp)
        }
    }

    /// Tint: the colour and opacity of the grid lines, the same settings as
    /// the grid button's menu and Image > Grid.
    private var tintRow: some View {
        let label = Strings.gridTint
        return CompactControlRow(label) {
            HStack(spacing: CompactPanelMetrics.columnSpacing) {
                CompactPopUp(Strings.gridColorMenu, help: Strings.gridColorHelp,
                             selection: Binding { model.grid.color } set: { model.grid.color = $0 },
                             items: GridColor.allCases.map { .init(Strings.gridColor($0), $0) })
                CompactPopUp(Strings.gridOpacityMenu, help: Strings.gridOpacityHelp,
                             selection: Binding { Self.nearestOpacity(model.grid.opacity) } set: { model.grid.opacity = $0 },
                             items: GridSettings.opacityChoices.map { .init(Strings.gridOpacity($0), $0) })
            }
        }
    }

    /// The menu's choice for a saved opacity (a value from another version falls on the nearest).
    private static func nearestOpacity(_ value: Double) -> Double {
        GridSettings.opacityChoices.min { abs($0 - value) < abs($1 - value) } ?? value
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

/// Done and Reset, on the Framing title row while cropping. Done (Return)
/// goes back to the tool used before; Reset gives the whole image and no
/// angle; Esc cancels the changes made since the mode began.
struct FramingModeButtons: View {
    @Bindable var model: AppModel

    var body: some View {
        Button { model.resetCrop() } label: { Image(systemName: "arrow.counterclockwise") }
            .buttonStyle(.bordered)
            .disabled(model.cropIsReset)
            .help(Strings.cropResetHelp)
            .accessibilityLabel(Strings.cropReset)
        Button(Strings.cropDone) { model.finishCrop() }
            .buttonStyle(.borderedProminent)
            .help(Strings.cropDoneHelp)
    }
}

/// Orientation (lot 1): quarter turns and mirror, for the display and the
/// export; the letter F drawn as the image is turned shows the state at a glance.
private struct OrientationRow: View {
    @Bindable var model: AppModel

    var body: some View {
        let label = String(localized: "Orientation", comment: "Panel label: turns and mirror of the image")
        let orientation = model.recipe.orientation
        CompactControlRow(label) {
            HStack(spacing: CompactPanelMetrics.columnSpacing) {
                button("rotate.left", Strings.withShortcut(Strings.rotateCounterclockwise, "⌘[")) {
                    model.rotateCounterclockwise()
                }
                button("rotate.right", Strings.withShortcut(Strings.rotateClockwise, "⌘]")) { model.rotateClockwise() }
                button("arrow.left.and.right.righttriangle.left.righttriangle.right", Strings.mirrorHorizontally) {
                    model.mirrorHorizontally()
                }
                Spacer(minLength: 0)
                OrientationGlyph(orientation: orientation)
                    .help(Strings.orientationDescription(orientation))
                    .accessibilityElement()
                    .accessibilityLabel(label)
                    .accessibilityValue(Strings.orientationDescription(orientation))
            }
        }
    }

    private func button(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            // VoiceOver hears the new state without going to the glyph.
            AccessibilityNotification.Announcement(Strings.orientationDescription(model.recipe.orientation)).post()
        } label: {
            Image(systemName: symbol)
        }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The letter F turned and mirrored like the image: a state, not a control
/// (secondary colour, no frame, no animation).
private struct OrientationGlyph: View {
    let orientation: Orientation

    var body: some View {
        Text(verbatim: "F")
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
            .scaleEffect(x: orientation.mirrored ? -1 : 1, y: 1)
            .rotationEffect(.degrees(Double(orientation.quarterTurns) * 90))
            .frame(width: CompactPanelMetrics.unitWidth)
    }
}
