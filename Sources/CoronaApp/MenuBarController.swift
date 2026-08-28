import AppKit

enum StatusItemDefaults {
    static func ensurePreferredPosition(_ position: CGFloat, autosaveName: String) {
        let key = "NSStatusItem Preferred Position \(autosaveName)"
        guard UserDefaults.standard.object(forKey: key) == nil else { return }
        UserDefaults.standard.set(position, forKey: key)
    }
}

@MainActor
final class MenuBarController {
    private enum E2ENotification {
        static let collapseHiddenSections = Notification.Name("com.ltz.corona.e2e.collapseHiddenSections")
        static let hiddenSectionsCollapsed = Notification.Name("com.ltz.corona.e2e.hiddenSectionsCollapsed")
    }

    private let settingsStore: SettingsStore
    private let permissionChecker: SystemPermissionChecker
    private let statusItem: NSStatusItem
    private let sectionController: StatusSectionController
    private let cacheController: MenuBarCacheController
    private let layoutStore: LayoutPersistenceStore
    private let thumbnailProvider: MenuBarThumbnailProviding
    private var settings: AppSettings
    private var mainPanelWindowController: MainPanelWindowController?
    private var hiddenItemsHoverBarController: HiddenItemsHoverBarController?
    private var layoutApplicationController: LayoutApplicationController?
    private var lastLayoutApplicationResult: LayoutApplicationResult?
    private var autoRehideTask: Task<Void, Never>?
    private var startupLayoutRestoreTask: Task<Void, Never>?

    private struct StabilitySignature: Equatable {
        var items: [Item]

        struct Item: Equatable {
            var uid: String
            var x: Int
            var y: Int
            var width: Int
            var height: Int

            init(uid: String, frame: CGRect) {
                self.uid = uid
                x = Int(frame.minX.rounded())
                y = Int(frame.minY.rounded())
                width = Int(frame.width.rounded())
                height = Int(frame.height.rounded())
            }
        }

        init(cache: ItemCache, boundary: SectionBoundary?) {
            let displayFrame = cache.displayID.map(CGDisplayBounds) ?? BuiltInMenuBarDisplay.target().frame
            let visibleItems = cache.allItems.filter { item in
                item.isOnScreen && item.bounds.intersects(displayFrame)
            }
            let boundaryItems = Self.items(for: boundary)

            items = (visibleItems.map(Self.item(for:)) + boundaryItems)
                .sorted { lhs, rhs in
                    if lhs.x != rhs.x {
                        return lhs.x < rhs.x
                    }
                    if lhs.y != rhs.y {
                        return lhs.y < rhs.y
                    }
                    return lhs.uid < rhs.uid
                }
        }

        private static func item(for item: MenuBarItem) -> Item {
            Item(uid: item.tag.stableIdentifier, frame: item.bounds)
        }

        private static func items(for boundary: SectionBoundary?) -> [Item] {
            guard let boundary else { return [] }
            var items = [Item(uid: "com.ltz.corona.control:hidden", frame: boundary.hiddenControlBounds)]
            if let alwaysHiddenControlBounds = boundary.alwaysHiddenControlBounds {
                items.append(Item(uid: "com.ltz.corona.control:alwaysHidden", frame: alwaysHiddenControlBounds))
            }
            return items
        }
    }

    private enum StabilityTiming {
        static let initialDelayNanoseconds: UInt64 = 180_000_000
        static let pollIntervalNanoseconds: UInt64 = 100_000_000
        static let requiredStableSamples = 4
        static let maxPolls = 18
    }

    init(
        settingsStore: SettingsStore,
        permissionChecker: SystemPermissionChecker
    ) {
        self.settingsStore = settingsStore
        self.permissionChecker = permissionChecker
        StatusItemDefaults.ensurePreferredPosition(0, autosaveName: "CoronaStatusItem")
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem.autosaveName = "CoronaStatusItem"
        self.sectionController = StatusSectionController()
        self.sectionController.ensureSpacerCoverage(displayWidth: BuiltInMenuBarDisplay.target().frame.width)
        self.cacheController = MenuBarCacheController(provider: PublicMenuBarDiscoveryProvider())
        self.layoutStore = UserDefaultsLayoutPersistenceStore()
        self.thumbnailProvider = MenuBarThumbnailProvider(
            settingsStore: settingsStore,
            permissionChecker: permissionChecker
        )
        self.settings = settingsStore.load()
    }

    func start() {
        configureStatusItem()
        installE2EObserversIfNeeded()
        sectionController.setAlwaysHiddenSectionEnabled(settings.enableAlwaysHiddenSection)
        sanitizeSavedLayout()
        startHiddenItemsHoverBar()
        rebuildMenu()
        scheduleStartupLayoutRestoreIfNeeded()
        showPermissionsOnFirstLaunchIfNeeded()
        showMainPanelOnLaunchIfReady()
    }

    deinit {
        autoRehideTask?.cancel()
        startupLayoutRestoreTask?.cancel()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        statusItem.length = NSStatusItem.squareLength
        button.image = Self.statusImage(named: "menubar.rectangle", accessibilityDescription: "Corona")
        button.image?.isTemplate = true
        button.toolTip = "Corona"
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func rebuildMenu() {
        updateStatusIcon(for: permissionChecker.snapshot())
    }

    private func makeStatusMenu() -> NSMenu {
        let snapshot = permissionChecker.snapshot()
        let menu = NSMenu()

        let mainPanel = NSMenuItem(
            title: "Organize Menu Bar...",
            action: #selector(openMainPanel),
            keyEquivalent: ""
        )
        mainPanel.target = self
        mainPanel.isEnabled = snapshot.canRunCoreFeatures
        menu.addItem(mainPanel)

        let quit = NSMenuItem(
            title: "Quit Corona",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func showPermissionsOnFirstLaunchIfNeeded() {
        guard !permissionChecker.snapshot().canRunCoreFeatures else { return }
        DispatchQueue.main.async { [weak self] in
            self?.openSettings()
        }
    }

    private func showMainPanelOnLaunchIfReady() {
        guard permissionChecker.snapshot().canRunCoreFeatures else { return }
        DispatchQueue.main.async { [weak self] in
            self?.openMainPanel()
        }
    }

    private func updateStatusIcon(for snapshot: PermissionSnapshot) {
        let symbolName: String
        switch snapshot.capabilityStatus {
        case .missing:
            symbolName = "exclamationmark.triangle"
        case .hasRequired:
            symbolName = "menubar.rectangle"
        case .hasAll:
            symbolName = "menubar.rectangle"
        }
        statusItem.isVisible = true
        statusItem.length = NSStatusItem.squareLength
        statusItem.button?.image = Self.statusImage(named: symbolName, accessibilityDescription: "Corona")
        statusItem.button?.image?.isTemplate = true
    }

    private static func statusImage(named symbolName: String, accessibilityDescription: String) -> NSImage? {
        NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)
            ?? NSImage(systemSymbolName: "rectangle", accessibilityDescription: accessibilityDescription)
            ?? NSImage(named: NSImage.applicationIconName)
    }

    private func installE2EObserversIfNeeded() {
        guard ProcessInfo.processInfo.environment["CORONA_ENABLE_E2E_CONTROL"] == "1" else { return }
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(collapseHiddenSectionsForE2E),
            name: E2ENotification.collapseHiddenSections,
            object: nil
        )
    }

    @MainActor
    @objc private func collapseHiddenSectionsForE2E() {
        autoRehideTask?.cancel()
        sectionController.setHiddenSectionVisible(false)
        if settings.enableAlwaysHiddenSection {
            sectionController.setAlwaysHiddenSectionVisible(false)
        }
        rebuildMenu()
        DistributedNotificationCenter.default().postNotificationName(
            E2ENotification.hiddenSectionsCollapsed,
            object: Bundle.main.bundleIdentifier ?? "com.ltz.corona",
            userInfo: nil,
            deliverImmediately: true
        )
    }

    @MainActor
    private func showHiddenItems(attachedTo button: NSStatusBarButton? = nil) {
        sectionController.setHiddenSectionVisible(true)
        scheduleAutoRehideIfNeeded()
        rebuildMenu()
        if let button {
            hiddenItemsHoverBarController?.show(attachedTo: button)
        }
    }

    @MainActor
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            if let button = statusItem.button {
                makeStatusMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
            }
            return
        }

        guard permissionChecker.snapshot().canRunCoreFeatures else {
            openSettings()
            return
        }

        showHiddenItems(attachedTo: statusItem.button)
    }

    @objc private func openMainPanel() {
        if mainPanelWindowController == nil {
            mainPanelWindowController = MainPanelWindowController(
                cacheController: cacheController,
                layoutStore: layoutStore,
                settingsStore: settingsStore,
                settings: settings,
                permissionChecker: permissionChecker,
                thumbnailProvider: thumbnailProvider,
                boundaryProvider: { [weak self] in
                    self?.sectionController.currentBoundary()
                },
                visualCacheProvider: { [weak self] in
                    guard let self else {
                        return ItemCache(displayID: nil, visibleItems: [], hiddenItems: [], alwaysHiddenItems: [])
                    }
                    return try await self.currentOrganizerMenuBarCache()
                },
                readOnlyCacheProvider: { [weak self] in
                    guard let self else {
                        return ItemCache(displayID: nil, visibleItems: [], hiddenItems: [], alwaysHiddenItems: [])
                    }
                    return try await self.currentMenuBarCacheWithoutChangingVisibility()
                },
                visualCacheCleanup: { },
                applyHandler: { [weak self] in
                    guard let self else { return .failed("Controller unavailable") }
                    let result = await self.applySavedLayoutWithVisibleBoundary()
                    self.lastLayoutApplicationResult = result
                    self.rebuildMenu()
                    return result
                },
                applyMoveHandler: { [weak self] uid, desiredOrder in
                    guard let self else { return .failed("Controller unavailable") }
                    let result = await self.applySingleMoveWithVisibleBoundary(uid: uid, desiredOrder: desiredOrder)
                    self.lastLayoutApplicationResult = result
                    self.rebuildMenu()
                    return result
                },
                onSettingsChanged: { [weak self] settings in
                    self?.settings = settings
                    self?.sectionController.setAlwaysHiddenSectionEnabled(settings.enableAlwaysHiddenSection)
                    self?.settingsStore.save(settings)
                    self?.rebuildMenu()
                },
                onPermissionsChanged: { [weak self] in
                    self?.rebuildMenu()
                }
            )
        }
        mainPanelWindowController?.show()
    }

    private func startHiddenItemsHoverBar() {
        guard hiddenItemsHoverBarController == nil else { return }
        let controller = HiddenItemsHoverBarController(
            cacheController: cacheController,
            layoutStore: layoutStore,
            thumbnailProvider: thumbnailProvider,
            permissionChecker: permissionChecker,
            boundaryProvider: { [weak self] in
                self?.sectionController.currentBoundary()
            },
            visualCacheProvider: { [weak self] in
                guard let self else {
                    return ItemCache(displayID: nil, visibleItems: [], hiddenItems: [], alwaysHiddenItems: [])
                }
                return try await self.currentMenuBarCacheWithoutChangingVisibility()
            },
            visualCacheCleanup: { },
            revealHandler: { [weak self] uid in
                guard let self else { return .failed("Controller unavailable") }
                CoronaDebugLog.log("hoverBar.reveal expandOnly uid=\(uid)")
                self.sectionController.setHiddenSectionVisible(true)
                self.rebuildMenu()
                self.scheduleAutoRehideIfNeeded()
                return .satisfied
            }
        )
        hiddenItemsHoverBarController = controller
        controller.start()
    }

    @MainActor
    private func currentMenuBarCacheWithoutChangingVisibility() async throws -> ItemCache {
        let snapshot = try await cacheController.refresh()
        guard sectionController.hiddenVisibility == .shown else {
            return physicallyVisibleCache(from: snapshot)
        }

        guard let boundary = sectionController.currentBoundary() else {
            return physicallyVisibleCache(from: snapshot)
        }
        guard boundary.isOnSameDisplay(as: snapshot.displayID) else {
            CoronaDebugLog.log("main.cache boundaryDisplayMismatch displayID=\(snapshot.displayID.map(String.init) ?? "nil") hidden=\(boundary.hiddenControlBounds.debugDescription) alwaysHidden=\(boundary.alwaysHiddenControlBounds?.debugDescription ?? "nil")")
            return physicallyVisibleCache(from: snapshot)
        }

        let sectionByWindowID = SectionClassifier().classify(items: snapshot.items, boundary: boundary)
        return ItemCacheBuilder().build(snapshot: snapshot, sectionByWindowID: sectionByWindowID)
    }

    @MainActor
    private func currentOrganizerMenuBarCache() async throws -> ItemCache {
        let previousVisibility = (
            hidden: sectionController.hiddenVisibility,
            alwaysHidden: sectionController.alwaysHiddenVisibility
        )
        let shouldExpandHidden = previousVisibility.hidden != .shown
        let shouldExpandAlwaysHidden = settings.enableAlwaysHiddenSection && previousVisibility.alwaysHidden != .shown

        if shouldExpandHidden {
            sectionController.setHiddenSectionVisible(true)
        }
        if shouldExpandAlwaysHidden {
            sectionController.setAlwaysHiddenSectionVisible(true)
        }

        let shouldRestoreVisibility = shouldExpandHidden || shouldExpandAlwaysHidden
        defer {
            if shouldRestoreVisibility {
                sectionController.setHiddenSectionVisible(previousVisibility.hidden == .shown)
                if settings.enableAlwaysHiddenSection {
                    sectionController.setAlwaysHiddenSectionVisible(previousVisibility.alwaysHidden == .shown)
                }
                rebuildMenu()
            }
        }

        if shouldRestoreVisibility {
            try? await Task.sleep(nanoseconds: 160_000_000)
        }

        let snapshot = try await cacheController.refresh()
        guard let boundary = sectionController.currentBoundary() else {
            CoronaDebugLog.log("main.organizerCache missingBoundary fallback=physicalVisible")
            return physicallyVisibleCache(from: snapshot)
        }
        guard boundary.isOnSameDisplay(as: snapshot.displayID) else {
            CoronaDebugLog.log("main.organizerCache boundaryDisplayMismatch displayID=\(snapshot.displayID.map(String.init) ?? "nil") hidden=\(boundary.hiddenControlBounds.debugDescription) alwaysHidden=\(boundary.alwaysHiddenControlBounds?.debugDescription ?? "nil")")
            return physicallyVisibleCache(from: snapshot)
        }

        let sectionByWindowID = SectionClassifier().classify(items: snapshot.items, boundary: boundary)
        let cache = ItemCacheBuilder().build(snapshot: snapshot, sectionByWindowID: sectionByWindowID)
        CoronaDebugLog.verbose("main.organizerCache expanded=\(shouldRestoreVisibility) visible=\(cache.visibleItems.count) hidden=\(cache.hiddenItems.count) alwaysHidden=\(cache.alwaysHiddenItems.count)")
        return cache
    }

    private func physicallyVisibleCache(from snapshot: MenuBarSnapshot) -> ItemCache {
        let displayFrame = snapshot.displayID.map(CGDisplayBounds) ?? BuiltInMenuBarDisplay.target().frame
        let visibleItems = snapshot.items.filter { item in
            item.isOnScreen && item.bounds.intersects(displayFrame)
        }
        let visibleWindowIDs = Set(visibleItems.map(\.windowID))
        let hiddenItems = snapshot.items.filter { item in
            !visibleWindowIDs.contains(item.windowID)
        }
        return ItemCache(
            displayID: snapshot.displayID,
            visibleItems: visibleItems.sortedByMenuBarPosition(),
            hiddenItems: hiddenItems.sortedByMenuBarPosition(),
            alwaysHiddenItems: []
        )
    }

    private func ensureLayoutApplicationController() -> LayoutApplicationController {
        if let layoutApplicationController {
            return layoutApplicationController
        }

        let controller = LayoutApplicationController(
            cacheController: cacheController,
            layoutStore: layoutStore,
            settingsStore: settingsStore,
            boundaryProvider: { [weak self] in
                self?.sectionController.currentBoundary()
            },
            boundaryItemsProvider: { [weak self] in
                self?.sectionController.boundaryItems() ?? [:]
            }
        )
        layoutApplicationController = controller
        return controller
    }

    private func scheduleStartupLayoutRestoreIfNeeded() {
        guard permissionChecker.snapshot().canRunCoreFeatures else { return }
        guard shouldRestoreSavedLayoutOnStartup else { return }

        startupLayoutRestoreTask?.cancel()
        startupLayoutRestoreTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard let self, !Task.isCancelled, self.permissionChecker.snapshot().canRunCoreFeatures else { return }
            let result = await self.applySavedLayoutWithVisibleBoundary(collapseAfterAttempt: true)
            self.lastLayoutApplicationResult = result
            CoronaDebugLog.log("startup.restoreSavedLayout result=\(result.statusTitle)")
        }
    }

    private var shouldRestoreSavedLayoutOnStartup: Bool {
        let order = layoutStore.loadSavedSectionOrder()
            .removingCoronaSelfItems()
            .removingLegacyAXGeneratedItems()
        if !order.hidden.isEmpty || !order.alwaysHidden.isEmpty {
            return true
        }
        return !layoutStore.loadPendingRelocations().isEmpty
    }

    private func applySavedLayoutWithVisibleBoundary(collapseAfterAttempt: Bool = false) async -> LayoutApplicationResult {
        var captureToken = MenuBarVisualCaptureGate.acquire(reason: "main.applySavedLayout")
        defer { captureToken.release() }

        sanitizeSavedLayout()
        autoRehideTask?.cancel()

        sectionController.setHiddenSectionVisible(true)
        if settings.enableAlwaysHiddenSection {
            sectionController.setAlwaysHiddenSectionVisible(true)
        }

        try? await Task.sleep(nanoseconds: 180_000_000)
        var result = await ensureLayoutApplicationController().applySavedLayout()

        if result.isSuccessfulApply {
            let layoutSatisfied = await savedLayoutIsActuallySatisfied()
            if !layoutSatisfied {
                result = .failed("savedLayoutNotRestored")
            }
        }

        if result.isSuccessfulApply || collapseAfterAttempt {
            await collapseHiddenSectionsAfterLayoutAttempt()
        } else {
            collapseHiddenSections()
        }
        rebuildMenu()
        return result
    }

    private func applySingleMoveWithVisibleBoundary(uid: String, desiredOrder: SectionOrder) async -> LayoutApplicationResult {
        var captureToken = MenuBarVisualCaptureGate.acquire(reason: "main.applySingleMove")
        defer { captureToken.release() }

        sanitizeSavedLayout()
        autoRehideTask?.cancel()

        sectionController.setHiddenSectionVisible(true)
        if settings.enableAlwaysHiddenSection {
            sectionController.setAlwaysHiddenSectionVisible(true)
        }

        try? await Task.sleep(nanoseconds: 120_000_000)
        var result = await ensureLayoutApplicationController().applySingleMove(uid: uid, desiredOrder: desiredOrder)

        if result.isSuccessfulApply {
            let layoutSatisfied = await savedLayoutIsActuallySatisfied()
            if !layoutSatisfied {
                result = .failed("savedLayoutNotRestored")
            }
        }

        if result.isSuccessfulApply {
            await collapseHiddenSectionsAfterLayoutAttempt()
        } else {
            collapseHiddenSections()
        }
        rebuildMenu()
        return result
    }

    private func collapseHiddenSections() {
        sectionController.setHiddenSectionVisible(false)
        if settings.enableAlwaysHiddenSection {
            sectionController.setAlwaysHiddenSectionVisible(false)
        }
    }

    private func collapseHiddenSectionsAfterLayoutAttempt() async {
        collapseHiddenSections()
        await waitForMenuBarLayoutToSettle()
    }

    private func waitForMenuBarLayoutToSettle() async {
        var previousSignature: StabilitySignature?
        var stableSampleCount = 0

        try? await Task.sleep(nanoseconds: StabilityTiming.initialDelayNanoseconds)

        for _ in 0..<StabilityTiming.maxPolls where !Task.isCancelled {
            do {
                let cache = try await currentMenuBarCacheWithoutChangingVisibility()
                let signature = StabilitySignature(cache: cache, boundary: sectionController.currentBoundary())
                if previousSignature == signature {
                    stableSampleCount += 1
                    if stableSampleCount >= StabilityTiming.requiredStableSamples {
                        CoronaDebugLog.verbose("main.menuStable items=\(signature.items.count) samples=\(stableSampleCount)")
                        return
                    }
                } else {
                    previousSignature = signature
                    stableSampleCount = 1
                }
            } catch {
                CoronaDebugLog.log("main.menuStabilityCheckFailed error=\(String(describing: error))")
                return
            }
            try? await Task.sleep(nanoseconds: StabilityTiming.pollIntervalNanoseconds)
        }

        CoronaDebugLog.log("main.menuStabilityTimeout")
    }

    private func savedLayoutIsActuallySatisfied() async -> Bool {
        guard let boundary = sectionController.currentBoundary() else {
            CoronaDebugLog.log("layout.visibleGuard missingBoundary")
            return false
        }

        do {
            let cache = try await cacheController.cache(boundary: boundary)
            let actualSectionByUID = sectionMap(for: cache)
            let itemByUID = Dictionary(uniqueKeysWithValues: cache.allItems.map { ($0.tag.stableIdentifier, $0) })
            let savedOrder = layoutStore.loadSavedSectionOrder()
                .removingCoronaSelfItems()
                .removingLegacyAXGeneratedItems()
            var desiredVisible: [String] = []
            var mismatches: [String] = []

            for section in MenuBarSection.allCases {
                for uid in savedOrder[section] {
                    guard let item = itemByUID[uid], item.isMovable else { continue }
                    let targetSection: MenuBarSection = item.canBeHidden ? section : .visible
                    if targetSection == .visible {
                        desiredVisible.append(uid)
                    }
                    if actualSectionByUID[uid] != targetSection {
                        mismatches.append("\(uid):desired=\(targetSection.rawValue),actual=\(actualSectionByUID[uid]?.rawValue ?? "missing")")
                    }
                }
            }

            let actualVisible = cache.visibleItems.map(\.tag.stableIdentifier)
            let actualHidden = cache.hiddenItems.map(\.tag.stableIdentifier)
            let actualAlwaysHidden = cache.alwaysHiddenItems.map(\.tag.stableIdentifier)

            if !mismatches.isEmpty {
                CoronaDebugLog.log("layout.visibleGuard failed desiredVisible=\(desiredVisible) mismatches=\(mismatches) actualVisible=\(actualVisible) actualHidden=\(actualHidden) actualAlwaysHidden=\(actualAlwaysHidden) boundaryHidden=\(boundary.hiddenControlBounds.debugDescription) boundaryAlwaysHidden=\(boundary.alwaysHiddenControlBounds?.debugDescription ?? "nil")")
                return false
            }

            CoronaDebugLog.log("layout.visibleGuard satisfied desiredVisible=\(desiredVisible) actualVisible=\(actualVisible) actualHidden=\(actualHidden) actualAlwaysHidden=\(actualAlwaysHidden)")
            return true
        } catch {
            CoronaDebugLog.log("layout.visibleGuard failed error=\(String(describing: error))")
            return false
        }
    }

    private func sectionMap(for cache: ItemCache) -> [String: MenuBarSection] {
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

    private func sanitizeSavedLayout() {
        let savedOrder = layoutStore.loadSavedSectionOrder()
        let sanitized = savedOrder
            .removingCoronaSelfItems()
            .removingLegacyAXGeneratedItems()
        if sanitized != savedOrder {
            layoutStore.saveSavedSectionOrder(sanitized)
        }

        let known = layoutStore.loadKnownItemIdentifiers()
        let sanitizedKnown = known.filter {
            !Self.isCoronaSelfIdentifier($0)
                && !Self.isLegacyAXGeneratedIdentifier($0)
        }
        if sanitizedKnown != known {
            layoutStore.saveKnownItemIdentifiers(Set(sanitizedKnown))
        }

        let savedUIDs = Set(savedOrder.visible + savedOrder.hidden + savedOrder.alwaysHidden)
        for uid in known.union(savedUIDs) where Self.isCoronaSelfIdentifier(uid) || Self.isLegacyAXGeneratedIdentifier(uid) {
            layoutStore.savePendingRelocation(nil, for: uid)
        }
    }

    nonisolated static func isCoronaSelfIdentifier(_ uid: String) -> Bool {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.ltz.corona"
        return uid.localizedCaseInsensitiveContains(bundleIdentifier)
            || uid.localizedCaseInsensitiveContains("com.ltz.corona")
            || uid.localizedCaseInsensitiveContains("Corona:Corona")
            || uid.localizedCaseInsensitiveContains("Corona:Status Item")
            || uid.localizedCaseInsensitiveContains("corona.control")
    }

    nonisolated static func isLegacyAXGeneratedIdentifier(_ uid: String) -> Bool {
        let parts = uid.split(separator: ":").map(String.init)
        guard parts.count >= 2 else { return false }
        let title = parts[1]
        guard title.hasPrefix("item-") else { return false }
        return title.dropFirst("item-".count).allSatisfy(\.isNumber)
    }

    private func scheduleAutoRehideIfNeeded() {
        let latestSettings = settingsStore.load()
        guard latestSettings.autoRehide else { return }

        autoRehideTask?.cancel()
        autoRehideTask = Task { @MainActor [weak self] in
            let delay = UInt64(max(0.5, latestSettings.rehideInterval) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled, self.permissionChecker.snapshot().canRunCoreFeatures else { return }
            self.sectionController.setHiddenSectionVisible(false)
            if self.settings.enableAlwaysHiddenSection {
                self.sectionController.setAlwaysHiddenSectionVisible(false)
            }
            self.rebuildMenu()
        }
    }

    @objc private func openSettings() {
        openMainPanel()
        mainPanelWindowController?.showSettings()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

extension SectionOrder {
    func removingCoronaSelfItems() -> SectionOrder {
        SectionOrder(
            visible: visible.filter { !MenuBarController.isCoronaSelfIdentifier($0) },
            hidden: hidden.filter { !MenuBarController.isCoronaSelfIdentifier($0) },
            alwaysHidden: alwaysHidden.filter { !MenuBarController.isCoronaSelfIdentifier($0) }
        )
    }

    func removingLegacyAXGeneratedItems() -> SectionOrder {
        SectionOrder(
            visible: visible.filter { !MenuBarController.isLegacyAXGeneratedIdentifier($0) },
            hidden: hidden.filter { !MenuBarController.isLegacyAXGeneratedIdentifier($0) },
            alwaysHidden: alwaysHidden.filter { !MenuBarController.isLegacyAXGeneratedIdentifier($0) }
        )
    }
}

extension LayoutApplicationResult {
    var isSuccessfulApply: Bool {
        switch self {
        case .satisfied, .applied, .moved:
            return true
        case .missingBoundary, .waitingForItem, .waitingForDestination, .failed:
            return false
        }
    }
}

private extension Array where Element == MenuBarItem {
    func sortedByMenuBarPosition() -> [MenuBarItem] {
        sorted { lhs, rhs in
            if abs(lhs.bounds.minX - rhs.bounds.minX) > 0.5 {
                return lhs.bounds.minX < rhs.bounds.minX
            }
            return lhs.windowID < rhs.windowID
        }
    }
}

private extension SectionBoundary {
    func isOnSameDisplay(as displayID: UInt32?) -> Bool {
        let displayFrame = displayID.map(CGDisplayBounds) ?? BuiltInMenuBarDisplay.target().frame
        guard hiddenControlBounds.intersects(displayFrame) else { return false }
        if let alwaysHiddenControlBounds {
            return alwaysHiddenControlBounds.intersects(displayFrame)
        }
        return true
    }
}
