import AppKit
import Foundation
import CoronaCore

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
                return moveCount > 0 ? .applied(moveCount) : result
            case .applied:
                return result
            }
        }

        return moveCount > 0 ? .applied(moveCount) : .satisfied
    }

    func applySingleMove(uid: String, desiredOrder: SectionOrder) async -> LayoutApplicationResult {
        guard let boundary = await boundaryProvider() else {
            CoronaDebugLog.log("layout.applySingleMove missingBoundary uid=\(uid)")
            return .missingBoundary
        }

        do {
            let cache = try await cacheController.cache(boundary: boundary)
            let manageableCache = cache.keepingOnlyManageableItems()
            guard let item = manageableCache.item(withStableIdentifier: uid) else {
                CoronaDebugLog.log("layout.applySingleMove waitingForItem uid=\(uid)")
                return .waitingForItem(uid)
            }

            let availableUIDs = Set(manageableCache.allItems.map(\.tag.stableIdentifier))
            let desired = desiredOrder.keepingOnlyAvailableUIDs(availableUIDs)
            guard let targetSection = desired.section(containing: uid) else {
                CoronaDebugLog.log("layout.applySingleMove targetMissing uid=\(uid)")
                return .waitingForItem(uid)
            }

            if targetSection != .visible, !item.canBeHidden {
                CoronaDebugLog.log("layout.applySingleMove rejectedNonHideable uid=\(uid) target=\(targetSection)")
                return .failed("Item cannot be hidden")
            }

            let target = singleMoveTarget(uid: uid, section: targetSection, desiredOrder: desired, cache: manageableCache)
            guard let destination = MoveDestinationResolver().resolve(
                target: target,
                cache: manageableCache,
                sectionBoundaries: await boundaryItemsProvider()
            ) else {
                CoronaDebugLog.log("layout.applySingleMove waitingForDestination uid=\(uid) target=\(target)")
                return .waitingForDestination
            }

            let move = LayoutMove(itemUID: uid, target: target)
            CoronaDebugLog.log("layout.applySingleMove uid=\(uid) target=\(target) destination=\(debugDescription(for: destination))")
            return await apply(
                step: .move(ResolvedLayoutMove(plannedMove: move, item: item, destination: destination)),
                cache: manageableCache,
                boundary: boundary
            )
        } catch {
            CoronaDebugLog.log("layout.applySingleMove failed uid=\(uid) error=\(String(describing: error))")
            return .failed(String(describing: error))
        }
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
                    return moveCount > 0 ? .applied(moveCount) : result
                case .applied:
                    return .applied(moveCount)
                }
            } catch {
                return moveCount > 0 ? .applied(moveCount) : .failed(String(describing: error))
            }
        }

        return moveCount > 0 ? .applied(moveCount) : .satisfied
    }

    private func applyNextStep() async -> LayoutApplicationResult {
        guard let boundary = await boundaryProvider() else {
            CoronaDebugLog.log("layout.applyNextStep missingBoundary")
            return .missingBoundary
        }

        do {
            let cache = try await cacheController.cache(boundary: boundary)
            let manageableCache = cache.keepingOnlyManageableItems()
            CoronaDebugLog.log("layout.applyNextStep boundary hidden=\(boundary.hiddenControlBounds.debugDescription) alwaysHidden=\(boundary.alwaysHiddenControlBounds?.debugDescription ?? "nil")")
            CoronaDebugLog.log("layout.applyNextStep cache visible=\(cache.visibleItems.map(\.tag.stableIdentifier)) hidden=\(cache.hiddenItems.map(\.tag.stableIdentifier)) alwaysHidden=\(cache.alwaysHiddenItems.map(\.tag.stableIdentifier))")
            if manageableCache.allItems.count != cache.allItems.count {
                let skipped = Set(cache.allItems.map(\.tag.stableIdentifier)).subtracting(manageableCache.allItems.map(\.tag.stableIdentifier))
                CoronaDebugLog.log("layout.applyNextStep skippedUnmanageable=\(skipped.sorted())")
            }
            let preference = layoutPreference(pruningUnavailableItemsIn: manageableCache)
            let currentOrder = SectionOrder(cache: manageableCache)
            var desiredOrder = sectionOnlyDesiredOrder(currentOrder: currentOrder, savedOrder: preference.savedOrder)
            desiredOrder = applyNotchOverflowIfNeeded(
                desiredOrder: desiredOrder,
                cache: cache,
                manageableCache: manageableCache,
                settings: settingsStore.load()
            )
            CoronaDebugLog.log("layout.applyNextStep preference visible=\(preference.savedOrder.visible) hidden=\(preference.savedOrder.hidden) alwaysHidden=\(preference.savedOrder.alwaysHidden)")
            CoronaDebugLog.log("layout.applyNextStep sectionOnlyDesired visible=\(desiredOrder.visible) hidden=\(desiredOrder.hidden) alwaysHidden=\(desiredOrder.alwaysHidden)")
            let step = planner.nextStep(
                cache: manageableCache,
                preference: LayoutPreference(
                    savedOrder: desiredOrder,
                    newItemsSection: preference.newItemsSection,
                    newItemsPlacement: preference.newItemsPlacement,
                    alwaysHiddenEnabled: preference.alwaysHiddenEnabled
                ),
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
                    let destinationSatisfied = resolvedMove.destination.isSatisfied(for: resolvedMove.plannedMove.itemUID, in: refreshedCache)
                    let targetSectionSatisfied = targetSectionIsSatisfied(
                        for: resolvedMove.plannedMove,
                        in: refreshedCache
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

    private func targetSectionIsSatisfied(for move: LayoutMove, in cache: ItemCache) -> Bool {
        guard case .sectionBoundary(let section) = move.target else {
            return true
        }
        return cache.section(containing: move.itemUID) == section
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
                    return moveCount > 0 ? .applied(moveCount) : result
                case .applied(let count):
                    moveCount += count
                }
            } catch {
                return moveCount > 0 ? .applied(moveCount) : .failed(String(describing: error))
            }
        }

        return moveCount > 0 ? .applied(moveCount) : .satisfied
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

    private func singleMoveTarget(
        uid: String,
        section: MenuBarSection,
        desiredOrder: SectionOrder,
        cache: ItemCache
    ) -> LayoutTarget {
        guard let index = desiredOrder[section].firstIndex(of: uid), index > desiredOrder[section].startIndex else {
            return .sectionBoundary(section)
        }

        if section == .visible,
           let terminalSystemAnchor = terminalSystemAnchorBeforeEnd(uid: uid, desiredOrder: desiredOrder, cache: cache) {
            return .leftOfUID(terminalSystemAnchor)
        }

        return .rightOfUID(desiredOrder[section][desiredOrder[section].index(before: index)])
    }

    private func terminalSystemAnchorBeforeEnd(
        uid: String,
        desiredOrder: SectionOrder,
        cache: ItemCache
    ) -> String? {
        var visible = desiredOrder.visible
        guard let insertionIndex = visible.firstIndex(of: uid),
              insertionIndex == visible.index(before: visible.endIndex) else {
            return nil
        }

        visible.remove(at: insertionIndex)
        guard !visible.isEmpty else { return nil }

        var suffixStart = visible.endIndex
        while suffixStart > visible.startIndex {
            let previousIndex = visible.index(before: suffixStart)
            guard let item = cache.item(withStableIdentifier: visible[previousIndex]),
                  !item.canBeHidden else {
                break
            }
            suffixStart = previousIndex
        }

        guard suffixStart < visible.endIndex else { return nil }
        return visible[suffixStart]
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

    private func sectionOnlyDesiredOrder(currentOrder: SectionOrder, savedOrder: SectionOrder) -> SectionOrder {
        let savedSectionByUID = savedOrder.sectionMap
        var result = SectionOrder()
        for section in MenuBarSection.allCases {
            for uid in currentOrder[section] {
                let targetSection = savedSectionByUID[uid] ?? section
                result[targetSection].append(uid)
            }
        }
        return result
    }

    private func applyNotchOverflowIfNeeded(
        desiredOrder: SectionOrder,
        cache: ItemCache,
        manageableCache: ItemCache,
        settings: AppSettings
    ) -> SectionOrder {
        guard settings.enableNotchOverflow,
              let screen = screen(for: cache.displayID),
              screen.hasNotch,
              let notch = screen.frameOfNotch
        else {
            return desiredOrder
        }

        let rightBoundary = menuBarRightBoundary(cache: cache, notch: notch, screen: screen)
        let notchGap: CGFloat = 24
        let availableWidth = rightBoundary - (notch.maxX + notchGap)
        let visibleUIDs = Set(desiredOrder.visible)
        let itemWidths = Dictionary(uniqueKeysWithValues: cache.allItems.map { item in
            (item.tag.stableIdentifier, item.bounds.width)
        })
        let hideableUIDs = Set(
            manageableCache.allItems
                .filter { $0.canBeHidden && visibleUIDs.contains($0.tag.stableIdentifier) }
                .map(\.tag.stableIdentifier)
        )

        let plan = NotchOverflowPlanner().plan(
            desiredOrder: desiredOrder,
            itemWidths: itemWidths,
            hideableUIDs: hideableUIDs,
            availableWidth: availableWidth
        )
        if !plan.overflowUIDs.isEmpty {
            CoronaDebugLog.log("layout.notchOverflow availableWidth=\(availableWidth) rightBoundary=\(rightBoundary) notch=\(notch.debugDescription) overflow=\(plan.overflowUIDs)")
        }
        return plan.order
    }

    private func screen(for displayID: UInt32?) -> NSScreen? {
        if let displayID,
           let screen = NSScreen.screens.first(where: { UInt32($0.displayID) == displayID }) {
            return screen
        }
        return NSScreen.main
    }

    private func menuBarRightBoundary(cache: ItemCache, notch: CGRect, screen: NSScreen) -> CGFloat {
        let protectedVisibleItems = cache.allItems.filter { item in
            guard item.bounds.minX >= notch.maxX else { return false }
            return !item.canBeHidden
        }
        if let firstProtected = protectedVisibleItems.min(by: { $0.bounds.minX < $1.bounds.minX }) {
            return firstProtected.bounds.minX
        }
        return screen.frame.maxX
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

    var sectionMap: [String: MenuBarSection] {
        var result: [String: MenuBarSection] = [:]
        for section in MenuBarSection.allCases {
            for uid in self[section] {
                result[uid] = section
            }
        }
        return result
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
        isMovable
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
    }

    var hasNotch: Bool {
        auxiliaryTopLeftArea != nil
    }

    var frameOfNotch: CGRect? {
        guard let auxiliaryTopLeftArea,
              let auxiliaryTopRightArea else {
            return nil
        }

        return CGRect(
            x: auxiliaryTopLeftArea.maxX,
            y: frame.maxY - safeAreaInsets.top,
            width: auxiliaryTopRightArea.minX - auxiliaryTopLeftArea.maxX,
            height: safeAreaInsets.top
        )
    }
}
