import CoreGraphics
import Foundation

/// The boundary's observable position at one point in time: the control
/// items' minX coordinates rounded to whole points (matching the tolerance
/// used by `MenuBarStabilitySignature`).
public struct BoundaryValue: Equatable, Sendable {
    public var hiddenControlMinX: Int
    public var alwaysHiddenControlMinX: Int?

    public init(hiddenControlMinX: Int, alwaysHiddenControlMinX: Int? = nil) {
        self.hiddenControlMinX = hiddenControlMinX
        self.alwaysHiddenControlMinX = alwaysHiddenControlMinX
    }

    public init(boundary: SectionBoundary) {
        self.init(
            hiddenControlMinX: Int(boundary.hiddenControlBounds.minX.rounded()),
            alwaysHiddenControlMinX: boundary.alwaysHiddenControlBounds.map { Int($0.minX.rounded()) }
        )
    }
}

/// One sample fed to `BoundaryStabilityEvaluator`. `value` is nil when the
/// boundary could not be read at all (control item window not yet on screen);
/// a missing boundary never counts towards stability.
public struct BoundaryObservation: Equatable, Sendable {
    public var value: BoundaryValue?
    public var timestamp: TimeInterval

    public init(value: BoundaryValue?, timestamp: TimeInterval) {
        self.value = value
        self.timestamp = timestamp
    }

    public init(boundary: SectionBoundary?, timestamp: TimeInterval) {
        self.init(value: boundary.map(BoundaryValue.init(boundary:)), timestamp: timestamp)
    }
}

/// Pure, incremental decision procedure for "has the menu bar boundary
/// settled after expanding the hidden sections?". The polling loop lives in
/// the app layer; this type only looks at the observation sequence.
///
/// Stability requires `requiredStableSamples` consecutive observations with
/// an unchanged value that also differs from `reference` (the pre-expansion
/// position) — an unchanged collapsed position means the expansion never
/// took effect, not that the bar is ready. When `reference` is nil (sections
/// were already expanded) only the unchanged-run requirement applies.
/// `.timeout` is reported once `timeout` seconds have elapsed since the
/// first recorded observation without reaching stability.
public struct BoundaryStabilityEvaluator: Sendable {
    public enum Decision: Equatable, Sendable {
        case pending
        case stable
        case timeout
    }

    public let requiredStableSamples: Int
    public let timeout: TimeInterval

    private let reference: BoundaryValue?
    private var firstTimestamp: TimeInterval?
    private var lastValue: BoundaryValue?
    private var stableSampleCount = 0

    public init(
        reference: BoundaryValue?,
        requiredStableSamples: Int,
        timeout: TimeInterval
    ) {
        self.reference = reference
        self.requiredStableSamples = requiredStableSamples
        self.timeout = timeout
    }

    public mutating func record(_ observation: BoundaryObservation) -> Decision {
        if firstTimestamp == nil {
            firstTimestamp = observation.timestamp
        }

        if let value = observation.value {
            if value == lastValue {
                stableSampleCount += 1
            } else {
                lastValue = value
                stableSampleCount = 1
            }
            if stableSampleCount >= requiredStableSamples, value != reference {
                return .stable
            }
        } else {
            lastValue = nil
            stableSampleCount = 0
        }

        if observation.timestamp - (firstTimestamp ?? observation.timestamp) >= timeout {
            return .timeout
        }
        return .pending
    }
}
