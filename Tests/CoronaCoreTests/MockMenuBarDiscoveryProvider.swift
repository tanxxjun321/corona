import CoronaCore

struct MockMenuBarDiscoveryProvider: MenuBarDiscoveryProvider {
    var capability: DiscoveryCapability
    private var snapshotValue: MenuBarSnapshot

    init(
        capability: DiscoveryCapability = .appStoreFallback,
        snapshot: MenuBarSnapshot
    ) {
        self.capability = capability
        self.snapshotValue = snapshot
    }

    func snapshot() async throws -> MenuBarSnapshot {
        snapshotValue
    }
}
