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
            return resolveSectionBoundary(section, sectionBoundaries: sectionBoundaries)
        }
    }

    private func resolveSectionBoundary(
        _ section: MenuBarSection,
        sectionBoundaries: [MenuBarSection: MenuBarItem]
    ) -> MoveDestination? {
        switch section {
        case .visible:
            guard let boundary = sectionBoundaries[.visible] else { return nil }
            return .rightOfItem(boundary)
        case .hidden:
            guard let hiddenBoundary = sectionBoundaries[.hidden] else { return nil }
            guard let alwaysHiddenBoundary = sectionBoundaries[.alwaysHidden] else {
                return .leftOfItem(hiddenBoundary)
            }
            if alwaysHiddenBoundary.bounds.minX > hiddenBoundary.bounds.minX {
                return .rightOfItem(hiddenBoundary)
            }
            return .leftOfItem(hiddenBoundary)
        case .alwaysHidden:
            guard let boundary = sectionBoundaries[.alwaysHidden] ?? sectionBoundaries[.hidden] else { return nil }
            if let hiddenBoundary = sectionBoundaries[.hidden],
               boundary.bounds.minX > hiddenBoundary.bounds.minX {
                return .leftOfItem(hiddenBoundary)
            }
            return .leftOfItem(boundary)
        }
    }
}

public extension ItemCache {
    func item(withStableIdentifier uid: String) -> MenuBarItem? {
        allItems.first { $0.tag.stableIdentifier == uid }
    }
}
