// SPDX-License-Identifier: MIT
#if DEBUG
import AppKit
import X1ScanCore

/// Debug builds only (`-X1ScanAngleProbe YES`, with `-X1ScanAutoPreview YES`):
/// types an angle in the Framing section's Angle field and presses Return,
/// with each tool and during a preview, then Reset and Esc after an angle
/// typed and not confirmed (session of 2026-11-25); prints the
/// recipe's angle and the keyboard focus after each step, then quits.
/// Synthesized events sent to the main window; display only: the preview
/// runs on the virtual X1, no command reaches any scanner.
@MainActor
enum AngleProbe {
    static func run(window: NSWindow, model: AppModel) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            let savedTab = model.panel.layout.tab
            let framingWasFolded = model.panel.layout.isFolded(.framing)
            model.panel.showFraming()
            try? await Task.sleep(for: .milliseconds(500))
            var lines: [String] = []
            @MainActor func focus() -> String {
                guard let first = window.firstResponder else { return "nil" }
                if let text = first as? NSTextView, text.isFieldEditor { return "field editor" }
                return String(describing: type(of: first))
            }
            @MainActor func typeAngle(_ text: String) async -> Bool {
                guard let field = angleField(in: window) else { return false }
                click(at: field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil), in: window)
                try? await Task.sleep(for: .milliseconds(300))
                guard let editor = window.firstResponder as? NSTextView, editor.isFieldEditor else { return false }
                editor.selectAll(nil)
                editor.insertText(text, replacementRange: editor.selectedRange())
                try? await Task.sleep(for: .milliseconds(200))
                return true
            }
            // Return (36) and the keypad's Enter (76), with each tool, from 0° and from the rule's −1.3°.
            for tool in [Tool.hand, .crop, .straighten] {
                for (code, characters) in [(UInt16(36), "\r"), (UInt16(76), "\u{3}")] {
                    for start in [0.0, -1.3] {
                        model.resetFraming()
                        model.tools.selected = tool
                        model.setCropAngle(start)
                        try? await Task.sleep(for: .milliseconds(300))
                        let typed = await typeAngle("-3")
                        pressKey(code: code, characters: characters, in: window)
                        try? await Task.sleep(for: .milliseconds(400))
                        lines.append("PROBE key \(code), tool \(tool.rawValue), from \(start): field found \(typed), angle -> \(model.recipe.crop.angle) (-3 expected), focus \(focus()), tool now \(model.tools.selected.rawValue)")
                        model.finishCrop()
                        window.focusImageCanvas()
                    }
                }
            }
            // While a preview runs (rows arriving), then once it has ended.
            for tool in [Tool.hand, .crop] {
                model.resetFraming()
                model.tools.selected = tool
                model.startPreview()
                try? await Task.sleep(for: .milliseconds(200))
                let running = model.session.isBusy
                let typed = await typeAngle("-2")
                pressKey(code: 36, characters: "\r", in: window)
                try? await Task.sleep(for: .milliseconds(400))
                lines.append("PROBE during a preview (running \(running), still \(model.session.isBusy)), tool \(tool.rawValue): field found \(typed), angle -> \(model.recipe.crop.angle) (-2 expected), focus \(focus())")
                await model.session.waitUntilIdle()
                model.finishCrop()
                window.focusImageCanvas()
            }
            // Reset with an angle typed and not confirmed, then the focus lost.
            model.resetFraming()
            model.tools.selected = .hand
            model.rotateClockwise()
            try? await Task.sleep(for: .milliseconds(300))
            _ = await typeAngle("4")
            model.resetFraming()
            try? await Task.sleep(for: .milliseconds(300))
            window.focusImageCanvas()
            try? await Task.sleep(for: .milliseconds(400))
            lines.append("PROBE Reset with 4 typed, not confirmed, then focus lost: angle \(model.recipe.crop.angle) (0 expected), quarter turns \(model.recipe.orientation.quarterTurns), field shows \(angleField(in: window)?.stringValue ?? "?")")
            // Esc in crop mode with an angle typed and not confirmed (the action of Esc, called directly:
            // in the field, Esc belongs to the field editor).
            model.tools.selected = .crop
            try? await Task.sleep(for: .milliseconds(300))
            _ = await typeAngle("6")
            model.escape()
            try? await Task.sleep(for: .milliseconds(300))
            window.focusImageCanvas()
            try? await Task.sleep(for: .milliseconds(400))
            lines.append("PROBE Esc with 6 typed, not confirmed, then focus lost: angle \(model.recipe.crop.angle) (0 expected), tool \(model.tools.selected.rawValue), field shows \(angleField(in: window)?.stringValue ?? "?")")
            // The Esc key itself, the field having the focus.
            model.tools.selected = .crop
            try? await Task.sleep(for: .milliseconds(300))
            _ = await typeAngle("7")
            let restores = model.framingRestores
            pressKey(code: 53, characters: "\u{1b}", in: window)
            try? await Task.sleep(for: .milliseconds(400))
            let afterKey = (focus(), model.tools.selected, model.framingRestores - restores)
            window.focusImageCanvas()
            try? await Task.sleep(for: .milliseconds(400))
            lines.append("PROBE Esc key with 7 typed in the field: focus \(afterKey.0), tool \(afterKey.1.rawValue), restores +\(afterKey.2); then focus lost: angle \(model.recipe.crop.angle), tool \(model.tools.selected.rawValue)")
            model.finishCrop()
            model.resetFraming()
            model.panel.select(savedTab)  // saved with the panel layout: put it back
            model.panel.setFolded(.framing, framingWasFolded)
            for line in lines { FileHandle.standardError.write(Data((line + "\n").utf8)) }
            NSApp.terminate(nil)
        }
    }

    /// The Angle field: the editable text field whose row is labelled Angle.
    private static func angleField(in window: NSWindow) -> NSTextField? {
        guard let content = window.contentView else { return nil }
        return views(NSTextField.self, in: content).first {
            $0.isEditable && !$0.isHidden && !($0 is NSComboBox) && $0.placeholderString == Strings.cropAngle
        }
    }

    private static func pressKey(code: UInt16, characters: String, in window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                                            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                            context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                            isARepeat: false, keyCode: code) {
                NSApp.postEvent(event, atStart: false)  // through the queue, as a real key: local monitors see it
            }
        }
    }

    /// The mouse up is queued first: a control tracking the mouse reads it from the queue.
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
}
#endif
