import CoronaCore
import XCTest

final class PermissionSnapshotTests: XCTestCase {
    func testMissingAccessibilityDisablesCoreFeatures() {
        let snapshot = PermissionSnapshot(
            accessibility: .missing,
            screenRecording: .granted
        )

        XCTAssertEqual(snapshot.capabilityStatus, .missing)
        XCTAssertFalse(snapshot.canRunCoreFeatures)
        XCTAssertTrue(snapshot.canShowPixelPreviews)
    }

    func testAccessibilityWithoutScreenRecordingEnablesRequiredFeatures() {
        let snapshot = PermissionSnapshot(
            accessibility: .granted,
            screenRecording: .missing
        )

        XCTAssertEqual(snapshot.capabilityStatus, .hasRequired)
        XCTAssertTrue(snapshot.canRunCoreFeatures)
        XCTAssertFalse(snapshot.canShowPixelPreviews)
    }

    func testAllPermissionsEnableAllCapabilities() {
        let snapshot = PermissionSnapshot(
            accessibility: .granted,
            screenRecording: .granted
        )

        XCTAssertEqual(snapshot.capabilityStatus, .hasAll)
        XCTAssertTrue(snapshot.canRunCoreFeatures)
        XCTAssertTrue(snapshot.canShowPixelPreviews)
    }
}
