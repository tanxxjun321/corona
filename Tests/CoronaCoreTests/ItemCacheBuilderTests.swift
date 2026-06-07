import CoronaCore
import XCTest

final class ItemCacheBuilderTests: XCTestCase {
    func testBuildsCacheFromWindowSections() {
        let visible = makeItem(windowID: 1, namespace: "a", title: "A", sourcePID: 10)
        let hidden = makeItem(windowID: 2, namespace: "b", title: "B", sourcePID: 20)
        let alwaysHidden = makeItem(windowID: 3, namespace: "c", title: "C", sourcePID: 30)
        let snapshot = MenuBarSnapshot(displayID: 99, items: [visible, hidden, alwaysHidden])

        let cache = ItemCacheBuilder().build(
            snapshot: snapshot,
            sectionByWindowID: [
                2: .hidden,
                3: .alwaysHidden
            ]
        )

        XCTAssertEqual(cache.displayID, 99)
        XCTAssertEqual(cache.visibleItems.map(\.windowID), [1])
        XCTAssertEqual(cache.hiddenItems.map(\.windowID), [2])
        XCTAssertEqual(cache.alwaysHiddenItems.map(\.windowID), [3])
    }
}
