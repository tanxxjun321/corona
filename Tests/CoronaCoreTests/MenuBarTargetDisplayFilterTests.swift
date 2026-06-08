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

    func testKeepsBoundaryItemWithCenterAffinityForTargetDisplay() {
        let laptop = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let external = CGRect(x: 1728, y: 0, width: 1920, height: 1080)
        let item = makeItem(
            windowID: 1,
            bounds: CGRect(x: 1708, y: 0, width: 30, height: 24)
        )

        let filtered = MenuBarTargetDisplayFilter(
            targetDisplayFrame: laptop,
            otherDisplayFrames: [external]
        ).itemsOnTargetDisplay([item])

        XCTAssertEqual(filtered.map(\.windowID), [1])
    }

    func testRejectsItemBelowTargetMenuBarBand() {
        let laptop = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let item = makeItem(
            windowID: 1,
            bounds: CGRect(x: 565, y: 81, width: 137, height: 19)
        )

        let filtered = MenuBarTargetDisplayFilter(
            targetDisplayFrame: laptop,
            otherDisplayFrames: []
        ).itemsOnTargetDisplay([item])

        XCTAssertTrue(filtered.isEmpty)
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
