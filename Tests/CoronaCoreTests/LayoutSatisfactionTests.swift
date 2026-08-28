import CoronaCore
import XCTest

final class LayoutSatisfactionTests: XCTestCase {
    private let evaluator = LayoutSatisfactionEvaluator()
    private let allManageable: (MenuBarItem) -> Bool = { $0.isMovable && $0.canBeHidden }

    func testSatisfiedWhenSectionsAndOrderMatch() {
        let a = makeItem(windowID: 1, title: "A")
        let b = makeItem(windowID: 2, title: "B")
        let c = makeItem(windowID: 3, title: "C")
        let cache = ItemCache(displayID: nil, visibleItems: [a, b], hiddenItems: [c], alwaysHiddenItems: [])
        let savedOrder = SectionOrder(visible: ["app:A", "app:B"], hidden: ["app:C"])

        let report = evaluator.report(cache: cache, savedOrder: savedOrder, isOrderManageable: allManageable)

        XCTAssertTrue(report.isSatisfied)
        XCTAssertEqual(report, LayoutSatisfactionReport(sectionMismatches: [], orderMismatches: []))
    }

    func testFailsWhenSectionsMatchButVisibleOrderDiffers() {
        let a = makeItem(windowID: 1, title: "A")
        let b = makeItem(windowID: 2, title: "B")
        let cache = ItemCache(displayID: nil, visibleItems: [b, a], hiddenItems: [], alwaysHiddenItems: [])
        let savedOrder = SectionOrder(visible: ["app:A", "app:B"])

        let report = evaluator.report(cache: cache, savedOrder: savedOrder, isOrderManageable: allManageable)

        XCTAssertFalse(report.isSatisfied)
        XCTAssertEqual(report.sectionMismatches, [])
        XCTAssertEqual(
            report.orderMismatches,
            [LayoutOrderMismatch(section: .visible, expectedUIDs: ["app:A", "app:B"], actualUIDs: ["app:B", "app:A"])]
        )
    }

    func testFailsWhenHiddenOrderDiffers() {
        let a = makeItem(windowID: 1, title: "A")
        let b = makeItem(windowID: 2, title: "B")
        let cache = ItemCache(displayID: nil, visibleItems: [], hiddenItems: [b, a], alwaysHiddenItems: [])
        let savedOrder = SectionOrder(hidden: ["app:A", "app:B"])

        let report = evaluator.report(cache: cache, savedOrder: savedOrder, isOrderManageable: allManageable)

        XCTAssertFalse(report.isSatisfied)
        XCTAssertEqual(
            report.orderMismatches,
            [LayoutOrderMismatch(section: .hidden, expectedUIDs: ["app:A", "app:B"], actualUIDs: ["app:B", "app:A"])]
        )
    }

    func testUnmanageableItemsInterleavedPhysicallyDoNotAffectComparison() {
        let a = makeItem(windowID: 1, title: "A")
        let b = makeItem(windowID: 2, title: "B")
        let controlCenter = makeItem(windowID: 3, namespace: "control", title: "Center", isMovable: false, canBeHidden: false)
        let cache = ItemCache(displayID: nil, visibleItems: [a, controlCenter, b], hiddenItems: [], alwaysHiddenItems: [])
        let savedOrder = SectionOrder(visible: ["app:A", "app:B"])

        let report = evaluator.report(cache: cache, savedOrder: savedOrder, isOrderManageable: allManageable)

        XCTAssertTrue(report.isSatisfied)
    }

    func testUnsavedNewItemInterleavedPhysicallyDoesNotAffectComparison() {
        let a = makeItem(windowID: 1, title: "A")
        let b = makeItem(windowID: 2, title: "B")
        let newItem = makeItem(windowID: 3, title: "New")
        let cache = ItemCache(displayID: nil, visibleItems: [a, newItem, b], hiddenItems: [], alwaysHiddenItems: [])
        let savedOrder = SectionOrder(visible: ["app:A", "app:B"])

        let report = evaluator.report(cache: cache, savedOrder: savedOrder, isOrderManageable: allManageable)

        XCTAssertTrue(report.isSatisfied)
    }

    func testCoronaControlItemExcludedByPredicateDoesNotAffectComparison() {
        let a = makeItem(windowID: 1, title: "A")
        let b = makeItem(windowID: 2, title: "B")
        let coronaControl = makeItem(windowID: 3, namespace: "com.ltz.corona", title: "control")
        let cache = ItemCache(displayID: nil, visibleItems: [a, coronaControl, b], hiddenItems: [], alwaysHiddenItems: [])
        // Even if a stale Corona control uid lingers in the saved order, the
        // caller's manageability predicate keeps it out of the order comparison.
        let savedOrder = SectionOrder(visible: ["app:A", "com.ltz.corona:control", "app:B"])
        let excludingCorona: (MenuBarItem) -> Bool = {
            $0.isMovable && $0.canBeHidden && !$0.tag.stableIdentifier.contains("corona")
        }

        let report = evaluator.report(cache: cache, savedOrder: savedOrder, isOrderManageable: excludingCorona)

        XCTAssertTrue(report.isSatisfied)
    }

    func testSavedItemExcludedByPredicateDoesNotAffectComparison() {
        let a = makeItem(windowID: 1, title: "A")
        let b = makeItem(windowID: 2, title: "B")
        let controlCenter = makeItem(windowID: 3, namespace: "control", title: "Center", isMovable: false, canBeHidden: false)
        let cache = ItemCache(displayID: nil, visibleItems: [a, controlCenter, b], hiddenItems: [], alwaysHiddenItems: [])
        let savedOrder = SectionOrder(visible: ["app:A", "control:Center", "app:B"])

        let report = evaluator.report(cache: cache, savedOrder: savedOrder, isOrderManageable: allManageable)

        XCTAssertTrue(report.isSatisfied)
    }

    func testSectionMismatchIsStillDetected() {
        let a = makeItem(windowID: 1, title: "A")
        let cache = ItemCache(displayID: nil, visibleItems: [a], hiddenItems: [], alwaysHiddenItems: [])
        let savedOrder = SectionOrder(hidden: ["app:A"])

        let report = evaluator.report(cache: cache, savedOrder: savedOrder, isOrderManageable: allManageable)

        XCTAssertFalse(report.isSatisfied)
        XCTAssertEqual(
            report.sectionMismatches,
            [LayoutSectionMismatch(uid: "app:A", expectedSection: .hidden, actualSection: .visible)]
        )
    }

    func testMovableItemThatCannotBeHiddenIsExpectedVisible() {
        let a = makeItem(windowID: 1, title: "A", canBeHidden: false)
        let cache = ItemCache(displayID: nil, visibleItems: [a], hiddenItems: [], alwaysHiddenItems: [])
        let savedOrder = SectionOrder(hidden: ["app:A"])

        let report = evaluator.report(cache: cache, savedOrder: savedOrder, isOrderManageable: allManageable)

        XCTAssertTrue(report.isSatisfied)
    }

    func testSavedItemMissingFromCacheIsSkipped() {
        let a = makeItem(windowID: 1, title: "A")
        let cache = ItemCache(displayID: nil, visibleItems: [a], hiddenItems: [], alwaysHiddenItems: [])
        let savedOrder = SectionOrder(visible: ["app:A"], hidden: ["app:Ghost"])

        let report = evaluator.report(cache: cache, savedOrder: savedOrder, isOrderManageable: allManageable)

        XCTAssertTrue(report.isSatisfied)
    }

    private func makeItem(
        windowID: UInt32,
        namespace: String = "app",
        title: String,
        isMovable: Bool = true,
        canBeHidden: Bool = true
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: namespace, title: title, volatileWindowID: windowID),
            windowID: windowID,
            ownerPID: 1,
            sourcePID: 1,
            bounds: CGRect(x: Int(windowID) * 10, y: 0, width: 20, height: 22),
            title: title,
            isOnScreen: true,
            isMovable: isMovable,
            canBeHidden: canBeHidden
        )
    }
}

final class LayoutApplyStepBudgetTests: XCTestCase {
    func testFloorAppliesToSmallLayouts() {
        XCTAssertEqual(LayoutApplyStepBudget.stepLimit(manageableItemCount: 0), 20)
        XCTAssertEqual(LayoutApplyStepBudget.stepLimit(manageableItemCount: 3), 20)
        XCTAssertEqual(LayoutApplyStepBudget.stepLimit(manageableItemCount: 5), 20)
    }

    func testBudgetScalesWithManageableItemCount() {
        XCTAssertEqual(LayoutApplyStepBudget.stepLimit(manageableItemCount: 6), 24)
        XCTAssertEqual(LayoutApplyStepBudget.stepLimit(manageableItemCount: 10), 40)
    }

    func testNegativeCountFallsBackToFloor() {
        XCTAssertEqual(LayoutApplyStepBudget.stepLimit(manageableItemCount: -2), 20)
    }
}
