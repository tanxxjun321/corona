import CoronaCore
import XCTest

final class LayoutApplicationPlannerTests: XCTestCase {
    func testNoSavedOrderLeavesCurrentLayoutSatisfied() {
        let item = makeItem(windowID: 1, namespace: "app", title: "A", sourcePID: 10)
        let cache = ItemCache(displayID: nil, visibleItems: [item], hiddenItems: [], alwaysHiddenItems: [])

        let step = LayoutApplicationPlanner().nextStep(
            cache: cache,
            preference: LayoutPreference(),
            sectionBoundaries: [:]
        )

        XCTAssertEqual(step, .satisfied(SectionOrder(cache: cache)))
    }

    func testResolvesCrossSectionMoveToBoundary() {
        let item = makeItem(windowID: 1, namespace: "app", title: "A", sourcePID: 10)
        let boundary = makeItem(windowID: 99, namespace: "control", title: "hidden", sourcePID: 10)
        let cache = ItemCache(displayID: nil, visibleItems: [item], hiddenItems: [], alwaysHiddenItems: [])
        let preference = LayoutPreference(savedOrder: SectionOrder(hidden: ["app:A"]))

        let step = LayoutApplicationPlanner().nextStep(
            cache: cache,
            preference: preference,
            sectionBoundaries: [.hidden: boundary]
        )

        XCTAssertEqual(
            step,
            .move(
                ResolvedLayoutMove(
                    plannedMove: LayoutMove(itemUID: "app:A", target: .sectionBoundary(.hidden)),
                    item: item,
                    destination: .leftOfItem(boundary)
                )
            )
        )
    }

    func testWaitsForMissingSectionBoundary() {
        let item = makeItem(windowID: 1, namespace: "app", title: "A", sourcePID: 10)
        let cache = ItemCache(displayID: nil, visibleItems: [item], hiddenItems: [], alwaysHiddenItems: [])
        let preference = LayoutPreference(savedOrder: SectionOrder(hidden: ["app:A"]))

        let step = LayoutApplicationPlanner().nextStep(
            cache: cache,
            preference: preference,
            sectionBoundaries: [:]
        )

        XCTAssertEqual(step, .waitingForDestination(.sectionBoundary(.hidden)))
    }

    func testWaitsForMissingSavedItem() {
        let cache = ItemCache(displayID: nil, visibleItems: [], hiddenItems: [], alwaysHiddenItems: [])
        let preference = LayoutPreference(savedOrder: SectionOrder(hidden: ["app:A"]))

        let step = LayoutApplicationPlanner().nextStep(
            cache: cache,
            preference: preference,
            sectionBoundaries: [:]
        )

        XCTAssertEqual(step, .waitingForItem("app:A"))
    }
}
