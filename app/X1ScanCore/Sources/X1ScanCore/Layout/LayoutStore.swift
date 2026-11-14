// SPDX-License-Identifier: MIT
import Foundation
import Observation

/// A named, saved layout (later stage: menu to save and switch workspaces).
public struct Workspace: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var layout: PaletteLayout

    public init(id: UUID = UUID(), name: String, layout: PaletteLayout) {
        self.id = id
        self.name = name
        self.layout = layout
    }
}

/// Persistence of the current layout and of the workspaces.
public protocol LayoutStore: Sendable {
    func loadLayout() -> PaletteLayout?
    func saveLayout(_ layout: PaletteLayout)
    func loadWorkspaces() -> [Workspace]
    func saveWorkspaces(_ workspaces: [Workspace])
}

/// JSON in UserDefaults. A layout that does not decode is ignored (defaults used).
public struct UserDefaultsLayoutStore: LayoutStore, @unchecked Sendable {
    // UserDefaults is thread-safe; it is not marked Sendable.
    private let defaults: UserDefaults
    private let layoutKey = "PaletteLayout"
    private let workspacesKey = "Workspaces"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadLayout() -> PaletteLayout? { decode(PaletteLayout.self, layoutKey) }
    public func saveLayout(_ layout: PaletteLayout) { encode(layout, layoutKey) }
    public func loadWorkspaces() -> [Workspace] { decode([Workspace].self, workspacesKey) ?? [] }
    public func saveWorkspaces(_ workspaces: [Workspace]) { encode(workspaces, workspacesKey) }

    private func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private func encode<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}

/// For tests and previews.
public final class InMemoryLayoutStore: LayoutStore, @unchecked Sendable {
    private let lock = NSLock()
    private var layout: PaletteLayout?
    private var workspaces: [Workspace] = []
    public private(set) var saveCount = 0

    public init(layout: PaletteLayout? = nil) { self.layout = layout }

    public func loadLayout() -> PaletteLayout? { lock.withLock { layout } }
    public func saveLayout(_ layout: PaletteLayout) {
        lock.withLock {
            self.layout = layout
            saveCount += 1
        }
    }
    public func loadWorkspaces() -> [Workspace] { lock.withLock { workspaces } }
    public func saveWorkspaces(_ workspaces: [Workspace]) { lock.withLock { self.workspaces = workspaces } }
}

/// The layout the window shows. Changes are saved at once.
@MainActor
@Observable
public final class LayoutController {
    public let registry: PaletteRegistry
    public private(set) var layout: PaletteLayout {
        didSet { if layout != oldValue { store.saveLayout(layout) } }
    }
    public private(set) var workspaces: [Workspace]

    private let store: any LayoutStore

    public init(registry: PaletteRegistry = .standard, store: any LayoutStore) {
        self.registry = registry
        self.store = store
        layout = (store.loadLayout() ?? PaletteLayout(registry: registry)).reconciled(with: registry)
        workspaces = store.loadWorkspaces().map {
            Workspace(id: $0.id, name: $0.name, layout: $0.layout.reconciled(with: registry))
        }
    }

    public func toggleCollapsed(_ id: PaletteID) { layout.toggleCollapsed(id) }
    public func toggleHidden(_ id: PaletteID) { layout.toggleHidden(id) }
    public func setHidden(_ id: PaletteID, _ value: Bool) { layout.setHidden(id, value) }
    public func toggleAllHidden() { layout.toggleAllHidden() }
    public func move(_ id: PaletteID, to index: Int) { layout.move(id, to: index) }
    public func move(_ id: PaletteID, before target: PaletteID?) { layout.move(id, before: target) }
    public func setColumnWidth(_ width: Double) { layout.setColumnWidth(width) }
    public func toggleColumnMode() { layout.toggleColumnMode() }

    /// Icon bar click: opens or closes the palette beside the bar (several may be open).
    public func toggleOverlay(_ id: PaletteID) {
        guard layout.columnMode == .iconBar, registry.contains(id) else { return }
        layout.toggleOpenInIconBar(id)
    }

    public func detach(_ id: PaletteID, frame: StoredFrame) { layout.detach(id, frame: frame) }
    public func attach(_ id: PaletteID) { layout.attach(id) }
    public func attachAll() { layout.attachAll() }
    public func setFloatingFrame(_ frame: StoredFrame, for id: PaletteID) { layout.setFloatingFrame(frame, for: id) }

    public func resetToDefault() {
        layout = PaletteLayout(registry: registry)
    }

    // MARK: Workspaces (model only at this stage)

    @discardableResult
    public func saveWorkspace(named name: String) -> Workspace {
        let workspace = Workspace(name: name, layout: layout)
        workspaces.append(workspace)
        store.saveWorkspaces(workspaces)
        return workspace
    }

    public func apply(_ workspace: Workspace) {
        layout = workspace.layout.reconciled(with: registry)
    }

    public func deleteWorkspace(_ id: UUID) {
        workspaces.removeAll { $0.id == id }
        store.saveWorkspaces(workspaces)
    }
}
