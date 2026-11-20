// SPDX-License-Identifier: MIT
#if DEBUG
import AppKit
import X1ScanCore

/// Debug builds only (`-X1ScanKeyProbe YES`): checks that the single-key
/// tool shortcuts (C, R…) reach the window whatever was clicked before.
/// Clicks and key presses are synthesized events sent to the main window;
/// each step prints the first responder and the tool selected, then the
/// app quits. Display only: no command reaches any scanner (the preview,
/// if any, runs on the virtual X1 only).
@MainActor
enum KeyProbe {
    static func run(window: NSWindow, model: AppModel) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(500))
            var lines: [String] = []
            @MainActor func responder() -> String {
                guard let first = window.firstResponder else { return "nil" }
                if let text = first as? NSTextView, text.isFieldEditor { return "field editor (a text field)" }
                return String(describing: type(of: first))
            }
            @MainActor func step(_ label: String, key: String, before: @MainActor () -> Void) async {
                model.tools.selected = .hand
                before()
                try? await Task.sleep(for: .milliseconds(400))
                let focus = responder()
                let tab = model.panel.layout.tab.rawValue
                press(key, in: window)
                try? await Task.sleep(for: .milliseconds(300))
                lines.append("PROBE \(label): tab=\(tab) focus=\(focus) key=\(key) -> tool=\(model.tools.selected.rawValue), tab now \(model.panel.layout.tab.rawValue), focus now \(responder())")
                // Leave the crop mode the way Done does, for the next step.
                model.finishCrop()
            }
            let savedTab = model.panel.layout.tab
            await step("launch", key: "c") {}
            await step("click tab Scan", key: "c") { clickSegment(1, in: window) }
            await step("click tab Output", key: "r") { clickSegment(2, in: window) }
            await step("click tab Prepare", key: "r") { clickSegment(0, in: window) }
            // Test 3 of the user: C from the Scan tab, then R and C again without touching anything.
            clickSegment(1, in: window)
            try? await Task.sleep(for: .milliseconds(400))
            for key in ["c", "r", "c"] {
                let focus = responder()
                press(key, in: window)
                try? await Task.sleep(for: .milliseconds(400))
                lines.append("PROBE chain: focus=\(focus) key=\(key) -> tool=\(model.tools.selected.rawValue), tab \(model.panel.layout.tab.rawValue)")
            }
            model.finishCrop()
            await step("click first text field (Scan tab)", key: "c") {
                model.panel.select(.scan)
                clickFirstTextField(in: window)
            }
            // A value typed in a field of the Scan tab (Return), then another tab: the field is gone.
            model.tools.selected = .hand
            model.panel.select(.scan)
            try? await Task.sleep(for: .milliseconds(400))
            clickFirstTextField(in: window)
            try? await Task.sleep(for: .milliseconds(300))
            pressReturn(in: window)
            try? await Task.sleep(for: .milliseconds(300))
            lines.append("PROBE after Return in a Scan field: focus=\(responder())")
            clickSegment(2, in: window)
            try? await Task.sleep(for: .milliseconds(400))
            let gone = responder()
            press("c", in: window)
            try? await Task.sleep(for: .milliseconds(300))
            lines.append("PROBE then tab Output: focus=\(gone) key=c -> tool=\(model.tools.selected.rawValue)")
            model.finishCrop()
            // A field left focused (clicked, nothing typed), then a click on another tab.
            model.panel.select(.scan)
            try? await Task.sleep(for: .milliseconds(400))
            clickFirstTextField(in: window)
            try? await Task.sleep(for: .milliseconds(300))
            clickSegment(2, in: window)
            try? await Task.sleep(for: .milliseconds(400))
            let left = responder()
            press("r", in: window)
            try? await Task.sleep(for: .milliseconds(300))
            lines.append("PROBE field focused, then tab Output: focus=\(left) key=r -> tool=\(model.tools.selected.rawValue)")
            model.finishCrop()
            // The tab bar holding the keyboard focus, as after a click with Keyboard navigation on.
            await step("focus on the tab bar (Scan tab)", key: "c") {
                model.panel.select(.scan)
                if let content = window.contentView, let bar = views(NSSegmentedControl.self, in: content).first {
                    window.makeFirstResponder(bar)
                }
            }
            // The canvas's keys in crop mode: → (1°), ⇧→ (to 5°), Return (Done); then Esc; Space held.
            window.focusImageCanvas()
            model.tools.selected = .zoom
            model.tools.selected = .crop
            let startAngle = model.recipe.crop.angle
            pressKey(code: 124, characters: String(UnicodeScalar(NSRightArrowFunctionKey)!), shift: false, in: window)
            let afterArrow = model.recipe.crop.angle
            pressKey(code: 124, characters: String(UnicodeScalar(NSRightArrowFunctionKey)!), shift: true, in: window)
            let afterShiftArrow = model.recipe.crop.angle
            pressKey(code: 36, characters: "\r", shift: false, in: window)
            let afterReturn = model.tools.selected
            model.tools.selected = .crop
            pressKey(code: 53, characters: "\u{1b}", shift: false, in: window)
            let afterEscape = model.tools.selected
            pressKey(code: 49, characters: " ", shift: false, in: window, only: .keyDown)
            let spaceHeld = model.tools.spaceHeld
            pressKey(code: 49, characters: " ", shift: false, in: window, only: .keyUp)
            lines.append("PROBE canvas keys: angle \(startAngle) -> → \(afterArrow) -> ⇧→ \(afterShiftArrow); Return -> \(afterReturn.rawValue) (zoom expected); Esc -> \(afterEscape.rawValue) (zoom expected); Space held -> \(spaceHeld), released -> \(model.tools.spaceHeld)")
            model.panel.select(savedTab)  // the tab is saved with the panel layout: put it back
            for line in lines { FileHandle.standardError.write(Data((line + "\n").utf8)) }
            NSApp.terminate(nil)
        }
    }

    private static func press(_ key: String, in window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let codes: [String: UInt16] = ["c": 8, "r": 15, "h": 4, "z": 6]  // ANSI key codes
            guard let code = codes[key] else { preconditionFailure("no key code for \(key)") }
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: window.windowNumber, context: nil, characters: key,
                                            charactersIgnoringModifiers: key, isARepeat: false, keyCode: code) {
                NSApp.sendEvent(event)
            }
        }
    }

    /// A key pressed and released, or only one of the two (`only`).
    private static func pressKey(code: UInt16, characters: String, shift: Bool, in window: NSWindow,
                                 only: NSEvent.EventType? = nil) {
        for type in only.map({ [$0] }) ?? [.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: shift ? [.shift] : [],
                                            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                            context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                            isARepeat: false, keyCode: code) {
                NSApp.sendEvent(event)
            }
        }
    }

    private static func pressReturn(in window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: window.windowNumber, context: nil, characters: "\r",
                                            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36) {
                NSApp.sendEvent(event)
            }
        }
    }

    /// The mouse up is queued first: a control tracking the mouse after the
    /// mouse down reads it from the queue (sent afterwards, it would never come).
    private static func click(at point: NSPoint, in window: NSWindow) {
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        }
        guard let down = event(.leftMouseDown), let up = event(.leftMouseUp) else { return }
        NSApp.postEvent(up, atStart: false)
        NSApp.sendEvent(down)
    }

    private static func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        var found: [T] = []
        if let match = view as? T { found.append(match) }
        for subview in view.subviews { found += views(type, in: subview) }
        return found
    }

    private static func clickSegment(_ index: Int, in window: NSWindow) {
        guard let content = window.contentView, let control = views(NSSegmentedControl.self, in: content).first else { return }
        let width = control.bounds.width / CGFloat(control.segmentCount)
        let local = NSPoint(x: width * (CGFloat(index) + 0.5), y: control.bounds.midY)
        click(at: control.convert(local, to: nil), in: window)
    }

    private static func clickFirstTextField(in window: NSWindow) {
        guard let content = window.contentView,
              let field = views(NSTextField.self, in: content)
                  .first(where: { $0.isEditable && !$0.isHidden && !($0 is NSComboBox) }) else { return }  // not the zoom box
        click(at: field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil), in: window)
    }
}
#endif
