import CoronaCore
import XCTest

final class MoveDestinationResolverTests: XCTestCase {
    func testResolvesNeighborTargetsFromCache() {
        let item = makeItem(windowID: 1, namespace: "app", title: "A", sourcePID: 10)
        let cache = ItemCache(displayID: nil, visibleItems: [item], hiddenItems: [], alwaysHiddenItems: [])

        XCTAssertEqual(
            MoveDestinationResolver().resolve(target: .leftOfUID("app:A"), cache: cache, sectionBoundaries: [:]),
            .leftOfItem(item)
        )
        XCTAssertEqual(
            MoveDestinationResolver().resolve(target: .rightOfUID("app:A"), cache: cache, sectionBoundaries: [:]),
            .rightOfItem(item)
        )
    }

    func testResolvesSectionBoundary() {
        let boundary = makeItem(windowID: 99, namespace: "control", title: "hidden", sourcePID: 10)
        let cache = ItemCache(displayID: nil, visibleItems: [], hiddenItems: [], alwaysHiddenItems: [])

        let destination = MoveDestinationResolver().resolve(
            target: .sectionBoundary(.hidden),
            cache: cache,
            sectionBoundaries: [.hidden: boundary]
        )

        XCTAssertEqual(destination, .leftOfItem(boundary))
    }

    func testResolvesHiddenBoundaryToRightOfHiddenControlWhenAlwaysHiddenControlIsRight() {
        let hidden = makeBoundary(windowID: 1, title: "hidden", minX: 100)
        let alwaysHidden = makeBoundary(windowID: 2, title: "alwaysHidden", minX: 200)
        let cache = ItemCache(displayID: nil, visibleItems: [], hiddenItems: [], alwaysHiddenItems: [])

        let destination = MoveDestinationResolver().resolve(
            target: .sectionBoundary(.hidden),
            cache: cache,
            sectionBoundaries: [.hidden: hidden, .alwaysHidden: alwaysHidden]
        )

        XCTAssertEqual(destination, .rightOfItem(hidden))
    }

    func testResolvesHiddenBoundaryToLeftOfHiddenControlWhenAlwaysHiddenControlIsLeft() {
        let alwaysHidden = makeBoundary(windowID: 1, title: "alwaysHidden", minX: 100)
        let hidden = makeBoundary(windowID: 2, title: "hidden", minX: 200)
        let cache = ItemCache(displayID: nil, visibleItems: [], hiddenItems: [], alwaysHiddenItems: [])

        let destination = MoveDestinationResolver().resolve(
            target: .sectionBoundary(.hidden),
            cache: cache,
            sectionBoundaries: [.hidden: hidden, .alwaysHidden: alwaysHidden]
        )

        XCTAssertEqual(destination, .leftOfItem(hidden))
    }

    func testResolvesVisibleBoundaryToRightOfControl() {
        let boundary = makeItem(windowID: 99, namespace: "control", title: "hidden", sourcePID: 10)
        let cache = ItemCache(displayID: nil, visibleItems: [], hiddenItems: [], alwaysHiddenItems: [])

        let destination = MoveDestinationResolver().resolve(
            target: .sectionBoundary(.visible),
            cache: cache,
            sectionBoundaries: [.visible: boundary]
        )

        XCTAssertEqual(destination, .rightOfItem(boundary))
    }

    func testReturnsNilForMissingTarget() {
        let cache = ItemCache(displayID: nil, visibleItems: [], hiddenItems: [], alwaysHiddenItems: [])

        XCTAssertNil(MoveDestinationResolver().resolve(target: .leftOfUID("missing"), cache: cache, sectionBoundaries: [:]))
        XCTAssertNil(MoveDestinationResolver().resolve(target: .sectionBoundary(.hidden), cache: cache, sectionBoundaries: [:]))
    }

    private func makeBoundary(windowID: UInt32, title: String, minX: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: "control", title: title, volatileWindowID: windowID),
            windowID: windowID,
            ownerPID: 10,
            sourcePID: 10,
            bounds: CGRect(x: minX, y: 0, width: 10, height: 22),
            title: title,
            isOnScreen: true,
            isMovable: false,
            canBeHidden: false
        )
    }
}
