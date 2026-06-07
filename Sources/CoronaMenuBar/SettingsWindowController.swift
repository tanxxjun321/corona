import AppKit
import CoronaCore
import SwiftUI

final class SettingsWindowController: NSWindowController {
    private let model: SettingsViewModel

    init(
        settings: AppSettings,
        settingsStore: SettingsStore,
        permissionChecker: SystemPermissionChecker,
        onSettingsChanged: @escaping (AppSettings) -> Void,
        onPermissionsChanged: @escaping () -> Void
    ) {
        self.model = SettingsViewModel(
            settings: settings,
            permissionChecker: permissionChecker,
            onSettingsChanged: onSettingsChanged,
            onPermissionsChanged: onPermissionsChanged
        )

        let hostingController = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Corona Settings"
        window.setContentSize(NSSize(width: 680, height: 460))
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
        refreshPermissions()
    }

    func refreshPermissions() {
        model.refreshPermissions()
    }
}
