import CoronaCore
import CoreGraphics
import XCTest

final class MenuBarCacheClassificationTests: XCTestCase {
    func testBuildsClassifiedCacheFromBoundary() async throws {
        let visible = withBounds(
            makeItem(windowID: 1, namespace: "app", title: "Visible", sourcePID: 10),
            CGRect(x: 720, y: 0, width: 20, height: 22)
        )
        let hidden = withBounds(
            makeItem(windowID: 2, namespace: "app", title: "Hidden", sourcePID: 10),
            CGRect(x: 620, y: 0, width: 20, height: 22)
        )
        let alwaysHidden = withBounds(
            makeItem(windowID: 3, namespace: "app", title: "Always", sourcePID: 10),
            CGRect(x: 420, y: 0, width: 20, height: 22)
        )
        let controller = MenuBarCacheController(
            provider: MockMenuBarDiscoveryProvider(
                snapshot: MenuBarSnapshot(displayID: 1, items: [visible, hidden, alwaysHidden])
            )
        )
        let boundary = SectionBoundary(
            hiddenControlBounds: CGRect(x: 700, y: 0, width: 10, height: 22),
            alwaysHiddenControlBounds: CGRect(x: 500, y: 0, width: 10, height: 22)
        )

        let cache = try await controller.cache(boundary: boundary)

        XCTAssertEqual(cache.visibleItems.map(\.windowID), [1])
        XCTAssertEqual(cache.hiddenItems.map(\.windowID), [2])
        XCTAssertEqual(cache.alwaysHiddenItems.map(\.windowID), [3])
    }

    private func withBounds(_ item: MenuBarItem, _ bounds: CGRect) -> MenuBarItem {
        var copy = item
        copy.bounds = bounds
        return copy
    }
}
