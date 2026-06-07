import AppKit
import CoronaCore
import SwiftUI
import UniformTypeIdentifiers

final class MainPanelWindowController: NSWindowController {
    private let model: MainPanelViewModel
    private let settingsModel: SettingsViewModel

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
            applyHandler: applyHandler
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
        settingsModel.refreshPermissions()
    }

    func showSettings() {
        model.selectedTab = .settings
        show()
    }

    func refreshPermissions() {
        settingsModel.refreshPermissions()
        model.refresh()
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
        var isSystemItem: Bool
        var thumbnail: NSImage
        var visualWidth: CGFloat
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
    private var draft = LayoutDraft()
    private var itemByUID: [String: MenuBarItem] = [:]
    private var positionByUID: [String: Int] = [:]
    private var physicalSectionByUID: [String: MenuBarSection] = [:]

    init(
        cacheController: MenuBarCacheController,
        layoutStore: LayoutPersistenceStore,
        settingsStore: SettingsStore,
        permissionChecker: SystemPermissionChecker,
        visualSnapshotProvider: MenuBarVisualSnapshotProvider,
        boundaryProvider: @escaping @MainActor () -> SectionBoundary?,
        visualCacheProvider: @escaping @MainActor () async throws -> ItemCache,
        visualCacheCleanup: @escaping @MainActor () -> Void,
        applyHandler: @escaping @MainActor () async -> LayoutApplicationResult
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
    }

    var visibleRows: [Row] {
        filteredRows.filter { $0.desiredSection == .visible }
    }

    var hiddenRows: [Row] {
        filteredRows.filter { $0.desiredSection == .hidden }
    }

    var alwaysHiddenRows: [Row] {
        filteredRows.filter { $0.desiredSection == .alwaysHidden }
    }

    var hasRows: Bool {
        !rows.isEmpty
    }

    var selectedRow: Row? {
        guard let selectedUID else { return filteredRows.first }
        return rows.first { $0.uid == selectedUID }
    }

    func refresh() {
        let snapshot = permissionChecker.snapshot()
        canRunCoreFeatures = snapshot.canRunCoreFeatures
        statusMessage = snapshot.canRunCoreFeatures ? nil : "Accessibility permission is required before Corona can scan or move menu bar items."
        CoronaDebugLog.log("main.refresh permission canRun=\(snapshot.canRunCoreFeatures) status=\(snapshot.capabilityStatus)")
        guard snapshot.canRunCoreFeatures else {
            rows = []
            return
        }

        isLoading = true
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
                positionByUID = Self.positionMap(for: manageableItems)
                physicalSectionByUID = Self.sectionMap(for: cache)
                draft = LayoutDraft(order: availableOrder(preferredOrder(cache: cache).removingCoronaSelfItems()))
                rebuildRows()
                CoronaDebugLog.log("main.refresh draft visible=\(draft.order.visible) hidden=\(draft.order.hidden) alwaysHidden=\(draft.order.alwaysHidden)")
                if selectedUID == nil || rows.contains(where: { $0.uid == selectedUID }) == false {
                    selectedUID = rows.first?.uid
                }
            } catch {
                CoronaDebugLog.log("main.refresh failed error=\(String(describing: error))")
                errorMessage = String(describing: error)
            }
            visualCacheCleanup()
            isLoading = false
        }
    }

    func setHidden(_ hidden: Bool, uid: String) {
        guard let item = itemByUID[uid], item.canBeHidden, item.isMovable else { return }
        CoronaDebugLog.log("main.setHidden uid=\(uid) hidden=\(hidden)")
        draft.move(uid, to: hidden ? .hidden : .visible)
        selectedUID = uid
        rebuildRows()
    }

    func select(uid: String) {
        selectedUID = uid
    }

    func toggleHidden(uid: String) {
        guard let row = rows.first(where: { $0.uid == uid }) else { return }
        setHidden(!row.isHidden, uid: uid)
    }

    func move(uid: String, to section: MenuBarSection) {
        guard let item = itemByUID[uid], item.canBeHidden, item.isMovable else { return }
        CoronaDebugLog.log("main.move uid=\(uid) section=\(section)")
        draft.move(uid, to: section)
        selectedUID = uid
        rebuildRows()
    }

    func move(uid: String, to section: MenuBarSection, at index: Int) {
        guard let item = itemByUID[uid], item.canBeHidden, item.isMovable else { return }
        CoronaDebugLog.log("main.move uid=\(uid) section=\(section) index=\(index)")
        draft.move(uid, to: section, at: index)
        selectedUID = uid
        rebuildRows()
    }

    func apply() {
        isApplying = true
        statusMessage = nil
        let sanitizedOrder = availableOrder(draft.order.removingCoronaSelfItems())
        draft = LayoutDraft(order: sanitizedOrder)
        CoronaDebugLog.log("main.apply save visible=\(sanitizedOrder.visible) hidden=\(sanitizedOrder.hidden) alwaysHidden=\(sanitizedOrder.alwaysHidden)")
        layoutStore.saveSavedSectionOrder(sanitizedOrder)
        layoutStore.saveKnownItemIdentifiers(Set(sanitizedOrder.visible + sanitizedOrder.hidden + sanitizedOrder.alwaysHidden))

        CoronaDebugLog.log("main.apply savedOnly visible=\(sanitizedOrder.visible) hidden=\(sanitizedOrder.hidden) alwaysHidden=\(sanitizedOrder.alwaysHidden)")
        Task {
            let result = await applyHandler()
            CoronaDebugLog.log("main.apply result=\(result.statusTitle)")
            statusMessage = result.statusTitle
            isApplying = false
            if result.isSuccessfulApply {
                refresh()
            } else {
                statusMessage = hasManualPlacementMismatches(in: sanitizedOrder)
                    ? "\(result.statusTitle). Some icons still need placement."
                    : result.statusTitle
                CoronaDebugLog.log("main.apply keepDraftAfterFailure visible=\(draft.order.visible) hidden=\(draft.order.hidden) alwaysHidden=\(draft.order.alwaysHidden)")
                rebuildRows()
            }
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

    private func preferredOrder(cache: ItemCache) -> SectionOrder {
        let currentOrder = SectionOrder(cache: cache).removingCoronaSelfItems()
        return currentOrder
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

    private func visualRows(for order: SectionOrder) -> [Row] {
        var draftOrderedCache = ItemCache(displayID: nil, visibleItems: [], hiddenItems: [], alwaysHiddenItems: [])
        for uid in order.visible + order.hidden + order.alwaysHidden {
            guard let item = itemByUID[uid],
                  let desiredSection = order.section(containing: uid) else { continue }
            switch desiredSection {
            case .visible:
                draftOrderedCache.visibleItems.append(item)
            case .hidden:
                draftOrderedCache.hiddenItems.append(item)
            case .alwaysHidden:
                draftOrderedCache.alwaysHiddenItems.append(item)
            }
        }

        let snapshot = visualSnapshotProvider.snapshot(cache: draftOrderedCache, desiredOrder: order)
        let rowByUID = Dictionary(uniqueKeysWithValues: snapshot.items.compactMap { item -> (String, Row)? in
            guard let row = makeRow(from: item) else { return nil }
            return (row.uid, row)
        })

        return (order.visible + order.hidden + order.alwaysHidden).compactMap { uid in
            rowByUID[uid]
        }
    }

    private func makeRow(from item: MenuBarVisualItem) -> Row? {
        guard !MenuBarController.isCoronaSelfIdentifier(item.uid) else {
            return nil
        }
        let placementDetail = placementDetail(
            desiredSection: item.desiredSection,
            physicalSection: item.physicalSection,
            isUserHideable: item.isMovable
        )
        return Row(
            uid: item.uid,
            title: item.title,
            owner: item.owner,
            detail: "#\(item.position)  \(placementDetail)  x \(Int(item.bounds.minX))-\(Int(item.bounds.maxX))",
            position: item.position,
            isHidden: item.isHidden,
            desiredSection: item.desiredSection,
            physicalSection: item.physicalSection,
            needsManualPlacement: item.needsApply,
            isMovable: item.isMovable,
            isSystemItem: item.isSystemItem,
            thumbnail: item.thumbnail,
            visualWidth: min(max(item.bounds.width, 22), 96)
        )
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
        isUserHideable: Bool
    ) -> String {
        guard isUserHideable else { return "System item" }
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
            }
            Spacer()
            Button("Apply") {
                model.apply()
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isApplying || !model.canRunCoreFeatures)
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
        VStack(alignment: .leading, spacing: 28) {
            PreviewSection(
                title: "Shown menu bar items",
                section: .visible,
                rows: model.visibleRows,
                placeholder: nil,
                model: model
            )
            PreviewSection(
                title: "Hidden menu bar items",
                section: .hidden,
                rows: model.hiddenRows,
                placeholder: "New menu bar items appear here",
                model: model
            )
            PreviewSection(
                title: "Always Hidden menu bar items",
                section: .alwaysHidden,
                rows: model.alwaysHiddenRows,
                placeholder: nil,
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
    var placeholder: String?
    @ObservedObject var model: MainPanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3)
                .fontWeight(.regular)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    MenuBarRailBackground()
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(Array(rows.enumerated()), id: \.element.uid) { index, row in
                                PreviewChip(
                                    row: row,
                                    isSelected: model.selectedUID == row.uid,
                                    model: model
                                )
                                .onDrop(
                                    of: [UTType.plainText],
                                    delegate: MenuBarItemDropDelegate(
                                        section: section,
                                        targetIndex: index,
                                        model: model
                                    )
                                )
                            }
                            if rows.isEmpty, let placeholder {
                                Text(placeholder)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.purple.opacity(0.82))
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minWidth: geometry.size.width - 32, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
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
            .frame(height: 50)
        }
    }
}

private struct MenuBarItemDropDelegate: DropDelegate {
    var section: MenuBarSection
    var targetIndex: Int
    var model: MainPanelViewModel

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [UTType.plainText]).first else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
            let uid: String?
            if let data = item as? Data {
                uid = String(data: data, encoding: .utf8)
            } else {
                uid = item as? String
            }
            guard let uid else { return }
            Task { @MainActor in
                model.move(uid: uid, to: section, at: targetIndex)
            }
        }
        return true
    }
}

private struct MenuBarRailBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(red: 0.72, green: 0.60, blue: 0.47).opacity(0.58))
    }
}

private struct PreviewChip: View {
    var row: MainPanelViewModel.Row
    var isSelected: Bool
    @ObservedObject var model: MainPanelViewModel

    var body: some View {
        Button {
            model.select(uid: row.uid)
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: row.thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(width: row.visualWidth, height: 28)
                    .foregroundStyle(row.isMovable ? .primary : .secondary)
                    .shadow(color: .black.opacity(0.28), radius: 2, x: 0, y: 1)
                if row.isSystemItem || row.needsManualPlacement {
                    Image(systemName: row.isSystemItem ? "lock.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(row.isSystemItem ? Color.secondary : Color.orange)
                        .background(.regularMaterial, in: Circle())
                        .offset(x: 5, y: -5)
                }
            }
            .frame(width: row.visualWidth + 8, height: 32)
            .contentShape(Rectangle())
            .background(isSelected ? Color.white.opacity(0.26) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.white.opacity(0.85) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("\(row.title) - \(row.owner)")
        .onDrag {
            NSItemProvider(object: row.uid as NSString)
        }
        .disabled(!row.isMovable)
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
                    Label(row.isHidden ? "Hidden" : row.isSystemItem ? "System" : "Visible", systemImage: row.isHidden ? "eye.slash" : row.isSystemItem ? "lock" : "eye")
                    Spacer()
                    Button(row.isHidden ? "Show" : "Hide") {
                        model.toggleHidden(uid: row.uid)
                    }
                    .disabled(!row.isMovable)
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
        List(model.visibleRows + model.hiddenRows) { row in
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
            .disabled(!row.isMovable)
            .help(row.isMovable ? "Hide this menu bar item" : "This item cannot be moved")
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
