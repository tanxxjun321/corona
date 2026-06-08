import Foundation

public final class UserDefaultsSettingsStore: SettingsStore {
    private enum Key {
        static let launchAtLogin = "Settings.launchAtLogin"
        static let showMainIcon = "Settings.showMainIcon"
        static let autoRehide = "Settings.autoRehide"
        static let rehideStrategy = "Settings.rehideStrategy"
        static let rehideInterval = "Settings.rehideInterval"
        static let newItemsSection = "Settings.newItemsSection"
        static let newItemsPlacement = "Settings.newItemsPlacement.v1"
        static let enableAlwaysHiddenSection = "Settings.enableAlwaysHiddenSection"
        static let enableNotchOverflow = "Settings.enableNotchOverflow"
        static let enableScreenRecordingPreviews = "Settings.enableScreenRecordingPreviews"
        static let enableDiagnosticLogging = "Settings.enableDiagnosticLogging"
        static let migratedDefaultNewItemsSection = "Settings.migratedDefaultNewItemsSection.v1"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppSettings {
        migrateUnsafeDefaultsIfNeeded()

        let defaults = AppSettings()
        return AppSettings(
            launchAtLogin: bool(forKey: Key.launchAtLogin, default: defaults.launchAtLogin),
            showMainIcon: bool(forKey: Key.showMainIcon, default: defaults.showMainIcon),
            autoRehide: bool(forKey: Key.autoRehide, default: defaults.autoRehide),
            rehideStrategy: RehideStrategy(rawValue: integer(forKey: Key.rehideStrategy, default: defaults.rehideStrategy.rawValue)) ?? defaults.rehideStrategy,
            rehideInterval: double(forKey: Key.rehideInterval, default: defaults.rehideInterval),
            newItemsSection: NewItemsSection(rawValue: string(forKey: Key.newItemsSection, default: defaults.newItemsSection.rawValue)) ?? defaults.newItemsSection,
            newItemsPlacement: codable(forKey: Key.newItemsPlacement, default: defaults.newItemsPlacement),
            enableAlwaysHiddenSection: bool(forKey: Key.enableAlwaysHiddenSection, default: defaults.enableAlwaysHiddenSection),
            enableNotchOverflow: bool(forKey: Key.enableNotchOverflow, default: defaults.enableNotchOverflow),
            enableScreenRecordingPreviews: bool(forKey: Key.enableScreenRecordingPreviews, default: defaults.enableScreenRecordingPreviews),
            enableDiagnosticLogging: bool(forKey: Key.enableDiagnosticLogging, default: defaults.enableDiagnosticLogging)
        )
    }

    public func save(_ settings: AppSettings) {
        defaults.set(settings.launchAtLogin, forKey: Key.launchAtLogin)
        defaults.set(settings.showMainIcon, forKey: Key.showMainIcon)
        defaults.set(settings.autoRehide, forKey: Key.autoRehide)
        defaults.set(settings.rehideStrategy.rawValue, forKey: Key.rehideStrategy)
        defaults.set(settings.rehideInterval, forKey: Key.rehideInterval)
        defaults.set(settings.newItemsSection.rawValue, forKey: Key.newItemsSection)
        if let data = try? encoder.encode(settings.newItemsPlacement) {
            defaults.set(data, forKey: Key.newItemsPlacement)
        }
        defaults.set(settings.enableAlwaysHiddenSection, forKey: Key.enableAlwaysHiddenSection)
        defaults.set(settings.enableNotchOverflow, forKey: Key.enableNotchOverflow)
        defaults.set(settings.enableScreenRecordingPreviews, forKey: Key.enableScreenRecordingPreviews)
        defaults.set(settings.enableDiagnosticLogging, forKey: Key.enableDiagnosticLogging)
    }

    private func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    private func integer(forKey key: String, default defaultValue: Int) -> Int {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.integer(forKey: key)
    }

    private func double(forKey key: String, default defaultValue: Double) -> Double {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.double(forKey: key)
    }

    private func string(forKey key: String, default defaultValue: String) -> String {
        defaults.string(forKey: key) ?? defaultValue
    }

    private func codable<Value: Decodable>(forKey key: String, default defaultValue: Value) -> Value {
        guard let data = defaults.data(forKey: key),
              let value = try? decoder.decode(Value.self, from: data) else {
            return defaultValue
        }
        return value
    }

    private func migrateUnsafeDefaultsIfNeeded() {
        guard defaults.object(forKey: Key.migratedDefaultNewItemsSection) == nil else { return }

        if defaults.string(forKey: Key.newItemsSection) == NewItemsSection.hidden.rawValue {
            defaults.set(NewItemsSection.visible.rawValue, forKey: Key.newItemsSection)
        }
        defaults.set(true, forKey: Key.migratedDefaultNewItemsSection)
    }
}
