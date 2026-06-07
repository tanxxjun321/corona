import AppKit
import CoronaCore
import SwiftUI

final class LayoutEditorWindowController: NSWindowController {
    private let model: LayoutEditorViewModel

    init(
        cacheController: MenuBarCacheController,
        layoutStore: LayoutPersistenceStore,
        settingsStore: SettingsStore
    ) {
        self.model = LayoutEditorViewModel(
            cacheController: cacheController,
            layoutStore: layoutStore,
            settingsStore: settingsStore
        )
        let hostingController = NSHostingController(rootView: LayoutEditorView(model: model))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Layout Editor"
        window.setContentSize(NSSize(width: 980, height: 620))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        model.refresh()
    }
}

@MainActor
final class LayoutEditorViewModel: ObservableObject {
    struct Row: Identifiable, Equatable {
        var id: String { uid }
        var uid: String
        var title: String
        var owner: String
        var detail: String
    }

    @Published private(set) var visibleRows: [Row] = []
    @Published private(set) var hiddenRows: [Row] = []
    @Published private(set) var alwaysHiddenRows: [Row] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasUnsavedChanges = false

    private let cacheController: MenuBarCacheController
    private let layoutStore: LayoutPersistenceStore
    private let settingsStore: SettingsStore
    private var itemByUID: [String: MenuBarItem] = [:]
    private var draft = LayoutDraft()

    init(
        cacheController: MenuBarCacheController,
        layoutStore: LayoutPersistenceStore,
        settingsStore: SettingsStore
    ) {
        self.cacheController = cacheController
        self.layoutStore = layoutStore
        self.settingsStore = settingsStore
    }

    func refresh() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let snapshot = try await cacheController.refresh()
                let cache = ItemCache(
                    displayID: snapshot.displayID,
                    visibleItems: snapshot.items,
                    hiddenItems: [],
                    alwaysHiddenItems: []
                )
                itemByUID = Dictionary(uniqueKeysWithValues: snapshot.items.map { item in
                    (item.tag.stableIdentifier, item)
                })
                draft = LayoutDraft(order: LayoutPlanner().mergedOrder(
                    cache: cache,
                    preference: layoutPreference()
                ))
                rebuildRows()
                hasUnsavedChanges = false
            } catch {
                errorMessage = String(describing: error)
            }
            isLoading = false
        }
    }

    func move(_ uid: String, to section: MenuBarSection) {
        draft.move(uid, to: section)
        rebuildRows()
        hasUnsavedChanges = true
    }

    func moveUp(_ uid: String, in section: MenuBarSection) {
        draft.moveUp(uid, in: section)
        rebuildRows()
        hasUnsavedChanges = true
    }

    func moveDown(_ uid: String, in section: MenuBarSection) {
        draft.moveDown(uid, in: section)
        rebuildRows()
        hasUnsavedChanges = true
    }

    func save() {
        layoutStore.saveSavedSectionOrder(draft.order)
        layoutStore.saveKnownItemIdentifiers(Set(draft.order.visible + draft.order.hidden + draft.order.alwaysHidden))
        hasUnsavedChanges = false
    }

    func resetToDetectedOrder() {
        draft.reset(visibleUIDs: itemByUID.keys.sorted())
        rebuildRows()
        hasUnsavedChanges = true
    }

    private func layoutPreference() -> LayoutPreference {
        let settings = settingsStore.load()
        return LayoutPreference(
            savedOrder: layoutStore.loadSavedSectionOrder(),
            newItemsSection: MenuBarSection(settings.newItemsSection),
            newItemsPlacement: .append,
            alwaysHiddenEnabled: settings.enableAlwaysHiddenSection
        )
    }

    private func rebuildRows() {
        visibleRows = rows(for: .visible)
        hiddenRows = rows(for: .hidden)
        alwaysHiddenRows = rows(for: .alwaysHidden)
    }

    private func rows(for section: MenuBarSection) -> [Row] {
        draft.order[section].map { uid in
            guard let item = itemByUID[uid] else {
                return Row(uid: uid, title: uid, owner: "Unavailable", detail: "Saved item is not currently running")
            }
            return Row(
                uid: uid,
                title: item.title ?? item.tag.title,
                owner: item.tag.namespace,
                detail: "window \(item.windowID)  pid \(item.ownerPID)"
            )
        }
    }
}

private extension MenuBarSection {
    init(_ newItemsSection: NewItemsSection) {
        switch newItemsSection {
        case .visible:
            self = .visible
        case .hidden:
            self = .hidden
        case .alwaysHidden:
            self = .alwaysHidden
        }
    }
}
