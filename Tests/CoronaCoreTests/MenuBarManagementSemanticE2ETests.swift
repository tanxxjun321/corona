import CoreGraphics
import CoronaCore
import XCTest

final class MenuBarManagementSemanticE2ETests: XCTestCase {
    func testShowHiddenDisplaysHiddenItemsButNeverAlwaysHiddenItems() {
        let shown = item("shown")
        let hidden = item("hidden")
        let alwaysHidden = item("alwaysHidden")
        let cache = ItemCache(
            displayID: nil,
            visibleItems: [shown],
            hiddenItems: [hidden],
            alwaysHiddenItems: [alwaysHidden]
        )
        let savedOrder = SectionOrder(
            visible: [shown.uid],
            hidden: [hidden.uid],
            alwaysHidden: [alwaysHidden.uid]
        )

        let displayed = MenuBarHiddenPresentationPolicy()
            .displayedHiddenUIDs(savedOrder: savedOrder, cache: cache)

        XCTAssertEqual(displayed, [hidden.uid])
        XCTAssertFalse(displayed.contains(alwaysHidden.uid))
    }

    func testHiddenToShownIntentDoesNotShowEveryHiddenItem() {
        let shown = item("shown")
        let moved = item("moved")
        let stillHidden = item("stillHidden")
        let before = SemanticSession(
            savedOrder: SectionOrder(
                visible: [shown.uid],
                hidden: [moved.uid, stillHidden.uid],
                alwaysHidden: []
            ),
            actualCache: ItemCache(
                displayID: nil,
                visibleItems: [shown],
                hiddenItems: [moved, stillHidden],
                alwaysHiddenItems: []
            ),
            hiddenSectionVisible: false,
            alwaysHiddenSectionVisible: false
        )

        let after = before.movingIntentOnly(uid: moved.uid, to: .visible)

        XCTAssertEqual(after.savedOrder.visible, [shown.uid, moved.uid])
        XCTAssertEqual(after.savedOrder.hidden, [stillHidden.uid])
        XCTAssertEqual(after.actualSection(of: moved.uid), .hidden)
        XCTAssertEqual(after.actualSection(of: stillHidden.uid), .hidden)
        XCTAssertFalse(after.hiddenSectionVisible)
        XCTAssertTrue(after.hasMismatch(uid: moved.uid))
    }

    func testHiddenToShownApplyPlansOnlyTheMovedItem() {
        let shown = item("shown", windowID: 10)
        let moved = item("moved", windowID: 20)
        let stillHidden = item("stillHidden", windowID: 30)
        let visibleBoundary = item("visibleBoundary", windowID: 90)
        let cache = ItemCache(
            displayID: nil,
            visibleItems: [shown],
            hiddenItems: [moved, stillHidden],
            alwaysHiddenItems: []
        )
        let preference = LayoutPreference(
            savedOrder: SectionOrder(
                visible: [shown.uid, moved.uid],
                hidden: [stillHidden.uid],
                alwaysHidden: []
            )
        )

        let step = LayoutApplicationPlanner().nextStep(
            cache: cache,
            preference: preference,
            sectionBoundaries: [.visible: visibleBoundary]
        )

        XCTAssertEqual(
            step,
            .move(
                ResolvedLayoutMove(
                    plannedMove: LayoutMove(itemUID: moved.uid, target: .sectionBoundary(.visible)),
                    item: moved,
                    destination: .rightOfItem(visibleBoundary)
                )
            )
        )
    }

    func testShownToHiddenIntentDoesNotHidePhysicalShownItemByCollapsingSection() {
        let moved = item("moved")
        let hidden = item("hidden")
        let before = SemanticSession(
            savedOrder: SectionOrder(
                visible: [moved.uid],
                hidden: [hidden.uid],
                alwaysHidden: []
            ),
            actualCache: ItemCache(
                displayID: nil,
                visibleItems: [moved],
                hiddenItems: [hidden],
                alwaysHiddenItems: []
            ),
            hiddenSectionVisible: false,
            alwaysHiddenSectionVisible: false
        )

        let after = before.movingIntentOnly(uid: moved.uid, to: .hidden)

        XCTAssertEqual(after.savedOrder.visible, [])
        XCTAssertEqual(after.savedOrder.hidden, [hidden.uid, moved.uid])
        XCTAssertEqual(after.actualSection(of: moved.uid), .visible)
        XCTAssertFalse(after.hiddenSectionVisible)
        XCTAssertTrue(after.hasMismatch(uid: moved.uid))
    }

    func testShownToAlwaysHiddenApplyDoesNotExposeOrdinaryHiddenItems() {
        let moved = item("moved", windowID: 10)
        let ordinaryHidden = item("ordinaryHidden", windowID: 20)
        let hiddenBoundary = item("hiddenBoundary", windowID: 80)
        let alwaysHiddenBoundary = item("alwaysHiddenBoundary", windowID: 70)
        let cache = ItemCache(
            displayID: nil,
            visibleItems: [moved],
            hiddenItems: [ordinaryHidden],
            alwaysHiddenItems: []
        )
        let preference = LayoutPreference(
            savedOrder: SectionOrder(
                visible: [],
                hidden: [ordinaryHidden.uid],
                alwaysHidden: [moved.uid]
            )
        )

        let step = LayoutApplicationPlanner().nextStep(
            cache: cache,
            preference: preference,
            sectionBoundaries: [
                .hidden: hiddenBoundary,
                .alwaysHidden: alwaysHiddenBoundary,
            ]
        )

        XCTAssertEqual(
            step,
            .move(
                ResolvedLayoutMove(
                    plannedMove: LayoutMove(itemUID: moved.uid, target: .sectionBoundary(.alwaysHidden)),
                    item: moved,
                    destination: .leftOfItem(alwaysHiddenBoundary)
                )
            )
        )
        XCTAssertEqual(
            MenuBarHiddenPresentationPolicy().displayedHiddenUIDs(savedOrder: preference.savedOrder, cache: cache),
            [ordinaryHidden.uid]
        )
    }

    func testOrganizeRefreshUsesSavedIntentEvenWhenPhysicalSectionDiffers() {
        let itemA = item("A")
        let cache = ItemCache(
            displayID: nil,
            visibleItems: [itemA],
            hiddenItems: [],
            alwaysHiddenItems: []
        )
        let savedOrder = SectionOrder(visible: [], hidden: [itemA.uid], alwaysHidden: [])

        let displayedOrder = LayoutPlanner().mergedOrder(
            cache: cache,
            preference: LayoutPreference(savedOrder: savedOrder)
        )

        XCTAssertEqual(displayedOrder.hidden, [itemA.uid])
        XCTAssertEqual(SectionOrder(cache: cache).visible, [itemA.uid])
    }

    func testClickingCoronaShowHiddenDoesNotMutateSavedOrderOrActualSections() {
        let shown = item("shown")
        let hidden = item("hidden")
        let before = SemanticSession(
            savedOrder: SectionOrder(visible: [shown.uid], hidden: [hidden.uid], alwaysHidden: []),
            actualCache: ItemCache(displayID: nil, visibleItems: [shown], hiddenItems: [hidden], alwaysHiddenItems: []),
            hiddenSectionVisible: false,
            alwaysHiddenSectionVisible: false
        )

        let after = before.showHiddenSection()

        XCTAssertEqual(after.savedOrder, before.savedOrder)
        XCTAssertEqual(SectionOrder(cache: after.actualCache), SectionOrder(cache: before.actualCache))
        XCTAssertTrue(after.hiddenSectionVisible)
        XCTAssertFalse(after.alwaysHiddenSectionVisible)
    }

    func testAlwaysHiddenIsOnlyVisibleThroughAlwaysHiddenIntent() {
        let hidden = item("hidden")
        let alwaysHidden = item("alwaysHidden")
        let cache = ItemCache(
            displayID: nil,
            visibleItems: [],
            hiddenItems: [hidden],
            alwaysHiddenItems: [alwaysHidden]
        )
        let savedOrder = SectionOrder(visible: [], hidden: [hidden.uid], alwaysHidden: [alwaysHidden.uid])

        XCTAssertEqual(
            MenuBarHiddenPresentationPolicy().displayedHiddenUIDs(savedOrder: savedOrder, cache: cache),
            [hidden.uid]
        )
        XCTAssertEqual(savedOrder.alwaysHidden, [alwaysHidden.uid])
    }

    func testApplySuccessRequiresActualSectionsToMatchSavedIntent() {
        let shown = item("shown")
        let intendedHidden = item("intendedHidden")
        let session = SemanticSession(
            savedOrder: SectionOrder(
                visible: [shown.uid],
                hidden: [intendedHidden.uid],
                alwaysHidden: []
            ),
            actualCache: ItemCache(
                displayID: nil,
                visibleItems: [shown, intendedHidden],
                hiddenItems: [],
                alwaysHiddenItems: []
            ),
            hiddenSectionVisible: false,
            alwaysHiddenSectionVisible: false
        )

        XCTAssertFalse(session.savedIntentMatchesActualSections)
        XCTAssertTrue(session.hasMismatch(uid: intendedHidden.uid))
    }

    private func item(_ title: String, windowID: UInt32? = nil) -> MenuBarItem {
        let id = windowID ?? UInt32(abs(title.hashValue % 10_000) + 1)
        return MenuBarItem(
            tag: MenuBarItemTag(namespace: "test.app", title: title),
            windowID: id,
            ownerPID: 10,
            sourcePID: 10,
            bounds: CGRect(x: CGFloat(id), y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true,
            isMovable: true,
            canBeHidden: true
        )
    }
}

private struct SemanticSession {
    var savedOrder: SectionOrder
    var actualCache: ItemCache
    var hiddenSectionVisible: Bool
    var alwaysHiddenSectionVisible: Bool

    func movingIntentOnly(uid: String, to section: MenuBarSection) -> SemanticSession {
        var copy = self
        for currentSection in MenuBarSection.allCases {
            copy.savedOrder[currentSection].removeAll { $0 == uid }
        }
        copy.savedOrder[section].append(uid)
        return copy
    }

    func showHiddenSection() -> SemanticSession {
        var copy = self
        copy.hiddenSectionVisible = true
        return copy
    }

    func actualSection(of uid: String) -> MenuBarSection? {
        SectionOrder(cache: actualCache).section(containing: uid)
    }

    func hasMismatch(uid: String) -> Bool {
        savedOrder.section(containing: uid) != actualSection(of: uid)
    }

    var savedIntentMatchesActualSections: Bool {
        let actual = SectionOrder(cache: actualCache)
        for section in MenuBarSection.allCases {
            for uid in savedOrder[section] where actual.section(containing: uid) != section {
                return false
            }
        }
        return true
    }
}

private extension MenuBarItem {
    var uid: String { tag.stableIdentifier }
}
