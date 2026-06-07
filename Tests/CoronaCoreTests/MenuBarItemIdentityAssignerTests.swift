import CoronaCore
import CoreGraphics
import XCTest

final class MenuBarItemIdentityAssignerTests: XCTestCase {
    func testAssignsNoInstanceIndexForSingleItem() {
        let item = makeItem(windowID: 1, namespace: "com.example.one", title: "One", sourcePID: 100)

        let assigned = MenuBarItemIdentityAssigner().assignInstanceIndexes(to: [item])

        XCTAssertNil(assigned[0].tag.instanceIndex)
        XCTAssertEqual(assigned[0].tag.stableIdentifier, "com.example.one:One")
    }

    func testAssignsInstanceIndexesForDuplicateNamespaceAndTitle() {
        let first = makeItem(windowID: 20, namespace: "com.example.one", title: "One", sourcePID: 100)
        let second = makeItem(windowID: 10, namespace: "com.example.one", title: "One", sourcePID: 100)

        let assigned = MenuBarItemIdentityAssigner().assignInstanceIndexes(to: [first, second])

        XCTAssertEqual(assigned[0].tag.instanceIndex, 1)
        XCTAssertEqual(assigned[1].tag.instanceIndex, 0)
        XCTAssertEqual(assigned[0].tag.stableIdentifier, "com.example.one:One:1")
        XCTAssertEqual(assigned[1].tag.stableIdentifier, "com.example.one:One:0")
    }

    func testPersistenceFiltersUnresolvedSourcePIDAndNonHideableItems() {
        let stable = makeItem(windowID: 1, namespace: "com.example.stable", title: "Stable", sourcePID: 100)
        let unresolved = makeItem(windowID: 2, namespace: "com.example.unresolved", title: "Unresolved", sourcePID: nil)
        let control = makeItem(windowID: 3, namespace: "com.example.control", title: "Control", sourcePID: 200, canBeHidden: false)

        let items = MenuBarItemIdentityAssigner().stableItemsForPersistence(from: [stable, unresolved, control])

        XCTAssertEqual(items.map(\.windowID), [1])
    }
}

func makeItem(
    windowID: UInt32,
    namespace: String,
    title: String,
    sourcePID: Int32?,
    canBeHidden: Bool = true
) -> MenuBarItem {
    MenuBarItem(
        tag: MenuBarItemTag(namespace: namespace, title: title, volatileWindowID: windowID),
        windowID: windowID,
        ownerPID: sourcePID ?? 1,
        sourcePID: sourcePID,
        bounds: CGRect(x: Int(windowID) * 10, y: 0, width: 20, height: 22),
        title: title,
        isOnScreen: true,
        isMovable: true,
        canBeHidden: canBeHidden
    )
}
