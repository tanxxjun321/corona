import CoronaCore
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            onSettingsChanged(settings)
        }
    }

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
        self.permissions = permissionChecker.snapshot()
        self.onSettingsChanged = onSettingsChanged
        self.onPermissionsChanged = onPermissionsChanged
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
