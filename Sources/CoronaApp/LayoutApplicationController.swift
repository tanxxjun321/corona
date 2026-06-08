import AppKit
import Foundation

enum LayoutApplicationResult: Equatable {
    case satisfied
    case applied(Int)
    case moved(String)
    case missingBoundary
    case waitingForItem(String)
    case waitingForDestination
    case failed(String)

    var statusTitle: String {
        switch self {
        case .satisfied:
            return "Layout up to date"
        case .applied(let count):
            return "Applied \(count) layout moves"
        case .moved(let uid):
            return "Moved \(uid)"
        case .missingBoundary:
            return "Layout controls unavailable"
        case .waitingForItem(let uid):
            return "Waiting for \(uid)"
        case .waitingForDestination:
            return "Layout target unavailable"
        case .failed(let message):
            return "Layout apply failed: \(message)"
        }
    }
}

final class LayoutApplicationController {
    private enum Constants {
        static let verificationTolerancePixels: CGFloat = 8
        static let enableDirectMouseMoveEnvironmentKey = "CORONA_ENABLE_DIRECT_MOUSE_MOVE"
    }

    private let cacheController: MenuBarCacheController
    private let layoutStore: LayoutPersistenceStore
    private let settingsStore: SettingsStore
    private let boundaryProvider: @MainActor () -> SectionBoundary?
    private let boundaryItemsProvider: @MainActor () -> [MenuBarSection: MenuBarItem]
    private let executor: MoveEventExecutor
    private let logger: DiagnosticLogging
    private let planner = LayoutApplicationPlanner()

    init(
        cacheController: MenuBarCacheController,
        layoutStore: LayoutPersistenceStore,
        settingsStore: SettingsStore,
        boundaryProvider: @escaping @MainActor () -> SectionBoundary?,
        boundaryItemsProvider: @escaping @MainActor () -> [MenuBarSection: MenuBarItem],
        executor: MoveEventExecutor = DirectMoveEventExecutor(),
        logger: DiagnosticLogging = DisabledDiagnosticLogger()
    ) {
        self.cacheController = cacheController
        self.layoutStore = layoutStore
        self.settingsStore = settingsStore
        self.boundaryProvider = boundaryProvider
        self.boundaryItemsProvider = boundaryItemsProvider
        self.executor = executor
        self.logger = logger
    }

    func applySavedLayout(maxSteps: Int = 20) async -> LayoutApplicationResult {
        let limit = max(1, maxSteps)
        var moveCount = 0
        CoronaDebugLog.log("layout.applySavedLayout start maxSteps=\(limit)")
        let pendingResult = await recoverPendingRelocations(maxSteps: limit)
        CoronaDebugLog.log("layout.applySavedLayout pendingResult=\(pendingResult.statusTitle)")

        switch pendingResult {
        case .moved:
            moveCount += 1
        case .applied(let count):
            moveCount += count
        case .satisfied:
            break
        case .waitingForItem, .waitingForDestination, .missingBoundary, .failed:
            return pendingResult
        }

        for _ in 0..<limit {
            let result = await applyNextStep()
            CoronaDebugLog.log("layout.applySavedLayout stepResult=\(result.statusTitle)")
            switch result {
            case .moved:
                moveCount += 1
                continue
            case .satisfied:
                return moveCount > 0 ? .applied(moveCount) : .satisfied
            case .waitingForItem, .waitingForDestination, .missingBoundary, .failed:
                return result
            case .applied:
                return result
            }
        }

        return .failed("maxStepsExceeded")
    }

    func applySingleMove(uid: String, desiredOrder: SectionOrder) async -> LayoutApplicationResult {
        layoutStore.saveSavedSectionOrder(desiredOrder)
        layoutStore.saveKnownItemIdentifiers(Set(desiredOrder.visible + desiredOrder.hidden + desiredOrder.alwaysHidden))
        CoronaDebugLog.log("layout.applySingleMove savedIntent uid=\(uid) visible=\(desiredOrder.visible) hidden=\(desiredOrder.hidden) alwaysHidden=\(desiredOrder.alwaysHidden)")
        return await applySavedLayout()
    }

    func reveal(uid: String, maxSteps: Int = 8) async -> LayoutApplicationResult {
        guard let boundary = await boundaryProvider() else {
            return .missingBoundary
        }

        let limit = max(1, maxSteps)
        var moveCount = 0

        for _ in 0..<limit {
            do {
                let cache = try await cacheController.cache(boundary: boundary)
                guard cache.item(withStableIdentifier: uid) != nil else {
                    return moveCount > 0 ? .applied(moveCount) : .waitingForItem(uid)
                }

                let currentOrder = SectionOrder(cache: cache)
                if currentOrder.visible.contains(uid) {
                    return moveCount > 0 ? .applied(moveCount) : .satisfied
                }
                if moveCount == 0, let originalSection = currentOrder.section(containing: uid) {
                    layoutStore.savePendingRelocation(.section(originalSection), for: uid)
                }

                let desiredOrder = visibleRevealOrder(uid: uid, currentOrder: currentOrder)
                let step = planner.nextStep(
                    cache: cache,
                    preference: LayoutPreference(savedOrder: desiredOrder, alwaysHiddenEnabled: true),
                    sectionBoundaries: await boundaryItemsProvider()
                )

                let result = await apply(step: step, cache: cache, boundary: boundary)
                switch result {
                case .moved:
                    moveCount += 1
                    continue
                case .satisfied:
                    return moveCount > 0 ? .applied(moveCount) : .satisfied
                case .waitingForItem, .waitingForDestination, .missingBoundary, .failed:
                    return result
                case .applied:
                    return .applied(moveCount)
                }
            } catch {
                return .failed(String(describing: error))
            }
        }

        return .failed("maxStepsExceeded")
    }

    private func applyNextStep() async -> LayoutApplicationResult {
        guard let boundary = await boundaryProvider() else {
            CoronaDebugLog.log("layout.applyNextStep missingBoundary")
            return .missingBoundary
        }

        do {
            let cache = try await cacheController.cache(boundary: boundary)
            guard boundary.isOnSameDisplay(as: cache.displayID) else {
                CoronaDebugLog.log("layout.applyNextStep boundaryDisplayMismatch displayID=\(cache.displayID.map(String.init) ?? "nil") hidden=\(boundary.hiddenControlBounds.debugDescription) alwaysHidden=\(boundary.alwaysHiddenControlBounds?.debugDescription ?? "nil")")
                return .missingBoundary
            }
            let manageableCache = cache.keepingOnlyManageableItems()
            CoronaDebugLog.log("layout.applyNextStep boundary hidden=\(boundary.hiddenControlBounds.debugDescription) alwaysHidden=\(boundary.alwaysHiddenControlBounds?.debugDescription ?? "nil")")
            CoronaDebugLog.log("layout.applyNextStep cache visible=\(cache.visibleItems.map(\.tag.stableIdentifier)) hidden=\(cache.hiddenItems.map(\.tag.stableIdentifier)) alwaysHidden=\(cache.alwaysHiddenItems.map(\.tag.stableIdentifier))")
            if manageableCache.allItems.count != cache.allItems.count {
                let skipped = Set(cache.allItems.map(\.tag.stableIdentifier)).subtracting(manageableCache.allItems.map(\.tag.stableIdentifier))
                CoronaDebugLog.log("layout.applyNextStep skippedUnmanageable=\(skipped.sorted())")
            }
            let preference = layoutPreference(pruningUnavailableItemsIn: manageableCache)
            CoronaDebugLog.log("layout.applyNextStep preference visible=\(preference.savedOrder.visible) hidden=\(preference.savedOrder.hidden) alwaysHidden=\(preference.savedOrder.alwaysHidden)")
            let step = planner.nextStep(
                cache: manageableCache,
                preference: preference,
                sectionBoundaries: await boundaryItemsProvider()
            )
            CoronaDebugLog.log("layout.applyNextStep planned=\(debugDescription(for: step))")

            switch step {
            case .satisfied:
                return .satisfied
            case .waitingForItem(let uid):
                return .waitingForItem(uid)
            case .waitingForDestination:
                return .waitingForDestination
            case .move:
                return await apply(step: step, cache: manageableCache, boundary: boundary)
            }
        } catch {
            CoronaDebugLog.log("layout.applyNextStep failed error=\(String(describing: error))")
            return .failed(String(describing: error))
        }
    }

    private func apply(
        step: LayoutApplicationStep,
        cache: ItemCache,
        boundary: SectionBoundary
    ) async -> LayoutApplicationResult {
        switch step {
        case .satisfied:
            return .satisfied
        case .waitingForItem(let uid):
            return .waitingForItem(uid)
        case .waitingForDestination:
            return .waitingForDestination
        case .move(let resolvedMove):
            logger.log(.moveStarted(uid: resolvedMove.plannedMove.itemUID, target: resolvedMove.plannedMove.target))
            CoronaDebugLog.log("layout.move start uid=\(resolvedMove.plannedMove.itemUID) target=\(resolvedMove.plannedMove.target) destination=\(debugDescription(for: resolvedMove.destination)) itemBounds=\(resolvedMove.item.bounds.debugDescription)")
            let fallbackResult = await PersistentMenuBarLayoutFallback().apply(
                desiredOrder: layoutStore.loadSavedSectionOrder(),
                movedUID: resolvedMove.plannedMove.itemUID
            )
            CoronaDebugLog.log("layout.move persistentFallback result=\(fallbackResult.debugDescription)")
            if fallbackResult.didApply {
                return .moved(resolvedMove.plannedMove.itemUID)
            }

            guard Self.directMouseMoveEnabled else {
                logger.log(.moveFinished(uid: resolvedMove.plannedMove.itemUID, success: false))
                CoronaDebugLog.log("layout.move skippedDirectMouse uid=\(resolvedMove.plannedMove.itemUID) fallback=\(fallbackResult.debugDescription)")
                return .failed("backgroundMoveUnavailable; direct mouse move disabled")
            }

            var lastError: Error?
            for attempt in 0..<3 {
                do {
                    let latestCache = attempt == 0 ? cache : try await cacheController.cache(boundary: boundary)
                    let latestItem = latestCache.item(withStableIdentifier: resolvedMove.plannedMove.itemUID) ?? resolvedMove.item
                    CoronaDebugLog.log("layout.move attempt=\(attempt + 1) uid=\(resolvedMove.plannedMove.itemUID) latestBounds=\(latestItem.bounds.debugDescription)")
                    try await executor.move(
                        item: latestItem,
                        to: resolvedMove.destination,
                        on: latestCache.displayID,
                        skipInputPause: false,
                        maxAttempts: 1
                    )
                    let refreshedCache = try await cacheController.cache(boundary: boundary)
                    CoronaDebugLog.log("layout.move refreshed visible=\(refreshedCache.visibleItems.map(\.tag.stableIdentifier)) hidden=\(refreshedCache.hiddenItems.map(\.tag.stableIdentifier)) alwaysHidden=\(refreshedCache.alwaysHiddenItems.map(\.tag.stableIdentifier))")
                    let destinationSatisfied = resolvedMove.destination.isSatisfied(
                        for: resolvedMove.plannedMove.itemUID,
                        in: refreshedCache,
                        tolerancePixels: Constants.verificationTolerancePixels
                    )
                    let targetSectionSatisfied = targetSectionIsSatisfied(
                        for: resolvedMove.plannedMove,
                        in: refreshedCache,
                        boundary: boundary
                    )
                    if destinationSatisfied && targetSectionSatisfied {
                        logger.log(.moveFinished(uid: resolvedMove.plannedMove.itemUID, success: true))
                        CoronaDebugLog.log("layout.move success uid=\(resolvedMove.plannedMove.itemUID)")
                        return .moved(resolvedMove.plannedMove.itemUID)
                    }
                    CoronaDebugLog.log("layout.move mismatch uid=\(resolvedMove.plannedMove.itemUID) destinationSatisfied=\(destinationSatisfied) targetSectionSatisfied=\(targetSectionSatisfied)")
                    lastError = MoveExecutorError.finalPositionMismatch
                } catch {
                    CoronaDebugLog.log("layout.move error attempt=\(attempt + 1) uid=\(resolvedMove.plannedMove.itemUID) error=\(String(describing: error))")
                    lastError = error
                }
            }

            logger.log(.moveFinished(uid: resolvedMove.plannedMove.itemUID, success: false))
            CoronaDebugLog.log("layout.move failed uid=\(resolvedMove.plannedMove.itemUID) lastError=\(String(describing: lastError ?? MoveExecutorError.finalPositionMismatch))")
            return .failed(String(describing: lastError ?? MoveExecutorError.finalPositionMismatch))
        }
    }

    private static var directMouseMoveEnabled: Bool {
        ProcessInfo.processInfo.environment[Constants.enableDirectMouseMoveEnvironmentKey] == "1"
    }

    private func targetSectionIsSatisfied(
        for move: LayoutMove,
        in cache: ItemCache,
        boundary: SectionBoundary
    ) -> Bool {
        guard case .sectionBoundary(let section) = move.target else {
            return true
        }
        guard let item = cache.item(withStableIdentifier: move.itemUID) else {
            return false
        }
        if cache.section(containing: move.itemUID) == section {
            return true
        }
        return tolerantSection(for: item.bounds, boundary: boundary) == section
    }

    private func tolerantSection(for itemBounds: CGRect, boundary: SectionBoundary) -> MenuBarSection {
        let tolerance = Constants.verificationTolerancePixels
        let hidden = boundary.hiddenControlBounds
        guard let alwaysHidden = boundary.alwaysHiddenControlBounds else {
            if itemBounds.maxX <= hidden.minX + tolerance {
                return .hidden
            }
            return .visible
        }

        if alwaysHidden.minX < hidden.minX {
            if itemBounds.maxX <= alwaysHidden.minX + tolerance {
                return .alwaysHidden
            }
            if itemBounds.maxX <= hidden.minX + tolerance {
                return .hidden
            }
            return .visible
        }

        if itemBounds.maxX <= hidden.minX + tolerance {
            return .alwaysHidden
        }
        if itemBounds.maxX <= alwaysHidden.minX + tolerance {
            return .hidden
        }
        return .visible
    }

    private func debugDescription(for step: LayoutApplicationStep) -> String {
        switch step {
        case .satisfied(let order):
            return "satisfied visible=\(order.visible) hidden=\(order.hidden) alwaysHidden=\(order.alwaysHidden)"
        case .waitingForItem(let uid):
            return "waitingForItem uid=\(uid)"
        case .waitingForDestination(let target):
            return "waitingForDestination target=\(target)"
        case .move(let move):
            return "move uid=\(move.plannedMove.itemUID) target=\(move.plannedMove.target) destination=\(debugDescription(for: move.destination))"
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

    private func recoverPendingRelocations(maxSteps: Int) async -> LayoutApplicationResult {
        var pending = layoutStore.loadPendingRelocations()
        guard !pending.isEmpty else { return .satisfied }
        guard let boundary = await boundaryProvider() else {
            return .missingBoundary
        }

        var moveCount = 0
        let limit = max(1, maxSteps)
        for _ in 0..<limit {
            do {
                let cache = try await cacheController.cache(boundary: boundary)
                let currentOrder = SectionOrder(cache: cache)

                pending = pending.reduce(into: [String: PendingRelocation]()) { result, entry in
                    let uid = entry.key
                    let relocation = entry.value
                    guard let item = cache.item(withStableIdentifier: uid),
                          relocation.shouldAttemptRecovery(currentWindowID: item.windowID) else {
                        return
                    }
                    if currentOrder[relocation.targetSection].contains(uid) {
                        layoutStore.savePendingRelocation(nil, for: uid)
                        return
                    }
                    result[uid] = relocation
                }

                guard let entry = pending.first else {
                    return moveCount > 0 ? .applied(moveCount) : .satisfied
                }

                let desiredOrder = pendingRecoveryOrder(
                    uid: entry.key,
                    targetSection: entry.value.targetSection,
                    currentOrder: currentOrder
                )
                let step = planner.nextStep(
                    cache: cache,
                    preference: LayoutPreference(savedOrder: desiredOrder, alwaysHiddenEnabled: true),
                    sectionBoundaries: await boundaryItemsProvider()
                )

                let result = await apply(step: step, cache: cache, boundary: boundary)
                switch result {
                case .moved:
                    moveCount += 1
                    continue
                case .satisfied:
                    layoutStore.savePendingRelocation(nil, for: entry.key)
                    pending.removeValue(forKey: entry.key)
                    continue
                case .waitingForItem, .waitingForDestination, .missingBoundary, .failed:
                    return result
                case .applied(let count):
                    moveCount += count
                }
            } catch {
                return .failed(String(describing: error))
            }
        }

        return .failed("maxStepsExceeded")
    }

    private func pendingRecoveryOrder(
        uid: String,
        targetSection: MenuBarSection,
        currentOrder: SectionOrder
    ) -> SectionOrder {
        var order = currentOrder
        for section in MenuBarSection.allCases {
            order[section].removeAll { $0 == uid }
        }
        order[targetSection].insert(uid, at: 0)
        return order
    }

    private func visibleRevealOrder(uid: String, currentOrder: SectionOrder) -> SectionOrder {
        var order = currentOrder
        for section in MenuBarSection.allCases {
            order[section].removeAll { $0 == uid }
        }
        order.visible.insert(uid, at: 0)
        return order
    }

    private func layoutPreference() -> LayoutPreference {
        let settings = settingsStore.load()
        return LayoutPreference(
            savedOrder: layoutStore.loadSavedSectionOrder(),
            newItemsSection: MenuBarSection(settings.newItemsSection),
            newItemsPlacement: settings.newItemsPlacement,
            alwaysHiddenEnabled: settings.enableAlwaysHiddenSection
        )
    }

    private func layoutPreference(pruningUnavailableItemsIn cache: ItemCache) -> LayoutPreference {
        var preference = layoutPreference()
        let availableUIDs = Set(cache.allItems.map(\.tag.stableIdentifier))
        let hideableUIDs = Set(cache.allItems.filter(\.canBeHidden).map(\.tag.stableIdentifier))
        let originalOrder = preference.savedOrder
        preference.savedOrder = originalOrder.keepingOnlyAvailableUIDs(availableUIDs)
        let nonHideableRequestedHidden = (preference.savedOrder.hidden + preference.savedOrder.alwaysHidden)
            .filter { !hideableUIDs.contains($0) }
        if !nonHideableRequestedHidden.isEmpty {
            preference.savedOrder.hidden.removeAll { nonHideableRequestedHidden.contains($0) }
            preference.savedOrder.alwaysHidden.removeAll { nonHideableRequestedHidden.contains($0) }
            for uid in nonHideableRequestedHidden where !preference.savedOrder.visible.contains(uid) {
                preference.savedOrder.visible.append(uid)
            }
            CoronaDebugLog.log("layout.preference forcedNonHideableVisible=\(nonHideableRequestedHidden.sorted())")
        }

        let removedUIDs = Set(originalOrder.allUIDs).subtracting(preference.savedOrder.allUIDs)
        if !removedUIDs.isEmpty {
            CoronaDebugLog.log("layout.preference prunedUnavailable=\(removedUIDs.sorted())")
        }

        return preference
    }

}

private extension MenuBarSection {
    init(_ newItemsSection: NewItemsSection) {
        switch newItemsSection {
        case .visible:
            self = .visible
        case .hidden:
            self = .hidden
        case .alwaysHidden:
            self = .alwaysHidden
        }
    }
}

private extension SectionOrder {
    var allUIDs: [String] {
        visible + hidden + alwaysHidden
    }

    func keepingOnlyAvailableUIDs(_ availableUIDs: Set<String>) -> SectionOrder {
        SectionOrder(
            visible: visible.filter { availableUIDs.contains($0) },
            hidden: hidden.filter { availableUIDs.contains($0) },
            alwaysHidden: alwaysHidden.filter { availableUIDs.contains($0) }
        )
    }
}

private extension ItemCache {
    func keepingOnlyManageableItems() -> ItemCache {
        ItemCache(
            displayID: displayID,
            visibleItems: visibleItems.filter(\.isManageableByCorona),
            hiddenItems: hiddenItems.filter(\.isManageableByCorona),
            alwaysHiddenItems: alwaysHiddenItems.filter(\.isManageableByCorona)
        )
    }

    func section(containing uid: String) -> MenuBarSection? {
        if visibleItems.contains(where: { $0.tag.stableIdentifier == uid }) {
            return .visible
        }
        if hiddenItems.contains(where: { $0.tag.stableIdentifier == uid }) {
            return .hidden
        }
        if alwaysHiddenItems.contains(where: { $0.tag.stableIdentifier == uid }) {
            return .alwaysHidden
        }
        return nil
    }
}

private extension MenuBarItem {
    var isManageableByCorona: Bool {
        isMovable && canBeHidden
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
    }
}

private extension SectionBoundary {
    func isOnSameDisplay(as displayID: UInt32?) -> Bool {
        let displayFrame = displayID.map(CGDisplayBounds) ?? CGDisplayBounds(CGMainDisplayID())
        guard hiddenControlBounds.intersects(displayFrame) else { return false }
        if let alwaysHiddenControlBounds {
            return alwaysHiddenControlBounds.intersects(displayFrame)
        }
        return true
    }
}

private struct PersistentMenuBarLayoutFallback {
    private static let enabledEnvironmentKey = "CORONA_ENABLE_CONTROL_CENTER_PLIST_FALLBACK"
    private static let domain = "com.apple.controlcenter"
    private static let candidateOrderKeys = [
        "NSStatusItem Preferred Position Item-Ordering",
        "NSStatusItem Visible Item-Ordering",
        "MenuExtras",
        "menuExtras"
    ]

    func apply(desiredOrder: SectionOrder, movedUID: String) async -> Result {
        guard ProcessInfo.processInfo.environment[Self.enabledEnvironmentKey] == "1" else {
            return .disabled
        }

        let desiredUIDs = desiredOrder.visible + desiredOrder.hidden + desiredOrder.alwaysHidden
        guard !desiredUIDs.isEmpty else {
            return .unavailable("emptyDesiredOrder")
        }

        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(Self.domain).plist")
        guard let plist = NSMutableDictionary(contentsOf: url) else {
            return .unavailable("missingPlist:\(url.path)")
        }

        for key in Self.candidateOrderKeys {
            guard let currentArray = plist[key] as? [String], !currentArray.isEmpty else {
                continue
            }

            let reordered = reorderedSystemArray(currentArray, desiredUIDs: desiredUIDs)
            guard reordered != currentArray else {
                continue
            }

            plist[key] = reordered
            guard plist.write(to: url, atomically: true) else {
                return .failed("writeFailed:\(url.path)")
            }

            CFPreferencesAppSynchronize(Self.domain as CFString)
            notifyControlCenterReload()
            return .applied(key: key, movedUID: movedUID)
        }

        return .unavailable("noKnownOrderArray")
    }

    private func reorderedSystemArray(_ currentArray: [String], desiredUIDs: [String]) -> [String] {
        let rankByToken = Dictionary(uniqueKeysWithValues: desiredUIDs.enumerated().flatMap { index, uid in
            identifierTokens(for: uid).map { ($0, index) }
        })

        return currentArray.enumerated().sorted { lhs, rhs in
            let lhsRank = bestRank(for: lhs.element, rankByToken: rankByToken) ?? Int.max
            let rhsRank = bestRank(for: rhs.element, rankByToken: rankByToken) ?? Int.max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private func bestRank(for systemIdentifier: String, rankByToken: [String: Int]) -> Int? {
        let lowercased = systemIdentifier.lowercased()
        return rankByToken.compactMap { token, rank in
            lowercased.contains(token) ? rank : nil
        }.min()
    }

    private func identifierTokens(for uid: String) -> [String] {
        uid.lowercased()
            .split(separator: ":")
            .map(String.init)
            .filter { $0.count >= 4 && !$0.hasPrefix("item-") }
    }

    private func notifyControlCenterReload() {
        let notification = "com.apple.controlcenter.preferences-changed" as CFString
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDistributedCenter(),
            CFNotificationName(notification),
            nil,
            nil,
            true
        )

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["ControlCenter"]
        try? task.run()
    }

    enum Result {
        case disabled
        case unavailable(String)
        case failed(String)
        case applied(key: String, movedUID: String)

        var didApply: Bool {
            if case .applied = self {
                return true
            }
            return false
        }

        var debugDescription: String {
            switch self {
            case .disabled:
                return "disabled"
            case .unavailable(let reason):
                return "unavailable(\(reason))"
            case .failed(let reason):
                return "failed(\(reason))"
            case .applied(let key, let movedUID):
                return "applied key=\(key) movedUID=\(movedUID)"
            }
        }
    }
}
