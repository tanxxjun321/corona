import Foundation

public struct MenuBarSnapshot: Equatable, Sendable {
    public var displayID: UInt32?
    public var items: [MenuBarItem]

    public init(displayID: UInt32?, items: [MenuBarItem]) {
        self.displayID = displayID
        self.items = items
    }
}

public protocol MenuBarDiscoveryProvider {
    var capability: DiscoveryCapability { get }
    func snapshot() async throws -> MenuBarSnapshot
}

public struct MockMenuBarDiscoveryProvider: MenuBarDiscoveryProvider {
    public var capability: DiscoveryCapability
    private var snapshotValue: MenuBarSnapshot

    public init(
        capability: DiscoveryCapability = .appStoreFallback,
        snapshot: MenuBarSnapshot
    ) {
        self.capability = capability
        self.snapshotValue = snapshot
    }

    public func snapshot() async throws -> MenuBarSnapshot {
        snapshotValue
    }
}
