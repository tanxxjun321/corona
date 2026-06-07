import CoronaCore
import XCTest

final class MenuBarCacheControllerTests: XCTestCase {
    func testRefreshAssignsInstanceIndexesAndCachesSnapshot() async throws {
        let first = makeItem(windowID: 20, namespace: "app", title: "A", sourcePID: 10)
        let second = makeItem(windowID: 10, namespace: "app", title: "A", sourcePID: 10)
        let provider = MockMenuBarDiscoveryProvider(
            snapshot: MenuBarSnapshot(displayID: 1, items: [first, second])
        )
        let controller = MenuBarCacheController(provider: provider)

        let refreshed = try await controller.refresh()
        let cached = await controller.cachedSnapshotValue()

        XCTAssertEqual(refreshed.items.map(\.tag.instanceIndex), [1, 0])
        XCTAssertEqual(cached, refreshed)
    }

    func testSnapshotCanReturnCachedValueWithoutRefreshing() async throws {
        let provider = CountingDiscoveryProvider()
        let controller = MenuBarCacheController(provider: provider)

        _ = try await controller.refresh()
        _ = try await controller.snapshot(refreshIfNeeded: false)

        XCTAssertEqual(provider.callCount, 1)
    }
}

private final class CountingDiscoveryProvider: MenuBarDiscoveryProvider, @unchecked Sendable {
    private var storedCallCount = 0

    var callCount: Int {
        storedCallCount
    }

    var capability: DiscoveryCapability {
        .appStoreFallback
    }

    func snapshot() async throws -> MenuBarSnapshot {
        storedCallCount += 1
        let windowID = UInt32(storedCallCount)

        return MenuBarSnapshot(
            displayID: nil,
            items: [makeItem(windowID: windowID, namespace: "app", title: "A", sourcePID: 10)]
        )
    }
}
