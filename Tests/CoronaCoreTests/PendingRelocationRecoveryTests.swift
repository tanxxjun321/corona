import CoronaCore
import XCTest

final class PendingRelocationRecoveryTests: XCTestCase {
    func testSortedUIDsDeterministicOrder() {
        let pending: [String: PendingRelocation] = [
            "app:C": .section(.hidden),
            "app:A": .section(.visible),
            "app:B": .section(.alwaysHidden)
        ]

        XCTAssertEqual(PendingRelocationRecovery.sortedUIDs(pending), ["app:A", "app:B", "app:C"])
    }

    func testRecoveryOrderRestoresSavedPositionWithinSection() {
        let current = SectionOrder(visible: ["a", "b", "c"], hidden: ["x"])
        let saved = SectionOrder(visible: ["a", "x", "b", "c"])

        let order = PendingRelocationRecovery.recoveryOrder(
            uid: "x",
            targetSection: .visible,
            currentOrder: current,
            savedOrder: saved
        )

        XCTAssertEqual(order.visible, ["a", "x", "b", "c"])
        XCTAssertEqual(order.hidden, [])
    }

    func testRecoveryOrderRemovesUIDFromOtherSections() {
        let current = SectionOrder(visible: ["x", "a"], hidden: ["h"])
        let saved = SectionOrder(visible: ["a"], hidden: ["x", "h"])

        let order = PendingRelocationRecovery.recoveryOrder(
            uid: "x",
            targetSection: .hidden,
            currentOrder: current,
            savedOrder: saved
        )

        XCTAssertEqual(order.visible, ["a"])
        XCTAssertEqual(order.hidden, ["x", "h"])
    }

    func testRecoveryOrderAppendsUIDUnknownToSavedOrder() {
        let current = SectionOrder(visible: ["a", "b"])
        let saved = SectionOrder(visible: ["a", "b"])

        let order = PendingRelocationRecovery.recoveryOrder(
            uid: "new",
            targetSection: .visible,
            currentOrder: current,
            savedOrder: saved
        )

        XCTAssertEqual(order.visible, ["a", "b", "new"])
    }
}
