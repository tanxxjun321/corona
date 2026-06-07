import AppKit
import CoronaCore

struct DirectMoveEventExecutor: MoveEventExecutor {
    private enum Constants {
        static let edgeInset: CGFloat = 2
        static let dragSteps = 12
        static let stepDelayNanoseconds: UInt64 = 12_000_000
    }

    func move(
        item: MenuBarItem,
        to destination: MoveDestination,
        on displayID: UInt32?,
        skipInputPause: Bool,
        maxAttempts: Int
    ) async throws {
        guard item.isMovable else {
            throw MoveExecutorError.itemNotMovable(item.tag.stableIdentifier)
        }
        guard item.sourcePID != nil else {
            throw MoveExecutorError.sourceProcessUnavailable(item.tag.stableIdentifier)
        }

        let attempts = max(1, maxAttempts)
        var lastError: Error?
        for _ in 0..<attempts {
            do {
                try await drag(item: item, to: destination)
                return
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }
        throw MoveExecutorError.timedOut
    }

    private func drag(item: MenuBarItem, to destination: MoveDestination) async throws {
        let source = CGPoint(x: item.bounds.midX, y: item.bounds.midY)
        let target = destinationPoint(for: destination, sourceY: source.y)

        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: source, mouseButton: .left),
              let drag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: source, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: target, mouseButton: .left) else {
            throw MoveExecutorError.destinationUnavailable
        }

        down.flags = .maskCommand
        drag.flags = .maskCommand
        up.flags = .maskCommand

        down.post(tap: .cghidEventTap)
        try await Task.sleep(nanoseconds: Constants.stepDelayNanoseconds)

        for step in 1...Constants.dragSteps {
            let progress = CGFloat(step) / CGFloat(Constants.dragSteps)
            let point = CGPoint(
                x: source.x + ((target.x - source.x) * progress),
                y: source.y + ((target.y - source.y) * progress)
            )
            drag.location = point
            drag.post(tap: .cghidEventTap)
            try await Task.sleep(nanoseconds: Constants.stepDelayNanoseconds)
        }

        up.post(tap: .cghidEventTap)
        try await Task.sleep(nanoseconds: Constants.stepDelayNanoseconds)
    }

    private func destinationPoint(for destination: MoveDestination, sourceY: CGFloat) -> CGPoint {
        switch destination {
        case .leftOfItem(let item):
            return CGPoint(x: item.bounds.minX - Constants.edgeInset, y: sourceY)
        case .rightOfItem(let item):
            return CGPoint(x: item.bounds.maxX + Constants.edgeInset, y: sourceY)
        }
    }
}
