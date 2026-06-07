import AppKit
import CoronaCore

final class MenuBarController {
    private let settingsStore: SettingsStore
    private let permissionChecker: SystemPermissionChecker
    private let statusItem: NSStatusItem
    private let sectionController: StatusSectionController
    private let cacheController: MenuBarCacheController
    private let layoutStore: LayoutPersistenceStore
    private let thumbnailProvider: MenuBarThumbnailProviding
    private var settings: AppSettings
    private var scanResultsWindowController: ScanResultsWindowController?
    private var mainPanelWindowController: MainPanelWindowController?
    private var layoutEditorWindowController: LayoutEditorWindowController?
    private var hiddenItemsPanelWindowController: HiddenItemsPanelWindowController?
    private var layoutApplicationController: LayoutApplicationController?
    private var lastLayoutApplicationResult: LayoutApplicationResult?
    private var didScheduleInitialLayoutRestore = false
    private var autoRehideTask: Task<Void, Never>?

    init(
        settingsStore: SettingsStore,
        permissionChecker: SystemPermissionChecker
    ) {
        self.settingsStore = settingsStore
        self.permissionChecker = permissionChecker
        self.sectionController = StatusSectionController()
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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
        sectionController.setAlwaysHiddenSectionEnabled(settings.enableAlwaysHiddenSection)
        sanitizeSavedLayout()
        rebuildMenu()
        scheduleInitialLayoutRestore()
        showPermissionsOnFirstLaunchIfNeeded()
        showMainPanelOnLaunchIfReady()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "Corona")
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

        let statusItem = NSMenuItem(title: statusTitle(for: snapshot), action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(NSMenuItem.separator())

        let showHidden = NSMenuItem(title: "Show Hidden Items", action: #selector(showHiddenItems), keyEquivalent: "")
        showHidden.target = self
        showHidden.isEnabled = snapshot.canRunCoreFeatures && sectionController.hiddenVisibility == .hidden
        menu.addItem(showHidden)

        let hideHidden = NSMenuItem(title: "Hide Hidden Items", action: #selector(hideHiddenItems), keyEquivalent: "")
        hideHidden.target = self
        hideHidden.isEnabled = snapshot.canRunCoreFeatures && sectionController.hiddenVisibility == .shown
        menu.addItem(hideHidden)

        let hiddenPanel = NSMenuItem(
            title: "Hidden Items Panel...",
            action: #selector(openHiddenPanel),
            keyEquivalent: ""
        )
        hiddenPanel.target = self
        hiddenPanel.isEnabled = snapshot.canRunCoreFeatures
        menu.addItem(hiddenPanel)

        let mainPanel = NSMenuItem(
            title: "Organize Menu Bar...",
            action: #selector(openMainPanel),
            keyEquivalent: ""
        )
        mainPanel.target = self
        mainPanel.isEnabled = snapshot.canRunCoreFeatures
        menu.addItem(mainPanel)

        let layout = NSMenuItem(
            title: "Advanced Layout Editor...",
            action: #selector(openLayoutEditor),
            keyEquivalent: ""
        )
        layout.target = self
        layout.isEnabled = snapshot.canRunCoreFeatures
        menu.addItem(layout)

        let applyLayout = NSMenuItem(
            title: "Apply Saved Layout",
            action: #selector(applySavedLayout),
            keyEquivalent: ""
        )
        applyLayout.target = self
        applyLayout.isEnabled = snapshot.canRunCoreFeatures
        menu.addItem(applyLayout)

        if let lastLayoutApplicationResult {
            let applyStatus = NSMenuItem(title: lastLayoutApplicationResult.statusTitle, action: nil, keyEquivalent: "")
            applyStatus.isEnabled = false
            menu.addItem(applyStatus)
        }

        let scan = NSMenuItem(
            title: "Scan Menu Bar Items...",
            action: #selector(openScanResults),
            keyEquivalent: ""
        )
        scan.target = self
        scan.isEnabled = snapshot.canRunCoreFeatures
        menu.addItem(scan)

        let refresh = NSMenuItem(
            title: "Refresh Permission Status",
            action: #selector(refreshPermissions),
            keyEquivalent: "r"
        )
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(
            title: "Quit Corona",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func scheduleInitialLayoutRestore() {
        guard !didScheduleInitialLayoutRestore else { return }
        didScheduleInitialLayoutRestore = true

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self, self.permissionChecker.snapshot().canRunCoreFeatures else { return }
            await MainActor.run {
                self.sanitizeSavedLayout()
            }
            let result = await self.applySavedLayoutWithVisibleBoundary()
            await MainActor.run {
                self.lastLayoutApplicationResult = result
                self.rebuildMenu()
            }
        }
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

    private func statusTitle(for snapshot: PermissionSnapshot) -> String {
        switch snapshot.capabilityStatus {
        case .missing:
            return "Accessibility Required"
        case .hasRequired:
            return "Ready - Icon Previews Disabled"
        case .hasAll:
            return "Ready"
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
        statusItem.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Corona")
        statusItem.button?.image?.isTemplate = true
    }

    @objc private func showHiddenItems() {
        sectionController.setHiddenSectionVisible(true)
        scheduleAutoRehideIfNeeded()
        rebuildMenu()
    }

    @objc private func hideHiddenItems() {
        autoRehideTask?.cancel()
        sectionController.setHiddenSectionVisible(false)
        rebuildMenu()
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            if let button = statusItem.button {
                makeStatusMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
            }
            return
        }

        switch sectionController.hiddenVisibility {
        case .shown:
            hideHiddenItems()
        case .hidden:
            showHiddenItems()
        }
    }

    @objc private func openMainPanel() {
        if mainPanelWindowController == nil {
            mainPanelWindowController = MainPanelWindowController(
                cacheController: cacheController,
                layoutStore: layoutStore,
                settingsStore: settingsStore,
                settings: settings,
                permissionChecker: permissionChecker,
                boundaryProvider: { [weak self] in
                    self?.sectionController.currentBoundary()
                },
                applyHandler: { [weak self] in
                    guard let self else { return .failed("Controller unavailable") }
                    let result = await self.applySavedLayoutWithVisibleBoundary()
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

    @objc private func openLayoutEditor() {
        if layoutEditorWindowController == nil {
            layoutEditorWindowController = LayoutEditorWindowController(
                cacheController: cacheController,
                layoutStore: layoutStore,
                settingsStore: settingsStore,
                boundaryProvider: { [weak self] in
                    self?.sectionController.currentBoundary()
                },
                applyHandler: { [weak self] in
                    guard let self else { return .failed("Controller unavailable") }
                    let result = await self.applySavedLayoutWithVisibleBoundary()
                    self.lastLayoutApplicationResult = result
                    self.rebuildMenu()
                    return result
                }
            )
        }
        layoutEditorWindowController?.show()
    }

    @objc private func openHiddenPanel() {
        if hiddenItemsPanelWindowController == nil {
            hiddenItemsPanelWindowController = HiddenItemsPanelWindowController(
                cacheController: cacheController,
                layoutStore: layoutStore,
                thumbnailProvider: thumbnailProvider,
                revealHandler: { [weak self] uid in
                    guard let self else { return .failed("Controller unavailable") }
                    let result = await self.ensureLayoutApplicationController().reveal(uid: uid)
                    self.scheduleAutoRehideIfNeeded()
                    return result
                }
            )
        }
        hiddenItemsPanelWindowController?.show()
    }

    @objc private func openScanResults() {
        if scanResultsWindowController == nil {
            scanResultsWindowController = ScanResultsWindowController(
                cacheController: cacheController,
                thumbnailProvider: thumbnailProvider,
                boundaryProvider: { [weak self] in
                    self?.sectionController.currentBoundary()
                }
            )
        }
        scanResultsWindowController?.show()
    }

    @objc private func applySavedLayout() {
        Task { [weak self] in
            guard let self else { return }
            let result = await self.applySavedLayoutWithVisibleBoundary()
            await MainActor.run {
                self.lastLayoutApplicationResult = result
                self.rebuildMenu()
            }
        }
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

    @MainActor
    private func applySavedLayoutWithVisibleBoundary() async -> LayoutApplicationResult {
        sanitizeSavedLayout()
        autoRehideTask?.cancel()

        sectionController.setHiddenSectionVisible(true)
        if settings.enableAlwaysHiddenSection {
            sectionController.setAlwaysHiddenSectionVisible(true)
        }

        try? await Task.sleep(nanoseconds: 180_000_000)
        let result = await ensureLayoutApplicationController().applySavedLayout()

        sectionController.setHiddenSectionVisible(false)
        if settings.enableAlwaysHiddenSection {
            sectionController.setAlwaysHiddenSectionVisible(false)
        }
        rebuildMenu()
        return result
    }

    private func sanitizeSavedLayout() {
        let savedOrder = layoutStore.loadSavedSectionOrder()
        let sanitized = savedOrder.removingCoronaSelfItems()
        if sanitized != savedOrder {
            layoutStore.saveSavedSectionOrder(sanitized)
        }

        let known = layoutStore.loadKnownItemIdentifiers()
        let sanitizedKnown = known.filter { !Self.isCoronaSelfIdentifier($0) }
        if sanitizedKnown != known {
            layoutStore.saveKnownItemIdentifiers(Set(sanitizedKnown))
        }

        let savedUIDs = Set(savedOrder.visible + savedOrder.hidden + savedOrder.alwaysHidden)
        for uid in known.union(savedUIDs) where Self.isCoronaSelfIdentifier(uid) {
            layoutStore.savePendingRelocation(nil, for: uid)
        }
    }

    static func isCoronaSelfIdentifier(_ uid: String) -> Bool {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.ltz.corona"
        return uid.localizedCaseInsensitiveContains(bundleIdentifier)
            || uid.localizedCaseInsensitiveContains("com.ltz.corona")
            || uid.localizedCaseInsensitiveContains("Corona:Corona")
            || uid.localizedCaseInsensitiveContains("Corona:Status Item")
            || uid.localizedCaseInsensitiveContains("corona.control")
    }

    private func scheduleAutoRehideIfNeeded() {
        let latestSettings = settingsStore.load()
        guard latestSettings.autoRehide else { return }

        autoRehideTask?.cancel()
        autoRehideTask = Task { [weak self] in
            let delay = UInt64(max(0.5, latestSettings.rehideInterval) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled, self.permissionChecker.snapshot().canRunCoreFeatures else { return }
            let result = await self.applySavedLayoutWithVisibleBoundary()
            await MainActor.run {
                self.lastLayoutApplicationResult = result
                self.rebuildMenu()
            }
        }
    }

    @objc private func openSettings() {
        openMainPanel()
        mainPanelWindowController?.showSettings()
    }

    @objc private func refreshPermissions() {
        mainPanelWindowController?.refreshPermissions()
        rebuildMenu()
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
}
