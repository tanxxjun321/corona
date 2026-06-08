import CoreGraphics
import CoronaCore
import XCTest

final class MenuBarDisplayDuplicateFilterTests: XCTestCase {
    func testKeepsPrimaryDisplayCopyOfMirroredMenuBarItem() {
        let primary = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let secondary = CGRect(x: 1728, y: 0, width: 1512, height: 982)
        let primaryItem = makeItem(
            windowID: 1,
            bounds: CGRect(x: 1600, y: 0, width: 28, height: 24)
        )
        let secondaryItem = makeItem(
            windowID: 2,
            bounds: CGRect(x: 1728 + 1384, y: 0, width: 28, height: 24)
        )

        let filtered = MenuBarDisplayDuplicateFilter(
            primaryDisplayFrame: primary,
            displayFrames: [primary, secondary]
        ).uniqueItems(from: [secondaryItem, primaryItem])

        XCTAssertEqual(filtered.map(\.windowID), [1])
    }

    func testKeepsDistinctItemsFromSameAppAtDifferentPositions() {
        let primary = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let first = makeItem(windowID: 1, bounds: CGRect(x: 1600, y: 0, width: 28, height: 24))
        let second = makeItem(windowID: 2, bounds: CGRect(x: 1560, y: 0, width: 28, height: 24))

        let filtered = MenuBarDisplayDuplicateFilter(
            primaryDisplayFrame: primary,
            displayFrames: [primary]
        ).uniqueItems(from: [first, second])

        XCTAssertEqual(filtered.map(\.windowID), [1, 2])
    }

    private func makeItem(windowID: UInt32, bounds: CGRect) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: "com.example.status", title: "Example", volatileWindowID: windowID),
            windowID: windowID,
            ownerPID: 42,
            sourcePID: 42,
            bounds: bounds,
            title: "Example",
            isOnScreen: true,
            isMovable: true,
            canBeHidden: true
        )
    }
}
