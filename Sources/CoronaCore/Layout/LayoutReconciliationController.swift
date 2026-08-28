import Foundation

/// Pure reconciliation decision logic (#20). The app layer owns polling,
/// timers, and the apply call; this type only decides, from injected time
/// and satisfaction reports, whether a physical deviation from the saved
/// order has persisted long enough to warrant one corrective apply.
///
/// Semantics (product decisions from the #14 PRD):
/// - The saved order is the single source of truth; any deviation reported
///   by `LayoutSatisfactionEvaluator` (section *or* order) is a candidate
///   for correction.
/// - Cooldown: after Corona's own apply finishes, ticks inside the
///   cooldown window perform no deviation detection at all — the episode
///   state is reset, so self-inflicted transient states can neither
///   trigger a request nor bank debounce time.
/// - Debounce: a deviation must be continuously present for `debounce`
///   seconds before a request is emitted. A deviation that resolves first
///   emits nothing and resets.
/// - At most one `requestApply` per deviation episode. An episode ends
///   when a tick reports the layout satisfied (outside cooldown) or when
///   `ownApplyStarted()` resets it; a deviation that appears afterwards is
///   a new episode with a fresh debounce budget.
///
/// All time is injected as `TimeInterval` values (monotonic clock units);
/// the controller never reads the system clock.
public struct LayoutReconciliationController: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        /// No action needed.
        case none
        /// The deviation is real and sustained: ask the app layer to apply
        /// the saved order once.
        case requestApply
    }

    public static let defaultCooldown: TimeInterval = 5
    public static let defaultDebounce: TimeInterval = 2.5

    /// Post-own-apply window during which deviation detection is suppressed.
    public let cooldown: TimeInterval
    /// How long a deviation must persist before it triggers a request.
    public let debounce: TimeInterval

    /// End of the current cooldown window (`ownApplyFinished` time +
    /// `cooldown`), nil when no own apply has finished. A tick is inside
    /// the window while `now < cooldownEndsAt`.
    public private(set) var cooldownEndsAt: TimeInterval?
    /// When the current deviation episode first appeared, nil when no
    /// deviation is being tracked.
    public private(set) var deviationSince: TimeInterval?
    /// Whether the current episode's single request has been spent.
    public private(set) var requestEmittedForCurrentEpisode = false

    public init(
        cooldown: TimeInterval = LayoutReconciliationController.defaultCooldown,
        debounce: TimeInterval = LayoutReconciliationController.defaultDebounce
    ) {
        self.cooldown = cooldown
        self.debounce = debounce
        self.cooldownEndsAt = nil
        self.deviationSince = nil
    }

    public func isInCooldown(at now: TimeInterval) -> Bool {
        guard let cooldownEndsAt else { return false }
        return now < cooldownEndsAt
    }

    /// Poll observation: compare the physical cache against the saved order
    /// and fold the result into the state machine.
    @discardableResult
    public mutating func tick(
        at now: TimeInterval,
        cache: ItemCache,
        savedOrder: SectionOrder,
        isOrderManageable: (MenuBarItem) -> Bool
    ) -> Decision {
        let report = LayoutSatisfactionEvaluator().report(
            cache: cache,
            savedOrder: savedOrder,
            isOrderManageable: isOrderManageable
        )
        return tick(at: now, report: report)
    }

    /// Poll observation with an already-computed satisfaction report.
    @discardableResult
    public mutating func tick(at now: TimeInterval, report: LayoutSatisfactionReport) -> Decision {
        // Inside the cooldown window there is no detection at all: any
        // in-progress episode is discarded rather than paused, so time
        // spent in the window never counts toward the debounce.
        guard !isInCooldown(at: now) else {
            resetEpisode()
            return .none
        }
        guard !report.isSatisfied else {
            resetEpisode()
            return .none
        }
        if deviationSince == nil {
            deviationSince = now
        }
        guard !requestEmittedForCurrentEpisode else { return .none }
        guard now - (deviationSince ?? now) >= debounce else { return .none }
        requestEmittedForCurrentEpisode = true
        return .requestApply
    }

    /// Corona's own apply started. The apply will change the physical
    /// state, so any pending deviation measurement is discarded; the
    /// cooldown window itself is (re)armed by `ownApplyFinished`.
    public mutating func ownApplyStarted() {
        resetEpisode()
    }

    /// Corona's own apply finished; opens the cooldown window.
    public mutating func ownApplyFinished(at now: TimeInterval) {
        cooldownEndsAt = now + cooldown
    }

    private mutating func resetEpisode() {
        deviationSince = nil
        requestEmittedForCurrentEpisode = false
    }
}
