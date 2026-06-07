import AppKit
import CoronaCore
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
        revealHandler: @escaping @MainActor (String) async -> LayoutApplicationResult
    ) {
        self.model = HiddenItemsHoverBarModel(
            cacheController: cacheController,
            layoutStore: layoutStore,
            thumbnailProvider: thumbnailProvider,
            permissionChecker: permissionChecker,
            boundaryProvider: boundaryProvider,
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
        guard model.hasSavedHiddenItems else {
            panel?.orderOut(nil)
            return
        }
        hideTask?.cancel()
        let panel = ensurePanel()
        model.refresh()

        let width = min(max(model.replicaWidth, 180), screen.frame.width - 32)
        let height = model.replicaHeight
        let preferredMaxX = min(screen.frame.maxX - 12, triggerFrame.maxX + 8)
        let x = min(max(preferredMaxX - width, screen.frame.minX + 2), screen.frame.maxX - width - 12)
        let y: CGFloat
        if triggerFrame.midY > screen.frame.midY {
            y = screen.frame.maxY - 10 - height
        } else {
            y = screen.frame.minY + 10
        }

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
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 260, height: 54),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
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

    var replicaWidth: CGFloat {
        let contentWidth = rows.reduce(CGFloat.zero) { partialResult, row in
            partialResult + row.displayWidth
        }
        let gaps = max(0, rows.count - 1) * 4
        return contentWidth + CGFloat(gaps) + 20
    }

    var replicaHeight: CGFloat {
        let maxItemHeight = rows.map(\.itemHeight).max() ?? 24
        return min(max(maxItemHeight + 20, 46), 58)
    }

    private let cacheController: MenuBarCacheController
    private let layoutStore: LayoutPersistenceStore
    private let thumbnailProvider: MenuBarThumbnailProviding
    private let permissionChecker: SystemPermissionChecker
    private let boundaryProvider: @MainActor () -> SectionBoundary?
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
        revealHandler: @escaping @MainActor (String) async -> LayoutApplicationResult
    ) {
        self.cacheController = cacheController
        self.layoutStore = layoutStore
        self.thumbnailProvider = thumbnailProvider
        self.permissionChecker = permissionChecker
        self.boundaryProvider = boundaryProvider
        self.revealHandler = revealHandler
    }

    func refresh() {
        guard !isRefreshing, permissionChecker.snapshot().canRunCoreFeatures else { return }
        if let lastRefreshAt, Date().timeIntervalSince(lastRefreshAt) < 0.35 {
            return
        }
        lastRefreshAt = Date()
        isRefreshing = true
        Task {
            defer { isRefreshing = false }
            do {
                let cache: ItemCache
                if let boundary = boundaryProvider() {
                    cache = try await cacheController.cache(boundary: boundary)
                } else {
                    let snapshot = try await cacheController.snapshot(refreshIfNeeded: false)
                    cache = ItemCache(displayID: snapshot.displayID, visibleItems: snapshot.items, hiddenItems: [], alwaysHiddenItems: [])
                }
                let itemByUID = Dictionary(uniqueKeysWithValues: cache.allItems.map { item in
                    (item.tag.stableIdentifier, item)
                })
                let order = layoutStore.loadSavedSectionOrder().removingCoronaSelfItems()
                rows = makeRows(uids: order.hidden, itemByUID: itemByUID)
            } catch {
                CoronaDebugLog.log("hoverBar.refresh failed error=\(String(describing: error))")
            }
        }
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
        let order = layoutStore.loadSavedSectionOrder().removingCoronaSelfItems()
        return !order.hidden.isEmpty
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
                itemWidth: item.bounds.width,
                itemHeight: item.bounds.height
            )
        }
    }
}

private extension HiddenItemsHoverBarModel.Row {
    var displayWidth: CGFloat {
        min(max(itemWidth, 24), 180)
    }

    var displayHeight: CGFloat {
        min(max(itemHeight, 20), 32)
    }
}

private struct HiddenItemsHoverBarView: View {
    @ObservedObject var model: HiddenItemsHoverBarModel

    var body: some View {
        HStack(spacing: 4) {
            if model.rows.isEmpty {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 24)
            } else {
                ForEach(model.rows) { row in
                    Button {
                        model.reveal(uid: row.uid)
                    } label: {
                        ZStack {
                            Image(nsImage: row.thumbnail)
                                .resizable()
                                .scaledToFit()
                                .frame(width: row.displayWidth, height: row.displayHeight)
                                .opacity(row.isAvailable ? 1 : 0.45)
                            if model.revealingUID == row.uid {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        .frame(width: row.displayWidth, height: 34)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(row.title)
                    .disabled(!row.isAvailable || model.revealingUID != nil)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}
