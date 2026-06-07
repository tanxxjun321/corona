import Foundation

public enum PermissionState: String, Codable, Equatable, Sendable {
    case missing
    case granted
}

public enum CapabilityStatus: String, Codable, Equatable, Sendable {
    case missing
    case hasRequired
    case hasAll
}

public struct PermissionSnapshot: Codable, Equatable, Sendable {
    public var accessibility: PermissionState
    public var screenRecording: PermissionState

    public init(
        accessibility: PermissionState,
        screenRecording: PermissionState
    ) {
        self.accessibility = accessibility
        self.screenRecording = screenRecording
    }

    public var capabilityStatus: CapabilityStatus {
        switch (accessibility, screenRecording) {
        case (.missing, _):
            return .missing
        case (.granted, .missing):
            return .hasRequired
        case (.granted, .granted):
            return .hasAll
        }
    }

    public var canRunCoreFeatures: Bool {
        accessibility == .granted
    }

    public var canShowPixelPreviews: Bool {
        screenRecording == .granted
    }
}

public protocol PermissionChecking {
    func snapshot() -> PermissionSnapshot
}
