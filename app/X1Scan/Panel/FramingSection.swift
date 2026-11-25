// SPDX-License-Identifier: MIT
import SwiftUI
import X1ScanCore

/// The Framing section (lot 1b), always in the Prepare tab: orientation,
/// proportions, fine angle, straightening, the crop grid and its tint, the
/// constraint. Before lot 1b these options appeared at the top of the panel
/// only while cropping. Its title row carries Reset, and Done in crop mode
/// (Crop or Straightening Rule tool), when the section is lightly tinted
/// (`FramingHeaderButtons`).
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
                         texts: Strings.sliderRow(label: Strings.cropAngle, unit: "°", format: Self.angleFormat,
                                                  help: Strings.tooltip(.angle)),
                         typingResetToken: model.framingRestores)  // Reset, Esc: an angle typed and not confirmed is dropped
            // An angle typed and confirmed with Return: back to the image, so that X, ← → and
            // Return act on the frame again at once (as after the zoom field).
            .onSubmit { if model.tools.showsCropOptions { NSApp.keyWindow?.focusImageCanvas() } }
        straightenRow
        let grid = Strings.gridTool
        CompactControlRow(grid, help: Strings.cropGridHelp) {
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
        return CompactControlRow(label, help: Strings.gridTintHelp) {
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
        return CompactControlRow(label, help: Strings.cropProportionsHelp) {
            HStack(spacing: CompactPanelMetrics.columnSpacing) {
                CompactPopUp(label, help: Strings.cropProportionsHelp,
                             selection: Binding { choice } set: { choose($0) },
                             sections: [[.init(Strings.cropFree, .free), .init(Strings.cropOriginal, .original)],
                                        presets, [.init(Strings.cropCustom, .custom)]])
                    .popover(isPresented: $customShown, arrowEdge: .bottom) { customRatio }
                Button { model.toggleCropPortrait() } label: {
                    // The frame's real direction (portrait means "exchanged", not "upright").
                    SwapDimensionsIcon(
                        upright: (model.cropRatio ?? model.cropFrameInDocument.map { $0.width / $0.height } ?? 1) < 1)
                }
                .buttonStyle(.borderless)
                .help(Strings.tooltip(.swapProportions))
                .accessibilityLabel(Strings.cropSwap)
                .accessibilityValue(model.recipe.crop.portrait ? Strings.cropSwapped : Strings.cropAsNamed)
                Toggle(isOn: Binding { model.recipe.crop.locked } set: { model.setCropLocked($0) }) {
                    Image(model.recipe.crop.locked ? AppIcon.lockClosed : .lockOpen)
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
                    .help(Strings.cropCustomWidthHelp)
                    .frame(width: CompactPanelMetrics.fieldWidth)
                Text(verbatim: "×")
                TextField(Strings.cropCustomHeight, text: $customHeight)
                    .help(Strings.cropCustomHeightHelp)
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
        return CompactControlRow(label, help: Strings.tooltip(.straightenRow)) {
            HStack(spacing: CompactPanelMetrics.columnSpacing) {
                Button(Strings.cropRule) {
                    model.tools.selected = ruleSelected ? .crop : .straighten
                }
                .tint(ruleSelected ? .accentColor : nil)
                .buttonStyle(.bordered)
                .help(Strings.tooltip(.ruleButton))
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

/// The Framing title row: Reset, always (lot 1b), and Done while cropping.
/// Reset puts back the orientation, the proportions, the angle and the
/// frame, and ⌘Z undoes it; Done (Return) goes back to the tool used before;
/// Esc cancels the changes made since the crop mode began.
struct FramingHeaderButtons: View {
    @Bindable var model: AppModel

    var body: some View {
        Button { reset() } label: { Image(AppIcon.reset) }
            .buttonStyle(.bordered)
            .disabled(model.framingIsReset && model.ruleLine == nil)  // Reset also removes the rule's line
            .help(Strings.tooltip(.reset))
            .accessibilityLabel(Strings.framingReset)
        if model.tools.showsCropOptions {
            Button(Strings.cropDone) { model.finishCrop() }
                .buttonStyle(.borderedProminent)
                .help(Strings.tooltip(.done))
        }
    }

    /// Reset, undone by Edit > Undo (⌘Z) through the window's undo manager (`AppModel.undoManager`).
    private func reset() {
        model.resetFraming(actionName: Strings.framingResetAction)
    }
}

/// Orientation (lot 1): quarter turns and mirror, for the display and the
/// export; the letter F drawn as the image is turned shows the state at a glance.
private struct OrientationRow: View {
    @Bindable var model: AppModel

    var body: some View {
        let label = String(localized: "Orientation", comment: "Panel label: turns and mirror of the image")
        let orientation = model.recipe.orientation
        CompactControlRow(label, help: Strings.orientationHelp) {
            HStack(spacing: CompactPanelMetrics.columnSpacing) {
                // The state first, in its small frame (user's tests of lot 1b), set a little apart
                // from the actions so that it does not read as a fourth button.
                OrientationGlyph(orientation: orientation)
                    .help(Strings.orientationDescription(orientation))
                    .accessibilityElement()
                    .accessibilityLabel(label)
                    .accessibilityValue(Strings.orientationDescription(orientation))
                    .padding(.trailing, CompactPanelMetrics.groupSpacing - CompactPanelMetrics.columnSpacing)
                button(.rotateLeft, Strings.rotateCounterclockwise, help: Strings.tooltip(.rotateCounterclockwise)) {
                    model.rotateCounterclockwise()
                }
                button(.rotateRight, Strings.rotateClockwise, help: Strings.tooltip(.rotateClockwise)) {
                    model.rotateClockwise()
                }
                button(.mirror, Strings.mirrorHorizontally,
                       help: Strings.mirrorHorizontally) {
                    model.mirrorHorizontally()
                }
            }
            .fixedSize(horizontal: false, vertical: true)  // the glyph's frame takes the buttons' height
        }
    }

    /// `label` for VoiceOver, `help` (with the shortcut) for the tooltip.
    private func button(_ icon: AppIcon, _ label: String, help: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            // VoiceOver hears the new state without going to the glyph.
            AccessibilityNotification.Announcement(Strings.orientationDescription(model.recipe.orientation)).post()
        } label: {
            Image(icon)
        }
        .help(help)
        .accessibilityLabel(label)
    }
}

/// The letter F turned and mirrored like the image: a state, not a control
/// (secondary colour, no animation), in a small thin frame at the start of
/// the Orientation row, like a thumbnail of the image's direction (user's
/// tests of lot 1b; the frame is not a button: no fill, no shadow).
private struct OrientationGlyph: View {
    let orientation: Orientation

    var body: some View {
        Text(verbatim: "F")
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
            .scaleEffect(x: orientation.mirrored ? -1 : 1, y: 1)
            .rotationEffect(.degrees(Double(orientation.quarterTurns) * 90))
            .frame(width: CompactPanelMetrics.indicatorWidth)
            .frame(maxHeight: .infinity)
            .overlay {
                RoundedRectangle(cornerRadius: CompactPanelMetrics.indicatorCornerRadius)
                    .strokeBorder(.tertiary, lineWidth: 1)
            }
    }
}

/// The icon of "Swap Width and Height" (user's choice after the tests of
/// lot 1b; the plain rectangle was not clear): the frame in its current
/// direction (`upright`: higher than wide), a two-way arrow, and the
/// exchanged frame. Drawn with the foreground style, as a symbol is.
struct SwapDimensionsIcon: View {
    /// Two frames and the arrow between them, the height of the lock symbol next to it (small controls).
    static let size = CGSize(width: 34, height: 16)

    let upright: Bool

    var body: some View {
        Canvas { context, size in
            let height = size.height - 5, narrow = height * 0.6
            let y = (size.height - height) / 2
            func frame(x: CGFloat, upright: Bool) -> Path {
                let rect = upright ? CGRect(x: x, y: y, width: narrow, height: height)
                                   : CGRect(x: x, y: y + (height - narrow) / 2, width: height, height: narrow)
                return Path(roundedRect: rect, cornerRadius: 1.2)
            }
            context.stroke(frame(x: 1, upright: upright), with: .foreground, lineWidth: 1.3)
            let secondX = size.width - 1 - (upright ? height : narrow)
            context.stroke(frame(x: secondX, upright: !upright), with: .foreground, lineWidth: 1.3)
            // A two-way arrow between them: the button exchanges, both ways.
            let left = 1 + (upright ? narrow : height) + 2, right = secondX - 2, mid = size.height / 2
            var arrow = Path()
            arrow.move(to: CGPoint(x: left, y: mid))
            arrow.addLine(to: CGPoint(x: right, y: mid))
            arrow.move(to: CGPoint(x: right - 2.5, y: mid - 2.5))
            arrow.addLine(to: CGPoint(x: right, y: mid))
            arrow.addLine(to: CGPoint(x: right - 2.5, y: mid + 2.5))
            arrow.move(to: CGPoint(x: left + 2.5, y: mid - 2.5))
            arrow.addLine(to: CGPoint(x: left, y: mid))
            arrow.addLine(to: CGPoint(x: left + 2.5, y: mid + 2.5))
            context.stroke(arrow, with: .foreground, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}
