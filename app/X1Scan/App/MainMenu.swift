// SPDX-License-Identifier: MIT
import AppKit
import X1ScanCore

/// The menu bar, built in code. Items send their actions to the responder
/// chain; MainWindowController (the window's delegate) handles them and
/// validates them.
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu(appMenu()))
        menu.addItem(submenu(fileMenu()))
        menu.addItem(submenu(editMenu()))
        menu.addItem(submenu(viewMenu()))
        menu.addItem(submenu(scannerMenu()))
        let window = windowMenu()
        menu.addItem(submenu(window))
        NSApp.windowsMenu = window
        let help = NSMenu(title: String(localized: "Help", comment: "Menu"))
        menu.addItem(submenu(help))
        NSApp.helpMenu = help
        return menu
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func appMenu() -> NSMenu {
        let name = ProcessInfo.processInfo.processName
        let menu = NSMenu(title: name)
        menu.addItem(item(String(localized: "About \(name)", comment: "Menu item"),
                          #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Settings…", comment: "Menu item"),
                          #selector(AppDelegate.showSettings(_:)), ","))
        menu.addItem(.separator())
        let services = NSMenu(title: String(localized: "Services", comment: "Menu"))
        menu.addItem(submenu(services))
        NSApp.servicesMenu = services
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Hide \(name)", comment: "Menu item"), #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item(String(localized: "Hide Others", comment: "Menu item"),
                          #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item(String(localized: "Show All", comment: "Menu item"),
                          #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Quit \(name)", comment: "Menu item"), #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "File", comment: "Menu"))
        menu.addItem(item(String(localized: "Export…", comment: "Menu item"),
                          #selector(MainWindowController.exportImage(_:)), "e", [.command, .shift]))
        menu.addItem(item(String(localized: "Choose Export Folder…", comment: "Menu item"),
                          #selector(MainWindowController.chooseExportFolder(_:))))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Close", comment: "Menu item"), #selector(NSWindow.performClose(_:)), "w"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Edit", comment: "Menu"))
        menu.addItem(item(String(localized: "Undo", comment: "Menu item"), Selector(("undo:")), "z"))
        menu.addItem(item(String(localized: "Redo", comment: "Menu item"), Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Cut", comment: "Menu item"), #selector(NSText.cut(_:)), "x"))
        menu.addItem(item(String(localized: "Copy", comment: "Menu item"), #selector(NSText.copy(_:)), "c"))
        menu.addItem(item(String(localized: "Paste", comment: "Menu item"), #selector(NSText.paste(_:)), "v"))
        menu.addItem(item(String(localized: "Select All", comment: "Menu item"), #selector(NSText.selectAll(_:)), "a"))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "View", comment: "Menu"))
        menu.addItem(item(Strings.zoomMode(.fit), #selector(MainWindowController.zoomToFit(_:)), "0"))
        menu.addItem(item(Strings.zoomMode(.fill), #selector(MainWindowController.zoomToFill(_:)), "0",
                          [.command, .option]))
        menu.addItem(item(String(localized: "Actual Size", comment: "Menu item"),
                          #selector(MainWindowController.zoomToActualSize(_:)), "1"))
        menu.addItem(item(String(localized: "Zoom In", comment: "Menu item"), #selector(MainWindowController.zoomIn(_:)), "+"))
        // ⌘= also zooms in (same key as + without Shift on many layouts), hidden alternate.
        let zoomInAlternate = item(String(localized: "Zoom In", comment: "Menu item"),
                                   #selector(MainWindowController.zoomIn(_:)), "=")
        zoomInAlternate.isHidden = true
        zoomInAlternate.allowsKeyEquivalentWhenHidden = true
        menu.addItem(zoomInAlternate)
        menu.addItem(item(String(localized: "Zoom Out", comment: "Menu item"), #selector(MainWindowController.zoomOut(_:)), "-"))
        let steps = NSMenu(title: String(localized: "zoom.steps", defaultValue: "Zoom", comment: "Menu: zoom steps (not the window zoom)"))
        for step in Viewport.steps {
            let stepItem = item(Strings.zoom(step), #selector(MainWindowController.zoomToStep(_:)))
            stepItem.representedObject = step
            steps.addItem(stepItem)
        }
        menu.addItem(submenu(steps))
        menu.addItem(.separator())
        let tools = NSMenu(title: String(localized: "Tools", comment: "Menu"))
        // The single-key shortcuts (H, Z, C, Space) are handled by the canvas, not
        // here: a menu key equivalent without modifier would steal typing from text fields.
        tools.addItem(item(Strings.toolName(.hand), #selector(MainWindowController.selectHandTool(_:))))
        tools.addItem(item(Strings.toolName(.zoom), #selector(MainWindowController.selectZoomTool(_:))))
        tools.addItem(item(Strings.toolName(.crop), #selector(MainWindowController.selectCropTool(_:))))
        menu.addItem(submenu(tools))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Show Palettes as Icons", comment: "Menu item"),
                          #selector(MainWindowController.toggleColumnMode(_:)), "p", [.command, .option]))
        menu.addItem(.separator())
        // AppKit adds "Enter Full Screen" (⌃⌘F) to the View menu by itself.
        return menu
    }

    private static func scannerMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Scanner", comment: "Menu"))
        menu.addItem(item(String(localized: "Preview", comment: "Menu item and toolbar button"),
                          #selector(MainWindowController.startPreview(_:)), "r"))
        menu.addItem(item(String(localized: "Stop", comment: "Menu item and toolbar button"),
                          #selector(MainWindowController.stopPreview(_:)), "."))
        menu.addItem(.separator())
        menu.addItem(item(Strings.source(.virtual), #selector(MainWindowController.selectVirtualSource(_:))))
        menu.addItem(item(Strings.source(.real), #selector(MainWindowController.selectRealSource(_:))))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Read Identity", comment: "Menu item and button"),
                          #selector(AppDelegate.readIdentity(_:))))
        menu.addItem(item(String(localized: "Scanner Information…", comment: "Menu item"),
                          #selector(AppDelegate.showScannerInformation(_:)), "i"))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Window", comment: "Menu"))
        menu.addItem(item(String(localized: "Minimize", comment: "Menu item"), #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item(String(localized: "Zoom", comment: "Menu item: window zoom"), #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        // Same titles as the palette headers (Strings.paletteTitle).
        for id in PaletteRegistry.standard.ids {
            let paletteItem = item(Strings.paletteTitle(id), #selector(MainWindowController.togglePalette(_:)))
            paletteItem.representedObject = id.rawValue
            menu.addItem(paletteItem)
        }
        // Tab, as in Photoshop. Disabled while a text field is being edited, so
        // that Tab still moves between fields there (MainWindowController).
        menu.addItem(item(String(localized: "Show/Hide All Palettes", comment: "Menu item"),
                          #selector(MainWindowController.toggleAllPalettes(_:)), "\t", []))
        menu.addItem(item(String(localized: "Reset Palette Layout", comment: "Menu item"),
                          #selector(MainWindowController.resetPaletteLayout(_:))))
        menu.addItem(.separator())
        return menu
    }
}
