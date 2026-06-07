import Foundation

public enum MoveDestination: Codable, Equatable, Sendable {
    case leftOfItem(MenuBarItem)
    case rightOfItem(MenuBarItem)
}

public extension MoveDestination {
    func isSatisfied(for itemUID: String, in cache: ItemCache) -> Bool {
        guard let movedItem = cache.item(withStableIdentifier: itemUID) else {
            return false
        }

        switch self {
        case .leftOfItem(let anchor):
            guard let currentAnchor = cache.item(withStableIdentifier: anchor.tag.stableIdentifier) else {
                return false
            }
            return movedItem.bounds.midX < currentAnchor.bounds.midX
        case .rightOfItem(let anchor):
            guard let currentAnchor = cache.item(withStableIdentifier: anchor.tag.stableIdentifier) else {
                return false
            }
            return movedItem.bounds.midX > currentAnchor.bounds.midX
        }
    }
}

public enum MoveExecutorError: Error, Equatable, Sendable {
    case itemNotMovable(String)
    case sourceProcessUnavailable(String)
    case destinationUnavailable
    case timedOut
    case finalPositionMismatch
}

public protocol MoveEventExecutor {
    func move(
        item: MenuBarItem,
        to destination: MoveDestination,
        on displayID: UInt32?,
        skipInputPause: Bool,
        maxAttempts: Int
    ) async throws
}

public struct NoopMoveEventExecutor: MoveEventExecutor {
    public init() {}

    public func move(
        item: MenuBarItem,
        to destination: MoveDestination,
        on displayID: UInt32?,
        skipInputPause: Bool,
        maxAttempts: Int
    ) async throws {
        guard item.isMovable else {
            throw MoveExecutorError.itemNotMovable(item.tag.stableIdentifier)
        }
    }
}
