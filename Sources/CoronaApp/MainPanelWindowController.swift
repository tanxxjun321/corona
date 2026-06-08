import AppKit
import CoronaCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
private enum MenuBarMenuSuppressor {
    private static var savedMenu: NSMenu?
    private static var isSuppressed = false

    static func suppress() {
        guard !isSuppressed else { return }
        savedMenu = NSApplication.shared.mainMenu
        NSApplication.shared.mainMenu = suppressedMainMenu()
        isSuppressed = true
    }

    static func restore() {
        guard isSuppressed else { return }
        NSApplication.shared.mainMenu = savedMenu
        savedMenu = nil
        isSuppressed = false
    }

    private static func suppressedMainMenu() -> NSMenu {
        NSMenu(title: "")
    }
}

final class MainPanelWindowController: NSWindowController, NSWindowDelegate {
    private let model: MainPanelViewModel
    private let settingsModel: SettingsViewModel
    private var refreshTask: Task<Void, Never>?

    init(
        cacheController: MenuBarCacheController,
        layoutStore: LayoutPersistenceStore,
        settingsStore: SettingsStore,
        settings: AppSettings,
        permissionChecker: SystemPermissionChecker,
        thumbnailProvider: MenuBarThumbnailProviding,
        boundaryProvider: @escaping @MainActor () -> SectionBoundary?,
        visualCacheProvider: @escaping @MainActor () async throws -> ItemCache,
        visualCacheCleanup: @escaping @MainActor () -> Void,
        applyHandler: @escaping @MainActor () async -> LayoutApplicationResult,
        applyMoveHandler: @escaping @MainActor (String, SectionOrder) async -> LayoutApplicationResult,
        onSettingsChanged: @escaping (AppSettings) -> Void,
        onPermissionsChanged: @escaping () -> Void
    ) {
        self.model = MainPanelViewModel(
            cacheController: cacheController,
            layoutStore: layoutStore,
            settingsStore: settingsStore,
            permissionChecker: permissionChecker,
            visualSnapshotProvider: MenuBarVisualSnapshotProvider(thumbnailProvider: thumbnailProvider),
            boundaryProvider: boundaryProvider,
            visualCacheProvider: visualCacheProvider,
            visualCacheCleanup: visualCacheCleanup,
            applyHandler: applyHandler,
            applyMoveHandler: applyMoveHandler
        )
        self.settingsModel = SettingsViewModel(
            settings: settings,
            permissionChecker: permissionChecker,
            onSettingsChanged: onSettingsChanged,
            onPermissionsChanged: onPermissionsChanged
        )
        let hostingController = NSHostingController(rootView: MainPanelView(model: model, settingsModel: settingsModel))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Organize Menu Bar"
        window.setContentSize(NSSize(width: 980, height: 620))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    deinit {
        refreshTask?.cancel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }
        refreshTask?.cancel()
        model.prepareForPresentation()
        MenuBarMenuSuppressor.suppress()
        NSApplication.shared.setActivationPolicy(.regular)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else { return }
            self.model.refresh()
        }
        settingsModel.refreshPermissions()
    }

    func showSettings() {
        model.selectedTab = .settings
        show()
    }

    func refreshPermissions() {
        settingsModel.refreshPermissions()
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else { return }
            self.model.refresh()
        }
    }

    func windowWillClose(_ notification: Notification) {
        refreshTask?.cancel()
        MenuBarMenuSuppressor.restore()
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

enum MainPanelTab: Hashable {
    case organize
    case settings
}

@MainActor
final class MainPanelViewModel: ObservableObject {
    struct Row: Identifiable, Equatable {
        var id: String { uid }
        var uid: String
        var title: String
        var owner: String
        var detail: String
        var position: Int
        var isHidden: Bool
        var desiredSection: MenuBarSection
        var physicalSection: MenuBarSection
        var needsManualPlacement: Bool
        var isMovable: Bool
        var canHide: Bool
        var isSystemItem: Bool
        var thumbnail: NSImage
        var visualWidth: CGFloat
        var visualHeight: CGFloat
        var isPixelPreview: Bool
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isApplying = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var canRunCoreFeatures = false
    @Published var selectedTab: MainPanelTab = .organize
    @Published var searchText = ""
    @Published var selectedUID: String?

    private let cacheController: MenuBarCacheController
    private let layoutStore: LayoutPersistenceStore
    private let settingsStore: SettingsStore
    private let permissionChecker: SystemPermissionChecker
    private let visualSnapshotProvider: MenuBarVisualSnapshotProvider
    private let boundaryProvider: @MainActor () -> SectionBoundary?
    private let visualCacheProvider: @MainActor () async throws -> ItemCache
    private let visualCacheCleanup: @MainActor () -> Void
    private let applyHandler: @MainActor () async -> LayoutApplicationResult
    private let applyMoveHandler: @MainActor (String, SectionOrder) async -> LayoutApplicationResult
    private var draft = LayoutDraft()
    private var itemByUID: [String: MenuBarItem] = [:]
    private var physicalCache = ItemCache(displayID: nil, visibleItems: [], hiddenItems: [], alwaysHiddenItems: [])
    private var positionByUID: [String: Int] = [:]
    private var physicalSectionByUID: [String: MenuBarSection] = [:]
    private var pendingAutoApply = false
    private var pendingAutoApplyUID: String?
    private var newItemsSection: MenuBarSection = .visible
    private var newItemsPlacement: NewItemsPlacement = .append
    private var didExpandMenuBarForRendering = false

    init(
        cacheController: MenuBarCacheController,
        layoutStore: LayoutPersistenceStore,
        settingsStore: SettingsStore,
        permissionChecker: SystemPermissionChecker,
        visualSnapshotProvider: MenuBarVisualSnapshotProvider,
        boundaryProvider: @escaping @MainActor () -> SectionBoundary?,
        visualCacheProvider: @escaping @MainActor () async throws -> ItemCache,
        visualCacheCleanup: @escaping @MainActor () -> Void,
        applyHandler: @escaping @MainActor () async -> LayoutApplicationResult,
        applyMoveHandler: @escaping @MainActor (String, SectionOrder) async -> LayoutApplicationResult
    ) {
        self.cacheController = cacheController
        self.layoutStore = layoutStore
        self.settingsStore = settingsStore
        self.permissionChecker = permissionChecker
        self.visualSnapshotProvider = visualSnapshotProvider
        self.boundaryProvider = boundaryProvider
        self.visualCacheProvider = visualCacheProvider
        self.visualCacheCleanup = visualCacheCleanup
        self.applyHandler = applyHandler
        self.applyMoveHandler = applyMoveHandler
    }

    var visibleRows: [Row] {
        filteredRows.filter { displaySection(for: $0) == .visible }
    }

    var hiddenRows: [Row] {
        filteredRows.filter { displaySection(for: $0) == .hidden }
    }

    var alwaysHiddenRows: [Row] {
        filteredRows.filter { displaySection(for: $0) == .alwaysHidden }
    }

    var hasRows: Bool {
        !rows.isEmpty
    }

    var selectedRow: Row? {
        guard let selectedUID else { return filteredRows.first }
        return rows.first { $0.uid == selectedUID }
    }

    func refresh() {
        refresh(showLoading: true)
    }

    func prepareForPresentation() {
        didExpandMenuBarForRendering = false
    }

    private func refresh(showLoading: Bool) {
        let snapshot = permissionChecker.snapshot()
        canRunCoreFeatures = snapshot.canRunCoreFeatures
        statusMessage = snapshot.canRunCoreFeatures ? nil : "Accessibility permission is required before Corona can scan or move menu bar items."
        CoronaDebugLog.log("main.refresh permission canRun=\(snapshot.canRunCoreFeatures) status=\(snapshot.capabilityStatus)")
        guard snapshot.canRunCoreFeatures else {
            rows = []
            return
        }

        if showLoading {
            isLoading = true
        }
        errorMessage = nil
        Task {
            do {
                let cache = try await currentCache()
                CoronaDebugLog.log("main.refresh cache visible=\(cache.visibleItems.count) hidden=\(cache.hiddenItems.count) alwaysHidden=\(cache.alwaysHiddenItems.count) all=\(cache.allItems.count)")
                let manageableItems = cache.allItems.filter { item in
                    !Self.isCoronaSelfItem(item)
                }
                CoronaDebugLog.log("main.refresh manageable=\(manageableItems.count)")
                itemByUID = Dictionary(uniqueKeysWithValues: manageableItems.map { item in
                    (item.tag.stableIdentifier, item)
                })
                physicalCache = ItemCache(
                    displayID: cache.displayID,
                    visibleItems: cache.visibleItems.filter { !Self.isCoronaSelfItem($0) },
                    hiddenItems: cache.hiddenItems.filter { !Self.isCoronaSelfItem($0) },
                    alwaysHiddenItems: cache.alwaysHiddenItems.filter { !Self.isCoronaSelfItem($0) }
                )
                positionByUID = Self.positionMap(for: manageableItems)
                physicalSectionByUID = Self.sectionMap(for: cache)
                let settings = settingsStore.load()
                newItemsSection = MenuBarSection(settings.newItemsSection)
                newItemsPlacement = settings.newItemsPlacement
                draft = LayoutDraft(order: availableOrder(preferredOrder(cache: cache).removingCoronaSelfItems()))
                rebuildRows()
                CoronaDebugLog.log("main.refresh draft visible=\(draft.order.visible) hidden=\(draft.order.hidden) alwaysHidden=\(draft.order.alwaysHidden)")
                if selectedUID == nil || rows.contains(where: { $0.uid == selectedUID }) == false {
                    selectedUID = rows.first?.uid
                }
                if shouldExpandMenuBarForRendering() {
                    expandMenuBarAndRefresh()
                }
            } catch {
                CoronaDebugLog.log("main.refresh failed error=\(String(describing: error))")
                errorMessage = String(describing: error)
            }
            visualCacheCleanup()
            if showLoading {
                isLoading = false
            }
        }
    }

    func setHidden(_ hidden: Bool, uid: String) {
        guard canMove(uid: uid, to: hidden ? .hidden : .visible) else { return }
        CoronaDebugLog.log("main.setHidden uid=\(uid) hidden=\(hidden)")
        draft.move(uid, to: hidden ? .hidden : .visible)
        selectedUID = uid
        rebuildRows()
        persistAndApplyDraft(movedUID: uid)
    }

    func select(uid: String) {
        selectedUID = uid
    }

    func toggleHidden(uid: String) {
        guard let row = rows.first(where: { $0.uid == uid }) else { return }
        setHidden(!row.isHidden, uid: uid)
    }

    func move(uid: String, to section: MenuBarSection) {
        guard canMove(uid: uid, to: section) else { return }
        CoronaDebugLog.log("main.move uid=\(uid) section=\(section)")
        draft.move(uid, to: section)
        selectedUID = uid
        rebuildRows()
        persistAndApplyDraft(movedUID: uid)
    }

    func move(uid: String, to section: MenuBarSection, at index: Int) {
        guard canMove(uid: uid, to: section) else { return }
        CoronaDebugLog.log("main.move uid=\(uid) section=\(section) index=\(index)")
        draft.move(uid, to: section, at: desiredInsertionIndex(section: section, displayedIndex: index))
        selectedUID = uid
        rebuildRows()
        persistAndApplyDraft(movedUID: uid)
    }

    func moveNewItemsMarker(to section: MenuBarSection, at index: Int) {
        let sanitizedOrder = availableOrder(draft.order.removingCoronaSelfItems())
        let placement = newItemsPlacement(for: section, index: index, order: sanitizedOrder)
        var settings = settingsStore.load()
        settings.newItemsSection = NewItemsSection(section)
        settings.newItemsPlacement = placement
        settingsStore.save(settings)
        newItemsSection = section
        newItemsPlacement = placement
        statusMessage = "New menu bar items will appear in \(section.label)."
        CoronaDebugLog.log("main.moveNewItemsMarker section=\(section) index=\(index) placement=\(placement)")
        rebuildRows()
    }

    func newItemsMarkerIndex(in section: MenuBarSection, rowUIDs: [String]) -> Int? {
        guard section == newItemsSection else { return nil }
        switch newItemsPlacement {
        case .prepend:
            return 0
        case .append:
            return rowUIDs.count
        case .leftOf(let anchor):
            return rowUIDs.firstIndex(of: anchor) ?? rowUIDs.count
        case .rightOf(let anchor):
            return rowUIDs.firstIndex(of: anchor).map { min($0 + 1, rowUIDs.count) } ?? rowUIDs.count
        }
    }

    private func desiredInsertionIndex(section: MenuBarSection, displayedIndex: Int) -> Int {
        let displayedUIDs = filteredRows
            .filter { displaySection(for: $0) == section }
            .map(\.uid)
        let targetOrder = draft.order[section]

        if displayedIndex <= 0 {
            return 0
        }
        if displayedIndex >= displayedUIDs.count {
            return targetOrder.count
        }

        let previousUID = displayedUIDs[displayedIndex - 1]
        if let previousIndex = targetOrder.firstIndex(of: previousUID) {
            return targetOrder.index(after: previousIndex)
        }

        let nextUID = displayedUIDs[displayedIndex]
        if let nextIndex = targetOrder.firstIndex(of: nextUID) {
            return nextIndex
        }

        return targetOrder.count
    }

    func apply() {
        persistAndApplyDraft()
    }

    private func persistAndApplyDraft() {
        persistAndApplyDraft(movedUID: nil)
    }

    private func persistAndApplyDraft(movedUID: String?) {
        let sanitizedOrder = persistDraft()
        CoronaDebugLog.log("main.autoApply requested movedUID=\(movedUID ?? "nil") visible=\(sanitizedOrder.visible) hidden=\(sanitizedOrder.hidden) alwaysHidden=\(sanitizedOrder.alwaysHidden)")
        guard !isApplying else {
            pendingAutoApply = true
            pendingAutoApplyUID = movedUID
            statusMessage = "Applying latest changes..."
            CoronaDebugLog.log("main.autoApply queued")
            return
        }

        isApplying = true
        statusMessage = nil
        Task {
            await runAutoApplyLoop(initialOrder: sanitizedOrder, movedUID: movedUID)
        }
    }

    private func persistDraft() -> SectionOrder {
        let sanitizedOrder = availableOrder(draft.order.removingCoronaSelfItems())
        draft = LayoutDraft(order: sanitizedOrder)
        layoutStore.saveSavedSectionOrder(sanitizedOrder)
        layoutStore.saveKnownItemIdentifiers(Set(sanitizedOrder.visible + sanitizedOrder.hidden + sanitizedOrder.alwaysHidden))
        CoronaDebugLog.log("main.persistDraft visible=\(sanitizedOrder.visible) hidden=\(sanitizedOrder.hidden) alwaysHidden=\(sanitizedOrder.alwaysHidden)")
        return sanitizedOrder
    }

    private func runAutoApplyLoop(initialOrder: SectionOrder, movedUID: String?) async {
        var orderForStatus = initialOrder
        var uidForApply = movedUID

        while true {
            pendingAutoApply = false
            pendingAutoApplyUID = nil
            statusMessage = "Applying changes..."
            CoronaDebugLog.log("main.autoApply savedOnly movedUID=\(uidForApply ?? "nil") visible=\(orderForStatus.visible) hidden=\(orderForStatus.hidden) alwaysHidden=\(orderForStatus.alwaysHidden)")

            let result: LayoutApplicationResult
            if let uidForApply {
                result = await applyMoveHandler(uidForApply, orderForStatus)
            } else {
                result = await applyHandler()
            }
            CoronaDebugLog.log("main.autoApply result=\(result.statusTitle)")

            if pendingAutoApply {
                orderForStatus = availableOrder(draft.order.removingCoronaSelfItems())
                uidForApply = pendingAutoApplyUID
                CoronaDebugLog.log("main.autoApply continueWithPending visible=\(orderForStatus.visible) hidden=\(orderForStatus.hidden) alwaysHidden=\(orderForStatus.alwaysHidden)")
                continue
            }

            isApplying = false
            if result.isSuccessfulApply {
                statusMessage = result.statusTitle
                refresh(showLoading: false)
            } else {
                statusMessage = hasManualPlacementMismatches(in: orderForStatus)
                    ? "\(result.statusTitle). Some icons still need placement."
                    : result.statusTitle
                CoronaDebugLog.log("main.autoApply keepDraftAfterFailure visible=\(draft.order.visible) hidden=\(draft.order.hidden) alwaysHidden=\(draft.order.alwaysHidden)")
                rebuildRows()
            }
            return
        }
    }

    func openPermissions() {
        selectedTab = .settings
    }

    private var filteredRows: [Row] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        return rows.filter { row in
            row.title.localizedCaseInsensitiveContains(query)
                || row.owner.localizedCaseInsensitiveContains(query)
                || row.detail.localizedCaseInsensitiveContains(query)
        }
    }

    private func currentCache() async throws -> ItemCache {
        try await visualCacheProvider()
    }

    private func canMove(uid: String, to section: MenuBarSection) -> Bool {
        guard let item = itemByUID[uid], item.isMovable else { return false }
        return section == .visible || item.canBeHidden
    }

    private func newItemsPlacement(for section: MenuBarSection, index: Int, order: SectionOrder) -> NewItemsPlacement {
        let uids = order[section]
        guard !uids.isEmpty else { return .append }
        if index <= 0 {
            return .prepend
        }
        if index >= uids.count {
            return .append
        }
        return .rightOf(uids[index - 1])
    }

    private func preferredOrder(cache: ItemCache) -> SectionOrder {
        let savedOrder = layoutStore.loadSavedSectionOrder().removingCoronaSelfItems()
        let currentOrder = SectionOrder(cache: cache).removingCoronaSelfItems()
        return organizerOrder(savedOrder: savedOrder, currentOrder: currentOrder)
    }

    private func layoutPreference() -> LayoutPreference {
        let settings = settingsStore.load()
        return LayoutPreference(
            savedOrder: layoutStore.loadSavedSectionOrder(),
            newItemsSection: MenuBarSection(settings.newItemsSection),
            newItemsPlacement: settings.newItemsPlacement,
            alwaysHiddenEnabled: settings.enableAlwaysHiddenSection
        )
    }

    private func rebuildRows() {
        let sanitizedOrder = availableOrder(draft.order.removingCoronaSelfItems())
        draft = LayoutDraft(order: sanitizedOrder)
        rows = visualRows(for: sanitizedOrder)
        if let selectedUID, rows.contains(where: { $0.uid == selectedUID }) == false {
            self.selectedUID = rows.first?.uid
        }
    }

    private func availableOrder(_ order: SectionOrder) -> SectionOrder {
        let availableUIDs = Set(itemByUID.keys)
        var result = SectionOrder(
            visible: order.visible.filter { availableUIDs.contains($0) },
            hidden: order.hidden.filter { availableUIDs.contains($0) },
            alwaysHidden: order.alwaysHidden.filter { availableUIDs.contains($0) }
        )

        let protectedUIDs = Set(itemByUID.values.filter { !$0.canBeHidden }.map(\.tag.stableIdentifier))
        let protectedInHidden = (result.hidden + result.alwaysHidden).filter { protectedUIDs.contains($0) }
        guard !protectedInHidden.isEmpty else { return result }

        result.hidden.removeAll { protectedUIDs.contains($0) }
        result.alwaysHidden.removeAll { protectedUIDs.contains($0) }
        for uid in protectedInHidden.sorted(by: physicalOrder) where !result.visible.contains(uid) {
            result.visible.append(uid)
        }
        return result
    }

    private func savedIntentOrder(savedOrder: SectionOrder, currentOrder: SectionOrder) -> SectionOrder {
        let currentUIDs = Set(currentOrder.visible + currentOrder.hidden + currentOrder.alwaysHidden)
        let savedUIDs = Set(savedOrder.visible + savedOrder.hidden + savedOrder.alwaysHidden)
        var result = SectionOrder(
            visible: savedOrder.visible.filter { currentUIDs.contains($0) },
            hidden: savedOrder.hidden.filter { currentUIDs.contains($0) },
            alwaysHidden: savedOrder.alwaysHidden.filter { currentUIDs.contains($0) }
        )

        for section in MenuBarSection.allCases {
            for uid in currentOrder[section] where !savedUIDs.contains(uid) {
                result[section].append(uid)
            }
        }
        return result
    }

    private func organizerOrder(savedOrder: SectionOrder, currentOrder: SectionOrder) -> SectionOrder {
        let currentUIDs = Set(currentOrder.visible + currentOrder.hidden + currentOrder.alwaysHidden)
        let savedHiddenUIDs = Set(savedOrder.hidden + savedOrder.alwaysHidden)
        var result = SectionOrder(
            visible: currentOrder.visible.filter { !savedHiddenUIDs.contains($0) },
            hidden: savedOrder.hidden.filter { currentUIDs.contains($0) },
            alwaysHidden: savedOrder.alwaysHidden.filter { currentUIDs.contains($0) }
        )

        for uid in currentOrder.hidden where !result.hidden.contains(uid) && !result.alwaysHidden.contains(uid) {
            result.hidden.append(uid)
        }
        for uid in currentOrder.alwaysHidden where !result.alwaysHidden.contains(uid) && !result.hidden.contains(uid) {
            result.alwaysHidden.append(uid)
        }

        let assignedUIDs = Set(result.visible + result.hidden + result.alwaysHidden)
        for uid in currentOrder.visible where !assignedUIDs.contains(uid) {
            result.visible.append(uid)
        }
        return result
    }

    private func visualRows(for order: SectionOrder) -> [Row] {
        visualSnapshotProvider.snapshot(cache: physicalCache, desiredOrder: order)
            .items
            .compactMap(makeRow(from:))
    }

    private func makeRow(from item: MenuBarVisualItem) -> Row? {
        guard !MenuBarController.isCoronaSelfIdentifier(item.uid) else {
            return nil
        }
        let displaySection = displaySection(
            desiredSection: item.desiredSection,
            physicalSection: item.physicalSection
        )
        let placementDetail = placementDetail(
            desiredSection: item.desiredSection,
            physicalSection: item.physicalSection,
            canReorder: item.isMovable,
            canHide: item.canHide
        )
        return Row(
            uid: item.uid,
            title: item.title,
            owner: item.owner,
            detail: "#\(item.position)  \(placementDetail)  x \(Int(item.bounds.minX))-\(Int(item.bounds.maxX))",
            position: item.position,
            isHidden: displaySection != .visible,
            desiredSection: item.desiredSection,
            physicalSection: item.physicalSection,
            needsManualPlacement: item.needsApply,
            isMovable: item.isMovable,
            canHide: item.canHide,
            isSystemItem: item.isSystemItem,
            thumbnail: item.thumbnail,
            visualWidth: max(item.bounds.width, 1),
            visualHeight: max(item.bounds.height, 1),
            isPixelPreview: item.isPixelPreview
        )
    }

    private func displaySection(for row: Row) -> MenuBarSection {
        displaySection(desiredSection: row.desiredSection, physicalSection: row.physicalSection)
    }

    private func displaySection(
        desiredSection: MenuBarSection,
        physicalSection: MenuBarSection
    ) -> MenuBarSection {
        if physicalSection == .visible && desiredSection != .visible {
            return .hidden
        }
        return physicalSection
    }

    private func shouldExpandMenuBarForRendering() -> Bool {
        guard !didExpandMenuBarForRendering else { return false }
        guard settingsStore.load().enableScreenRecordingPreviews,
              permissionChecker.snapshot().canShowPixelPreviews else {
            return false
        }
        return rows.contains { !$0.isPixelPreview }
    }

    private func expandMenuBarAndRefresh() {
        didExpandMenuBarForRendering = true
        let failedUIDs = rows.filter { !$0.isPixelPreview }.map(\.uid)
        CoronaDebugLog.log("main.render.expandForFallback count=\(failedUIDs.count) uids=\(failedUIDs)")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            refresh(showLoading: false)
        }
    }

    private func hasManualPlacementMismatches(in order: SectionOrder) -> Bool {
        for section in MenuBarSection.allCases {
            for uid in order[section] {
                guard let item = itemByUID[uid], item.isMovable, item.canBeHidden else {
                    continue
                }
                if (physicalSectionByUID[uid] ?? .visible) != section {
                    return true
                }
            }
        }
        return false
    }

    private func placementDetail(
        desiredSection: MenuBarSection,
        physicalSection: MenuBarSection,
        canReorder: Bool,
        canHide: Bool
    ) -> String {
        guard canReorder else { return "Locked: cannot be reordered" }
        guard desiredSection == .visible || canHide else { return "Cannot be hidden" }
        guard desiredSection != physicalSection else {
            return "Ready  desired \(desiredSection.label)  physical \(physicalSection.label)"
        }
        switch (desiredSection, physicalSection) {
        case (.visible, _):
            return "Needs manual placement: drag right of Corona"
        case (_, .visible):
            return "Needs manual placement: drag left of Corona"
        default:
            return "Needs manual placement: desired \(desiredSection.label), physical \(physicalSection.label)"
        }
    }

    private func physicalOrder(_ lhs: String, _ rhs: String) -> Bool {
        (positionByUID[lhs] ?? Int.max) < (positionByUID[rhs] ?? Int.max)
    }

    private static func isCoronaSelfItem(_ item: MenuBarItem) -> Bool {
        MenuBarController.isCoronaSelfIdentifier(item.tag.stableIdentifier)
            || item.ownerPID == Int32(ProcessInfo.processInfo.processIdentifier)
            || item.sourcePID == Int32(ProcessInfo.processInfo.processIdentifier)
    }

    private static func positionMap(for items: [MenuBarItem]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: items
            .sorted { lhs, rhs in
                if lhs.bounds.minX != rhs.bounds.minX {
                    return lhs.bounds.minX < rhs.bounds.minX
                }
                return lhs.windowID < rhs.windowID
            }
            .enumerated()
            .map { index, item in
                (item.tag.stableIdentifier, index + 1)
            })
    }

    private static func sectionMap(for cache: ItemCache) -> [String: MenuBarSection] {
        var result: [String: MenuBarSection] = [:]
        for item in cache.visibleItems {
            result[item.tag.stableIdentifier] = .visible
        }
        for item in cache.hiddenItems {
            result[item.tag.stableIdentifier] = .hidden
        }
        for item in cache.alwaysHiddenItems {
            result[item.tag.stableIdentifier] = .alwaysHidden
        }
        return result
    }
}

private struct MainPanelView: View {
    @ObservedObject var model: MainPanelViewModel
    @ObservedObject var settingsModel: SettingsViewModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            VStack(spacing: 0) {
                toolbar
                Divider()
                content
                Divider()
                footer
            }
            .tabItem {
                Label("Organize", systemImage: "menubar.rectangle")
            }
            .tag(MainPanelTab.organize)

            SettingsView(model: settingsModel)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(MainPanelTab.settings)
        }
        .frame(minWidth: 920, minHeight: 560)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Drag your menu bar items to arrange them as you want.")
                .font(.headline)
            Spacer()
            TextField("Search", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh detected menu bar items")
        }
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !model.canRunCoreFeatures {
            VStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("Accessibility permission is required.")
                    .font(.headline)
                Text("Screen Recording only enables icon previews; it is not required for hiding.")
                    .foregroundStyle(.secondary)
                Button("Open Permissions") {
                    model.openPermissions()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = model.errorMessage {
            Text(errorMessage)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !model.hasRows {
            Text("No menu bar items detected")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            MenuBarPreview(model: model)
                .padding(20)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let statusMessage = model.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Changes apply automatically after dragging.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if model.isApplying {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(14)
    }
}

private struct MenuBarPreview: View {
    @ObservedObject var model: MainPanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PreviewSection(
                title: "Shown menu bar items",
                section: .visible,
                rows: model.visibleRows,
                model: model
            )
            PreviewSection(
                title: "Hidden menu bar items",
                section: .hidden,
                rows: model.hiddenRows,
                model: model
            )
            PreviewSection(
                title: "Always Hidden menu bar items",
                section: .alwaysHidden,
                rows: model.alwaysHiddenRows,
                model: model
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct PreviewSection: View {
    var title: String
    var section: MenuBarSection
    var rows: [MainPanelViewModel.Row]
    @ObservedObject var model: MainPanelViewModel

    private var railHeight: CGFloat {
        max(rows.map(\.visualHeight).max() ?? 24, 24)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3)
                .fontWeight(.regular)

            GeometryReader { geometry in
                let rowUIDs = rows.map(\.uid)
                ZStack(alignment: .leading) {
                    MenuBarRailBackground()
                    ScrollView(.horizontal) {
                        HStack(spacing: 0) {
                            InsertDropZone(
                                section: section,
                                targetIndex: 0,
                                model: model
                            )
                            if model.newItemsMarkerIndex(in: section, rowUIDs: rowUIDs) == 0 {
                                NewItemsMarkerView()
                            }
                            ForEach(Array(rows.enumerated()), id: \.element.uid) { index, row in
                                HStack(spacing: 0) {
                                    PreviewChip(
                                        row: row,
                                        isSelected: model.selectedUID == row.uid,
                                        model: model
                                    )
                                    InsertDropZone(
                                        section: section,
                                        targetIndex: index + 1,
                                        model: model
                                    )
                                    if model.newItemsMarkerIndex(in: section, rowUIDs: rowUIDs) == index + 1 {
                                        NewItemsMarkerView()
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minWidth: geometry.size.width, alignment: .leading)
                    }
                    .scrollIndicators(.visible)
                }
                .onDrop(
                    of: [UTType.plainText],
                    delegate: MenuBarItemDropDelegate(
                        section: section,
                        targetIndex: rows.count,
                        model: model
                    )
                )
            }
            .frame(height: railHeight)
        }
    }
}

private struct MenuBarItemDropDelegate: DropDelegate {
    var section: MenuBarSection
    var targetIndex: Int
    var model: MainPanelViewModel

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [UTType.plainText]).first else {
            return false
        }
        MenuBarDragPayload.load(from: provider) { payload in
            Task { @MainActor in
                switch payload {
                case .item(let uid):
                    model.move(uid: uid, to: section, at: targetIndex)
                case .newItemsMarker:
                    model.moveNewItemsMarker(to: section, at: targetIndex)
                }
            }
        }
        return true
    }
}

private enum MenuBarDragPayload {
    enum Payload {
        case item(String)
        case newItemsMarker
    }

    private static let newItemsMarkerToken = "__corona_new_items_marker__"

    static func provider(uid: String) -> NSItemProvider {
        provider(value: uid)
    }

    static func newItemsMarkerProvider() -> NSItemProvider {
        provider(value: newItemsMarkerToken)
    }

    private static func provider(value: String) -> NSItemProvider {
        let provider = NSItemProvider(object: value as NSString)
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.plainText.identifier,
            visibility: .all
        ) { completion in
            completion(value.data(using: .utf8), nil)
            return nil
        }
        return provider
    }

    static func load(from provider: NSItemProvider, completion: @escaping (Payload) -> Void) {
        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
            if let data = item as? Data, let uid = String(data: data, encoding: .utf8) {
                completion(payload(for: uid))
                return
            }
            if let uid = item as? String {
                completion(payload(for: uid))
                return
            }
            if let uid = item as? NSString {
                completion(payload(for: uid as String))
                return
            }

            provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                guard let data,
                      let uid = String(data: data, encoding: .utf8) else { return }
                completion(payload(for: uid))
            }
        }
    }

    private static func payload(for value: String) -> Payload {
        value == newItemsMarkerToken ? .newItemsMarker : .item(value)
    }
}

private struct InsertDropZone: View {
    var section: MenuBarSection
    var targetIndex: Int
    @ObservedObject var model: MainPanelViewModel
    @State private var isTargeted = false

    var body: some View {
        Rectangle()
            .fill(isTargeted ? Color.accentColor.opacity(0.9) : Color.clear)
            .frame(width: isTargeted ? 8 : 0, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .onDrop(
                of: [UTType.plainText],
                isTargeted: $isTargeted,
                perform: performDrop(providers:)
            )
    }

    private func performDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) else {
            return false
        }
        MenuBarDragPayload.load(from: provider) { payload in
            Task { @MainActor in
                switch payload {
                case .item(let uid):
                    model.move(uid: uid, to: section, at: targetIndex)
                case .newItemsMarker:
                    model.moveNewItemsMarker(to: section, at: targetIndex)
                }
            }
        }
        return true
    }
}

private struct NewItemsMarkerView: View {
    var body: some View {
        Text("New menu bar items appear here")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.purple.opacity(0.86))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 2)
            .onDrag {
                MenuBarDragPayload.newItemsMarkerProvider()
            }
            .help("Drag to choose where newly detected menu bar items should appear")
    }
}

private struct MenuBarRailBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
    }
}

private struct PreviewChip: View {
    var row: MainPanelViewModel.Row
    var isSelected: Bool
    @ObservedObject var model: MainPanelViewModel

    var body: some View {
        ZStack(alignment: .center) {
            if isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.18))
            }
            Image(nsImage: row.thumbnail)
                .resizable()
                .frame(width: row.visualWidth, height: row.visualHeight)
                .foregroundStyle(row.isMovable ? .primary : .secondary)
        }
        .frame(width: row.visualWidth, height: row.visualHeight)
        .contentShape(Rectangle())
        .overlay(
            statusIndicator,
            alignment: .topTrailing
        )
        .onTapGesture {
            model.select(uid: row.uid)
        }
        .help("\(row.title) - \(row.owner)")
        .onDrag {
            MenuBarDragPayload.provider(uid: row.uid)
        }
        .opacity(row.isMovable ? 1 : 0.58)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if !row.isMovable || row.needsManualPlacement {
            Image(systemName: !row.isMovable ? "lock.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(!row.isMovable ? Color.secondary : Color.orange)
                .offset(x: 3, y: -3)
        }
    }
}

private struct InspectorPane: View {
    @ObservedObject var model: MainPanelViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            selectedDetails
                .frame(minWidth: 300, maxWidth: 360, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
            Divider()
            diagnosticList
        }
    }

    @ViewBuilder
    private var selectedDetails: some View {
        if let row = model.selectedRow {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("#\(row.position)")
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 48, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(row.owner)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack {
                    Label(row.isHidden ? "Hidden" : row.canHide ? "Visible" : "Shown only", systemImage: row.isHidden ? "eye.slash" : row.canHide ? "eye" : "arrow.left.arrow.right")
                    Spacer()
                    Button(row.isHidden ? "Show" : "Hide") {
                        model.toggleHidden(uid: row.uid)
                    }
                    .disabled(row.isHidden ? !row.isMovable : (!row.isMovable || !row.canHide))
                }

                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(row.needsManualPlacement ? .orange : .secondary)
                    .lineLimit(3)
            }
        } else {
            Text("Select an item")
                .foregroundStyle(.secondary)
        }
    }

    private var diagnosticList: some View {
        List(model.visibleRows + model.hiddenRows + model.alwaysHiddenRows) { row in
            MainPanelRow(row: row, model: model)
                .listRowSeparator(.hidden)
                .onTapGesture {
                    model.select(uid: row.uid)
                }
        }
        .listStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MainPanelRow: View {
    var row: MainPanelViewModel.Row
    @ObservedObject var model: MainPanelViewModel

    var body: some View {
        HStack(spacing: 10) {
            Text("#\(row.position)")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(row.isMovable ? .primary : .secondary)
                .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .lineLimit(1)
                Text(row.owner)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(row.detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if row.needsManualPlacement {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help(row.detail)
            }
            Toggle("Hidden", isOn: Binding(
                get: { row.isHidden },
                set: { model.setHidden($0, uid: row.uid) }
            ))
            .labelsHidden()
            .disabled(row.isHidden ? !row.isMovable : (!row.isMovable || !row.canHide))
            .help(row.canHide ? "Hide this menu bar item" : "This item can be reordered but not hidden")
        }
        .padding(.vertical, 6)
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

    var label: String {
        switch self {
        case .visible:
            return "visible"
        case .hidden:
            return "hidden"
        case .alwaysHidden:
            return "always hidden"
        }
    }
}

private extension NewItemsSection {
    init(_ section: MenuBarSection) {
        switch section {
        case .visible:
            self = .visible
        case .hidden:
            self = .hidden
        case .alwaysHidden:
            self = .alwaysHidden
        }
    }
}
