import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private let settingsStore = UserDefaultsSettingsStore()
    private let permissionChecker = SystemPermissionChecker()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(
            settingsStore: settingsStore,
            permissionChecker: permissionChecker
        )
        menuBarController?.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
