import CoronaCore
import XCTest

final class LayoutReconciliationControllerTests: XCTestCase {
    private let satisfied = LayoutSatisfactionReport(sectionMismatches: [], orderMismatches: [])

    private var orderDeviating: LayoutSatisfactionReport {
        LayoutSatisfactionReport(
            sectionMismatches: [],
            orderMismatches: [LayoutOrderMismatch(
                section: .visible,
                expectedUIDs: ["app:A", "app:B"],
                actualUIDs: ["app:B", "app:A"]
            )]
        )
    }

    private var sectionDeviating: LayoutSatisfactionReport {
        LayoutSatisfactionReport(
            sectionMismatches: [LayoutSectionMismatch(
                uid: "app:A",
                expectedSection: .hidden,
                actualSection: .visible
            )],
            orderMismatches: []
        )
    }

    func testDefaultsAreFiveSecondCooldownAndTwoPointFiveSecondDebounce() {
        let controller = LayoutReconciliationController()
        XCTAssertEqual(controller.cooldown, 5)
        XCTAssertEqual(controller.debounce, 2.5)
        XCTAssertNil(controller.cooldownEndsAt)
        XCTAssertNil(controller.deviationSince)
        XCTAssertFalse(controller.requestEmittedForCurrentEpisode)
    }

    func testSectionAndOrderMismatchesBothCountAsDeviation() {
        var controller = LayoutReconciliationController()
        XCTAssertEqual(controller.tick(at: 0, report: orderDeviating), .none)
        XCTAssertNotNil(controller.deviationSince)

        controller.ownApplyStarted()
        XCTAssertEqual(controller.tick(at: 0, report: sectionDeviating), .none)
        XCTAssertNotNil(controller.deviationSince)
    }

    func testTransientDeviationResolvingWithinDebounceEmitsNothing() {
        var controller = LayoutReconciliationController()
        XCTAssertEqual(controller.tick(at: 0, report: orderDeviating), .none)
        XCTAssertEqual(controller.tick(at: 1, report: orderDeviating), .none)
        XCTAssertEqual(controller.tick(at: 2, report: satisfied), .none)

        // The episode ended; a later deviation starts from zero.
        XCTAssertNil(controller.deviationSince)
        XCTAssertEqual(controller.tick(at: 4, report: orderDeviating), .none)
        XCTAssertEqual(controller.tick(at: 6, report: orderDeviating), .none)
        XCTAssertEqual(controller.tick(at: 6.5, report: orderDeviating), .requestApply)
    }

    func testSustainedDeviationEmitsExactlyOneRequestPerEpisode() {
        var controller = LayoutReconciliationController()
        XCTAssertEqual(controller.tick(at: 0, report: orderDeviating), .none)
        XCTAssertEqual(controller.tick(at: 2.5, report: orderDeviating), .requestApply)
        XCTAssertTrue(controller.requestEmittedForCurrentEpisode)

        // Same episode: no repeats no matter how long it persists.
        XCTAssertEqual(controller.tick(at: 3, report: orderDeviating), .none)
        XCTAssertEqual(controller.tick(at: 10, report: orderDeviating), .none)
    }

    func testDeviationAfterEpisodeEndsIsANewEpisodeWithFreshRequest() {
        var controller = LayoutReconciliationController()
        XCTAssertEqual(controller.tick(at: 0, report: orderDeviating), .none)
        XCTAssertEqual(controller.tick(at: 2.5, report: orderDeviating), .requestApply)
        XCTAssertEqual(controller.tick(at: 3, report: satisfied), .none)

        XCTAssertEqual(controller.tick(at: 5, report: orderDeviating), .none)
        XCTAssertEqual(controller.tick(at: 6, report: orderDeviating), .none)
        XCTAssertEqual(controller.tick(at: 7.5, report: orderDeviating), .requestApply)
    }

    func testCooldownSuppressesDetectionAndDoesNotBankDebounceTime() {
        var controller = LayoutReconciliationController()
        controller.ownApplyFinished(at: 0)

        // Deviation throughout the whole window: no detection, no timing.
        XCTAssertEqual(controller.tick(at: 1, report: orderDeviating), .none)
        XCTAssertEqual(controller.tick(at: 4.9, report: orderDeviating), .none)
        XCTAssertNil(controller.deviationSince)

        // After the window the deviation must persist for a full debounce.
        XCTAssertEqual(controller.tick(at: 5, report: orderDeviating), .none)
        XCTAssertEqual(controller.deviationSince, 5)
        XCTAssertEqual(controller.tick(at: 7.4, report: orderDeviating), .none)
        XCTAssertEqual(controller.tick(at: 7.5, report: orderDeviating), .requestApply)
    }

    func testCooldownBoundaryTickAtExactEndResumesDetection() {
        var controller = LayoutReconciliationController(cooldown: 5, debounce: 2.5)
        controller.ownApplyFinished(at: 10)
        XCTAssertTrue(controller.isInCooldown(at: 14.9))
        XCTAssertFalse(controller.isInCooldown(at: 15))

        XCTAssertEqual(controller.tick(at: 15, report: orderDeviating), .none)
        XCTAssertEqual(controller.deviationSince, 15)
    }

    func testDebounceBoundaryExactDurationRequestsShorterDoesNot() {
        var controller = LayoutReconciliationController(debounce: 2.5)
        XCTAssertEqual(controller.tick(at: 0, report: orderDeviating), .none)
        XCTAssertEqual(controller.tick(at: 2.49, report: orderDeviating), .none)
        XCTAssertEqual(controller.tick(at: 2.5, report: orderDeviating), .requestApply)
    }

    func testOwnApplyStartedResetsPendingDeviationTiming() {
        var controller = LayoutReconciliationController()
        XCTAssertEqual(controller.tick(at: 0, report: orderDeviating), .none)
        XCTAssertEqual(controller.tick(at: 2, report: orderDeviating), .none)

        controller.ownApplyStarted()
        XCTAssertNil(controller.deviationSince)
        XCTAssertFalse(controller.requestEmittedForCurrentEpisode)

        // The pre-own-apply 2 seconds no longer count.
        XCTAssertEqual(controller.tick(at: 2.5, report: orderDeviating), .none)
        XCTAssertEqual(controller.deviationSince, 2.5)
        XCTAssertEqual(controller.tick(at: 5, report: orderDeviating), .requestApply)
    }

    func testOwnApplyStartedAfterEmissionAllowsNewEpisodeAfterResolution() {
        var controller = LayoutReconciliationController()
        XCTAssertEqual(controller.tick(at: 0, report: orderDeviating), .none)
        XCTAssertEqual(controller.tick(at: 2.5, report: orderDeviating), .requestApply)

        controller.ownApplyStarted()
        controller.ownApplyFinished(at: 3)

        // Cooldown covers the physical churn of the own apply.
        XCTAssertEqual(controller.tick(at: 4, report: orderDeviating), .none)
        // Still deviating after cooldown: full debounce, then one request.
        XCTAssertEqual(controller.tick(at: 8, report: orderDeviating), .none)
        XCTAssertEqual(controller.tick(at: 10.5, report: orderDeviating), .requestApply)
    }

    func testCacheBasedTickEvaluatesWithSatisfactionEvaluator() {
        let allManageable: (MenuBarItem) -> Bool = { $0.isMovable && $0.canBeHidden }
        let a = makeItem(windowID: 1, title: "A")
        let b = makeItem(windowID: 2, title: "B")
        let savedOrder = SectionOrder(visible: ["app:A", "app:B"])

        var controller = LayoutReconciliationController()

        let satisfiedCache = ItemCache(
            displayID: nil,
            visibleItems: [a, b],
            hiddenItems: [],
            alwaysHiddenItems: []
        )
        XCTAssertEqual(
            controller.tick(at: 0, cache: satisfiedCache, savedOrder: savedOrder, isOrderManageable: allManageable),
            .none
        )
        XCTAssertNil(controller.deviationSince)

        let deviatingCache = ItemCache(
            displayID: nil,
            visibleItems: [b, a],
            hiddenItems: [],
            alwaysHiddenItems: []
        )
        XCTAssertEqual(
            controller.tick(at: 1, cache: deviatingCache, savedOrder: savedOrder, isOrderManageable: allManageable),
            .none
        )
        XCTAssertEqual(
            controller.tick(at: 3.5, cache: deviatingCache, savedOrder: savedOrder, isOrderManageable: allManageable),
            .requestApply
        )
    }

    private func makeItem(windowID: UInt32, title: String) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: "app", title: title, volatileWindowID: windowID),
            windowID: windowID,
            ownerPID: 1,
            sourcePID: 1,
            bounds: CGRect(x: Int(windowID) * 10, y: 0, width: 20, height: 22),
            title: title,
            isOnScreen: true,
            isMovable: true,
            canBeHidden: true
        )
    }
}
