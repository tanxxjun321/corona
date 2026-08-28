import Foundation
import ServiceManagement

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            onSettingsChanged(settings)
        }
    }

    @Published private(set) var launchAtLogin: Bool

    @Published private(set) var permissions: PermissionSnapshot

    private let permissionChecker: SystemPermissionChecker
    private let onSettingsChanged: (AppSettings) -> Void
    private let onPermissionsChanged: () -> Void

    init(
        settings: AppSettings,
        permissionChecker: SystemPermissionChecker,
        onSettingsChanged: @escaping (AppSettings) -> Void,
        onPermissionsChanged: @escaping () -> Void
    ) {
        self.settings = settings
        self.permissionChecker = permissionChecker
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        self.permissions = permissionChecker.snapshot()
        self.onSettingsChanged = onSettingsChanged
        self.onPermissionsChanged = onPermissionsChanged
    }

    func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            CoronaDebugLog.log("Launch at login \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
        launchAtLogin = service.status == .enabled
    }

    func refreshPermissions() {
        permissions = permissionChecker.snapshot()
        onPermissionsChanged()
    }

    func requestAccessibility() {
        permissionChecker.requestAccessibilityPermission()
        refreshPermissions()
    }

    func openScreenRecordingSettings() {
        permissionChecker.openScreenRecordingSettings()
        refreshPermissions()
    }
}
