import AppKit
import SwiftUI

@MainActor
final class HiddenItemsHoverBarController {
    private let model: HiddenItemsHoverBarModel
    private var panel: NSPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var hideTask: Task<Void, Never>?

    init(
        cacheController: MenuBarCacheController,
        layoutStore: LayoutPersistenceStore,
        thumbnailProvider: MenuBarThumbnailProviding,
        permissionChecker: SystemPermissionChecker,
        boundaryProvider: @escaping @MainActor () -> SectionBoundary?,
        visualCacheProvider: @escaping @MainActor () async throws -> ItemCache,
        visualCacheCleanup: @escaping @MainActor () -> Void,
        revealHandler: @escaping @MainActor (String) async -> LayoutApplicationResult
    ) {
        self.model = HiddenItemsHoverBarModel(
            cacheController: cacheController,
            layoutStore: layoutStore,
            thumbnailProvider: thumbnailProvider,
            permissionChecker: permissionChecker,
            boundaryProvider: boundaryProvider,
            visualCacheProvider: visualCacheProvider,
            visualCacheCleanup: visualCacheCleanup,
            revealHandler: revealHandler
        )
    }

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseMoved()
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor in
                self?.handleMouseMoved()
            }
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
        hideTask?.cancel()
        panel?.orderOut(nil)
    }

    func show(attachedTo button: NSStatusBarButton) {
        guard let window = button.window else { return }
        if panel?.isVisible == true {
            panel?.orderOut(nil)
            return
        }

        let anchorFrame = window.frame
        let screen = window.screen
            ?? NSScreen.screens.first(where: { $0.frame.intersects(anchorFrame) })
            ?? NSScreen.main

        Task { @MainActor in
            guard let screen else { return }
            await model.refreshNow(on: screen)
            show(near: anchorFrame, on: screen)
        }
    }

    private func handleMouseMoved() {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            model.refreshTriggerFrame(on: screen)
            if let triggerFrame = model.triggerFrame,
               triggerFrame.contains(mouse) {
                show(near: triggerFrame, on: screen)
                return
            }
        }

        if let panel, panel.frame.insetBy(dx: -12, dy: -12).contains(mouse) {
            hideTask?.cancel()
            return
        }

        scheduleHide()
    }

    private func show(near triggerFrame: CGRect, on screen: NSScreen) {
        hideTask?.cancel()
        let panel = ensurePanel()
        model.refresh(on: screen)
        panel.backgroundColor = model.menuBarBackgroundColor

        let width = min(max(model.replicaWidth, 1), screen.frame.width - 32)
        let height = model.replicaHeight
        let preferredMaxX = min(screen.frame.maxX - 12, triggerFrame.maxX + 8)
        let x = min(max(preferredMaxX - width, screen.frame.minX + 2), screen.frame.maxX - width - 12)
        let preferredY = triggerFrame.minY - 2 - height
        let y = min(max(preferredY, screen.frame.minY + 2), screen.frame.maxY - height - 2)

        panel.setFrame(CGRect(x: x, y: y, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let self, !Task.isCancelled else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let hostingController = NSHostingController(rootView: HiddenItemsHoverBarView(model: model))
        let effectView = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: 260, height: 37))
        effectView.material = .menu
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.autoresizingMask = [.width, .height]
        hostingController.view.frame = effectView.bounds
        hostingController.view.autoresizingMask = [.width, .height]
        effectView.addSubview(hostingController.view)

        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 260, height: 37),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = effectView
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        self.panel = panel
        return panel
    }

}

@MainActor
final class HiddenItemsHoverBarModel: ObservableObject {
    struct Row: Identifiable {
        var id: String { uid }
        var uid: String
        var title: String
        var thumbnail: NSImage
        var isAvailable: Bool
        var itemWidth: CGFloat
        var itemHeight: CGFloat
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var revealingUID: String?
    @Published private(set) var triggerFrame: CGRect?
    @Published private(set) var menuBarBackgroundColor = MenuBarAppearanceSampler.backgroundColor(displayID: nil)

    var replicaWidth: CGFloat {
        let contentWidth = rows.reduce(CGFloat.zero) { partialResult, row in
            partialResult + row.itemWidth
        }
        return max(contentWidth, 32)
    }

    var replicaHeight: CGFloat {
        let maxItemHeight = rows.map(\.itemHeight).max() ?? 24
        return min(max(maxItemHeight, 24), 40)
    }

    private let cacheController: MenuBarCacheController
    private let layoutStore: LayoutPersistenceStore
    private let thumbnailProvider: MenuBarThumbnailProviding
    private let permissionChecker: SystemPermissionChecker
    private let boundaryProvider: @MainActor () -> SectionBoundary?
    private let visualCacheProvider: @MainActor () async throws -> ItemCache
    private let visualCacheCleanup: @MainActor () -> Void
    private let revealHandler: @MainActor (String) async -> LayoutApplicationResult
    private var isRefreshing = false
    private var isRefreshingTriggerFrame = false
    private var lastRefreshAt: Date?
    private var lastTriggerRefreshAt: Date?
    private let geometry = MenuBarInteractionGeometry()

    init(
        cacheController: MenuBarCacheController,
        layoutStore: LayoutPersistenceStore,
        thumbnailProvider: MenuBarThumbnailProviding,
        permissionChecker: SystemPermissionChecker,
        boundaryProvider: @escaping @MainActor () -> SectionBoundary?,
        visualCacheProvider: @escaping @MainActor () async throws -> ItemCache,
        visualCacheCleanup: @escaping @MainActor () -> Void,
        revealHandler: @escaping @MainActor (String) async -> LayoutApplicationResult
    ) {
        self.cacheController = cacheController
        self.layoutStore = layoutStore
        self.thumbnailProvider = thumbnailProvider
        self.permissionChecker = permissionChecker
        self.boundaryProvider = boundaryProvider
        self.visualCacheProvider = visualCacheProvider
        self.visualCacheCleanup = visualCacheCleanup
        self.revealHandler = revealHandler
    }

    func refresh(on screen: NSScreen? = nil) {
        guard !isRefreshing, permissionChecker.snapshot().canRunCoreFeatures else { return }
        if let lastRefreshAt, Date().timeIntervalSince(lastRefreshAt) < 0.35 {
            return
        }
        lastRefreshAt = Date()
        isRefreshing = true
        Task {
            defer { isRefreshing = false }
            await refreshNow(on: screen)
        }
    }

    func refreshNow(on screen: NSScreen? = nil) async {
        guard permissionChecker.snapshot().canRunCoreFeatures else { return }
        do {
            let cache = targetScopedCache(try await visualCacheProvider(), on: screen)
            menuBarBackgroundColor = MenuBarAppearanceSampler.backgroundColor(displayID: cache.displayID ?? screen?.displayID)
            let itemByUID = Dictionary(uniqueKeysWithValues: cache.allItems.map { item in
                (item.tag.stableIdentifier, item)
            })
            let order = layoutStore.loadSavedSectionOrder()
                .removingCoronaSelfItems()
                .removingLegacyAXGeneratedItems()
            let physicalHiddenUIDs = (cache.hiddenItems + cache.alwaysHiddenItems)
                .map(\.tag.stableIdentifier)
                .filter {
                    !MenuBarController.isCoronaSelfIdentifier($0)
                        && !MenuBarController.isLegacyAXGeneratedIdentifier($0)
                }
            let savedHiddenUIDs = (order.hidden + order.alwaysHidden).filter { itemByUID[$0] != nil }
            rows = makeRows(
                uids: mergedHiddenUIDs(saved: savedHiddenUIDs, physical: physicalHiddenUIDs),
                itemByUID: itemByUID
            )
        } catch {
            CoronaDebugLog.log("hoverBar.refresh failed error=\(String(describing: error))")
        }
        visualCacheCleanup()
    }

    private func currentCache() async throws -> ItemCache {
        if let boundary = boundaryProvider() {
            return try await cacheController.cache(boundary: boundary)
        }
        let snapshot = try await cacheController.snapshot(refreshIfNeeded: false)
        return ItemCache(displayID: snapshot.displayID, visibleItems: snapshot.items, hiddenItems: [], alwaysHiddenItems: [])
    }

    private func targetScopedCache(_ cache: ItemCache, on screen: NSScreen?) -> ItemCache {
        guard let screen else { return cache }
        if let displayID = cache.displayID, screen.displayID != displayID {
            CoronaDebugLog.log("hoverBar.targetScope skippedNonManagedScreen cacheDisplayID=\(displayID) screenDisplayID=\(screen.displayID)")
            return cache
        }
        let targetFrame = screen.frame
        let otherFrames = NSScreen.screens
            .map(\.frame)
            .filter { !$0.equalTo(targetFrame) }
        let filter = MenuBarTargetDisplayFilter(
            targetDisplayFrame: targetFrame,
            otherDisplayFrames: otherFrames
        )
        return ItemCache(
            displayID: cache.displayID,
            visibleItems: filter.itemsOnTargetDisplay(cache.visibleItems),
            hiddenItems: filter.itemsOnTargetDisplay(cache.hiddenItems),
            alwaysHiddenItems: filter.itemsOnTargetDisplay(cache.alwaysHiddenItems)
        )
    }

    func refreshTriggerFrame(on screen: NSScreen) {
        guard !isRefreshingTriggerFrame, permissionChecker.snapshot().canRunCoreFeatures else { return }
        if let lastTriggerRefreshAt, Date().timeIntervalSince(lastTriggerRefreshAt) < 0.4 {
            return
        }
        lastTriggerRefreshAt = Date()
        isRefreshingTriggerFrame = true
        Task {
            defer { isRefreshingTriggerFrame = false }
            do {
                let snapshot = try await cacheController.snapshot(refreshIfNeeded: false)
                let itemBounds = snapshot.items
                    .filter { !MenuBarController.isCoronaSelfIdentifier($0.tag.stableIdentifier) }
                    .map(\.bounds)
                triggerFrame = geometry.statusItemTriggerFrame(
                    itemBounds: itemBounds,
                    screenFrame: screen.frame
                )
            } catch {
                CoronaDebugLog.log("hoverBar.triggerRefresh failed error=\(String(describing: error))")
            }
        }
    }

    var hasSavedHiddenItems: Bool {
        let order = layoutStore.loadSavedSectionOrder()
            .removingCoronaSelfItems()
            .removingLegacyAXGeneratedItems()
        return !order.hidden.isEmpty || !rows.isEmpty
    }

    private func mergedHiddenUIDs(saved: [String], physical: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for uid in saved + physical where !seen.contains(uid) {
            seen.insert(uid)
            result.append(uid)
        }
        return result
    }

    func reveal(uid: String) {
        revealingUID = uid
        Task {
            let result = await revealHandler(uid)
            CoronaDebugLog.log("hoverBar.reveal uid=\(uid) result=\(result.statusTitle)")
            revealingUID = nil
            refresh()
        }
    }

    private func makeRows(uids: [String], itemByUID: [String: MenuBarItem]) -> [Row] {
        uids.map { uid in
            guard let item = itemByUID[uid] else {
                return Row(
                    uid: uid,
                    title: uid,
                    thumbnail: NSImage(systemSymbolName: "questionmark.app.dashed", accessibilityDescription: uid)
                        ?? NSWorkspace.shared.icon(for: .applicationBundle),
                    isAvailable: false,
                    itemWidth: 28,
                    itemHeight: 24
                )
            }
            return Row(
                uid: uid,
                title: item.title ?? item.tag.title,
                thumbnail: thumbnailProvider.thumbnail(for: item),
                isAvailable: true,
                itemWidth: max(item.bounds.width, 1),
                itemHeight: max(item.bounds.height, 1)
            )
        }
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
    }
}

private struct HiddenItemsHoverBarView: View {
    @ObservedObject var model: HiddenItemsHoverBarModel

    var body: some View {
        HStack(spacing: 0) {
            if model.rows.isEmpty {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: model.replicaHeight)
            } else {
                ForEach(model.rows) { row in
                    Button {
                        model.reveal(uid: row.uid)
                    } label: {
                        ZStack {
                            Image(nsImage: row.thumbnail)
                                .resizable()
                                .frame(width: row.itemWidth, height: row.itemHeight)
                                .opacity(row.isAvailable ? 1 : 0.45)
                            if model.revealingUID == row.uid {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        .frame(width: row.itemWidth, height: model.replicaHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(row.title)
                    .disabled(!row.isAvailable || model.revealingUID != nil)
                }
            }
        }
        .frame(width: model.replicaWidth, height: model.replicaHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: model.menuBarBackgroundColor))
        .clipShape(Rectangle())
        .overlay(
            Rectangle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
