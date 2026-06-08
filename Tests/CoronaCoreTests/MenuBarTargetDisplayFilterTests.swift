import CoreGraphics
import CoronaCore
import XCTest

final class MenuBarTargetDisplayFilterTests: XCTestCase {
    func testRejectsItemInsideOtherDisplayFrame() {
        let laptop = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let external = CGRect(x: 1728, y: 0, width: 1920, height: 1080)
        let item = makeItem(
            windowID: 1,
            bounds: CGRect(x: 3000, y: 0, width: 24, height: 24)
        )

        let filtered = MenuBarTargetDisplayFilter(
            targetDisplayFrame: laptop,
            otherDisplayFrames: [external]
        ).itemsOnTargetDisplay([item])

        XCTAssertTrue(filtered.isEmpty)
    }

    func testKeepsOffscreenItemInTargetMenuBarBand() {
        let laptop = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let external = CGRect(x: 1728, y: 0, width: 1920, height: 1080)
        let item = makeItem(
            windowID: 1,
            bounds: CGRect(x: -10_000, y: 0, width: 24, height: 24)
        )

        let filtered = MenuBarTargetDisplayFilter(
            targetDisplayFrame: laptop,
            otherDisplayFrames: [external]
        ).itemsOnTargetDisplay([item])

        XCTAssertEqual(filtered.map(\.windowID), [1])
    }

    private func makeItem(windowID: UInt32, bounds: CGRect) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: "com.example.status", title: "Example", volatileWindowID: windowID),
            windowID: windowID,
            ownerPID: 42,
            sourcePID: 42,
            bounds: bounds,
            title: "Example",
            isOnScreen: true,
            isMovable: true,
            canBeHidden: true
        )
    }
}
