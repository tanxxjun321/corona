import Foundation

public enum DiagnosticEvent: Equatable, Sendable {
    case permissionChanged(PermissionSnapshot)
    case cacheRefreshed(displayID: UInt32?, itemCount: Int)
    case sourcePIDResolutionFailed(count: Int)
    case moveStarted(uid: String, target: LayoutTarget)
    case moveFinished(uid: String, success: Bool)
    case pendingRelocationChanged(uid: String, value: PendingRelocation?)
    case warning(String)
}

public protocol DiagnosticLogging {
    func log(_ event: DiagnosticEvent)
}

public struct DisabledDiagnosticLogger: DiagnosticLogging {
    public init() {}

    public func log(_ event: DiagnosticEvent) {}
}
