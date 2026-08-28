import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var showMainIcon: Bool
    public var autoRehide: Bool
    public var rehideInterval: TimeInterval
    public var newItemsSection: MenuBarSection
    public var newItemsPlacement: NewItemsPlacement
    public var enableAlwaysHiddenSection: Bool
    public var enableScreenRecordingPreviews: Bool
    public var enableDiagnosticLogging: Bool

    public init(
        showMainIcon: Bool = true,
        autoRehide: Bool = true,
        rehideInterval: TimeInterval = 8,
        newItemsSection: MenuBarSection = .visible,
        newItemsPlacement: NewItemsPlacement = .append,
        enableAlwaysHiddenSection: Bool = false,
        enableScreenRecordingPreviews: Bool = false,
        enableDiagnosticLogging: Bool = false
    ) {
        self.showMainIcon = showMainIcon
        self.autoRehide = autoRehide
        self.rehideInterval = rehideInterval
        self.newItemsSection = newItemsSection
        self.newItemsPlacement = newItemsPlacement
        self.enableAlwaysHiddenSection = enableAlwaysHiddenSection
        self.enableScreenRecordingPreviews = enableScreenRecordingPreviews
        self.enableDiagnosticLogging = enableDiagnosticLogging
    }
}

public protocol SettingsStore {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}
