import AppKit
import CoronaCore
import SwiftUI

final class LayoutEditorWindowController: NSWindowController {
    private let model: LayoutEditorViewModel

    init(
        provider: MenuBarDiscoveryProvider,
        layoutStore: LayoutPersistenceStore,
        settingsStore: SettingsStore
    ) {
        self.model = LayoutEditorViewModel(
            provider: provider,
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

    private let provider: MenuBarDiscoveryProvider
    private let layoutStore: LayoutPersistenceStore
    private let settingsStore: SettingsStore
    private var itemByUID: [String: MenuBarItem] = [:]
    private var currentOrder = SectionOrder()

    init(
        provider: MenuBarDiscoveryProvider,
        layoutStore: LayoutPersistenceStore,
        settingsStore: SettingsStore
    ) {
        self.provider = provider
        self.layoutStore = layoutStore
        self.settingsStore = settingsStore
    }

    func refresh() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let snapshot = try await provider.snapshot()
                let cache = ItemCache(
                    displayID: snapshot.displayID,
                    visibleItems: snapshot.items,
                    hiddenItems: [],
                    alwaysHiddenItems: []
                )
                itemByUID = Dictionary(uniqueKeysWithValues: snapshot.items.map { item in
                    (item.tag.stableIdentifier, item)
                })
                currentOrder = LayoutPlanner().mergedOrder(
                    cache: cache,
                    preference: layoutPreference()
                )
                rebuildRows()
                hasUnsavedChanges = false
            } catch {
                errorMessage = String(describing: error)
            }
            isLoading = false
        }
    }

    func move(_ uid: String, to section: MenuBarSection) {
        remove(uid)
        currentOrder[section].append(uid)
        rebuildRows()
        hasUnsavedChanges = true
    }

    func moveUp(_ uid: String, in section: MenuBarSection) {
        guard let index = currentOrder[section].firstIndex(of: uid), index > currentOrder[section].startIndex else {
            return
        }
        currentOrder[section].swapAt(index, currentOrder[section].index(before: index))
        rebuildRows()
        hasUnsavedChanges = true
    }

    func moveDown(_ uid: String, in section: MenuBarSection) {
        guard let index = currentOrder[section].firstIndex(of: uid) else { return }
        let next = currentOrder[section].index(after: index)
        guard next < currentOrder[section].endIndex else { return }
        currentOrder[section].swapAt(index, next)
        rebuildRows()
        hasUnsavedChanges = true
    }

    func save() {
        layoutStore.saveSavedSectionOrder(currentOrder)
        layoutStore.saveKnownItemIdentifiers(Set(currentOrder.visible + currentOrder.hidden + currentOrder.alwaysHidden))
        hasUnsavedChanges = false
    }

    func resetToDetectedOrder() {
        currentOrder = SectionOrder(visible: itemByUID.keys.sorted(), hidden: [], alwaysHidden: [])
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

    private func remove(_ uid: String) {
        for section in MenuBarSection.allCases {
            currentOrder[section].removeAll { $0 == uid }
        }
    }

    private func rebuildRows() {
        visibleRows = rows(for: .visible)
        hiddenRows = rows(for: .hidden)
        alwaysHiddenRows = rows(for: .alwaysHidden)
    }

    private func rows(for section: MenuBarSection) -> [Row] {
        currentOrder[section].map { uid in
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
