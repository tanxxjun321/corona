import AppKit
import CoronaCore
import SwiftUI

final class LayoutEditorWindowController: NSWindowController {
    private let model: LayoutEditorViewModel

    init(
        cacheController: MenuBarCacheController,
        layoutStore: LayoutPersistenceStore,
        settingsStore: SettingsStore,
        boundaryProvider: @escaping @MainActor () -> SectionBoundary?,
        applyHandler: @escaping @MainActor () async -> LayoutApplicationResult
    ) {
        self.model = LayoutEditorViewModel(
            cacheController: cacheController,
            layoutStore: layoutStore,
            settingsStore: settingsStore,
            boundaryProvider: boundaryProvider,
            applyHandler: applyHandler
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
    @Published private(set) var isApplying = false
    @Published private(set) var applyMessage: String?

    private let cacheController: MenuBarCacheController
    private let layoutStore: LayoutPersistenceStore
    private let settingsStore: SettingsStore
    private let boundaryProvider: @MainActor () -> SectionBoundary?
    private let applyHandler: @MainActor () async -> LayoutApplicationResult
    private var itemByUID: [String: MenuBarItem] = [:]
    private var draft = LayoutDraft()

    init(
        cacheController: MenuBarCacheController,
        layoutStore: LayoutPersistenceStore,
        settingsStore: SettingsStore,
        boundaryProvider: @escaping @MainActor () -> SectionBoundary?,
        applyHandler: @escaping @MainActor () async -> LayoutApplicationResult
    ) {
        self.cacheController = cacheController
        self.layoutStore = layoutStore
        self.settingsStore = settingsStore
        self.boundaryProvider = boundaryProvider
        self.applyHandler = applyHandler
    }

    func refresh() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let cache = try await currentCache()
                let editableItems = cache.allItems.filter { item in
                    !Self.isCoronaSelfItem(item)
                }
                itemByUID = Dictionary(uniqueKeysWithValues: editableItems.map { item in
                    (item.tag.stableIdentifier, item)
                })
                draft = LayoutDraft(order: availableOrder(preferredOrder(cache: cache).removingCoronaSelfItems()))
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
        let sanitizedOrder = availableOrder(draft.order.removingCoronaSelfItems())
        draft = LayoutDraft(order: sanitizedOrder)
        layoutStore.saveSavedSectionOrder(sanitizedOrder)
        layoutStore.saveKnownItemIdentifiers(Set(sanitizedOrder.visible + sanitizedOrder.hidden + sanitizedOrder.alwaysHidden))
        hasUnsavedChanges = false
    }

    func saveAndApply() {
        save()
        isApplying = true
        applyMessage = nil
        Task {
            let result = await applyHandler()
            applyMessage = result.statusTitle
            isApplying = false
            refresh()
        }
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

    private func currentCache() async throws -> ItemCache {
        if let boundary = boundaryProvider() {
            return try await cacheController.cache(boundary: boundary)
        }

        let snapshot = try await cacheController.refresh()
        return ItemCache(
            displayID: snapshot.displayID,
            visibleItems: snapshot.items,
            hiddenItems: [],
            alwaysHiddenItems: []
        )
    }

    private func preferredOrder(cache: ItemCache) -> SectionOrder {
        let savedOrder = layoutStore.loadSavedSectionOrder()
        let currentOrder = SectionOrder(cache: cache)
        guard !savedOrder.isEmpty else {
            return currentOrder
        }

        return SectionOrder(
            visible: ordered(currentOrder.visible, using: savedOrder.visible),
            hidden: ordered(currentOrder.hidden, using: savedOrder.hidden),
            alwaysHidden: ordered(currentOrder.alwaysHidden, using: savedOrder.alwaysHidden)
        )
    }

    private func ordered(_ currentUIDs: [String], using savedUIDs: [String]) -> [String] {
        let currentSet = Set(currentUIDs)
        let savedInCurrentSection = savedUIDs.filter { currentSet.contains($0) }
        let newOrMovedUIDs = currentUIDs.filter { !savedInCurrentSection.contains($0) }
        return savedInCurrentSection + newOrMovedUIDs
    }

    private func rebuildRows() {
        draft = LayoutDraft(order: availableOrder(draft.order.removingCoronaSelfItems()))
        visibleRows = rows(for: .visible)
        hiddenRows = rows(for: .hidden)
        alwaysHiddenRows = rows(for: .alwaysHidden)
    }

    private func availableOrder(_ order: SectionOrder) -> SectionOrder {
        let availableUIDs = Set(itemByUID.keys)
        return SectionOrder(
            visible: order.visible.filter { availableUIDs.contains($0) },
            hidden: order.hidden.filter { availableUIDs.contains($0) },
            alwaysHidden: order.alwaysHidden.filter { availableUIDs.contains($0) }
        )
    }

    private func rows(for section: MenuBarSection) -> [Row] {
        draft.order[section].compactMap { uid in
            guard !MenuBarController.isCoronaSelfIdentifier(uid) else {
                return nil
            }
            guard let item = itemByUID[uid] else { return nil }
            return Row(
                uid: uid,
                title: item.title ?? item.tag.title,
                owner: item.tag.namespace,
                detail: "window \(item.windowID)  pid \(item.ownerPID)"
            )
        }
    }

    private static func isCoronaSelfItem(_ item: MenuBarItem) -> Bool {
        MenuBarController.isCoronaSelfIdentifier(item.tag.stableIdentifier)
            || item.ownerPID == Int32(ProcessInfo.processInfo.processIdentifier)
            || item.sourcePID == Int32(ProcessInfo.processInfo.processIdentifier)
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
