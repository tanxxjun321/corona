import Foundation

public enum MoveDestination: Codable, Equatable, Sendable {
    case leftOfItem(MenuBarItem)
    case rightOfItem(MenuBarItem)
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
