import AppKit
import CoronaCore

struct DirectMoveEventExecutor: MoveEventExecutor {
    private enum Constants {
        static let edgeInset: CGFloat = 2
        static let minimumDropGap: CGFloat = 8
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
        CoronaDebugLog.log("executor.move request uid=\(item.tag.stableIdentifier) displayID=\(displayID.map(String.init) ?? "nil") sourcePID=\(item.sourcePID.map(String.init) ?? "nil") bounds=\(item.bounds.debugDescription) destination=\(debugDescription(for: destination)) skipInputPause=\(skipInputPause) maxAttempts=\(maxAttempts)")
        guard item.isMovable else {
            CoronaDebugLog.log("executor.move rejected notMovable uid=\(item.tag.stableIdentifier)")
            throw MoveExecutorError.itemNotMovable(item.tag.stableIdentifier)
        }
        guard item.sourcePID != nil else {
            CoronaDebugLog.log("executor.move rejected missingSourcePID uid=\(item.tag.stableIdentifier)")
            throw MoveExecutorError.sourceProcessUnavailable(item.tag.stableIdentifier)
        }

        await Self.gate.acquire()
        await SnapshotPollingGate.shared.acquireSuspension()
        CoronaDebugLog.log("executor.move gate acquired uid=\(item.tag.stableIdentifier)")
        defer {
            Task {
                await SnapshotPollingGate.shared.releaseSuspension()
                await Self.gate.release()
                CoronaDebugLog.log("executor.move gate released uid=\(item.tag.stableIdentifier)")
            }
        }

        do {
            let attempts = max(1, maxAttempts)
            var lastError: Error?
            for _ in 0..<attempts {
                do {
                    try await drag(item: item, to: destination, skipInputPause: skipInputPause)
                    CoronaDebugLog.log("executor.move drag posted uid=\(item.tag.stableIdentifier)")
                    return
                } catch {
                    CoronaDebugLog.log("executor.move drag error uid=\(item.tag.stableIdentifier) error=\(String(describing: error))")
                    lastError = error
                }
            }

            if let lastError {
                throw lastError
            }
            throw MoveExecutorError.timedOut
        }
    }

    private func drag(
        item: MenuBarItem,
        to destination: MoveDestination,
        skipInputPause: Bool
    ) async throws {
        let source = CGPoint(x: item.bounds.midX, y: item.bounds.midY)
        let target = destinationPoint(for: destination, movingItemBounds: item.bounds, sourceY: source.y)
        CoronaDebugLog.log("executor.drag uid=\(item.tag.stableIdentifier) source=\(source.debugDescription) target=\(target.debugDescription)")
        let originalMouseLocation = CGEvent(source: nil)?.location
        var didPostMouseUp = false

        guard let eventSource = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseDown, mouseCursorPosition: source, mouseButton: .left),
              let drag = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseDragged, mouseCursorPosition: source, mouseButton: .left),
              let hover = CGEvent(mouseEventSource: eventSource, mouseType: .mouseMoved, mouseCursorPosition: target, mouseButton: .left),
              let up = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseUp, mouseCursorPosition: target, mouseButton: .left) else {
            CoronaDebugLog.log("executor.drag failed createEvents uid=\(item.tag.stableIdentifier)")
            throw MoveExecutorError.destinationUnavailable
        }

        eventSource.setLocalEventsFilterDuringSuppressionState([], state: .eventSuppressionStateSuppressionInterval)
        eventSource.setLocalEventsFilterDuringSuppressionState([], state: .eventSuppressionStateRemoteMouseDrag)

        down.flags = .maskCommand
        drag.flags = .maskCommand
        hover.flags = .maskCommand
        up.flags = .maskCommand
        configure(down, for: item)
        configure(drag, for: item)
        configure(hover, for: item)
        configure(up, for: item)

        defer {
            if !didPostMouseUp {
                postMouseUp(eventSource: eventSource, item: item, point: target)
            }
            if let originalMouseLocation {
                restoreMouse(eventSource: eventSource, to: originalMouseLocation)
            }
        }

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

        hover.location = target
        hover.post(tap: .cghidEventTap)
        if !skipInputPause {
            CoronaDebugLog.log("executor.drag hoverPause uid=\(item.tag.stableIdentifier) pauseNs=\(Constants.inputPauseNanoseconds)")
            try await Task.sleep(nanoseconds: Constants.inputPauseNanoseconds)
        }

        up.post(tap: .cghidEventTap)
        didPostMouseUp = true
        try await Task.sleep(nanoseconds: Constants.stepDelayNanoseconds)
    }

    private func postMouseUp(eventSource: CGEventSource, item: MenuBarItem, point: CGPoint) {
        guard let up = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            return
        }
        up.flags = .maskCommand
        configure(up, for: item)
        up.post(tap: .cghidEventTap)
    }

    private func restoreMouse(eventSource: CGEventSource, to location: CGPoint) {
        if let restore = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .mouseMoved,
            mouseCursorPosition: location,
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

    private func destinationPoint(
        for destination: MoveDestination,
        movingItemBounds: CGRect,
        sourceY: CGFloat
    ) -> CGPoint {
        let midpointOffset = (movingItemBounds.width / 2) + Constants.minimumDropGap
        switch destination {
        case .leftOfItem(let item):
            return CGPoint(x: item.bounds.minX - midpointOffset, y: sourceY)
        case .rightOfItem(let item):
            return CGPoint(x: item.bounds.maxX + midpointOffset, y: sourceY)
        }
    }

    private func debugDescription(for destination: MoveDestination) -> String {
        switch destination {
        case .leftOfItem(let item):
            return "leftOf uid=\(item.tag.stableIdentifier) bounds=\(item.bounds.debugDescription)"
        case .rightOfItem(let item):
            return "rightOf uid=\(item.tag.stableIdentifier) bounds=\(item.bounds.debugDescription)"
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
