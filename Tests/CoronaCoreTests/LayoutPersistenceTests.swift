import CoronaCore
import XCTest

final class LayoutPersistenceTests: XCTestCase {
    func testSavedSectionOrderRoundTrips() {
        let suiteName = "CoronaLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsLayoutPersistenceStore(defaults: defaults)
        let expected = SectionOrder(
            visible: ["a"],
            hidden: ["b"],
            alwaysHidden: ["c"]
        )

        store.saveSavedSectionOrder(expected)

        XCTAssertEqual(store.loadSavedSectionOrder(), expected)
    }

    func testKnownIdentifiersRoundTripSortedSet() {
        let suiteName = "CoronaLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsLayoutPersistenceStore(defaults: defaults)
        store.saveKnownItemIdentifiers(["b", "a"])

        XCTAssertEqual(store.loadKnownItemIdentifiers(), ["a", "b"])
    }
}
