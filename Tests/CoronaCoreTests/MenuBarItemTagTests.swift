import CoronaCore
import XCTest

final class MenuBarItemTagTests: XCTestCase {
    func testStableIdentifierDoesNotIncludeVolatileWindowID() {
        let first = MenuBarItemTag(
            namespace: "com.example.app",
            title: "Example",
            volatileWindowID: 100
        )
        let second = MenuBarItemTag(
            namespace: "com.example.app",
            title: "Example",
            volatileWindowID: 200
        )

        XCTAssertEqual(first.stableIdentifier, second.stableIdentifier)
        XCTAssertEqual(first.stableIdentifier, "com.example.app:Example")
    }

    func testStableIdentifierIncludesInstanceIndexWhenPresent() {
        let tag = MenuBarItemTag(
            namespace: "com.example.app",
            title: "Example",
            instanceIndex: 2,
            volatileWindowID: 100
        )

        XCTAssertEqual(tag.stableIdentifier, "com.example.app:Example:2")
    }
}
