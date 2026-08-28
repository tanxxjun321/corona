import CoronaCore
import CoreGraphics
import XCTest

final class BoundaryStabilityEvaluatorTests: XCTestCase {
    private func observation(
        hiddenMinX: Int?,
        alwaysHiddenMinX: Int? = nil,
        timestamp: TimeInterval
    ) -> BoundaryObservation {
        BoundaryObservation(
            value: hiddenMinX.map { BoundaryValue(hiddenControlMinX: $0, alwaysHiddenControlMinX: alwaysHiddenMinX) },
            timestamp: timestamp
        )
    }

    func testStableAfterRequiredUnchangedSamplesDifferentFromReference() {
        var evaluator = BoundaryStabilityEvaluator(
            reference: BoundaryValue(hiddenControlMinX: 1000),
            requiredStableSamples: 3,
            timeout: 2.5
        )

        XCTAssertEqual(evaluator.record(observation(hiddenMinX: 900, timestamp: 0)), .pending)
        XCTAssertEqual(evaluator.record(observation(hiddenMinX: 900, timestamp: 0.04)), .pending)
        XCTAssertEqual(evaluator.record(observation(hiddenMinX: 900, timestamp: 0.08)), .stable)
    }

    func testStillChangingBoundaryStaysPending() {
        var evaluator = BoundaryStabilityEvaluator(
            reference: BoundaryValue(hiddenControlMinX: 1000),
            requiredStableSamples: 3,
            timeout: 10
        )

        XCTAssertEqual(evaluator.record(observation(hiddenMinX: 900, timestamp: 0)), .pending)
        XCTAssertEqual(evaluator.record(observation(hiddenMinX: 900, timestamp: 0.04)), .pending)
        // Position moved: the unchanged run restarts.
        XCTAssertEqual(evaluator.record(observation(hiddenMinX: 850, timestamp: 0.08)), .pending)
        XCTAssertEqual(evaluator.record(observation(hiddenMinX: 850, timestamp: 0.12)), .pending)
        XCTAssertEqual(evaluator.record(observation(hiddenMinX: 850, timestamp: 0.16)), .stable)
    }

    func testUnchangedCollapsedPositionIsNotStable() {
        // Expansion never took effect: the boundary sits unchanged at its
        // pre-expansion (reference) position, so this must time out rather
        // than report stable.
        var evaluator = BoundaryStabilityEvaluator(
            reference: BoundaryValue(hiddenControlMinX: 1000),
            requiredStableSamples: 3,
            timeout: 0.2
        )

        XCTAssertEqual(evaluator.record(observation(hiddenMinX: 1000, timestamp: 0)), .pending)
        XCTAssertEqual(evaluator.record(observation(hiddenMinX: 1000, timestamp: 0.1)), .pending)
        XCTAssertEqual(evaluator.record(observation(hiddenMinX: 1000, timestamp: 0.2)), .timeout)
    }

    func testNilReferenceOnlyRequiresUnchangedRun() {
        // Sections already expanded: no reference to differ from.
        var evaluator = BoundaryStabilityEvaluator(
            reference: nil,
            requiredStableSamples: 2,
            timeout: 2.5
        )

        XCTAssertEqual(evaluator.record(observation(hiddenMinX: 900, timestamp: 0)), .pending)
        XCTAssertEqual(evaluator.record(observation(hiddenMinX: 900, timestamp: 0.04)), .stable)
    }

    func testMissingBoundaryNeverCountsAsStable() {
        var evaluator = BoundaryStabilityEvaluator(
            reference: BoundaryValue(hiddenControlMinX: 1000),
            requiredStableSamples: 3,
            timeout: 10
        )

        XCTAssertEqual(evaluator.record(observation(hiddenMinX: 900, timestamp: 0)), .pending)
        XCTAssertEqual(evaluator.record(observation(hiddenMinX: 900, timestamp: 0.04)), .pending)
        // Unreadable boundary resets the run even with the same coordinates.
        XCTAssertEqual(evaluator.record(observation(hiddenMinX: nil, timestamp: 0.08)), .pending)
        XCTAssertEqual(evaluator.record(observation(hiddenMinX: 900, timestamp: 0.12)), .pending)
        XCTAssertEqual(evaluator.record(observation(hiddenMinX: 900, timestamp: 0.16)), .pending)
        XCTAssertEqual(evaluator.record(observation(hiddenMinX: 900, timestamp: 0.20)), .stable)
    }

    func testTimeoutWhileStillChanging() {
        var evaluator = BoundaryStabilityEvaluator(
            reference: BoundaryValue(hiddenControlMinX: 1000),
            requiredStableSamples: 3,
            timeout: 0.2
        )

        XCTAssertEqual(evaluator.record(observation(hiddenMinX: 900, timestamp: 0)), .pending)
        XCTAssertEqual(evaluator.record(observation(hiddenMinX: 800, timestamp: 0.1)), .pending)
        XCTAssertEqual(evaluator.record(observation(hiddenMinX: 700, timestamp: 0.21)), .timeout)
    }

    func testAlwaysHiddenCoordinateParticipatesInComparison() {
        var evaluator = BoundaryStabilityEvaluator(
            reference: BoundaryValue(hiddenControlMinX: 1000, alwaysHiddenControlMinX: 980),
            requiredStableSamples: 2,
            timeout: 10
        )

        XCTAssertEqual(evaluator.record(observation(hiddenMinX: 900, alwaysHiddenMinX: 880, timestamp: 0)), .pending)
        // Same hidden position, but the always-hidden control still moved.
        XCTAssertEqual(evaluator.record(observation(hiddenMinX: 900, alwaysHiddenMinX: 860, timestamp: 0.04)), .pending)
        XCTAssertEqual(evaluator.record(observation(hiddenMinX: 900, alwaysHiddenMinX: 860, timestamp: 0.08)), .stable)
    }

    func testBoundaryInitRoundsCoordinates() {
        let boundary = SectionBoundary(
            hiddenControlBounds: CGRect(x: 899.6, y: 0, width: 10, height: 22),
            alwaysHiddenControlBounds: CGRect(x: 799.4, y: 0, width: 10, height: 22)
        )

        let observation = BoundaryObservation(boundary: boundary, timestamp: 0)
        XCTAssertEqual(observation.value, BoundaryValue(hiddenControlMinX: 900, alwaysHiddenControlMinX: 799))
        XCTAssertEqual(observation.timestamp, 0)

        let missing = BoundaryObservation(boundary: nil, timestamp: 1)
        XCTAssertNil(missing.value)
    }
}
