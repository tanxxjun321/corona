import AppKit

enum StatusItemDefaults {
    static func ensurePreferredPosition(_ position: CGFloat, autosaveName: String) {
        let key = "NSStatusItem Preferred Position \(autosaveName)"
        guard UserDefaults.standard.object(forKey: key) == nil else { return }
        UserDefaults.standard.set(position, forKey: key)
    }
}

@MainActor
final class MenuBarController {
    private enum E2ENotification {
        static let collapseHiddenSections = Notification.Name("com.ltz.corona.e2e.collapseHiddenSections")
        static let hiddenSectionsCollapsed = Notification.Name("com.ltz.corona.e2e.hiddenSectionsCollapsed")
    }

    private let settingsStore: SettingsStore
    private let permissionChecker: SystemPermissionChecker
    private let statusItem: NSStatusItem
    private let sectionController: StatusSectionController
    private let cacheController: MenuBarCacheController
    private let layoutStore: LayoutPersistenceStore
    private let thumbnailProvider: MenuBarThumbnailProviding
    private var settings: AppSettings
    private var mainPanelWindowController: MainPanelWindowController?
    private var hiddenItemsHoverBarController: HiddenItemsHoverBarController?
    private var layoutApplicationController: LayoutApplicationController?
    private var lastLayoutApplicationResult: LayoutApplicationResult?
    private var autoRehideTask: Task<Void, Never>?
    private var startupLayoutRestoreTask: Task<Void, Never>?
    /// The single in-flight apply session (an apply attempt plus its backoff
    /// retries). All apply entry points funnel through `requestApplySession`
    /// so two applies never run concurrently (#18).
    private var applySessionTask: Task<LayoutApplicationResult, Never>?
    private var applyRetryPolicy = LayoutApplyRetryPolicy()
    /// Set when an apply session exhausted its retries; drives the status
    /// item warning and the panel error until the next successful apply.
    private var persistentApplyFailure: LayoutApplicationResult?

    private enum BoundaryStabilityTiming {
        static let pollIntervalNanoseconds: UInt64 = 40_000_000
        static let requiredStableSamples = 3
        static let timeoutSeconds: TimeInterval = 2.5
    }

    private enum StabilityTiming {
        static let initialDelayNanoseconds: UInt64 = 180_000_000
        static let pollIntervalNanoseconds: UInt64 = 100_000_000
        static let requiredStableSamples = 4
        static let maxPolls = 18
    }

    init(
        settingsStore: SettingsStore,
        permissionChecker: SystemPermissionChecker
    ) {
        self.settingsStore = settingsStore
        self.permissionChecker = permissionChecker
        StatusItemDefaults.ensurePreferredPosition(0, autosaveName: "CoronaStatusItem")
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem.autosaveName = "CoronaStatusItem"
        self.sectionController = StatusSectionController()
        self.sectionController.ensureSpacerCoverage(displayWidth: BuiltInMenuBarDisplay.target().frame.width)
        self.cacheController = MenuBarCacheController(provider: PublicMenuBarDiscoveryProvider())
        self.layoutStore = UserDefaultsLayoutPersistenceStore()
        self.thumbnailProvider = MenuBarThumbnailProvider(
            settingsStore: settingsStore,
            permissionChecker: permissionChecker
        )
        self.settings = settingsStore.load()
    }

    func start() {
        configureStatusItem()
        installE2EObserversIfNeeded()
        sectionController.setAlwaysHiddenSectionEnabled(settings.enableAlwaysHiddenSection)
        sanitizeSavedLayout()
        startHiddenItemsHoverBar()
        rebuildMenu()
        scheduleStartupLayoutRestoreIfNeeded()
        showPermissionsOnFirstLaunchIfNeeded()
        showMainPanelOnLaunchIfReady()
    }

    deinit {
        autoRehideTask?.cancel()
        startupLayoutRestoreTask?.cancel()
        applySessionTask?.cancel()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        statusItem.length = NSStatusItem.squareLength
        button.image = Self.statusImage(named: "menubar.rectangle", accessibilityDescription: "Corona")
        button.image?.isTemplate = true
        button.toolTip = "Corona"
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func rebuildMenu() {
        updateStatusIcon(for: permissionChecker.snapshot())
    }

    private func makeStatusMenu() -> NSMenu {
        let snapshot = permissionChecker.snapshot()
        let menu = NSMenu()

        let mainPanel = NSMenuItem(
            title: "Organize Menu Bar...",
            action: #selector(openMainPanel),
            keyEquivalent: ""
        )
        mainPanel.target = self
        mainPanel.isEnabled = snapshot.canRunCoreFeatures
        menu.addItem(mainPanel)

        let quit = NSMenuItem(
            title: "Quit Corona",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func showPermissionsOnFirstLaunchIfNeeded() {
        guard !permissionChecker.snapshot().canRunCoreFeatures else { return }
        DispatchQueue.main.async { [weak self] in
            self?.openSettings()
        }
    }

    private func showMainPanelOnLaunchIfReady() {
        guard permissionChecker.snapshot().canRunCoreFeatures else { return }
        DispatchQueue.main.async { [weak self] in
            self?.openMainPanel()
        }
    }

    private func updateStatusIcon(for snapshot: PermissionSnapshot) {
        let symbolName: String
        let toolTip: String
        switch snapshot.capabilityStatus {
        case .missing:
            symbolName = "exclamationmark.triangle"
            toolTip = "Corona — Accessibility permission required"
        case .hasRequired, .hasAll:
            if persistentApplyFailure != nil {
                // Persistent apply failure (#18): warn until the next
                // successful apply clears it.
                symbolName = "exclamationmark.triangle.fill"
                toolTip = "Corona — saved layout could not be applied"
            } else {
                symbolName = "menubar.rectangle"
                toolTip = "Corona"
            }
        }
        statusItem.isVisible = settings.showMainIcon
        statusItem.length = NSStatusItem.squareLength
        statusItem.button?.image = Self.statusImage(named: symbolName, accessibilityDescription: "Corona")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = toolTip
    }

    private static func statusImage(named symbolName: String, accessibilityDescription: String) -> NSImage? {
        NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)
            ?? NSImage(systemSymbolName: "rectangle", accessibilityDescription: accessibilityDescription)
            ?? NSImage(named: NSImage.applicationIconName)
    }

    private func installE2EObserversIfNeeded() {
        guard ProcessInfo.processInfo.environment["CORONA_ENABLE_E2E_CONTROL"] == "1" else { return }
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(collapseHiddenSectionsForE2E),
            name: E2ENotification.collapseHiddenSections,
            object: nil
        )
    }

    @MainActor
    @objc private func collapseHiddenSectionsForE2E() {
        autoRehideTask?.cancel()
        sectionController.setHiddenSectionVisible(false)
        if settings.enableAlwaysHiddenSection {
            sectionController.setAlwaysHiddenSectionVisible(false)
        }
        rebuildMenu()
        DistributedNotificationCenter.default().postNotificationName(
            E2ENotification.hiddenSectionsCollapsed,
            object: Bundle.main.bundleIdentifier ?? "com.ltz.corona",
            userInfo: nil,
            deliverImmediately: true
        )
    }

    @MainActor
    private func showHiddenItems(attachedTo button: NSStatusBarButton? = nil) {
        sectionController.setHiddenSectionVisible(true)
        scheduleAutoRehideIfNeeded()
        rebuildMenu()
        if let button {
            hiddenItemsHoverBarController?.show(attachedTo: button)
        }
    }

    @MainActor
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            if let button = statusItem.button {
                makeStatusMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
            }
            return
        }

        guard permissionChecker.snapshot().canRunCoreFeatures else {
            openSettings()
            return
        }

        showHiddenItems(attachedTo: statusItem.button)
    }

    /// Re-entry path for the "icon hidden" state: launching Corona again while
    /// it is already running (Finder/Spotlight/`open`) must always surface a
    /// usable UI. We deliberately re-open the main panel unconditionally —
    /// when the icon is hidden this is the only way back in, and the panel
    /// itself offers to restore the icon (see MainPanelView's hidden-icon
    /// banner). Never gate this on `settings.showMainIcon`.
    func handleReopen() {
        openMainPanel()
    }

    @objc private func openMainPanel() {
        if mainPanelWindowController == nil {
            mainPanelWindowController = MainPanelWindowController(
                cacheController: cacheController,
                layoutStore: layoutStore,
                settingsStore: settingsStore,
                settings: settings,
                permissionChecker: permissionChecker,
                thumbnailProvider: thumbnailProvider,
                boundaryProvider: { [weak self] in
                    self?.sectionController.currentBoundary()
                },
                visualCacheProvider: { [weak self] in
                    guard let self else {
                        return ItemCache(displayID: nil, visibleItems: [], hiddenItems: [], alwaysHiddenItems: [])
                    }
                    return try await self.currentOrganizerMenuBarCache()
                },
                readOnlyCacheProvider: { [weak self] in
                    guard let self else {
                        return ItemCache(displayID: nil, visibleItems: [], hiddenItems: [], alwaysHiddenItems: [])
                    }
                    return try await self.currentMenuBarCacheWithoutChangingVisibility()
                },
                visualCacheCleanup: { },
                applyHandler: { [weak self] in
                    guard let self else { return .failed("Controller unavailable") }
                    let result = await self.requestApplySession()
                    self.rebuildMenu()
                    return result
                },
                applyMoveHandler: { [weak self] uid, desiredOrder in
                    guard let self else { return .failed("Controller unavailable") }
                    let result = await self.requestApplySession(
                        firstAttempt: { [weak self] in
                            guard let self else { return .failed("Controller unavailable") }
                            return await self.applySingleMoveWithVisibleBoundary(uid: uid, desiredOrder: desiredOrder)
                        }
                    )
                    self.rebuildMenu()
                    return result
                },
                onSettingsChanged: { [weak self] settings in
                    self?.settings = settings
                    self?.sectionController.setAlwaysHiddenSectionEnabled(settings.enableAlwaysHiddenSection)
                    self?.settingsStore.save(settings)
                    self?.rebuildMenu()
                },
                onPermissionsChanged: { [weak self] in
                    self?.rebuildMenu()
                }
            )
        }
        // Seed a failure that persisted while the panel was closed (e.g. a
        // failed startup restore) so the panel shows it immediately.
        mainPanelWindowController?.presentApplyFailure(persistentApplyFailureMessage)
        mainPanelWindowController?.show()
    }

    private func startHiddenItemsHoverBar() {
        guard hiddenItemsHoverBarController == nil else { return }
        let controller = HiddenItemsHoverBarController(
            cacheController: cacheController,
            layoutStore: layoutStore,
            thumbnailProvider: thumbnailProvider,
            permissionChecker: permissionChecker,
            boundaryProvider: { [weak self] in
                self?.sectionController.currentBoundary()
            },
            visualCacheProvider: { [weak self] in
                guard let self else {
                    return ItemCache(displayID: nil, visibleItems: [], hiddenItems: [], alwaysHiddenItems: [])
                }
                return try await self.currentMenuBarCacheWithoutChangingVisibility()
            },
            visualCacheCleanup: { },
            revealHandler: { [weak self] uid in
                guard let self else { return .failed("Controller unavailable") }
                CoronaDebugLog.log("hoverBar.reveal expandOnly uid=\(uid)")
                self.sectionController.setHiddenSectionVisible(true)
                self.rebuildMenu()
                self.scheduleAutoRehideIfNeeded()
                return .satisfied
            }
        )
        hiddenItemsHoverBarController = controller
        controller.start()
    }

    @MainActor
    private func currentMenuBarCacheWithoutChangingVisibility() async throws -> ItemCache {
        let snapshot = try await cacheController.refresh()
        guard sectionController.hiddenVisibility == .shown else {
            return physicallyVisibleCache(from: snapshot)
        }

        guard let boundary = sectionController.currentBoundary() else {
            return physicallyVisibleCache(from: snapshot)
        }
        guard boundary.isOnSameDisplay(as: snapshot.displayID) else {
            CoronaDebugLog.log("main.cache boundaryDisplayMismatch displayID=\(snapshot.displayID.map(String.init) ?? "nil") hidden=\(boundary.hiddenControlBounds.debugDescription) alwaysHidden=\(boundary.alwaysHiddenControlBounds?.debugDescription ?? "nil")")
            return physicallyVisibleCache(from: snapshot)
        }

        let sectionByWindowID = SectionClassifier().classify(items: snapshot.items, boundary: boundary)
        return ItemCacheBuilder().build(snapshot: snapshot, sectionByWindowID: sectionByWindowID)
    }

    @MainActor
    private func currentOrganizerMenuBarCache() async throws -> ItemCache {
        let previousVisibility = (
            hidden: sectionController.hiddenVisibility,
            alwaysHidden: sectionController.alwaysHiddenVisibility
        )
        let shouldExpandHidden = previousVisibility.hidden != .shown
        let shouldExpandAlwaysHidden = settings.enableAlwaysHiddenSection && previousVisibility.alwaysHidden != .shown
        let boundaryReference = (shouldExpandHidden || shouldExpandAlwaysHidden)
            ? currentBoundaryObservation().value
            : nil

        if shouldExpandHidden {
            sectionController.setHiddenSectionVisible(true)
        }
        if shouldExpandAlwaysHidden {
            sectionController.setAlwaysHiddenSectionVisible(true)
        }

        let shouldRestoreVisibility = shouldExpandHidden || shouldExpandAlwaysHidden
        defer {
            if shouldRestoreVisibility {
                sectionController.setHiddenSectionVisible(previousVisibility.hidden == .shown)
                if settings.enableAlwaysHiddenSection {
                    sectionController.setAlwaysHiddenSectionVisible(previousVisibility.alwaysHidden == .shown)
                }
                rebuildMenu()
            }
        }

        if shouldRestoreVisibility {
            // Read path degradation: on timeout fall back to the physically
            // visible cache (same fallback as a missing boundary) instead of
            // classifying with collapsed-state coordinates. Aborting the
            // refresh entirely would leave the panel showing stale content.
            guard await waitForBoundaryStability(reference: boundaryReference) else {
                CoronaDebugLog.log("main.organizerCache boundaryStabilityTimeout fallback=physicalVisible")
                let snapshot = try await cacheController.refresh()
                return physicallyVisibleCache(from: snapshot)
            }
        }

        let snapshot = try await cacheController.refresh()
        guard let boundary = sectionController.currentBoundary() else {
            CoronaDebugLog.log("main.organizerCache missingBoundary fallback=physicalVisible")
            return physicallyVisibleCache(from: snapshot)
        }
        guard boundary.isOnSameDisplay(as: snapshot.displayID) else {
            CoronaDebugLog.log("main.organizerCache boundaryDisplayMismatch displayID=\(snapshot.displayID.map(String.init) ?? "nil") hidden=\(boundary.hiddenControlBounds.debugDescription) alwaysHidden=\(boundary.alwaysHiddenControlBounds?.debugDescription ?? "nil")")
            return physicallyVisibleCache(from: snapshot)
        }

        let sectionByWindowID = SectionClassifier().classify(items: snapshot.items, boundary: boundary)
        let cache = ItemCacheBuilder().build(snapshot: snapshot, sectionByWindowID: sectionByWindowID)
        CoronaDebugLog.verbose("main.organizerCache expanded=\(shouldRestoreVisibility) visible=\(cache.visibleItems.count) hidden=\(cache.hiddenItems.count) alwaysHidden=\(cache.alwaysHiddenItems.count)")
        return cache
    }

    private func physicallyVisibleCache(from snapshot: MenuBarSnapshot) -> ItemCache {
        let displayFrame = snapshot.displayID.map(CGDisplayBounds) ?? BuiltInMenuBarDisplay.target().frame
        let visibleItems = snapshot.items.filter { item in
            item.isOnScreen && item.bounds.intersects(displayFrame)
        }
        let visibleWindowIDs = Set(visibleItems.map(\.windowID))
        let hiddenItems = snapshot.items.filter { item in
            !visibleWindowIDs.contains(item.windowID)
        }
        return ItemCache(
            displayID: snapshot.displayID,
            visibleItems: visibleItems.sortedByMenuBarPosition(),
            hiddenItems: hiddenItems.sortedByMenuBarPosition(),
            alwaysHiddenItems: []
        )
    }

    private func ensureLayoutApplicationController() -> LayoutApplicationController {
        if let layoutApplicationController {
            return layoutApplicationController
        }

        let controller = LayoutApplicationController(
            cacheController: cacheController,
            layoutStore: layoutStore,
            settingsStore: settingsStore,
            boundaryProvider: { [weak self] in
                self?.sectionController.currentBoundary()
            },
            boundaryItemsProvider: { [weak self] in
                self?.sectionController.boundaryItems() ?? [:]
            }
        )
        layoutApplicationController = controller
        return controller
    }

    private func scheduleStartupLayoutRestoreIfNeeded() {
        guard permissionChecker.snapshot().canRunCoreFeatures else { return }
        guard shouldRestoreSavedLayoutOnStartup else { return }

        startupLayoutRestoreTask?.cancel()
        startupLayoutRestoreTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard let self, !Task.isCancelled, self.permissionChecker.snapshot().canRunCoreFeatures else { return }
            // Routed through the shared apply session: failures get backoff
            // retries and, if persistent, the warning UI instead of a
            // log-only outcome (#18).
            let result = await self.requestApplySession(collapseAfterAttempt: true)
            CoronaDebugLog.log("startup.restoreSavedLayout result=\(result.statusTitle)")
        }
    }

    /// Startup restore runs for any non-empty saved order — an all-visible
    /// layout can still drift on screen — and whenever an interrupted apply
    /// left a pending relocation behind (#19).
    private var shouldRestoreSavedLayoutOnStartup: Bool {
        let order = layoutStore.loadSavedSectionOrder()
            .removingCoronaSelfItems()
            .removingLegacyAXGeneratedItems()
        return StartupLayoutRestorePolicy.shouldRestore(
            savedOrder: order,
            pendingRelocations: layoutStore.loadPendingRelocations()
        )
    }

    /// Single entry point for every layout apply (panel auto-apply, panel
    /// single move, startup restore). Coalescing rule (#18), shared by manual
    /// Organize and automatic retries: while an apply is running, the new
    /// request merges into the in-flight session; while a retry is only
    /// scheduled (sleeping out its backoff), the new request supersedes it so
    /// the newest intent applies immediately. Two applies never run
    /// concurrently either way.
    ///
    /// `firstAttempt`, when given, runs as the session's first attempt (e.g.
    /// a single-move apply for a panel drag); retries always fall back to a
    /// full saved-layout apply, which re-reads the persisted order.
    private func requestApplySession(
        collapseAfterAttempt: Bool = false,
        firstAttempt: (@MainActor () async -> LayoutApplicationResult)? = nil
    ) async -> LayoutApplicationResult {
        switch applyRetryPolicy.requestAction(applyInFlight: applySessionTask != nil) {
        case .coalesce:
            CoronaDebugLog.log("main.applySession coalesced")
            return await applySessionTask?.value ?? .failed("Controller unavailable")
        case .supersedeScheduledRetry:
            CoronaDebugLog.log("main.applySession supersedeScheduledRetry")
            applySessionTask?.cancel()
            applySessionTask = nil
            applyRetryPolicy.scheduledRetryWasCancelled()
        case .start:
            break
        }

        let task = Task { @MainActor [weak self] () -> LayoutApplicationResult in
            guard let self else { return .failed("Controller unavailable") }
            return await self.runApplySession(
                collapseAfterAttempt: collapseAfterAttempt,
                firstAttempt: firstAttempt
            )
        }
        applySessionTask = task
        let result = await task.value
        // A superseding request may already have installed a newer session.
        if applySessionTask == task {
            applySessionTask = nil
        }
        return result
    }

    private func runApplySession(
        collapseAfterAttempt: Bool,
        firstAttempt: (@MainActor () async -> LayoutApplicationResult)?
    ) async -> LayoutApplicationResult {
        applyRetryPolicy.beginSession()
        var attemptCount = 0
        var result: LayoutApplicationResult = .failed("applySessionDidNotRun")

        while true {
            attemptCount += 1
            if attemptCount == 1, let firstAttempt {
                result = await firstAttempt()
            } else {
                result = await applySavedLayoutWithVisibleBoundary(collapseAfterAttempt: collapseAfterAttempt)
            }
            lastLayoutApplicationResult = result
            CoronaDebugLog.log("main.applySession attempt=\(attemptCount) result=\(result.statusTitle)")

            if result.isSuccessfulApply {
                applyRetryPolicy.recordSuccess()
                clearPersistentApplyFailure()
                return result
            }
            guard !Task.isCancelled else { return result }
            guard let delay = applyRetryPolicy.backoffAfterFailure() else {
                presentPersistentApplyFailure(result)
                return result
            }
            CoronaDebugLog.log("main.applySession retryScheduled retry=\(applyRetryPolicy.retriesScheduled) delaySeconds=\(delay)")
            try? await Task.sleep(nanoseconds: UInt64((delay * 1_000_000_000).rounded()))
            if Task.isCancelled {
                // Superseded by a newer request during the backoff sleep.
                applyRetryPolicy.scheduledRetryWasCancelled()
                CoronaDebugLog.log("main.applySession retrySupersededDuringBackoff")
                return result
            }
            applyRetryPolicy.scheduledRetryDidFire()
        }
    }

    private var persistentApplyFailureMessage: String? {
        guard let persistentApplyFailure else { return nil }
        return "Could not apply the menu bar layout after several attempts (\(persistentApplyFailure.failureDetail)). Corona retries on the next layout change."
    }

    private func presentPersistentApplyFailure(_ result: LayoutApplicationResult) {
        persistentApplyFailure = result
        CoronaDebugLog.log("main.applySession persistentFailure result=\(result.statusTitle)")
        updateStatusIcon(for: permissionChecker.snapshot())
        mainPanelWindowController?.presentApplyFailure(persistentApplyFailureMessage)
    }

    private func clearPersistentApplyFailure() {
        guard persistentApplyFailure != nil else { return }
        persistentApplyFailure = nil
        CoronaDebugLog.log("main.applySession persistentFailureCleared")
        updateStatusIcon(for: permissionChecker.snapshot())
        mainPanelWindowController?.presentApplyFailure(nil)
    }

    private func applySavedLayoutWithVisibleBoundary(collapseAfterAttempt: Bool = false) async -> LayoutApplicationResult {
        var captureToken = MenuBarVisualCaptureGate.acquire(reason: "main.applySavedLayout")
        defer { captureToken.release() }

        sanitizeSavedLayout()
        autoRehideTask?.cancel()

        var result: LayoutApplicationResult
        if await expandSectionsAndWaitForBoundaryStability() {
            result = await ensureLayoutApplicationController().applySavedLayout()

            if result.isSuccessfulApply {
                let layoutSatisfied = await savedLayoutIsActuallySatisfied()
                if !layoutSatisfied {
                    result = .failed("savedLayoutNotRestored")
                }
            }
        } else {
            // Timeout path: abort instead of applying with collapsed-state
            // coordinates — continuing with a stale boundary would
            // misclassify every section and move items to the wrong targets.
            // The failure feeds into the retry session (#18).
            CoronaDebugLog.log("main.applySavedLayout boundaryStabilityTimeout action=abort")
            result = .failed("boundaryNotStable")
        }

        if result.isSuccessfulApply || collapseAfterAttempt {
            await collapseHiddenSectionsAfterLayoutAttempt()
        } else {
            collapseHiddenSections()
        }
        rebuildMenu()
        return result
    }

    private func applySingleMoveWithVisibleBoundary(uid: String, desiredOrder: SectionOrder) async -> LayoutApplicationResult {
        var captureToken = MenuBarVisualCaptureGate.acquire(reason: "main.applySingleMove")
        defer { captureToken.release() }

        sanitizeSavedLayout()
        autoRehideTask?.cancel()

        var result: LayoutApplicationResult
        if await expandSectionsAndWaitForBoundaryStability() {
            result = await ensureLayoutApplicationController().applySingleMove(uid: uid, desiredOrder: desiredOrder)

            if result.isSuccessfulApply {
                let layoutSatisfied = await savedLayoutIsActuallySatisfied()
                if !layoutSatisfied {
                    result = .failed("savedLayoutNotRestored")
                }
            }
        } else {
            // Same timeout policy as applySavedLayoutWithVisibleBoundary:
            // abort rather than move with collapsed-state coordinates.
            CoronaDebugLog.log("main.applySingleMove boundaryStabilityTimeout action=abort uid=\(uid)")
            result = .failed("boundaryNotStable")
        }

        if result.isSuccessfulApply {
            await collapseHiddenSectionsAfterLayoutAttempt()
        } else {
            collapseHiddenSections()
        }
        rebuildMenu()
        return result
    }

    private func collapseHiddenSections() {
        sectionController.setHiddenSectionVisible(false)
        if settings.enableAlwaysHiddenSection {
            sectionController.setAlwaysHiddenSectionVisible(false)
        }
    }

    private func currentBoundaryObservation() -> BoundaryObservation {
        BoundaryObservation(
            boundary: sectionController.currentBoundary(),
            timestamp: ProcessInfo.processInfo.systemUptime
        )
    }

    /// Expands the hidden sections and waits until macOS has finished
    /// reflowing the menu bar before returning true. Returns false when the
    /// boundary never settled within the timeout — the caller must then abort
    /// (apply paths) or degrade (read paths) instead of using collapsed-state
    /// coordinates.
    private func expandSectionsAndWaitForBoundaryStability() async -> Bool {
        let needsExpansion = sectionController.hiddenVisibility != .shown
            || (settings.enableAlwaysHiddenSection && sectionController.alwaysHiddenVisibility != .shown)
        let reference = needsExpansion ? currentBoundaryObservation().value : nil

        sectionController.setHiddenSectionVisible(true)
        if settings.enableAlwaysHiddenSection {
            sectionController.setAlwaysHiddenSectionVisible(true)
        }

        return await waitForBoundaryStability(reference: reference)
    }

    private func waitForBoundaryStability(reference: BoundaryValue?) async -> Bool {
        var evaluator = BoundaryStabilityEvaluator(
            reference: reference,
            requiredStableSamples: BoundaryStabilityTiming.requiredStableSamples,
            timeout: BoundaryStabilityTiming.timeoutSeconds
        )

        while !Task.isCancelled {
            let observation = currentBoundaryObservation()
            switch evaluator.record(observation) {
            case .stable:
                CoronaDebugLog.verbose("main.boundaryStable hiddenMinX=\(observation.value?.hiddenControlMinX ?? -1) alwaysHiddenMinX=\(observation.value?.alwaysHiddenControlMinX ?? -1)")
                return true
            case .timeout:
                CoronaDebugLog.log("main.boundaryStabilityTimeout lastHiddenMinX=\(observation.value?.hiddenControlMinX ?? -1) referenceHiddenMinX=\(reference?.hiddenControlMinX ?? -1)")
                return false
            case .pending:
                try? await Task.sleep(nanoseconds: BoundaryStabilityTiming.pollIntervalNanoseconds)
            }
        }
        return false
    }

    private func collapseHiddenSectionsAfterLayoutAttempt() async {
        collapseHiddenSections()
        await waitForMenuBarLayoutToSettle()
    }

    private func waitForMenuBarLayoutToSettle() async {
        var previousSignature: MenuBarStabilitySignature?
        var stableSampleCount = 0

        try? await Task.sleep(nanoseconds: StabilityTiming.initialDelayNanoseconds)

        for _ in 0..<StabilityTiming.maxPolls where !Task.isCancelled {
            do {
                let cache = try await currentMenuBarCacheWithoutChangingVisibility()
                let signature = MenuBarStabilitySignature(
                    cache: cache,
                    boundary: sectionController.currentBoundary(),
                    displayFrame: cache.displayID.map(CGDisplayBounds) ?? BuiltInMenuBarDisplay.target().frame
                )
                if previousSignature == signature {
                    stableSampleCount += 1
                    if stableSampleCount >= StabilityTiming.requiredStableSamples {
                        CoronaDebugLog.verbose("main.menuStable items=\(signature.items.count) samples=\(stableSampleCount)")
                        return
                    }
                } else {
                    previousSignature = signature
                    stableSampleCount = 1
                }
            } catch {
                CoronaDebugLog.log("main.menuStabilityCheckFailed error=\(String(describing: error))")
                return
            }
            try? await Task.sleep(nanoseconds: StabilityTiming.pollIntervalNanoseconds)
        }

        CoronaDebugLog.log("main.menuStabilityTimeout")
    }

    private func savedLayoutIsActuallySatisfied() async -> Bool {
        guard let boundary = sectionController.currentBoundary() else {
            CoronaDebugLog.log("layout.visibleGuard missingBoundary")
            return false
        }

        do {
            let cache = try await cacheController.cache(boundary: boundary)
            let savedOrder = layoutStore.loadSavedSectionOrder()
                .removingCoronaSelfItems()
                .removingLegacyAXGeneratedItems()
            let report = LayoutSatisfactionEvaluator().report(
                cache: cache,
                savedOrder: savedOrder,
                isOrderManageable: { item in
                    item.isMovable
                        && item.canBeHidden
                        && !Self.isCoronaSelfIdentifier(item.tag.stableIdentifier)
                }
            )

            let actualVisible = cache.visibleItems.map(\.tag.stableIdentifier)
            let actualHidden = cache.hiddenItems.map(\.tag.stableIdentifier)
            let actualAlwaysHidden = cache.alwaysHiddenItems.map(\.tag.stableIdentifier)

            if !report.isSatisfied {
                let sectionMismatches = report.sectionMismatches.map {
                    "\($0.uid):desired=\($0.expectedSection.rawValue),actual=\($0.actualSection?.rawValue ?? "missing")"
                }
                let orderMismatches = report.orderMismatches.map {
                    "\($0.section.rawValue):expected=\($0.expectedUIDs),actual=\($0.actualUIDs)"
                }
                CoronaDebugLog.log("layout.visibleGuard failed sectionMismatches=\(sectionMismatches) orderMismatches=\(orderMismatches) actualVisible=\(actualVisible) actualHidden=\(actualHidden) actualAlwaysHidden=\(actualAlwaysHidden) boundaryHidden=\(boundary.hiddenControlBounds.debugDescription) boundaryAlwaysHidden=\(boundary.alwaysHiddenControlBounds?.debugDescription ?? "nil")")
                return false
            }

            CoronaDebugLog.log("layout.visibleGuard satisfied actualVisible=\(actualVisible) actualHidden=\(actualHidden) actualAlwaysHidden=\(actualAlwaysHidden)")
            return true
        } catch {
            CoronaDebugLog.log("layout.visibleGuard failed error=\(String(describing: error))")
            return false
        }
    }

    private func sanitizeSavedLayout() {
        let savedOrder = layoutStore.loadSavedSectionOrder()
        let sanitized = savedOrder
            .removingCoronaSelfItems()
            .removingLegacyAXGeneratedItems()
        if sanitized != savedOrder {
            layoutStore.saveSavedSectionOrder(sanitized)
        }

        let known = layoutStore.loadKnownItemIdentifiers()
        let sanitizedKnown = known.filter {
            !Self.isCoronaSelfIdentifier($0)
                && !Self.isLegacyAXGeneratedIdentifier($0)
        }
        if sanitizedKnown != known {
            layoutStore.saveKnownItemIdentifiers(Set(sanitizedKnown))
        }

        let savedUIDs = Set(savedOrder.visible + savedOrder.hidden + savedOrder.alwaysHidden)
        for uid in known.union(savedUIDs) where Self.isCoronaSelfIdentifier(uid) || Self.isLegacyAXGeneratedIdentifier(uid) {
            layoutStore.savePendingRelocation(nil, for: uid)
        }
    }

    nonisolated static func isCoronaSelfIdentifier(_ uid: String) -> Bool {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.ltz.corona"
        return uid.localizedCaseInsensitiveContains(bundleIdentifier)
            || uid.localizedCaseInsensitiveContains("com.ltz.corona")
            || uid.localizedCaseInsensitiveContains("Corona:Corona")
            || uid.localizedCaseInsensitiveContains("Corona:Status Item")
            || uid.localizedCaseInsensitiveContains("corona.control")
    }

    nonisolated static func isLegacyAXGeneratedIdentifier(_ uid: String) -> Bool {
        let parts = uid.split(separator: ":").map(String.init)
        guard parts.count >= 2 else { return false }
        let title = parts[1]
        guard title.hasPrefix("item-") else { return false }
        return title.dropFirst("item-".count).allSatisfy(\.isNumber)
    }

    private func scheduleAutoRehideIfNeeded() {
        let latestSettings = settingsStore.load()
        guard latestSettings.autoRehide else { return }

        autoRehideTask?.cancel()
        autoRehideTask = Task { @MainActor [weak self] in
            let delay = UInt64(max(0.5, latestSettings.rehideInterval) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled, self.permissionChecker.snapshot().canRunCoreFeatures else { return }
            self.sectionController.setHiddenSectionVisible(false)
            if self.settings.enableAlwaysHiddenSection {
                self.sectionController.setAlwaysHiddenSectionVisible(false)
            }
            self.rebuildMenu()
        }
    }

    @objc private func openSettings() {
        openMainPanel()
        mainPanelWindowController?.showSettings()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

extension SectionOrder {
    func removingCoronaSelfItems() -> SectionOrder {
        SectionOrder(
            visible: visible.filter { !MenuBarController.isCoronaSelfIdentifier($0) },
            hidden: hidden.filter { !MenuBarController.isCoronaSelfIdentifier($0) },
            alwaysHidden: alwaysHidden.filter { !MenuBarController.isCoronaSelfIdentifier($0) }
        )
    }

    func removingLegacyAXGeneratedItems() -> SectionOrder {
        SectionOrder(
            visible: visible.filter { !MenuBarController.isLegacyAXGeneratedIdentifier($0) },
            hidden: hidden.filter { !MenuBarController.isLegacyAXGeneratedIdentifier($0) },
            alwaysHidden: alwaysHidden.filter { !MenuBarController.isLegacyAXGeneratedIdentifier($0) }
        )
    }
}

extension LayoutApplicationResult {
    var isSuccessfulApply: Bool {
        switch self {
        case .satisfied, .applied, .moved:
            return true
        case .missingBoundary, .waitingForItem, .waitingForDestination, .failed:
            return false
        }
    }
}

private extension Array where Element == MenuBarItem {
    func sortedByMenuBarPosition() -> [MenuBarItem] {
        sorted { lhs, rhs in
            if abs(lhs.bounds.minX - rhs.bounds.minX) > 0.5 {
                return lhs.bounds.minX < rhs.bounds.minX
            }
            return lhs.windowID < rhs.windowID
        }
    }
}

private extension SectionBoundary {
    func isOnSameDisplay(as displayID: UInt32?) -> Bool {
        let displayFrame = displayID.map(CGDisplayBounds) ?? BuiltInMenuBarDisplay.target().frame
        guard hiddenControlBounds.intersects(displayFrame) else { return false }
        if let alwaysHiddenControlBounds {
            return alwaysHiddenControlBounds.intersects(displayFrame)
        }
        return true
    }
}
