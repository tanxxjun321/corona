import AppKit

struct MenuBarItemEventExecutor: MoveEventExecutor {
    private enum Constants {
        static let syntheticEventMarker: Int64 = 0x434f524f4e41
        static let eventTimeoutNanoseconds: UInt64 = 80_000_000
        static let frameCheckTimeoutNanoseconds: UInt64 = 120_000_000
        static let mouseStillSampleDelayNanoseconds: UInt64 = 45_000_000
        static let mouseStillMaxWaitNanoseconds: UInt64 = 450_000_000
    }

    private static let gate = MoveEventGate()

    func move(
        item: MenuBarItem,
        to destination: MoveDestination,
        on displayID: UInt32?,
        skipInputPause: Bool,
        maxAttempts: Int
    ) async throws {
        CoronaDebugLog.log("executor.itemEvent request uid=\(item.tag.stableIdentifier) displayID=\(displayID.map(String.init) ?? "nil") sourcePID=\(item.sourcePID.map(String.init) ?? "nil") bounds=\(item.bounds.debugDescription) destination=\(debugDescription(for: destination)) maxAttempts=\(maxAttempts)")
        guard item.isMovable else {
            CoronaDebugLog.log("executor.itemEvent rejected notMovable uid=\(item.tag.stableIdentifier)")
            throw MoveExecutorError.itemNotMovable(item.tag.stableIdentifier)
        }
        guard eventPID(for: item) != nil else {
            CoronaDebugLog.log("executor.itemEvent rejected missingSourcePID uid=\(item.tag.stableIdentifier)")
            throw MoveExecutorError.sourceProcessUnavailable(item.tag.stableIdentifier)
        }

        await Self.gate.acquire()
        await SnapshotPollingGate.shared.acquireSuspension()
        CoronaDebugLog.log("executor.itemEvent gate acquired uid=\(item.tag.stableIdentifier)")

        if !skipInputPause {
            await waitForMouseToStopMoving()
        }
        let result = await runMoveTransaction(
            item: item,
            destination: destination,
            maxAttempts: maxAttempts
        )
        await SnapshotPollingGate.shared.releaseSuspension()
        await Self.gate.release()
        CoronaDebugLog.log("executor.itemEvent gate released uid=\(item.tag.stableIdentifier)")
        try result.get()
    }

    private func waitForMouseToStopMoving() async {
        var previous = CGEvent(source: nil)?.location
        let deadline = DispatchTime.now().uptimeNanoseconds + Constants.mouseStillMaxWaitNanoseconds

        while DispatchTime.now().uptimeNanoseconds < deadline {
            try? await Task.sleep(nanoseconds: Constants.mouseStillSampleDelayNanoseconds)
            let current = CGEvent(source: nil)?.location
            guard let previousSample = previous, let current else {
                return
            }
            if abs(previousSample.x - current.x) < 0.5, abs(previousSample.y - current.y) < 0.5 {
                return
            }
            previous = current
        }
    }

    private func runMoveTransaction(
        item: MenuBarItem,
        destination: MoveDestination,
        maxAttempts: Int
    ) async -> Result<Void, Error> {
        let attempts = max(1, maxAttempts)
        var lastError: Error?
        for attempt in 1...attempts {
            do {
                try await postMenuBarItemEvents(item: item, to: destination)
                CoronaDebugLog.log("executor.itemEvent posted uid=\(item.tag.stableIdentifier) attempt=\(attempt)")
                return .success(())
            } catch {
                CoronaDebugLog.log("executor.itemEvent error uid=\(item.tag.stableIdentifier) attempt=\(attempt) error=\(String(describing: error))")
                lastError = error
                try? await wakeUp(item)
            }
        }

        return .failure(lastError ?? MoveExecutorError.timedOut)
    }

    private func postMenuBarItemEvents(item: MenuBarItem, to destination: MoveDestination) async throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let pid = eventPID(for: item) else {
            throw MoveExecutorError.destinationUnavailable
        }
        permitLocalEvents(on: source)

        let initialBounds = item.bounds
        let targetItem = destination.targetItem
        let cursorPoint = currentMouseLocation() ?? CGPoint(x: item.bounds.midX, y: item.bounds.midY)

        guard let mouseDown = CGEvent.menuBarItemEvent(
            type: .move(.leftMouseDown),
            location: cursorPoint,
            targetItem: item,
            pid: pid,
            source: source,
            syntheticMarker: Constants.syntheticEventMarker
        ) else {
            throw MoveExecutorError.destinationUnavailable
        }

        do {
            try await scromble(
                mouseDown,
                from: .pid(pid),
                to: .sessionEventTap,
                waitingForFrameChangeOf: item,
                initialBounds: initialBounds
            )
            let targetBounds = currentBounds(for: targetItem)
            let endPoint = destinationPoint(for: destination, targetBounds: targetBounds)
            guard let mouseUp = CGEvent.menuBarItemEvent(
                type: .move(.leftMouseUp),
                location: endPoint,
                targetItem: targetItem,
                pid: pid,
                source: source,
                syntheticMarker: Constants.syntheticEventMarker
            ) else {
                throw MoveExecutorError.destinationUnavailable
            }
            try await scromble(
                mouseUp,
                from: .pid(pid),
                to: .sessionEventTap,
                waitingForFrameChangeOf: item,
                initialBounds: initialBounds
            )
        } catch {
            let fallbackBounds = currentBounds(for: item)
            let fallbackPoint = currentMouseLocation() ?? CGPoint(x: fallbackBounds.midX, y: fallbackBounds.midY)
            if let fallback = CGEvent.menuBarItemEvent(
                type: .move(.leftMouseUp),
                location: fallbackPoint,
                targetItem: item,
                pid: pid,
                source: source,
                syntheticMarker: Constants.syntheticEventMarker
            ) {
                try? await postAndWait(fallback, to: .sessionEventTap)
            }
            throw error
        }
    }

    private func wakeUp(_ item: MenuBarItem) async throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let pid = eventPID(for: item) else {
            return
        }
        let point = currentMouseLocation() ?? CGPoint(x: item.bounds.midX, y: item.bounds.midY)
        guard
            let mouseDown = CGEvent.menuBarItemEvent(
                type: .move(.leftMouseDown),
                location: point,
                targetItem: item,
                pid: pid,
                source: source,
                syntheticMarker: Constants.syntheticEventMarker
            ),
            let mouseUp = CGEvent.menuBarItemEvent(
                type: .move(.leftMouseUp),
                location: point,
                targetItem: item,
                pid: pid,
                source: source,
                syntheticMarker: Constants.syntheticEventMarker
            )
        else {
            return
        }
        try? await scromble(mouseDown, from: .pid(pid), to: .sessionEventTap)
        try? await scromble(mouseUp, from: .pid(pid), to: .sessionEventTap)
    }

    private func destinationPoint(for destination: MoveDestination, targetBounds: CGRect) -> CGPoint {
        switch destination {
        case .leftOfItem:
            return CGPoint(x: targetBounds.minX, y: targetBounds.midY)
        case .rightOfItem:
            return CGPoint(x: targetBounds.maxX, y: targetBounds.midY)
        }
    }

    private func currentBounds(for item: MenuBarItem) -> CGRect {
        MenuBarWindowFrameReader.frame(for: item.windowID) ?? item.bounds
    }

    private func currentMouseLocation() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    private func eventPID(for item: MenuBarItem) -> pid_t? {
        item.sourcePID ?? item.ownerPID
    }

    private func permitLocalEvents(on source: CGEventSource) {
        source.setLocalEventsFilterDuringSuppressionState(.permitAllEvents, state: .eventSuppressionStateSuppressionInterval)
        source.setLocalEventsFilterDuringSuppressionState(.permitAllEvents, state: .eventSuppressionStateRemoteMouseDrag)
        source.localEventsSuppressionInterval = 0
    }

    private func scromble(
        _ event: CGEvent,
        from firstLocation: MenuBarEventLocation,
        to secondLocation: MenuBarEventLocation,
        waitingForFrameChangeOf item: MenuBarItem? = nil,
        initialBounds: CGRect? = nil
    ) async throws {
        try await scromble(event, from: firstLocation, to: secondLocation)
        guard let item, let initialBounds else { return }
        try await waitForFrameChange(of: item, initialBounds: initialBounds)
    }

    private func scromble(
        _ event: CGEvent,
        from firstLocation: MenuBarEventLocation,
        to secondLocation: MenuBarEventLocation
    ) async throws {
        guard let nullEvent = CGEvent(source: nil) else {
            throw MoveExecutorError.destinationUnavailable
        }
        nullEvent.setIntegerValueField(.eventSourceUserData, value: Constants.syntheticEventMarker + 1)

        try await withCheckedThrowingContinuation { continuation in
            let session = MenuBarEventScrombleSession(
                event: event,
                nullEvent: nullEvent,
                firstLocation: firstLocation,
                secondLocation: secondLocation,
                timeoutNanoseconds: Constants.eventTimeoutNanoseconds
            )
            session.start { result in
                continuation.resume(with: result)
            }
        }
    }

    private func postAndWait(_ event: CGEvent, to location: MenuBarEventLocation) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let session = MenuBarEventPostSession(
                event: event,
                location: location,
                timeoutNanoseconds: Constants.eventTimeoutNanoseconds
            )
            session.start { result in
                continuation.resume(with: result)
            }
        }
    }

    private func waitForFrameChange(of item: MenuBarItem, initialBounds: CGRect) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + Constants.frameCheckTimeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if let current = MenuBarWindowFrameReader.frame(for: item.windowID),
               current != initialBounds {
                CoronaDebugLog.verbose("executor.itemEvent frameChanged uid=\(item.tag.stableIdentifier) frame=\(current.debugDescription)")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw MoveExecutorError.timedOut
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

private enum MenuBarEventLocation {
    case hidEventTap
    case sessionEventTap
    case annotatedSessionEventTap
    case pid(pid_t)

    var tapLocation: CGEventTapLocation? {
        switch self {
        case .hidEventTap:
            return .cghidEventTap
        case .sessionEventTap:
            return .cgSessionEventTap
        case .annotatedSessionEventTap:
            return .cgAnnotatedSessionEventTap
        case .pid:
            return nil
        }
    }

    func post(_ event: CGEvent) {
        switch self {
        case .hidEventTap:
            event.post(tap: .cghidEventTap)
        case .sessionEventTap:
            event.post(tap: .cgSessionEventTap)
        case .annotatedSessionEventTap:
            event.post(tap: .cgAnnotatedSessionEventTap)
        case .pid(let pid):
            event.postToPid(pid)
        }
    }

    func createTap(
        options: CGEventTapOptions,
        place: CGEventTapPlacement,
        eventsOfInterest: CGEventMask,
        callback: CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer?
    ) -> CFMachPort? {
        switch self {
        case .pid(let pid):
            return CGEvent.tapCreateForPid(
                pid: pid,
                place: place,
                options: options,
                eventsOfInterest: eventsOfInterest,
                callback: callback,
                userInfo: userInfo
            )
        case .hidEventTap, .sessionEventTap, .annotatedSessionEventTap:
            guard let tapLocation else { return nil }
            return CGEvent.tapCreate(
                tap: tapLocation,
                place: place,
                options: options,
                eventsOfInterest: eventsOfInterest,
                callback: callback,
                userInfo: userInfo
            )
        }
    }
}

private final class MenuBarEventPostSession {
    private let event: CGEvent
    private let location: MenuBarEventLocation
    private let timeoutNanoseconds: UInt64
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var completion: ((Result<Void, Error>) -> Void)?
    private var timeoutWorkItem: DispatchWorkItem?
    private var retainedSelf: Unmanaged<MenuBarEventPostSession>?

    init(event: CGEvent, location: MenuBarEventLocation, timeoutNanoseconds: UInt64) {
        self.event = event
        self.location = location
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        self.completion = completion
        let mask = Self.eventMask(for: [event.type])
        retainedSelf = Unmanaged.passRetained(self)
        let refcon = UnsafeMutableRawPointer(retainedSelf!.toOpaque())
        guard let tap = location.createTap(
            options: .listenOnly,
            place: .tailAppendEventTap,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: refcon
        ) else {
            finish(.failure(MoveExecutorError.destinationUnavailable))
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            finish(.failure(MoveExecutorError.destinationUnavailable))
            return
        }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        let workItem = DispatchWorkItem { [weak self] in
            self?.finish(.failure(MoveExecutorError.timedOut))
        }
        timeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(timeoutNanoseconds)), execute: workItem)
        location.post(event)
    }

    private func handle(type: CGEventType, event received: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(received)
        }
        guard received.matchesMenuBarEvent(event) else {
            return Unmanaged.passUnretained(received)
        }
        finish(.success(()))
        return Unmanaged.passUnretained(received)
    }

    private func finish(_ result: Result<Void, Error>) {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        guard let completion else { return }
        self.completion = nil
        let retained = retainedSelf
        retainedSelf = nil
        completion(result)
        retained?.release()
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let session = Unmanaged<MenuBarEventPostSession>.fromOpaque(userInfo).takeUnretainedValue()
        return session.handle(type: type, event: event)
    }

    private static func eventMask(for types: [CGEventType]) -> CGEventMask {
        types.reduce(0) { mask, type in
            mask | (1 << CGEventMask(type.rawValue))
        }
    }
}

private final class MenuBarEventScrombleSession {
    private let event: CGEvent
    private let nullEvent: CGEvent
    private let firstLocation: MenuBarEventLocation
    private let secondLocation: MenuBarEventLocation
    private let timeoutNanoseconds: UInt64
    private var firstTap: CFMachPort?
    private var secondTap: CFMachPort?
    private var firstSource: CFRunLoopSource?
    private var secondSource: CFRunLoopSource?
    private var completion: ((Result<Void, Error>) -> Void)?
    private var timeoutWorkItem: DispatchWorkItem?
    private var retainedSelf: Unmanaged<MenuBarEventScrombleSession>?

    init(
        event: CGEvent,
        nullEvent: CGEvent,
        firstLocation: MenuBarEventLocation,
        secondLocation: MenuBarEventLocation,
        timeoutNanoseconds: UInt64
    ) {
        self.event = event
        self.nullEvent = nullEvent
        self.firstLocation = firstLocation
        self.secondLocation = secondLocation
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        self.completion = completion
        retainedSelf = Unmanaged.passRetained(self)
        let refcon = UnsafeMutableRawPointer(retainedSelf!.toOpaque())
        guard
            let firstTap = firstLocation.createTap(
                options: .defaultTap,
                place: .tailAppendEventTap,
                eventsOfInterest: Self.eventMask(for: [nullEvent.type]),
                callback: Self.firstCallback,
                userInfo: refcon
            ),
            let secondTap = secondLocation.createTap(
                options: .listenOnly,
                place: .tailAppendEventTap,
                eventsOfInterest: Self.eventMask(for: [event.type]),
                callback: Self.secondCallback,
                userInfo: refcon
            ),
            let firstSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, firstTap, 0),
            let secondSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, secondTap, 0)
        else {
            finish(.failure(MoveExecutorError.destinationUnavailable))
            return
        }
        self.firstTap = firstTap
        self.secondTap = secondTap
        self.firstSource = firstSource
        self.secondSource = secondSource
        CFRunLoopAddSource(CFRunLoopGetMain(), firstSource, .commonModes)
        CFRunLoopAddSource(CFRunLoopGetMain(), secondSource, .commonModes)
        CGEvent.tapEnable(tap: firstTap, enable: true)
        CGEvent.tapEnable(tap: secondTap, enable: true)
        let workItem = DispatchWorkItem { [weak self] in
            self?.finish(.failure(MoveExecutorError.timedOut))
        }
        timeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(timeoutNanoseconds)), execute: workItem)
        firstLocation.post(nullEvent)
    }

    private func handleFirst(type: CGEventType, event received: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let firstTap {
                CGEvent.tapEnable(tap: firstTap, enable: true)
            }
            return nil
        }
        guard received.getIntegerValueField(.eventSourceUserData) == nullEvent.getIntegerValueField(.eventSourceUserData) else {
            return nil
        }
        if let firstTap {
            CGEvent.tapEnable(tap: firstTap, enable: false)
        }
        secondLocation.post(event)
        return nil
    }

    private func handleSecond(type: CGEventType, event received: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let secondTap {
                CGEvent.tapEnable(tap: secondTap, enable: true)
            }
            return Unmanaged.passUnretained(received)
        }
        guard received.matchesMenuBarEvent(event) else {
            return Unmanaged.passUnretained(received)
        }
        if let secondTap {
            CGEvent.tapEnable(tap: secondTap, enable: false)
        }
        firstLocation.post(event)
        finish(.success(()))
        return Unmanaged.passUnretained(received)
    }

    private func finish(_ result: Result<Void, Error>) {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        if let firstTap {
            CGEvent.tapEnable(tap: firstTap, enable: false)
        }
        if let secondTap {
            CGEvent.tapEnable(tap: secondTap, enable: false)
        }
        if let firstSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), firstSource, .commonModes)
        }
        if let secondSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), secondSource, .commonModes)
        }
        firstTap = nil
        secondTap = nil
        firstSource = nil
        secondSource = nil
        guard let completion else { return }
        self.completion = nil
        let retained = retainedSelf
        retainedSelf = nil
        completion(result)
        retained?.release()
    }

    private static let firstCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return nil }
        let session = Unmanaged<MenuBarEventScrombleSession>.fromOpaque(userInfo).takeUnretainedValue()
        return session.handleFirst(type: type, event: event)
    }

    private static let secondCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let session = Unmanaged<MenuBarEventScrombleSession>.fromOpaque(userInfo).takeUnretainedValue()
        return session.handleSecond(type: type, event: event)
    }

    private static func eventMask(for types: [CGEventType]) -> CGEventMask {
        types.reduce(0) { mask, type in
            mask | (1 << CGEventMask(type.rawValue))
        }
    }
}

private enum MenuBarItemEventButtonState {
    case leftMouseDown
    case leftMouseUp
}

private enum MenuBarItemEventType {
    case move(MenuBarItemEventButtonState)

    var cgEventType: CGEventType {
        switch self {
        case .move(.leftMouseDown):
            return .leftMouseDown
        case .move(.leftMouseUp):
            return .leftMouseUp
        }
    }

    var flags: CGEventFlags {
        switch self {
        case .move(.leftMouseDown):
            return .maskCommand
        case .move(.leftMouseUp):
            return []
        }
    }
}

private extension CGEvent {
    static func menuBarItemEvent(
        type: MenuBarItemEventType,
        location: CGPoint,
        targetItem: MenuBarItem,
        pid: pid_t,
        source: CGEventSource,
        syntheticMarker: Int64
    ) -> CGEvent? {
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type.cgEventType,
            mouseCursorPosition: location,
            mouseButton: .left
        ) else {
            return nil
        }

        event.flags = type.flags
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker + Int64(targetItem.windowID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(targetItem.windowID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(targetItem.windowID))
        event.setIntegerValueField(.windowID, value: Int64(targetItem.windowID))
        return event
    }

    func matchesMenuBarEvent(_ other: CGEvent) -> Bool {
        for field in CGEventField.menuBarItemEventFields where getIntegerValueField(field) != other.getIntegerValueField(field) {
            return false
        }
        return true
    }
}

private enum MenuBarWindowFrameReader {
    private typealias CGSConnectionID = Int32
    private typealias GetConnectionFn = @convention(c) () -> CGSConnectionID
    private typealias GetScreenRectForWindowFn = @convention(c) (
        CGSConnectionID,
        CGWindowID,
        UnsafeMutablePointer<CGRect>
    ) -> CGError

    private static let skyLightPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

    static func frame(for windowID: UInt32) -> CGRect? {
        guard let handle = dlopen(skyLightPath, RTLD_NOW) else { return nil }
        defer { dlclose(handle) }
        guard let mainConnectionSymbol = dlsym(handle, "CGSMainConnectionID"),
              let getFrameSymbol = dlsym(handle, "CGSGetScreenRectForWindow") else {
            return nil
        }
        let mainConnection = unsafeBitCast(mainConnectionSymbol, to: GetConnectionFn.self)
        let getFrame = unsafeBitCast(getFrameSymbol, to: GetScreenRectForWindowFn.self)
        var rect = CGRect.zero
        guard getFrame(mainConnection(), CGWindowID(windowID), &rect) == .success else {
            return nil
        }
        return rect
    }
}

private extension MoveDestination {
    var targetItem: MenuBarItem {
        switch self {
        case .leftOfItem(let item), .rightOfItem(let item):
            return item
        }
    }
}

private extension CGEventField {
    static let windowID = CGEventField(rawValue: 0x33)!

    static let menuBarItemEventFields: [CGEventField] = [
        .eventSourceUserData,
        .mouseEventWindowUnderMousePointer,
        .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
        .windowID,
    ]
}

private extension CGEventFilterMask {
    static let permitAllEvents: CGEventFilterMask = [
        .permitLocalMouseEvents,
        .permitLocalKeyboardEvents,
        .permitSystemDefinedEvents,
    ]
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

typealias MenuBarDragExecutor = MenuBarItemEventExecutor
typealias MenuBarDirectEventExecutor = MenuBarItemEventExecutor
typealias DirectMoveEventExecutor = MenuBarItemEventExecutor
