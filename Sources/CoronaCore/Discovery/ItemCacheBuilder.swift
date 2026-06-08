import Foundation

public struct ItemCacheBuilder {
    public init() {}

    public func build(
        snapshot: MenuBarSnapshot,
        sectionByWindowID: [UInt32: MenuBarSection]
    ) -> ItemCache {
        var visible: [MenuBarItem] = []
        var hidden: [MenuBarItem] = []
        var alwaysHidden: [MenuBarItem] = []

        for item in snapshot.items {
            switch sectionByWindowID[item.windowID, default: .visible] {
            case .visible:
                visible.append(item)
            case .hidden:
                hidden.append(item)
            case .alwaysHidden:
                alwaysHidden.append(item)
            }
        }

        return ItemCache(
            displayID: snapshot.displayID,
            visibleItems: visible.sortedByMenuBarPosition(),
            hiddenItems: hidden.sortedByMenuBarPosition(),
            alwaysHiddenItems: alwaysHidden.sortedByMenuBarPosition()
        )
    }
}

private extension Array where Element == MenuBarItem {
    func sortedByMenuBarPosition() -> [MenuBarItem] {
        sorted { lhs, rhs in
            if abs(lhs.bounds.minX - rhs.bounds.minX) > 0.5 {
                return lhs.bounds.minX < rhs.bounds.minX
            }
            return lhs.windowID < rhs.windowID
        }
    }
}
