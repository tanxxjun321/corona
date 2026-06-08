import CoronaCore
import CoreGraphics
import XCTest

final class MenuBarWindowCandidateFilterTests: XCTestCase {
    func testAcceptsOffscreenStatusItemInMenuBarVerticalBand() {
        let filter = makeFilter()
        let candidate = MenuBarWindowCandidate(
            ownerPID: 42,
            ownerName: "Example",
            title: "Item-0",
            bounds: CGRect(x: -10_000, y: 0, width: 24, height: 24),
            layer: 25
        )

        XCTAssertTrue(filter.isMenuBarItemCandidate(candidate, displayFrames: [CGRect(x: 0, y: 0, width: 1728, height: 1117)]))
    }

    func testAcceptsStatusItemOnSecondaryDisplay() {
        let filter = makeFilter()
        let candidate = MenuBarWindowCandidate(
            ownerPID: 42,
            ownerName: "Example",
            title: "Item-0",
            bounds: CGRect(x: 2050, y: 0, width: 24, height: 24),
            layer: 25
        )

        XCTAssertTrue(
            filter.isMenuBarItemCandidate(
                candidate,
                displayFrames: [
                    CGRect(x: 0, y: 0, width: 1728, height: 1117),
                    CGRect(x: 1728, y: 0, width: 1920, height: 1080),
                ]
            )
        )
    }

    func testRejectsNormalApplicationWindowAwayFromMenuBarBand() {
        let filter = makeFilter()
        let candidate = MenuBarWindowCandidate(
            ownerPID: 42,
            ownerName: "Example",
            title: "Document",
            bounds: CGRect(x: 100, y: 200, width: 600, height: 500),
            layer: 0
        )

        XCTAssertFalse(filter.isMenuBarItemCandidate(candidate, displayFrames: [CGRect(x: 0, y: 0, width: 1728, height: 1117)]))
    }

    func testRejectsWindowServerMenubarWindow() {
        let filter = makeFilter()
        let candidate = MenuBarWindowCandidate(
            ownerPID: 88,
            ownerName: "Window Server",
            title: "Menubar",
            bounds: CGRect(x: 0, y: 0, width: 1728, height: 37),
            layer: 24
        )

        XCTAssertFalse(filter.isMenuBarItemCandidate(candidate, displayFrames: [CGRect(x: 0, y: 0, width: 1728, height: 1117)]))
    }

    private func makeFilter() -> MenuBarWindowCandidateFilter {
        MenuBarWindowCandidateFilter(
            currentProcessID: 1,
            mainBundleIdentifier: "com.example.corona",
            bundleIdentifierForPID: { pid in
                pid == 1 ? "com.example.corona" : "com.example.other"
            }
        )
    }
}
