import CoronaCore
import CoreGraphics
import XCTest

final class MoveDestinationVerificationTests: XCTestCase {
    func testLeftOfItemIsSatisfiedWhenMovedItemIsLeftOfAnchor() {
        let moved = withBounds(
            makeItem(windowID: 1, namespace: "app", title: "A", sourcePID: 10),
            CGRect(x: 10, y: 0, width: 20, height: 22)
        )
        let anchor = withBounds(
            makeItem(windowID: 2, namespace: "app", title: "B", sourcePID: 10),
            CGRect(x: 60, y: 0, width: 20, height: 22)
        )
        let cache = ItemCache(displayID: nil, visibleItems: [moved, anchor], hiddenItems: [], alwaysHiddenItems: [])

        XCTAssertTrue(MoveDestination.leftOfItem(anchor).isSatisfied(for: moved.tag.stableIdentifier, in: cache))
        XCTAssertFalse(MoveDestination.rightOfItem(anchor).isSatisfied(for: moved.tag.stableIdentifier, in: cache))
    }

    func testRightOfItemIsSatisfiedWhenMovedItemIsRightOfAnchor() {
        let anchor = withBounds(
            makeItem(windowID: 1, namespace: "app", title: "A", sourcePID: 10),
            CGRect(x: 10, y: 0, width: 20, height: 22)
        )
        let moved = withBounds(
            makeItem(windowID: 2, namespace: "app", title: "B", sourcePID: 10),
            CGRect(x: 60, y: 0, width: 20, height: 22)
        )
        let cache = ItemCache(displayID: nil, visibleItems: [anchor, moved], hiddenItems: [], alwaysHiddenItems: [])

        XCTAssertTrue(MoveDestination.rightOfItem(anchor).isSatisfied(for: moved.tag.stableIdentifier, in: cache))
        XCTAssertFalse(MoveDestination.leftOfItem(anchor).isSatisfied(for: moved.tag.stableIdentifier, in: cache))
    }

    func testVerificationFailsWhenMovedItemOrAnchorIsMissing() {
        let moved = makeItem(windowID: 1, namespace: "app", title: "A", sourcePID: 10)
        let anchor = makeItem(windowID: 2, namespace: "app", title: "B", sourcePID: 10)
        let cache = ItemCache(displayID: nil, visibleItems: [moved], hiddenItems: [], alwaysHiddenItems: [])

        XCTAssertFalse(MoveDestination.leftOfItem(anchor).isSatisfied(for: moved.tag.stableIdentifier, in: cache))
        XCTAssertFalse(MoveDestination.leftOfItem(anchor).isSatisfied(for: "missing", in: cache))
    }

    func testVerificationAllowsSmallToleranceAfterSystemRelayout() {
        let moved = withBounds(
            makeItem(windowID: 1, namespace: "app", title: "A", sourcePID: 10),
            CGRect(x: 52, y: 0, width: 20, height: 22)
        )
        let anchor = withBounds(
            makeItem(windowID: 2, namespace: "app", title: "B", sourcePID: 10),
            CGRect(x: 40, y: 0, width: 20, height: 22)
        )
        let cache = ItemCache(displayID: nil, visibleItems: [anchor, moved], hiddenItems: [], alwaysHiddenItems: [])

        XCTAssertFalse(MoveDestination.leftOfItem(anchor).isSatisfied(for: moved.tag.stableIdentifier, in: cache))
        XCTAssertTrue(MoveDestination.leftOfItem(anchor).isSatisfied(
            for: moved.tag.stableIdentifier,
            in: cache,
            tolerancePixels: 13
        ))
    }

    private func withBounds(_ item: MenuBarItem, _ bounds: CGRect) -> MenuBarItem {
        var copy = item
        copy.bounds = bounds
        return copy
    }
}
