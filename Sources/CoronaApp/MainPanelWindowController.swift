import AppKit
import CoronaCore
import SwiftUI

final class MainPanelWindowController: NSWindowController {
    private let model: MainPanelViewModel
    private let settingsModel: SettingsViewModel

    init(
        cacheController: MenuBarCacheController,
        layoutStore: LayoutPersistenceStore,
        settingsStore: SettingsStore,
        settings: AppSettings,
        permissionChecker: SystemPermissionChecker,
        boundaryProvider: @escaping @MainActor () -> SectionBoundary?,
        applyHandler: @escaping @MainActor () async -> LayoutApplicationResult,
        onSettingsChanged: @escaping (AppSettings) -> Void,
        onPermissionsChanged: @escaping () -> Void
    ) {
        self.model = MainPanelViewModel(
            cacheController: cacheController,
            layoutStore: layoutStore,
            settingsStore: settingsStore,
            permissionChecker: permissionChecker,
            boundaryProvider: boundaryProvider,
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
        window.setContentSize(NSSize(width: 820, height: 600))
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
        var isMovable: Bool
        var isSystemItem: Bool
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
    private let boundaryProvider: @MainActor () -> SectionBoundary?
    private let applyHandler: @MainActor () async -> LayoutApplicationResult
    private var draft = LayoutDraft()
    private var itemByUID: [String: MenuBarItem] = [:]
    private var positionByUID: [String: Int] = [:]

    init(
        cacheController: MenuBarCacheController,
        layoutStore: LayoutPersistenceStore,
        settingsStore: SettingsStore,
        permissionChecker: SystemPermissionChecker,
        boundaryProvider: @escaping @MainActor () -> SectionBoundary?,
        applyHandler: @escaping @MainActor () async -> LayoutApplicationResult
    ) {
        self.cacheController = cacheController
        self.layoutStore = layoutStore
        self.settingsStore = settingsStore
        self.permissionChecker = permissionChecker
        self.boundaryProvider = boundaryProvider
        self.applyHandler = applyHandler
    }

    var visibleRows: [Row] {
        filteredRows.filter { !$0.isHidden }
    }

    var hiddenRows: [Row] {
        filteredRows.filter(\.isHidden)
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

    func apply() {
        isApplying = true
        statusMessage = nil
        let sanitizedOrder = availableOrder(draft.order.removingCoronaSelfItems())
        draft = LayoutDraft(order: sanitizedOrder)
        CoronaDebugLog.log("main.apply save visible=\(sanitizedOrder.visible) hidden=\(sanitizedOrder.hidden) alwaysHidden=\(sanitizedOrder.alwaysHidden)")
        layoutStore.saveSavedSectionOrder(sanitizedOrder)
        layoutStore.saveKnownItemIdentifiers(Set(sanitizedOrder.visible + sanitizedOrder.hidden + sanitizedOrder.alwaysHidden))

        Task {
            let result = await applyHandler()
            CoronaDebugLog.log("main.apply result=\(result.statusTitle)")
            statusMessage = result.statusTitle
            isApplying = false
            if result.isSuccessfulApply {
                refresh()
            } else {
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
        if let boundary = boundaryProvider() {
            return try await cacheController.cache(boundary: boundary)
        }

        let snapshot = try await cacheController.refresh()
        return ItemCache(displayID: snapshot.displayID, visibleItems: snapshot.items, hiddenItems: [], alwaysHiddenItems: [])
    }

    private func preferredOrder(cache: ItemCache) -> SectionOrder {
        let savedOrder = layoutStore.loadSavedSectionOrder()
        let currentOrder = SectionOrder(cache: cache)
        guard !savedOrder.isEmpty else {
            return currentOrder
        }
        return orderByCurrentSections(currentOrder: currentOrder, savedOrder: savedOrder)
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
        rows = (sanitizedOrder.visible.map { makeRow(uid: $0, isHidden: false) }
            + sanitizedOrder.hidden.map { makeRow(uid: $0, isHidden: true) }
            + sanitizedOrder.alwaysHidden.map { makeRow(uid: $0, isHidden: true) })
            .compactMap { $0 }
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

    private func orderByCurrentSections(currentOrder: SectionOrder, savedOrder: SectionOrder) -> SectionOrder {
        SectionOrder(
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

    private func makeRow(uid: String, isHidden: Bool) -> Row? {
        guard !MenuBarController.isCoronaSelfIdentifier(uid) else {
            return nil
        }
        guard let item = itemByUID[uid] else { return nil }

        let isUserHideable = item.isMovable && item.canBeHidden
        let movableDetail = isUserHideable ? "Hideable" : "System item"
        return Row(
            uid: uid,
            title: item.title ?? item.tag.title,
            owner: item.tag.namespace,
            detail: "#\(positionByUID[uid] ?? 0)  \(movableDetail)  x \(Int(item.bounds.minX))-\(Int(item.bounds.maxX))  pid \(item.ownerPID)",
            position: positionByUID[uid] ?? 0,
            isHidden: isHidden,
            isMovable: isUserHideable,
            isSystemItem: !item.canBeHidden
        )
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
                if lhs.bounds.maxX != rhs.bounds.maxX {
                    return lhs.bounds.maxX > rhs.bounds.maxX
                }
                return lhs.windowID < rhs.windowID
            }
            .enumerated()
            .map { index, item in
                (item.tag.stableIdentifier, index + 1)
            })
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
        .frame(minWidth: 760, minHeight: 540)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Organize Menu Bar")
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
            VStack(spacing: 0) {
                MenuBarPreview(model: model)
                    .padding(16)
                Divider()
                InspectorPane(model: model)
                    .frame(minHeight: 150)
            }
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
        VStack(spacing: 0) {
            HStack {
                Label("Menu Bar Preview", systemImage: "menubar.rectangle")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Label("\(model.visibleRows.count)", systemImage: "eye")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("\(model.hiddenRows.count)", systemImage: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 10)

            HStack(spacing: 0) {
                PreviewSection(
                    title: "Visible",
                    subtitle: "shown on the menu bar",
                    rows: model.visibleRows,
                    model: model
                )
                BoundaryMarker()
                PreviewSection(
                    title: "Hidden",
                    subtitle: "collapsed behind Corona",
                    rows: model.hiddenRows,
                    model: model
                )
            }
            .frame(maxWidth: .infinity, minHeight: 130)
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
    }
}

private struct PreviewSection: View {
    var title: String
    var subtitle: String
    var rows: [MainPanelViewModel.Row]
    @ObservedObject var model: MainPanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    if rows.isEmpty {
                        Text("Empty")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(height: 64)
                    } else {
                        ForEach(rows) { row in
                            PreviewChip(
                                row: row,
                                isSelected: model.selectedUID == row.uid,
                                model: model
                            )
                        }
                    }
                }
            }
            .scrollIndicators(.visible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 10)
    }
}

private struct BoundaryMarker: View {
    var body: some View {
        VStack(spacing: 6) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2)
            Image(systemName: "menubar.rectangle")
                .foregroundStyle(.secondary)
            Text("Corona")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize()
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2)
        }
        .frame(width: 54)
        .padding(.vertical, 4)
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
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Text("#\(row.position)")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 44, height: 34)
                        .foregroundStyle(row.isMovable ? .primary : .secondary)
                    Button {
                        model.toggleHidden(uid: row.uid)
                    } label: {
                        Image(systemName: row.isHidden ? "arrow.left" : "arrow.right")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help(row.isHidden ? "Move to Visible" : "Move to Hidden")
                    .disabled(!row.isMovable)
                }
                Text(row.title)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(width: 78)
                if row.isSystemItem {
                    Text("System")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 78)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .frame(width: 92, height: 82)
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(row.owner)
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
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
}
