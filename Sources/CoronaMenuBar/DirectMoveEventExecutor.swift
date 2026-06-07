import AppKit
import CoronaCore

struct DirectMoveEventExecutor: MoveEventExecutor {
    private enum Constants {
        static let edgeInset: CGFloat = 2
        static let dragSteps = 12
        static let stepDelayNanoseconds: UInt64 = 12_000_000
        static let inputPauseNanoseconds: UInt64 = 180_000_000
    }

    private static let gate = MoveEventGate()

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

        await Self.gate.acquire()
        do {
            if !skipInputPause {
                try await Task.sleep(nanoseconds: Constants.inputPauseNanoseconds)
            }

            let attempts = max(1, maxAttempts)
            var lastError: Error?
            for _ in 0..<attempts {
                do {
                    try await drag(item: item, to: destination)
                    await Self.gate.release()
                    return
                } catch {
                    lastError = error
                }
            }

            await Self.gate.release()
            if let lastError {
                throw lastError
            }
            throw MoveExecutorError.timedOut
        } catch {
            await Self.gate.release()
            throw error
        }
    }

    private func drag(item: MenuBarItem, to destination: MoveDestination) async throws {
        let source = CGPoint(x: item.bounds.midX, y: item.bounds.midY)
        let target = destinationPoint(for: destination, sourceY: source.y)
        let originalMouseLocation = CGEvent(source: nil)?.location

        guard let eventSource = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseDown, mouseCursorPosition: source, mouseButton: .left),
              let drag = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseDragged, mouseCursorPosition: source, mouseButton: .left),
              let up = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseUp, mouseCursorPosition: target, mouseButton: .left) else {
            throw MoveExecutorError.destinationUnavailable
        }

        eventSource.setLocalEventsFilterDuringSuppressionState([], state: .eventSuppressionStateSuppressionInterval)
        eventSource.setLocalEventsFilterDuringSuppressionState([], state: .eventSuppressionStateRemoteMouseDrag)

        down.flags = .maskCommand
        drag.flags = .maskCommand
        up.flags = .maskCommand
        configure(down, for: item)
        configure(drag, for: item)
        configure(up, for: item)

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

        if let originalMouseLocation,
           let restore = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .mouseMoved,
            mouseCursorPosition: originalMouseLocation,
            mouseButton: .left
           ) {
            restore.post(tap: .cghidEventTap)
        }
    }

    private func configure(_ event: CGEvent, for item: MenuBarItem) {
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(item.windowID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(item.windowID))
        if let sourcePID = item.sourcePID {
            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(sourcePID))
        }
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

private actor MoveEventGate {
    private var isAcquired = false

    func acquire() async {
        while isAcquired {
            await Task.yield()
        }
        isAcquired = true
    }

    func release() {
        isAcquired = false
    }
}
