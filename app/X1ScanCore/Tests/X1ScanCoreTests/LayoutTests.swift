// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import X1ScanCore

struct PaletteLayoutTests {
    @Test func defaultLayoutFollowsTheRegistry() {
        let layout = PaletteLayout()
        #expect(layout.order == [.scanner, .histogram, .info, .export])
        #expect(layout.isCollapsed(.export) && !layout.isCollapsed(.scanner))
        #expect(layout.columnMode == .expanded && layout.toolBarPlacement == .floating)
        #expect(layout.dockedPalettes == layout.order)
    }

    @Test func moveCollapseAndWidth() {
        var layout = PaletteLayout()
        layout.move(.info, to: 0)
        #expect(layout.order == [.info, .scanner, .histogram, .export])
        layout.move(.info, to: 99)
        #expect(layout.order == [.scanner, .histogram, .export, .info])
        layout.move(PaletteID(rawValue: "unknown"), to: 0)
        #expect(layout.order.count == 4)
        layout.toggleCollapsed(.scanner)
        #expect(layout.isCollapsed(.scanner))
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
        #expect(layout.dockedPalettes == [.scanner, .info, .export])
        layout.setPlacement(.docked, for: .histogram)
        #expect(layout.placements.isEmpty)
    }

    @Test func roundTripsThroughJSON() throws {
        var layout = PaletteLayout()
        layout.move(.export, to: 0)
        layout.toggleColumnMode()
        layout.toolBarPlacement = .dockedColumn
        layout.setPlacement(.floating(StoredFrame(x: 10, y: 20, width: 300, height: 200)), for: .info)
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
        #expect(layout.order == [.info, .scanner, .histogram, .export])
        #expect(layout.collapsed == [.info, .export])
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
        controller.move(.histogram, to: 0)
        #expect(store.saveCount == 2)
        let restored = LayoutController(store: store)
        #expect(restored.layout == controller.layout)
    }

    @Test func overlayOnlyFromTheIconBarAndNeverSaved() {
        let store = InMemoryLayoutStore()
        let controller = LayoutController(store: store)
        controller.toggleOverlay(.info)
        #expect(controller.overlayPalette == nil, "column expanded: no overlay")
        controller.toggleColumnMode()
        let saves = store.saveCount
        controller.toggleOverlay(.info)
        #expect(controller.overlayPalette == .info)
        controller.toggleOverlay(.histogram)
        #expect(controller.overlayPalette == .histogram)
        controller.toggleOverlay(.histogram)
        #expect(controller.overlayPalette == nil)
        controller.toggleOverlay(.info)
        controller.toggleColumnMode()
        #expect(controller.overlayPalette == nil)
        #expect(store.saveCount == saves + 1, "only the column mode change was saved")
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
