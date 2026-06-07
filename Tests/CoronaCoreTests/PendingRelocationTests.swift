import CoronaCore
import XCTest

final class PendingRelocationTests: XCTestCase {
    func testParsesPlainSection() {
        let relocation = PendingRelocation(rawValue: "hidden")

        XCTAssertEqual(relocation, .section(.hidden))
        XCTAssertEqual(relocation?.rawValue, "hidden")
        XCTAssertEqual(relocation?.targetSection, .hidden)
        XCTAssertEqual(relocation?.shouldAttemptRecovery(currentWindowID: 12), true)
    }

    func testParsesWaitForRelaunchSentinel() {
        let relocation = PendingRelocation(rawValue: "waitForRelaunch:42:alwaysHidden")

        XCTAssertEqual(relocation, .waitForRelaunch(windowID: 42, section: .alwaysHidden))
        XCTAssertEqual(relocation?.rawValue, "waitForRelaunch:42:alwaysHidden")
        XCTAssertEqual(relocation?.targetSection, .alwaysHidden)
    }

    func testWaitForRelaunchSkipsSameWindowIDAndRetriesNewWindowID() {
        let relocation = PendingRelocation.waitForRelaunch(windowID: 42, section: .hidden)

        XCTAssertFalse(relocation.shouldAttemptRecovery(currentWindowID: 42))
        XCTAssertTrue(relocation.shouldAttemptRecovery(currentWindowID: 43))
        XCTAssertTrue(relocation.shouldAttemptRecovery(currentWindowID: nil))
    }

    func testRejectsInvalidRawValue() {
        XCTAssertNil(PendingRelocation(rawValue: "waitForRelaunch:not-a-number:hidden"))
        XCTAssertNil(PendingRelocation(rawValue: "unknown"))
    }
}
