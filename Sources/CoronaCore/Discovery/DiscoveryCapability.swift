import Foundation

public enum CapabilityLevel: String, Codable, Equatable, Sendable {
    case unavailable
    case limited
    case full
}

public struct DiscoveryCapability: Codable, Equatable, Sendable {
    public var canEnumerateOffscreenMenuBarItems: Bool
    public var activeMenuBarDisplay: CapabilityLevel
    public var canCaptureStatusItemPixels: Bool
    public var canResolveSourcePID: Bool

    public init(
        canEnumerateOffscreenMenuBarItems: Bool,
        activeMenuBarDisplay: CapabilityLevel,
        canCaptureStatusItemPixels: Bool,
        canResolveSourcePID: Bool
    ) {
        self.canEnumerateOffscreenMenuBarItems = canEnumerateOffscreenMenuBarItems
        self.activeMenuBarDisplay = activeMenuBarDisplay
        self.canCaptureStatusItemPixels = canCaptureStatusItemPixels
        self.canResolveSourcePID = canResolveSourcePID
    }

    public static let appStoreFallback = DiscoveryCapability(
        canEnumerateOffscreenMenuBarItems: false,
        activeMenuBarDisplay: .limited,
        canCaptureStatusItemPixels: false,
        canResolveSourcePID: true
    )

    public static let directFull = DiscoveryCapability(
        canEnumerateOffscreenMenuBarItems: true,
        activeMenuBarDisplay: .full,
        canCaptureStatusItemPixels: true,
        canResolveSourcePID: true
    )
}
