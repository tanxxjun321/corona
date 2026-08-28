import CoronaCore
import XCTest

final class StartupLayoutRestorePolicyTests: XCTestCase {
    func testEmptySavedOrderWithoutPendingRelocationsSkipsRestore() {
        XCTAssertFalse(StartupLayoutRestorePolicy.shouldRestore(
            savedOrder: SectionOrder(),
            pendingRelocations: [:]
        ))
    }

    func testAllVisibleSavedOrderTriggersRestore() {
        XCTAssertTrue(StartupLayoutRestorePolicy.shouldRestore(
            savedOrder: SectionOrder(visible: ["app:A", "app:B"]),
            pendingRelocations: [:]
        ))
    }

    func testHiddenOnlySavedOrderTriggersRestore() {
        XCTAssertTrue(StartupLayoutRestorePolicy.shouldRestore(
            savedOrder: SectionOrder(hidden: ["app:A"]),
            pendingRelocations: [:]
        ))
    }

    func testPendingRelocationAloneTriggersRestore() {
        XCTAssertTrue(StartupLayoutRestorePolicy.shouldRestore(
            savedOrder: SectionOrder(),
            pendingRelocations: ["app:A": .section(.hidden)]
        ))
    }
}
