// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import X1ScanCore

/// The zoom percentage of the bottom bar: a combo box listing Zoom to Fit,
/// Fill Window and the steps, where a value can also be typed ("150",
/// "12,5 %"). An invalid value puts the current one back.
struct ZoomComboBox: NSViewRepresentable {
    let model: AppModel
    /// Read in the parent's body, so that SwiftUI updates the box on every change.
    let magnification: Double
    let enabled: Bool

    private static let entries = ZoomMenuEntry.all

    static func title(_ entry: ZoomMenuEntry) -> String {
        switch entry {
        case .fit: Strings.zoomMode(.fit)
        case .fill: Strings.zoomMode(.fill)
        case .step(let value): Strings.zoom(value)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSComboBox {
        let box = NSComboBox()
        box.addItems(withObjectValues: Self.entries.map(Self.title))
        box.numberOfVisibleItems = Self.entries.count
        box.completes = false
        box.isButtonBordered = false
        box.controlSize = .small
        box.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        box.alignment = .right
        box.delegate = context.coordinator
        box.target = context.coordinator
        box.action = #selector(Coordinator.commit(_:))
        // No action when the field just loses the focus: a value shown while
        // browsing the list (e.g. 6.25 %) must not be applied by clicking elsewhere.
        box.cell?.sendsActionOnEndEditing = false
        box.setAccessibilityLabel(String(localized: "zoom.steps", defaultValue: "Zoom", comment: "Menu: zoom steps (not the window zoom)"))
        return box
    }

    func updateNSView(_ box: NSComboBox, context: Context) {
        context.coordinator.model = model
        box.isEnabled = enabled
        if box.currentEditor() == nil { context.coordinator.show(Strings.zoom(magnification), in: box) }
    }

    @MainActor
    final class Coordinator: NSObject, NSComboBoxDelegate {
        var model: AppModel
        /// Text last written by the app: Return on it changes nothing (Fit stays Fit).
        private var shown = ""

        init(model: AppModel) { self.model = model }

        func show(_ text: String, in box: NSComboBox) {
            shown = text
            box.stringValue = text
        }

        // Browsing the list (pointer, arrow keys) changes nothing: a choice is
        // applied only when confirmed, in commit(_:). Applying every selection
        // change could set 6.25 %, the first step under Fit and Fill.

        /// A list entry clicked, or Return after typing or browsing.
        @objc func commit(_ sender: NSComboBox) {
            let text = sender.stringValue
            if text != shown {
                if let entry = ZoomMenuEntry.entry(titled: text, title: ZoomComboBox.title) {
                    apply(entry)
                } else {
                    model.zoom(typed: text)
                }
            }
            showCurrent(sender)
            // Back to the image area, so that Tab and the tool keys work again at once.
            if let window = sender.window {
                window.makeFirstResponder(window.contentView.flatMap(Self.canvas(in:)))
            }
        }

        private func apply(_ entry: ZoomMenuEntry) {
            switch entry {
            case .fit: model.zoomToFit()
            case .fill: model.zoomToFill()
            case .step(let value): model.zoom(to: value)
            }
        }

        private static func canvas(in view: NSView) -> ImageCanvasView? {
            if let canvas = view as? ImageCanvasView { return canvas }
            for subview in view.subviews {
                if let canvas = canvas(in: subview) { return canvas }
            }
            return nil
        }

        /// The box shows the percentage, also after a mode was chosen
        /// (NSComboBox writes the entry's title after the selection notification).
        private func showCurrent(_ box: NSComboBox) {
            DispatchQueue.main.async { [model] in
                if box.currentEditor() == nil { self.show(Strings.zoom(model.viewport.magnification), in: box) }
            }
        }
    }
}
