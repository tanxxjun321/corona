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

        for _ in 0..<limit {
            let result = await applyNextStep()
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

    private func applyNextStep() async -> LayoutApplicationResult {
        guard let boundary = await boundaryProvider() else {
            return .missingBoundary
        }

        do {
            let cache = try await cacheController.cache(boundary: boundary)
            let preference = layoutPreference()
            let step = planner.nextStep(
                cache: cache,
                preference: preference,
                sectionBoundaries: await boundaryItemsProvider()
            )

            switch step {
            case .satisfied:
                return .satisfied
            case .waitingForItem(let uid):
                return .waitingForItem(uid)
            case .waitingForDestination:
                return .waitingForDestination
            case .move(let resolvedMove):
                logger.log(.moveStarted(uid: resolvedMove.plannedMove.itemUID, target: resolvedMove.plannedMove.target))
                do {
                    try await executor.move(
                        item: resolvedMove.item,
                        to: resolvedMove.destination,
                        on: cache.displayID,
                        skipInputPause: false,
                        maxAttempts: 3
                    )
                    logger.log(.moveFinished(uid: resolvedMove.plannedMove.itemUID, success: true))
                    _ = try? await cacheController.cache(boundary: boundary)
                    return .moved(resolvedMove.plannedMove.itemUID)
                } catch {
                    logger.log(.moveFinished(uid: resolvedMove.plannedMove.itemUID, success: false))
                    return .failed(String(describing: error))
                }
            }
        } catch {
            return .failed(String(describing: error))
        }
    }

    private func layoutPreference() -> LayoutPreference {
        let settings = settingsStore.load()
        return LayoutPreference(
            savedOrder: layoutStore.loadSavedSectionOrder(),
            newItemsSection: MenuBarSection(settings.newItemsSection),
            newItemsPlacement: .append,
            alwaysHiddenEnabled: settings.enableAlwaysHiddenSection
        )
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
