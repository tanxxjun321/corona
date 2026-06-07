import Foundation

public struct MoveDestinationResolver {
    public init() {}

    public func resolve(
        target: LayoutTarget,
        cache: ItemCache,
        sectionBoundaries: [MenuBarSection: MenuBarItem]
    ) -> MoveDestination? {
        switch target {
        case .leftOfUID(let uid):
            guard let item = cache.item(withStableIdentifier: uid) else { return nil }
            return .leftOfItem(item)
        case .rightOfUID(let uid):
            guard let item = cache.item(withStableIdentifier: uid) else { return nil }
            return .rightOfItem(item)
        case .sectionBoundary(let section):
            guard let item = sectionBoundaries[section] else { return nil }
            if section == .visible {
                return .rightOfItem(item)
            }
            return .leftOfItem(item)
        }
    }
}

public extension ItemCache {
    func item(withStableIdentifier uid: String) -> MenuBarItem? {
        allItems.first { $0.tag.stableIdentifier == uid }
    }
}
