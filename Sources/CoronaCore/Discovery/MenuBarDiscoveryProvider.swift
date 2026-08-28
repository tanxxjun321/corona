import Foundation

public struct MenuBarSnapshot: Equatable, Sendable {
    public var displayID: UInt32?
    public var items: [MenuBarItem]

    public init(displayID: UInt32?, items: [MenuBarItem]) {
        self.displayID = displayID
        self.items = items
    }
}

public protocol MenuBarDiscoveryProvider: Sendable {
    var capability: DiscoveryCapability { get }
    func snapshot() async throws -> MenuBarSnapshot
}
