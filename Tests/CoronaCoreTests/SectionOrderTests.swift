import CoronaCore
import XCTest

final class SectionOrderTests: XCTestCase {
    func testBuildsFromCacheSections() {
        let cache = ItemCache(
            displayID: nil,
            visibleItems: [makeItem(windowID: 1, namespace: "app", title: "A", sourcePID: 10)],
            hiddenItems: [makeItem(windowID: 2, namespace: "app", title: "B", sourcePID: 10)],
            alwaysHiddenItems: [makeItem(windowID: 3, namespace: "app", title: "C", sourcePID: 10)]
        )

        XCTAssertEqual(
            SectionOrder(cache: cache),
            SectionOrder(visible: ["app:A"], hidden: ["app:B"], alwaysHidden: ["app:C"])
        )
    }

    func testIsEmptyRequiresAllSectionsEmpty() {
        XCTAssertTrue(SectionOrder().isEmpty)
        XCTAssertFalse(SectionOrder(visible: ["a"]).isEmpty)
        XCTAssertFalse(SectionOrder(hidden: ["a"]).isEmpty)
        XCTAssertFalse(SectionOrder(alwaysHidden: ["a"]).isEmpty)
    }
}
