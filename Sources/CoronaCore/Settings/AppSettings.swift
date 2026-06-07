import Foundation

public enum NewItemsSection: String, Codable, CaseIterable, Equatable, Sendable {
    case visible
    case hidden
    case alwaysHidden
}

public enum RehideStrategy: Int, Codable, CaseIterable, Equatable, Sendable {
    case smart = 0
    case timer = 1
    case appSwitch = 2
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var launchAtLogin: Bool
    public var showMainIcon: Bool
    public var autoRehide: Bool
    public var rehideStrategy: RehideStrategy
    public var rehideInterval: TimeInterval
    public var newItemsSection: NewItemsSection
    public var enableAlwaysHiddenSection: Bool
    public var enableScreenRecordingPreviews: Bool
    public var enableDiagnosticLogging: Bool

    public init(
        launchAtLogin: Bool = false,
        showMainIcon: Bool = true,
        autoRehide: Bool = true,
        rehideStrategy: RehideStrategy = .smart,
        rehideInterval: TimeInterval = 8,
        newItemsSection: NewItemsSection = .hidden,
        enableAlwaysHiddenSection: Bool = false,
        enableScreenRecordingPreviews: Bool = false,
        enableDiagnosticLogging: Bool = false
    ) {
        self.launchAtLogin = launchAtLogin
        self.showMainIcon = showMainIcon
        self.autoRehide = autoRehide
        self.rehideStrategy = rehideStrategy
        self.rehideInterval = rehideInterval
        self.newItemsSection = newItemsSection
        self.enableAlwaysHiddenSection = enableAlwaysHiddenSection
        self.enableScreenRecordingPreviews = enableScreenRecordingPreviews
        self.enableDiagnosticLogging = enableDiagnosticLogging
    }
}

public protocol SettingsStore {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}
