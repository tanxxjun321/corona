import Foundation

public actor MenuBarCacheController {
    private let provider: any MenuBarDiscoveryProvider
    private let identityAssigner: MenuBarItemIdentityAssigner
    private let logger: any DiagnosticLogging
    private var cachedSnapshot: MenuBarSnapshot?

    public init(
        provider: any MenuBarDiscoveryProvider,
        identityAssigner: MenuBarItemIdentityAssigner = MenuBarItemIdentityAssigner(),
        logger: any DiagnosticLogging = DisabledDiagnosticLogger()
    ) {
        self.provider = provider
        self.identityAssigner = identityAssigner
        self.logger = logger
    }

    public var capability: DiscoveryCapability {
        provider.capability
    }

    public func refresh() async throws -> MenuBarSnapshot {
        let rawSnapshot = try await provider.snapshot()
        let assignedItems = identityAssigner.assignInstanceIndexes(to: rawSnapshot.items)
        let snapshot = MenuBarSnapshot(displayID: rawSnapshot.displayID, items: assignedItems)
        cachedSnapshot = snapshot
        logger.log(.cacheRefreshed(displayID: snapshot.displayID, itemCount: snapshot.items.count))
        return snapshot
    }

    public func snapshot(refreshIfNeeded: Bool = true) async throws -> MenuBarSnapshot {
        if let cachedSnapshot, !refreshIfNeeded {
            return cachedSnapshot
        }
        return try await refresh()
    }

    public func cachedSnapshotValue() -> MenuBarSnapshot? {
        cachedSnapshot
    }
}
