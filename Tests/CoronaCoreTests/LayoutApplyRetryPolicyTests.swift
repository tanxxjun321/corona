import CoronaCore
import XCTest

final class LayoutApplyRetryPolicyTests: XCTestCase {
    func testDefaultBackoffDelaysAreOneThreeEightSeconds() {
        let policy = LayoutApplyRetryPolicy()
        XCTAssertEqual(policy.backoffDelays, [1, 3, 8])
    }

    func testNewRequestStartsSessionWhenIdle() {
        let policy = LayoutApplyRetryPolicy()
        XCTAssertEqual(policy.requestAction(applyInFlight: false), .start)
    }

    func testNewRequestCoalescesWhileApplyInFlight() {
        let policy = LayoutApplyRetryPolicy()
        XCTAssertEqual(policy.requestAction(applyInFlight: true), .coalesce)
    }

    func testNewRequestSupersedesScheduledRetry() {
        var policy = LayoutApplyRetryPolicy()
        policy.beginSession()
        _ = policy.backoffAfterFailure()

        // The backoff sleep still has a live session task on the app side,
        // but the scheduled retry must be cancelled, never stacked.
        XCTAssertEqual(policy.requestAction(applyInFlight: true), .supersedeScheduledRetry)
        XCTAssertEqual(policy.requestAction(applyInFlight: false), .supersedeScheduledRetry)
    }

    func testBackoffSequenceExhaustsAfterAllDelays() {
        var policy = LayoutApplyRetryPolicy()
        policy.beginSession()

        XCTAssertEqual(policy.backoffAfterFailure(), 1)
        XCTAssertEqual(policy.retriesScheduled, 1)
        policy.scheduledRetryDidFire()

        XCTAssertEqual(policy.backoffAfterFailure(), 3)
        XCTAssertEqual(policy.retriesScheduled, 2)
        policy.scheduledRetryDidFire()

        XCTAssertEqual(policy.backoffAfterFailure(), 8)
        XCTAssertEqual(policy.retriesScheduled, 3)
        policy.scheduledRetryDidFire()

        XCTAssertNil(policy.backoffAfterFailure())
        XCTAssertFalse(policy.retryIsScheduled)
    }

    func testScheduledRetryFlagTracksLifecycle() {
        var policy = LayoutApplyRetryPolicy()
        policy.beginSession()
        XCTAssertFalse(policy.retryIsScheduled)

        _ = policy.backoffAfterFailure()
        XCTAssertTrue(policy.retryIsScheduled)

        policy.scheduledRetryDidFire()
        XCTAssertFalse(policy.retryIsScheduled)
    }

    func testCancelledRetryClearsScheduledFlag() {
        var policy = LayoutApplyRetryPolicy()
        policy.beginSession()
        _ = policy.backoffAfterFailure()
        XCTAssertTrue(policy.retryIsScheduled)

        policy.scheduledRetryWasCancelled()
        XCTAssertFalse(policy.retryIsScheduled)
        XCTAssertEqual(policy.requestAction(applyInFlight: false), .start)
    }

    func testSuccessResetsRetryBudget() {
        var policy = LayoutApplyRetryPolicy()
        policy.beginSession()
        _ = policy.backoffAfterFailure()
        policy.scheduledRetryDidFire()
        _ = policy.backoffAfterFailure()
        policy.scheduledRetryDidFire()

        policy.recordSuccess()
        XCTAssertEqual(policy.retriesScheduled, 0)
        XCTAssertFalse(policy.retryIsScheduled)

        // The next failure streak starts from the first delay again.
        policy.beginSession()
        XCTAssertEqual(policy.backoffAfterFailure(), 1)
    }

    func testBeginSessionResetsBudgetAfterExhaustion() {
        var policy = LayoutApplyRetryPolicy()
        policy.beginSession()
        _ = policy.backoffAfterFailure()
        policy.scheduledRetryDidFire()
        _ = policy.backoffAfterFailure()
        policy.scheduledRetryDidFire()
        _ = policy.backoffAfterFailure()
        policy.scheduledRetryDidFire()
        XCTAssertNil(policy.backoffAfterFailure())

        // A later, brand-new request (e.g. manual Organize after the warning
        // has been showing) gets a full retry budget again.
        policy.beginSession()
        XCTAssertEqual(policy.backoffAfterFailure(), 1)
    }

    func testCustomDelaysAreRespected() {
        var policy = LayoutApplyRetryPolicy(backoffDelays: [0.5])
        policy.beginSession()
        XCTAssertEqual(policy.backoffAfterFailure(), 0.5)
        policy.scheduledRetryDidFire()
        XCTAssertNil(policy.backoffAfterFailure())
    }
}
