import CoronaCore
import XCTest

final class UserDefaultsSettingsStoreTests: XCTestCase {
    func testLoadReturnsDefaultsWhenNoValuesExist() {
        let suiteName = "CoronaTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = UserDefaultsSettingsStore(defaults: defaults).load()

        XCTAssertEqual(settings, AppSettings())
    }

    func testSaveAndLoadRoundTripsSettings() {
        let suiteName = "CoronaTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsSettingsStore(defaults: defaults)
        let expected = AppSettings(
            showMainIcon: false,
            autoRehide: false,
            rehideInterval: 12,
            newItemsSection: .alwaysHidden,
            newItemsPlacement: .rightOf("com.example.MenuItem:Status"),
            enableAlwaysHiddenSection: true,
            enableScreenRecordingPreviews: true,
            enableDiagnosticLogging: true
        )

        store.save(expected)

        XCTAssertEqual(store.load(), expected)
    }

    func testMigratesUnsafeHiddenNewItemsDefaultToVisible() {
        let suiteName = "CoronaTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(MenuBarSection.hidden.rawValue, forKey: "Settings.newItemsSection")

        let settings = UserDefaultsSettingsStore(defaults: defaults).load()

        XCTAssertEqual(settings.newItemsSection, .visible)
    }
}
