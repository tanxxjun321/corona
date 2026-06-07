import AppKit
import CoronaCore

final class MenuBarController {
    private let settingsStore: SettingsStore
    private let permissionChecker: SystemPermissionChecker
    private let statusItem: NSStatusItem
    private let sectionController: StatusSectionController
    private let cacheController: MenuBarCacheController
    private let layoutStore: LayoutPersistenceStore
    private var settings: AppSettings
    private var settingsWindowController: SettingsWindowController?
    private var scanResultsWindowController: ScanResultsWindowController?
    private var layoutEditorWindowController: LayoutEditorWindowController?
    private var hiddenItemsPanelWindowController: HiddenItemsPanelWindowController?

    init(
        settingsStore: SettingsStore,
        permissionChecker: SystemPermissionChecker
    ) {
        self.settingsStore = settingsStore
        self.permissionChecker = permissionChecker
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.sectionController = StatusSectionController()
        self.cacheController = MenuBarCacheController(provider: PublicMenuBarDiscoveryProvider())
        self.layoutStore = UserDefaultsLayoutPersistenceStore()
        self.settings = settingsStore.load()
    }

    func start() {
        configureStatusItem()
        sectionController.setAlwaysHiddenSectionEnabled(settings.enableAlwaysHiddenSection)
        rebuildMenu()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "Corona")
        button.image?.isTemplate = true
        button.toolTip = "Corona"
    }

    private func rebuildMenu() {
        let snapshot = permissionChecker.snapshot()
        let menu = NSMenu()

        let statusItem = NSMenuItem(title: statusTitle(for: snapshot), action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(NSMenuItem.separator())

        let toggleHidden = NSMenuItem(
            title: hiddenToggleTitle,
            action: #selector(showHiddenItems),
            keyEquivalent: ""
        )
        toggleHidden.target = self
        toggleHidden.isEnabled = snapshot.canRunCoreFeatures
        menu.addItem(toggleHidden)

        let hiddenPanel = NSMenuItem(
            title: "Open Hidden Panel...",
            action: #selector(openHiddenPanel),
            keyEquivalent: ""
        )
        hiddenPanel.target = self
        hiddenPanel.isEnabled = snapshot.canRunCoreFeatures
        menu.addItem(hiddenPanel)

        let layout = NSMenuItem(
            title: "Open Layout Editor...",
            action: #selector(openLayoutEditor),
            keyEquivalent: ""
        )
        layout.target = self
        layout.isEnabled = snapshot.canRunCoreFeatures
        menu.addItem(layout)

        let scan = NSMenuItem(
            title: "Scan Menu Bar Items...",
            action: #selector(openScanResults),
            keyEquivalent: ""
        )
        scan.target = self
        scan.isEnabled = snapshot.canRunCoreFeatures
        menu.addItem(scan)

        let permissions = NSMenuItem(
            title: "Permissions...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        permissions.target = self
        menu.addItem(permissions)

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

        statusItem.menu = menu
        updateStatusIcon(for: snapshot)
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

    private var hiddenToggleTitle: String {
        switch sectionController.hiddenVisibility {
        case .shown:
            return "Hide Hidden Items"
        case .hidden:
            return "Show Hidden Items"
        }
    }

    @objc private func showHiddenItems() {
        switch sectionController.hiddenVisibility {
        case .shown:
            sectionController.setHiddenSectionVisible(false)
        case .hidden:
            sectionController.setHiddenSectionVisible(true)
        }
        rebuildMenu()
    }

    @objc private func openLayoutEditor() {
        if layoutEditorWindowController == nil {
            layoutEditorWindowController = LayoutEditorWindowController(
                cacheController: cacheController,
                layoutStore: layoutStore,
                settingsStore: settingsStore
            )
        }
        layoutEditorWindowController?.show()
    }

    @objc private func openHiddenPanel() {
        if hiddenItemsPanelWindowController == nil {
            hiddenItemsPanelWindowController = HiddenItemsPanelWindowController(
                cacheController: cacheController,
                layoutStore: layoutStore
            )
        }
        hiddenItemsPanelWindowController?.show()
    }

    @objc private func openScanResults() {
        if scanResultsWindowController == nil {
            scanResultsWindowController = ScanResultsWindowController(cacheController: cacheController)
        }
        scanResultsWindowController?.show()
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settings: settings,
                settingsStore: settingsStore,
                permissionChecker: permissionChecker,
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
        settingsWindowController?.show()
    }

    @objc private func refreshPermissions() {
        settingsWindowController?.refreshPermissions()
        rebuildMenu()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
