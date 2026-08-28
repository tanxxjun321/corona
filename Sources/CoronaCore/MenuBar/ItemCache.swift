import Foundation

public enum MenuBarSection: String, Codable, CaseIterable, Equatable, Sendable {
    case visible
    case hidden
    case alwaysHidden
}

public struct ItemCache: Codable, Equatable, Sendable {
    public var displayID: UInt32?
    public var visibleItems: [MenuBarItem]
    public var hiddenItems: [MenuBarItem]
    public var alwaysHiddenItems: [MenuBarItem]

    public init(
        displayID: UInt32?,
        visibleItems: [MenuBarItem],
        hiddenItems: [MenuBarItem],
        alwaysHiddenItems: [MenuBarItem]
    ) {
        self.displayID = displayID
        self.visibleItems = visibleItems
        self.hiddenItems = hiddenItems
        self.alwaysHiddenItems = alwaysHiddenItems
    }

    public var allItems: [MenuBarItem] {
        visibleItems + hiddenItems + alwaysHiddenItems
    }
}
