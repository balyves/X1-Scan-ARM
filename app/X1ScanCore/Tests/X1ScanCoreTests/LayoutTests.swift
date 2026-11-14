// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import X1ScanCore

struct PaletteLayoutTests {
    @Test func defaultLayoutFollowsTheRegistry() {
        let layout = PaletteLayout()
        #expect(layout.order == [.histogram, .info, .export])
        #expect(layout.isCollapsed(.export) && !layout.isCollapsed(.histogram))
        #expect(layout.hidden.isEmpty && !layout.allHidden)
        #expect(layout.columnMode == .expanded && layout.toolBarPlacement == .floating)
        #expect(layout.dockedPalettes == layout.order)
    }

    @Test func moveCollapseAndWidth() {
        var layout = PaletteLayout()
        layout.move(.info, to: 0)
        #expect(layout.order == [.info, .histogram, .export])
        layout.move(.info, to: 99)
        #expect(layout.order == [.histogram, .export, .info])
        layout.move(PaletteID(rawValue: "unknown"), to: 0)
        #expect(layout.order.count == 3)
        layout.toggleCollapsed(.histogram)
        #expect(layout.isCollapsed(.histogram))
        layout.setCollapsed(PaletteID(rawValue: "unknown"), true)
        #expect(!layout.collapsed.contains(PaletteID(rawValue: "unknown")))
        layout.setColumnWidth(10)
        #expect(layout.columnWidth == PaletteLayout.minimumColumnWidth)
        layout.setColumnWidth(10_000)
        #expect(layout.columnWidth == PaletteLayout.maximumColumnWidth)
    }

    @Test func floatingPlacementIsRecordedAndLeavesTheColumn() {
        var layout = PaletteLayout()
        layout.setPlacement(.floating(StoredFrame(x: 1, y: 2, width: 300, height: 200)), for: .histogram)
        #expect(layout.dockedPalettes == [.info, .export])
        layout.setPlacement(.docked, for: .histogram)
        #expect(layout.placements.isEmpty)
    }

    @Test func paletteCanBeHiddenAndShown() {
        var layout = PaletteLayout()
        layout.toggleHidden(.info)
        #expect(layout.isHidden(.info))
        #expect(layout.visibleDockedPalettes == [.histogram, .export])
        #expect(layout.order == [.histogram, .info, .export], "a hidden palette keeps its place")
        layout.toggleHidden(.info)
        #expect(layout.visibleDockedPalettes == [.histogram, .info, .export])
        layout.setHidden(PaletteID(rawValue: "unknown"), true)
        #expect(layout.hidden.isEmpty)
    }

    @Test func showHideAllPalettes() {
        var layout = PaletteLayout()
        layout.setHidden(.info, true)
        layout.toggleAllHidden()  // some shown: hide all
        #expect(layout.allHidden && layout.visibleDockedPalettes.isEmpty)
        layout.toggleAllHidden()  // all hidden: show all
        #expect(layout.hidden.isEmpty)
    }

    @Test func roundTripsThroughJSON() throws {
        var layout = PaletteLayout()
        layout.move(.export, to: 0)
        layout.toggleColumnMode()
        layout.toolBarPlacement = .dockedColumn
        layout.setPlacement(.floating(StoredFrame(x: 10, y: 20, width: 300, height: 200)), for: .info)
        layout.setHidden(.histogram, true)
        layout.toggleOpenInIconBar(.export)
        let decoded = try JSONDecoder().decode(PaletteLayout.self, from: JSONEncoder().encode(layout))
        #expect(decoded == layout)
    }

    @Test func reconcilingDropsUnknownAndAddsNewPalettes() throws {
        // A layout saved by another version: an unknown palette, a missing one, a duplicate.
        let json = """
            {"version":1,"order":["info","future","scanner","info"],"collapsed":["future","info"],
             "columnMode":"iconBar","columnWidth":9000,"placements":[],"toolBarPlacement":"floating"}
            """
        let saved = try JSONDecoder().decode(PaletteLayout.self, from: Data(json.utf8))
        let layout = saved.reconciled(with: .standard)
        #expect(layout.order == [.info, .histogram, .export], "the Scanner palette of step 2 is dropped")
        #expect(layout.collapsed == [.info, .export])
        #expect(layout.hidden.isEmpty, "version 1: nothing hidden")
        #expect(layout.openInIconBar.isEmpty, "before version 3: nothing open beside the icon bar")
        #expect(layout.version == PaletteLayout.currentVersion)
        #expect(layout.columnMode == .iconBar)
        #expect(layout.columnWidth == PaletteLayout.maximumColumnWidth)
    }
}

@MainActor
struct LayoutControllerTests {
    @Test func changesAreSavedAndRestored() {
        let store = InMemoryLayoutStore()
        let controller = LayoutController(store: store)
        controller.toggleCollapsed(.histogram)
        controller.move(.histogram, to: 2)
        #expect(store.saveCount == 2)
        let restored = LayoutController(store: store)
        #expect(restored.layout == controller.layout)
    }

    @Test func severalPalettesOpenBesideTheIconBarAndSaved() {
        let store = InMemoryLayoutStore()
        let controller = LayoutController(store: store)
        controller.toggleOverlay(.info)
        #expect(controller.layout.openInIconBar.isEmpty, "column expanded: nothing opens")
        controller.toggleColumnMode()
        controller.toggleOverlay(.export)
        controller.toggleOverlay(.histogram)
        #expect(controller.layout.iconBarStack == [.histogram, .export], "stacked in palette order")
        controller.toggleOverlay(.export)
        #expect(controller.layout.iconBarStack == [.histogram])
        #expect(LayoutController(store: store).layout.iconBarStack == [.histogram], "saved")
        controller.toggleHidden(.histogram)
        #expect(controller.layout.iconBarStack.isEmpty, "a hidden palette is not shown")
    }

    @Test func dragAndDropOrder() {
        var layout = PaletteLayout()
        layout.move(.export, before: .histogram)
        #expect(layout.order == [.export, .histogram, .info])
        layout.move(.export, before: nil)
        #expect(layout.order == [.histogram, .info, .export])
        layout.move(.info, before: .info)
        #expect(layout.order == [.histogram, .info, .export], "onto itself: unchanged")
        layout.move(PaletteID(rawValue: "unknown"), before: .info)
        #expect(layout.order == [.histogram, .info, .export])
    }

    @Test func detachAndAttach() {
        var layout = PaletteLayout()
        layout.toggleColumnMode()
        layout.toggleOpenInIconBar(.info)
        layout.setHidden(.info, true)
        let frame = StoredFrame(x: 100, y: 200, width: 280, height: 300)
        layout.detach(.info, frame: frame)
        #expect(layout.placement(of: .info) == .floating(frame))
        #expect(!layout.isHidden(.info) && !layout.openInIconBar.contains(.info), "a detached palette is shown, alone")
        #expect(layout.visibleFloatingPalettes == [.info] && layout.visibleDockedPalettes == [.histogram, .export])
        let moved = StoredFrame(x: 10, y: 20, width: 300, height: 320)
        layout.setFloatingFrame(moved, for: .info)
        #expect(layout.placement(of: .info) == .floating(moved))
        layout.setFloatingFrame(moved, for: .export)
        #expect(layout.placement(of: .export) == .docked, "only floating palettes have a frame")
        layout.attach(.info)
        #expect(layout.visibleDockedPalettes == [.histogram, .info, .export], "back at its place")
        layout.detach(.export, frame: frame)
        layout.detach(.histogram, frame: frame)
        layout.attachAll()
        #expect(layout.placements.isEmpty)
    }

    @Test func columnIsEmptyWhenNothingIsDocked() {
        var layout = PaletteLayout()
        let frame = StoredFrame(x: 0, y: 0, width: 200, height: 200)
        layout.detach(.histogram, frame: frame)
        layout.detach(.info, frame: frame)
        layout.setHidden(.export, true)
        #expect(layout.columnIsEmpty && !layout.allHidden)
    }

    @Test func hidingIsSavedAndResetShowsEverything() {
        let store = InMemoryLayoutStore()
        let controller = LayoutController(store: store)
        controller.toggleHidden(.info)
        #expect(LayoutController(store: store).layout.isHidden(.info))
        controller.toggleAllHidden()
        #expect(LayoutController(store: store).layout.allHidden)
        controller.resetToDefault()
        #expect(controller.layout == PaletteLayout())
    }

    @Test func workspacesKeepALayout() {
        let store = InMemoryLayoutStore()
        let controller = LayoutController(store: store)
        controller.toggleColumnMode()
        let workspace = controller.saveWorkspace(named: "Retouche")
        controller.resetToDefault()
        #expect(controller.layout.columnMode == .expanded)
        controller.apply(workspace)
        #expect(controller.layout.columnMode == .iconBar)
        #expect(LayoutController(store: store).workspaces == [workspace])
        controller.deleteWorkspace(workspace.id)
        #expect(store.loadWorkspaces().isEmpty)
    }

    @Test func userDefaultsStoreIgnoresGarbage() {
        withTemporaryDefaults { defaults in
            defaults.set(Data("not json".utf8), forKey: "PaletteLayout")
            let store = UserDefaultsLayoutStore(defaults: defaults)
            #expect(store.loadLayout() == nil)
            store.saveLayout(PaletteLayout())
            #expect(store.loadLayout() == PaletteLayout())
        }
    }
}
