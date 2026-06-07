import CoronaCore
import XCTest

final class LayoutPlannerTests: XCTestCase {
    func testDefaultPreferenceAppendsNewItemsToVisible() {
        let cache = ItemCache(
            displayID: nil,
            visibleItems: [makeItem(windowID: 1, namespace: "app", title: "New", sourcePID: 10)],
            hiddenItems: [],
            alwaysHiddenItems: []
        )

        let order = LayoutPlanner().mergedOrder(cache: cache, preference: LayoutPreference())

        XCTAssertEqual(order.visible, ["app:New"])
        XCTAssertEqual(order.hidden, [])
    }

    func testMergedOrderAppendsNewItemsToConfiguredSection() {
        let cache = ItemCache(
            displayID: nil,
            visibleItems: [],
            hiddenItems: [makeItem(windowID: 1, namespace: "app", title: "New", sourcePID: 10)],
            alwaysHiddenItems: []
        )
        let preference = LayoutPreference(
            savedOrder: SectionOrder(hidden: ["app:Old"]),
            newItemsSection: .hidden,
            newItemsPlacement: .append,
            alwaysHiddenEnabled: false
        )

        let order = LayoutPlanner().mergedOrder(cache: cache, preference: preference)

        XCTAssertEqual(order.hidden, ["app:Old", "app:New"])
    }

    func testAlwaysHiddenNewItemsFallbackToHiddenWhenDisabled() {
        let cache = ItemCache(
            displayID: nil,
            visibleItems: [],
            hiddenItems: [],
            alwaysHiddenItems: [makeItem(windowID: 1, namespace: "app", title: "New", sourcePID: 10)]
        )
        let preference = LayoutPreference(
            newItemsSection: .alwaysHidden,
            alwaysHiddenEnabled: false
        )

        let order = LayoutPlanner().mergedOrder(cache: cache, preference: preference)

        XCTAssertEqual(order.hidden, ["app:New"])
        XCTAssertEqual(order.alwaysHidden, [])
    }

    func testNextMoveWithinSectionUsesPreviousDesiredNeighbor() {
        let current = SectionOrder(hidden: ["a", "b", "c"])
        let desired = SectionOrder(hidden: ["a", "c", "b"])

        let move = LayoutPlanner().nextMove(currentOrder: current, desiredOrder: desired)

        XCTAssertEqual(move, LayoutMove(itemUID: "c", target: .rightOfUID("a")))
    }

    func testNextMoveToSectionBoundaryForFirstItem() {
        let current = SectionOrder(hidden: ["a", "b", "c"])
        let desired = SectionOrder(hidden: ["c", "a", "b"])

        let move = LayoutPlanner().nextMove(currentOrder: current, desiredOrder: desired)

        XCTAssertEqual(move, LayoutMove(itemUID: "c", target: .sectionBoundary(.hidden)))
    }

    func testNextCrossSectionMoveUsesTargetSectionBoundary() {
        let current = SectionOrder(visible: ["a"], hidden: ["b"])
        let desired = SectionOrder(visible: [], hidden: ["a", "b"])

        let move = LayoutPlanner().nextMove(currentOrder: current, desiredOrder: desired)

        XCTAssertEqual(move, LayoutMove(itemUID: "a", target: .sectionBoundary(.hidden)))
    }
}
