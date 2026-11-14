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

    private enum Entry {
        case mode(ZoomMode)
        case step(Double)
    }

    private static let entries: [Entry] = [.mode(.fit), .mode(.fill)] + Viewport.steps.map(Entry.step)

    private static func title(_ entry: Entry) -> String {
        switch entry {
        case .mode(let mode): Strings.zoomMode(mode)
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
        /// Set by a list selection, whose action must not be read as typing.
        private var selecting = false

        init(model: AppModel) { self.model = model }

        func show(_ text: String, in box: NSComboBox) {
            shown = text
            box.stringValue = text
        }

        /// A list entry was chosen.
        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let box = notification.object as? NSComboBox else { return }
            let index = box.indexOfSelectedItem
            guard ZoomComboBox.entries.indices.contains(index) else { return }
            selecting = true
            switch ZoomComboBox.entries[index] {
            case .mode(.fit): model.zoomToFit()
            case .mode(.fill): model.zoomToFill()
            case .mode(.fixed): model.zoomToActualSize()
            case .step(let value): model.zoom(to: value)
            }
            showCurrent(box)
        }

        /// Return pressed after typing, or the field left.
        @objc func commit(_ sender: NSComboBox) {
            let text = sender.stringValue
            if selecting {
                selecting = false
            } else if text != shown {
                model.zoom(typed: text)
            }
            showCurrent(sender)
            sender.window?.makeFirstResponder(nil)
        }

        /// The box shows the percentage, also after a mode was chosen
        /// (NSComboBox writes the entry's title after the selection notification).
        private func showCurrent(_ box: NSComboBox) {
            DispatchQueue.main.async { [model] in
                self.selecting = false
                if box.currentEditor() == nil { self.show(Strings.zoom(model.viewport.magnification), in: box) }
            }
        }
    }
}
