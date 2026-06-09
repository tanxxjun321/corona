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

    func testRejectsApplicationChromeWindowInMenuBarBand() {
        let filter = makeFilter()
        let candidate = MenuBarWindowCandidate(
            ownerPID: 42,
            ownerName: "Example",
            title: nil,
            bounds: CGRect(x: 0, y: 0, width: 1512, height: 37),
            layer: 0
        )

        XCTAssertFalse(filter.isMenuBarItemCandidate(candidate, displayFrames: [CGRect(x: 0, y: 0, width: 1512, height: 982)]))
    }

    func testRejectsSmallLayerZeroWindowInMenuBarBand() {
        let filter = makeFilter()
        let candidate = MenuBarWindowCandidate(
            ownerPID: 42,
            ownerName: "Example",
            title: nil,
            bounds: CGRect(x: 480, y: 0, width: 32, height: 37),
            layer: 0
        )

        XCTAssertFalse(filter.isMenuBarItemCandidate(candidate, displayFrames: [CGRect(x: 0, y: 0, width: 1512, height: 982)]))
    }

    func testRejectsGenericControlCenterContainer() {
        let filter = makeFilter()
        let candidate = MenuBarWindowCandidate(
            ownerPID: 42,
            ownerName: "控制中心",
            title: nil,
            bounds: CGRect(x: 840, y: 0, width: 33, height: 24),
            layer: 25
        )

        XCTAssertFalse(filter.isMenuBarItemCandidate(candidate, displayFrames: [CGRect(x: 0, y: 0, width: 1512, height: 982)]))
    }

    func testAcceptsNamedControlCenterModule() {
        let filter = makeFilter()
        let candidate = MenuBarWindowCandidate(
            ownerPID: 42,
            ownerName: "控制中心",
            title: "WiFi",
            bounds: CGRect(x: 1296, y: 0, width: 38, height: 37),
            layer: 25
        )

        XCTAssertTrue(filter.isMenuBarItemCandidate(candidate, displayFrames: [CGRect(x: 0, y: 0, width: 1512, height: 982)]))
    }

    func testRejectsControlCenterSubviewArtifact() {
        let filter = makeFilter()
        let candidate = MenuBarWindowCandidate(
            ownerPID: 42,
            ownerName: "控制中心",
            title: "Sound",
            bounds: CGRect(x: 966, y: -6, width: 38, height: 24),
            layer: 25
        )

        XCTAssertFalse(filter.isMenuBarItemCandidate(candidate, displayFrames: [CGRect(x: 0, y: 0, width: 1512, height: 982)]))
    }

    func testRejectsLeftEdgeControlCenterArtifact() {
        let filter = makeFilter()
        let candidate = MenuBarWindowCandidate(
            ownerPID: 42,
            ownerName: "控制中心",
            title: "控制中心",
            bounds: CGRect(x: 0, y: 0, width: 38, height: 37),
            layer: 25
        )

        XCTAssertFalse(filter.isMenuBarItemCandidate(candidate, displayFrames: [CGRect(x: 0, y: 0, width: 1512, height: 982)]))
    }

    func testRejectsLeftApplicationMenuRegionItem() {
        let filter = makeFilter()
        let candidate = MenuBarWindowCandidate(
            ownerPID: 42,
            ownerName: "TextInputMenuAgent",
            title: "TextInputMenuAgent",
            bounds: CGRect(x: 0, y: 0, width: 44, height: 37),
            layer: 25
        )

        XCTAssertFalse(filter.isMenuBarItemCandidate(candidate, displayFrames: [CGRect(x: 0, y: 0, width: 1512, height: 982)]))
    }

    func testRejectsTextInputSubviewArtifact() {
        let filter = makeFilter(bundleIdentifier: "com.apple.TextInputMenuAgent")
        let candidate = MenuBarWindowCandidate(
            ownerPID: 42,
            ownerName: "TextInputMenuAgent",
            title: "Item-0",
            bounds: CGRect(x: 829, y: 1, width: 44, height: 24),
            layer: 25
        )

        XCTAssertFalse(filter.isMenuBarItemCandidate(candidate, displayFrames: [CGRect(x: 0, y: 0, width: 1512, height: 982)]))
    }

    func testAcceptsOffscreenThirdPartyHiddenStatusItem() {
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

    func testRejectsSmallWindowNearButBelowMenuBar() {
        let filter = makeFilter()
        let candidate = MenuBarWindowCandidate(
            ownerPID: 42,
            ownerName: "Example",
            title: "Floating Widget",
            bounds: CGRect(x: 351, y: 44, width: 14, height: 16),
            layer: 25
        )

        XCTAssertFalse(filter.isMenuBarItemCandidate(candidate, displayFrames: [CGRect(x: 0, y: 0, width: 1728, height: 1117)]))
    }

    func testRejectsSmallWindowNearBottomEdge() {
        let filter = makeFilter()
        let candidate = MenuBarWindowCandidate(
            ownerPID: 42,
            ownerName: "CursorUIViewService",
            title: "CursorUIViewService",
            bounds: CGRect(x: 0, y: 928, width: 54, height: 54),
            layer: 25
        )

        XCTAssertFalse(filter.isMenuBarItemCandidate(candidate, displayFrames: [CGRect(x: 0, y: 0, width: 1512, height: 982)]))
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

    private func makeFilter(bundleIdentifier: String = "com.example.other") -> MenuBarWindowCandidateFilter {
        MenuBarWindowCandidateFilter(
            currentProcessID: 1,
            mainBundleIdentifier: "com.example.corona",
            bundleIdentifierForPID: { pid in
                pid == 1 ? "com.example.corona" : bundleIdentifier
            }
        )
    }
}
