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

    func testRestoresSavedVisibleItemBeforeReorderingVisibleItems() {
        let a = makeItem(windowID: 1, namespace: "app", title: "A", sourcePID: 10)
        let b = makeItem(windowID: 2, namespace: "app", title: "B", sourcePID: 10)
        let c = makeItem(windowID: 3, namespace: "app", title: "C", sourcePID: 10)
        let visibleBoundary = makeItem(windowID: 99, namespace: "control", title: "visible", sourcePID: 10)
        let cache = ItemCache(displayID: nil, visibleItems: [c, a], hiddenItems: [b], alwaysHiddenItems: [])
        let preference = LayoutPreference(savedOrder: SectionOrder(visible: ["app:A", "app:B", "app:C"]))

        let step = LayoutApplicationPlanner().nextStep(
            cache: cache,
            preference: preference,
            sectionBoundaries: [.visible: visibleBoundary]
        )

        XCTAssertEqual(
            step,
            .move(
                ResolvedLayoutMove(
                    plannedMove: LayoutMove(itemUID: "app:B", target: .sectionBoundary(.visible)),
                    item: b,
                    destination: .rightOfItem(visibleBoundary)
                )
            )
        )
    }

    func testUsesSavedVisibleOrderWhenPhysicalVisibleOrderDiffers() {
        let a = makeItem(windowID: 1, namespace: "app", title: "A", sourcePID: 10)
        let b = makeItem(windowID: 2, namespace: "app", title: "B", sourcePID: 10)
        let visibleBoundary = makeItem(windowID: 99, namespace: "control", title: "visible", sourcePID: 10)
        let cache = ItemCache(displayID: nil, visibleItems: [b, a], hiddenItems: [], alwaysHiddenItems: [])
        let preference = LayoutPreference(savedOrder: SectionOrder(visible: ["app:A", "app:B"]))

        let step = LayoutApplicationPlanner().nextStep(
            cache: cache,
            preference: preference,
            sectionBoundaries: [.visible: visibleBoundary]
        )

        XCTAssertEqual(
            step,
            .move(
                ResolvedLayoutMove(
                    plannedMove: LayoutMove(itemUID: "app:A", target: .sectionBoundary(.visible)),
                    item: a,
                    destination: .rightOfItem(visibleBoundary)
                )
            )
        )
    }

    func testUsesSavedHiddenOrderWhenPhysicalHiddenOrderDiffers() {
        let a = makeItem(windowID: 1, namespace: "app", title: "A", sourcePID: 10)
        let b = makeItem(windowID: 2, namespace: "app", title: "B", sourcePID: 10)
        let hiddenBoundary = makeItem(windowID: 99, namespace: "control", title: "hidden", sourcePID: 10)
        let cache = ItemCache(displayID: nil, visibleItems: [], hiddenItems: [b, a], alwaysHiddenItems: [])
        let preference = LayoutPreference(savedOrder: SectionOrder(hidden: ["app:A", "app:B"]))

        let step = LayoutApplicationPlanner().nextStep(
            cache: cache,
            preference: preference,
            sectionBoundaries: [.hidden: hiddenBoundary]
        )

        XCTAssertEqual(
            step,
            .move(
                ResolvedLayoutMove(
                    plannedMove: LayoutMove(itemUID: "app:A", target: .sectionBoundary(.hidden)),
                    item: a,
                    destination: .leftOfItem(hiddenBoundary)
                )
            )
        )
    }

    func testPreferredItemMoveRunsBeforeOtherPendingVisibleRestorations() {
        let neat = makeItem(windowID: 1, namespace: "app", title: "Neat", sourcePID: 10)
        let memory = makeItem(windowID: 2, namespace: "app", title: "Memory", sourcePID: 10)
        let cpu = makeItem(windowID: 3, namespace: "app", title: "CPU", sourcePID: 10)
        let network = makeItem(windowID: 4, namespace: "app", title: "Network", sourcePID: 10)
        let visibleBoundary = makeItem(windowID: 99, namespace: "control", title: "visible", sourcePID: 10)
        let cache = ItemCache(
            displayID: nil,
            visibleItems: [cpu, memory, network],
            hiddenItems: [neat],
            alwaysHiddenItems: []
        )
        let preference = LayoutPreference(
            savedOrder: SectionOrder(visible: [
                "app:Neat",
                "app:Memory",
                "app:CPU",
                "app:Network",
            ])
        )

        let step = LayoutApplicationPlanner().nextStep(
            cache: cache,
            preference: preference,
            sectionBoundaries: [.visible: visibleBoundary],
            preferredItemUID: "app:CPU"
        )

        XCTAssertEqual(
            step,
            .move(
                ResolvedLayoutMove(
                    plannedMove: LayoutMove(itemUID: "app:CPU", target: .rightOfUID("app:Memory")),
                    item: cpu,
                    destination: .rightOfItem(memory)
                )
            )
        )
    }
}
