import Foundation

public actor SnapshotPollingGate {
    public static let shared = SnapshotPollingGate()

    private var suspensionCount = 0
    private var activeSnapshots = 0

    private init() {}

    public func withSnapshotAccess<T>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        while suspensionCount > 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        activeSnapshots += 1
        defer {
            activeSnapshots -= 1
        }

        return try await operation()
    }

    public func acquireSuspension() async {
        suspensionCount += 1
        while activeSnapshots > 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    public func releaseSuspension() {
        suspensionCount = max(0, suspensionCount - 1)
    }
}
