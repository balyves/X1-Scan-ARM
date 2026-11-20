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
        menu.addItem(submenu(imageMenu()))
        menu.addItem(submenu(scannerMenu()))
        let window = windowMenu()
        menu.addItem(submenu(window))
        NSApp.windowsMenu = window
        let help = NSMenu(title: String(localized: "Help", comment: "Menu"))
        // macOS adds the search field above; HelpSearch puts the help's pages in its results.
        help.addItem(item(String(localized: "X1 Scan Help", comment: "Menu item: opens the built-in help (Help menu); also its line on the help's Keyboard Shortcuts page"),
                          #selector(AppDelegate.showHelpWindow(_:)), shortcut: .help))
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

    /// An item whose shortcut comes from `AppShortcut`, the source the tooltips use too.
    private static func item(_ title: String, _ action: Selector?, shortcut: AppShortcut) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut.shortcut?.keyEquivalent ?? "")
        var mask: NSEvent.ModifierFlags = []
        let modifiers = shortcut.shortcut?.modifiers ?? []
        if modifiers.contains(.control) { mask.insert(.control) }
        if modifiers.contains(.option) { mask.insert(.option) }
        if modifiers.contains(.shift) { mask.insert(.shift) }
        if modifiers.contains(.command) { mask.insert(.command) }
        item.keyEquivalentModifierMask = mask
        return item
    }

    private static func appMenu() -> NSMenu {
        let name = ProcessInfo.processInfo.processName
        let menu = NSMenu(title: name)
        menu.addItem(item(String(localized: "About \(name)", comment: "Menu item"),
                          #selector(AppDelegate.showAbout(_:))))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Settings…", comment: "Menu item"),
                          #selector(AppDelegate.showSettings(_:)), shortcut: .settings))
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
                          #selector(MainWindowController.exportImage(_:)), shortcut: .export))
        menu.addItem(item(String(localized: "Choose Export Folder…", comment: "Menu item"),
                          #selector(MainWindowController.chooseExportFolder(_:))))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Close", comment: "Menu item"), #selector(NSWindow.performClose(_:)), "w"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Edit", comment: "Menu"))
        menu.addItem(item(String(localized: "Undo", comment: "Menu item"), Selector(("undo:")), shortcut: .undo))
        menu.addItem(item(String(localized: "Redo", comment: "Menu item"), Selector(("redo:")), shortcut: .redo))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Cut", comment: "Menu item"), #selector(NSText.cut(_:)), "x"))
        menu.addItem(item(String(localized: "Copy", comment: "Menu item"), #selector(NSText.copy(_:)), "c"))
        menu.addItem(item(String(localized: "Paste", comment: "Menu item"), #selector(NSText.paste(_:)), "v"))
        menu.addItem(item(String(localized: "Select All", comment: "Menu item"), #selector(NSText.selectAll(_:)), "a"))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "View", comment: "Menu"))
        menu.addItem(item(Strings.zoomMode(.fit), #selector(MainWindowController.zoomToFit(_:)), shortcut: .zoomToFit))
        menu.addItem(item(Strings.zoomMode(.fill), #selector(MainWindowController.zoomToFill(_:)), shortcut: .zoomToFill))
        menu.addItem(item(String(localized: "Actual Size", comment: "Menu item"),
                          #selector(MainWindowController.zoomToActualSize(_:)), shortcut: .actualSize))
        menu.addItem(item(String(localized: "Zoom In", comment: "Menu item"), #selector(MainWindowController.zoomIn(_:)),
                          shortcut: .zoomIn))
        // ⌘= also zooms in (same key as + without Shift on many layouts), hidden alternate.
        let zoomInAlternate = item(String(localized: "Zoom In", comment: "Menu item"),
                                   #selector(MainWindowController.zoomIn(_:)), "=")
        zoomInAlternate.isHidden = true
        zoomInAlternate.allowsKeyEquivalentWhenHidden = true
        menu.addItem(zoomInAlternate)
        menu.addItem(item(String(localized: "Zoom Out", comment: "Menu item"), #selector(MainWindowController.zoomOut(_:)),
                          shortcut: .zoomOut))
        let steps = NSMenu(title: String(localized: "zoom.steps", defaultValue: "Zoom", comment: "Menu: zoom steps (not the window zoom)"))
        for step in Viewport.steps {
            let stepItem = item(Strings.zoom(step), #selector(MainWindowController.zoomToStep(_:)))
            stepItem.representedObject = step
            steps.addItem(stepItem)
        }
        menu.addItem(submenu(steps))
        menu.addItem(.separator())
        let tools = NSMenu(title: String(localized: "Tools", comment: "Menu"))
        // The single-key shortcuts (H, Z, C, R, Space) are handled by the canvas, not
        // here: a menu key equivalent without modifier would steal typing from text fields.
        tools.addItem(item(Strings.toolName(.hand), #selector(MainWindowController.selectHandTool(_:))))
        tools.addItem(item(Strings.toolName(.zoom), #selector(MainWindowController.selectZoomTool(_:))))
        tools.addItem(item(Strings.toolName(.crop), #selector(MainWindowController.selectCropTool(_:))))
        tools.addItem(item(Strings.toolName(.straighten), #selector(MainWindowController.selectStraightenTool(_:))))
        menu.addItem(submenu(tools))
        menu.addItem(.separator())
        // The panel's tabs (lot 1b): ⌥⌘1, ⌥⌘2…, in the tab bar's order (AppShortcut.panelTab).
        for tab in PanelTab.visible {
            let tabItem = item(Strings.panelTabMenuItem(tab), #selector(MainWindowController.selectPanelTab(_:)),
                               shortcut: .panelTab(tab))
            tabItem.representedObject = tab.rawValue
            menu.addItem(tabItem)
        }
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Hide Settings Panel", comment: "Menu item"),
                          #selector(MainWindowController.toggleSettingsPanel(_:)), shortcut: .toggleSettingsPanel))
        menu.addItem(.separator())
        // AppKit adds "Enter Full Screen" (⌃⌘F) to the View menu by itself.
        return menu
    }

    /// Lot 1: orientation of the image (display and export, never the scan) and the grid (display only).
    private static func imageMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "menu.image", defaultValue: "Image", comment: "Menu: orientation of the image and grid"))
        menu.addItem(item(Strings.rotateCounterclockwise, #selector(MainWindowController.rotateCounterclockwise(_:)),
                          shortcut: .rotateCounterclockwise))
        menu.addItem(item(Strings.rotateClockwise, #selector(MainWindowController.rotateClockwise(_:)), shortcut: .rotateClockwise))
        menu.addItem(item(Strings.mirrorHorizontally, #selector(MainWindowController.mirrorHorizontally(_:))))
        menu.addItem(.separator())
        // Display only: the grid is never scanned nor exported.
        menu.addItem(item(Strings.showGrid, #selector(MainWindowController.toggleGrid(_:)), shortcut: .toggleGrid))
        for kind in GridKind.allCases {
            let kindItem = item(Strings.gridKind(kind), #selector(MainWindowController.chooseGridKind(_:)))
            kindItem.representedObject = kind.rawValue
            kindItem.indentationLevel = 1
            menu.addItem(kindItem)
        }
        let spacing = NSMenu(title: Strings.fineGridSpacing)
        for divisions in GridSettings.divisionChoices {
            let spacingItem = item(divisions.formatted(), #selector(MainWindowController.chooseGridDivisions(_:)))
            spacingItem.representedObject = divisions
            spacing.addItem(spacingItem)
        }
        let spacingItem = submenu(spacing)
        spacingItem.indentationLevel = 1
        menu.addItem(spacingItem)
        let colors = NSMenu(title: Strings.gridColorMenu)
        for color in GridColor.allCases {
            let colorItem = item(Strings.gridColor(color), #selector(MainWindowController.chooseGridColor(_:)))
            colorItem.representedObject = color.rawValue
            colors.addItem(colorItem)
        }
        let colorsItem = submenu(colors)
        colorsItem.indentationLevel = 1
        menu.addItem(colorsItem)
        let opacities = NSMenu(title: Strings.gridOpacityMenu)
        for opacity in GridSettings.opacityChoices {
            let opacityItem = item(Strings.gridOpacity(opacity), #selector(MainWindowController.chooseGridOpacity(_:)))
            opacityItem.representedObject = opacity
            opacities.addItem(opacityItem)
        }
        let opacitiesItem = submenu(opacities)
        opacitiesItem.indentationLevel = 1
        menu.addItem(opacitiesItem)
        return menu
    }

    private static func scannerMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Scanner", comment: "Menu"))
        menu.addItem(item(String(localized: "Preview", comment: "Menu item and toolbar button"),
                          #selector(MainWindowController.startPreview(_:)), shortcut: .preview))
        menu.addItem(item(String(localized: "Stop", comment: "Menu item and toolbar button"),
                          #selector(MainWindowController.stopPreview(_:)), shortcut: .stop))
        // The source is chosen in Settings > Scanner; Read Identity is in Scanner Information.
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Scanner Information…", comment: "Menu item"),
                          #selector(AppDelegate.showScannerInformation(_:)), shortcut: .scannerInformation))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Window", comment: "Menu"))
        menu.addItem(item(String(localized: "Minimize", comment: "Menu item"), #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item(String(localized: "Zoom", comment: "Menu item: window zoom"), #selector(NSWindow.performZoom(_:))))
        return menu
    }
}
