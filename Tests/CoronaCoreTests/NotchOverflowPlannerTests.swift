import CoronaCore
import XCTest

final class NotchOverflowPlannerTests: XCTestCase {
    func testMovesLeftmostHideableVisibleItemsIntoHiddenUntilRightSideFits() {
        let desired = SectionOrder(visible: ["a", "b", "c"], hidden: ["h"])

        let plan = NotchOverflowPlanner().plan(
            desiredOrder: desired,
            itemWidths: ["a": 24, "b": 24, "c": 24],
            hideableUIDs: ["a", "b", "c"],
            availableWidth: 48
        )

        XCTAssertEqual(plan.overflowUIDs, ["a"])
        XCTAssertEqual(plan.order.visible, ["b", "c"])
        XCTAssertEqual(plan.order.hidden, ["h", "a"])
    }

    func testKeepsNonHideableItemsVisibleAndOverflowsHideableItemsAroundThem() {
        let desired = SectionOrder(visible: ["a", "clock", "b"], hidden: [])

        let plan = NotchOverflowPlanner().plan(
            desiredOrder: desired,
            itemWidths: ["a": 24, "clock": 80, "b": 24],
            hideableUIDs: ["a", "b"],
            availableWidth: 40
        )

        XCTAssertEqual(plan.overflowUIDs, ["a"])
        XCTAssertEqual(plan.order.visible, ["clock", "b"])
        XCTAssertEqual(plan.order.hidden, ["a"])
    }

    func testReturnsOriginalOrderWhenEverythingFits() {
        let desired = SectionOrder(visible: ["a", "b"], hidden: ["h"])

        let plan = NotchOverflowPlanner().plan(
            desiredOrder: desired,
            itemWidths: ["a": 24, "b": 24],
            hideableUIDs: ["a", "b"],
            availableWidth: 80
        )

        XCTAssertEqual(plan.overflowUIDs, [])
        XCTAssertEqual(plan.order, desired)
    }
}
