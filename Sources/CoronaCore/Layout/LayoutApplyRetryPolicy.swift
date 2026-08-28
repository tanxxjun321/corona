import Foundation

/// Pure retry/backoff and coalescing decisions for layout apply sessions
/// (#18). The app layer (`MenuBarController`) owns the timers, tasks, and
/// apply calls; this type only tracks where in the retry sequence a session
/// is and what a new apply request should do.
///
/// State machine:
/// - `beginSession()` starts a fresh apply session with a full retry budget.
/// - Each failed attempt goes through `backoffAfterFailure()`, which returns
///   the delay before the next retry and marks that retry as scheduled, or
///   returns nil once every delay in `backoffDelays` has been consumed — the
///   failure is then persistent and must be surfaced by the caller.
/// - `scheduledRetryDidFire()` marks the scheduled retry as running;
///   `scheduledRetryWasCancelled()` abandons it (superseded by a newer
///   request). `recordSuccess()` clears all retry state.
///
/// Coalescing (`requestAction`): while an apply is running, a new request
/// merges into the in-flight session — two applies never run concurrently.
/// While a retry is only scheduled (sleeping out its backoff), a new request
/// supersedes it, so the newest intent applies immediately instead of
/// waiting out the remaining delay.
public struct LayoutApplyRetryPolicy: Equatable, Sendable {
    public enum RequestAction: Equatable, Sendable {
        /// Nothing is running or scheduled: start a new apply session.
        case start
        /// An apply is running: merge into the in-flight session.
        case coalesce
        /// A retry is scheduled but not running: cancel it and start now.
        case supersedeScheduledRetry
    }

    public static let defaultBackoffDelays: [TimeInterval] = [1, 3, 8]

    public let backoffDelays: [TimeInterval]
    /// Number of retries scheduled so far in the current failure streak.
    public private(set) var retriesScheduled = 0
    /// Whether a retry is scheduled (sleeping) but has not started running.
    public private(set) var retryIsScheduled = false

    public init(backoffDelays: [TimeInterval] = LayoutApplyRetryPolicy.defaultBackoffDelays) {
        self.backoffDelays = backoffDelays
    }

    /// Shared rule for manual Organize and automatic retries.
    /// `applyInFlight` is whether the app layer currently has an apply
    /// session alive (actively applying or backing off).
    public func requestAction(applyInFlight: Bool) -> RequestAction {
        if retryIsScheduled {
            return .supersedeScheduledRetry
        }
        return applyInFlight ? .coalesce : .start
    }

    /// Starts a fresh session with a full retry budget.
    public mutating func beginSession() {
        retriesScheduled = 0
        retryIsScheduled = false
    }

    /// Records a failed attempt. Returns the backoff delay before the next
    /// retry, or nil when the retry budget is exhausted (persistent failure).
    public mutating func backoffAfterFailure() -> TimeInterval? {
        guard retriesScheduled < backoffDelays.count else { return nil }
        let delay = backoffDelays[retriesScheduled]
        retriesScheduled += 1
        retryIsScheduled = true
        return delay
    }

    /// The scheduled retry started executing.
    public mutating func scheduledRetryDidFire() {
        retryIsScheduled = false
    }

    /// The scheduled retry was cancelled before firing (superseded by a
    /// newer apply request).
    public mutating func scheduledRetryWasCancelled() {
        retryIsScheduled = false
    }

    /// A successful apply ends the failure streak; the next failure starts
    /// a fresh backoff sequence.
    public mutating func recordSuccess() {
        retriesScheduled = 0
        retryIsScheduled = false
    }
}
