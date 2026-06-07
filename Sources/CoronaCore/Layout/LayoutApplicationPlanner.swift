import Foundation

public struct ResolvedLayoutMove: Codable, Equatable, Sendable {
    public var plannedMove: LayoutMove
    public var item: MenuBarItem
    public var destination: MoveDestination

    public init(plannedMove: LayoutMove, item: MenuBarItem, destination: MoveDestination) {
        self.plannedMove = plannedMove
        self.item = item
        self.destination = destination
    }
}

public enum LayoutApplicationStep: Codable, Equatable, Sendable {
    case satisfied(SectionOrder)
    case waitingForItem(String)
    case waitingForDestination(LayoutTarget)
    case move(ResolvedLayoutMove)
}

public struct LayoutApplicationPlanner {
    private var layoutPlanner: LayoutPlanner
    private var destinationResolver: MoveDestinationResolver

    public init(
        layoutPlanner: LayoutPlanner = LayoutPlanner(),
        destinationResolver: MoveDestinationResolver = MoveDestinationResolver()
    ) {
        self.layoutPlanner = layoutPlanner
        self.destinationResolver = destinationResolver
    }

    public func nextStep(
        cache: ItemCache,
        preference: LayoutPreference,
        sectionBoundaries: [MenuBarSection: MenuBarItem]
    ) -> LayoutApplicationStep {
        let currentOrder = SectionOrder(cache: cache)
        guard !preference.savedOrder.isEmpty else {
            return .satisfied(currentOrder)
        }

        let desiredOrder = layoutPlanner.mergedOrder(cache: cache, preference: preference)
        guard let plannedMove = layoutPlanner.nextMove(currentOrder: currentOrder, desiredOrder: desiredOrder) else {
            return .satisfied(desiredOrder)
        }

        guard let item = cache.item(withStableIdentifier: plannedMove.itemUID) else {
            return .waitingForItem(plannedMove.itemUID)
        }

        guard let destination = destinationResolver.resolve(
            target: plannedMove.target,
            cache: cache,
            sectionBoundaries: sectionBoundaries
        ) else {
            return .waitingForDestination(plannedMove.target)
        }

        return .move(ResolvedLayoutMove(plannedMove: plannedMove, item: item, destination: destination))
    }
}
