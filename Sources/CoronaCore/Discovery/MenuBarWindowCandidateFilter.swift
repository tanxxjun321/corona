import CoreGraphics
import Foundation

public struct MenuBarWindowCandidate: Equatable, Sendable {
    public var ownerPID: Int32
    public var ownerName: String?
    public var title: String?
    public var bounds: CGRect
    public var layer: Int

    public init(
        ownerPID: Int32,
        ownerName: String?,
        title: String?,
        bounds: CGRect,
        layer: Int
    ) {
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.title = title
        self.bounds = bounds
        self.layer = layer
    }
}

public struct MenuBarWindowCandidateFilter: Sendable {
    private let currentProcessID: Int32
    private let mainBundleIdentifier: String?
    private let bundleIdentifierForPID: @Sendable (Int32) -> String?

    public init(
        currentProcessID: Int32,
        mainBundleIdentifier: String?,
        bundleIdentifierForPID: @escaping @Sendable (Int32) -> String?
    ) {
        self.currentProcessID = currentProcessID
        self.mainBundleIdentifier = mainBundleIdentifier
        self.bundleIdentifierForPID = bundleIdentifierForPID
    }

    public func isMenuBarItemCandidate(
        _ candidate: MenuBarWindowCandidate,
        displayFrames: [CGRect]
    ) -> Bool {
        guard candidate.ownerPID != currentProcessID else { return false }
        guard candidate.ownerName != "Window Server", candidate.title != "Menubar" else { return false }
        guard bundleIdentifierForPID(candidate.ownerPID) != mainBundleIdentifier else { return false }
        guard isStatusItemSized(candidate.bounds, displayFrames: displayFrames) else { return false }
        return isInMenuBarVerticalBand(candidate.bounds, displayFrames: displayFrames)
    }

    private func isStatusItemSized(_ bounds: CGRect, displayFrames: [CGRect]) -> Bool {
        let widestDisplay = displayFrames.map(\.width).max() ?? 1728
        let maximumStatusItemWidth = min(max(widestDisplay * 0.75, 360), 1200)
        return bounds.width >= 4 &&
            bounds.width <= maximumStatusItemWidth &&
            bounds.height >= 8 &&
            bounds.height <= 80
    }

    private func isInMenuBarVerticalBand(_ bounds: CGRect, displayFrames: [CGRect]) -> Bool {
        displayFrames.contains { frame in
            let verticalTolerance: CGFloat = 96
            return abs(bounds.minY - frame.minY) <= verticalTolerance ||
                abs(bounds.maxY - frame.maxY) <= verticalTolerance ||
                (bounds.midY >= frame.minY - verticalTolerance &&
                    bounds.midY <= frame.minY + verticalTolerance) ||
                (bounds.midY >= frame.maxY - verticalTolerance &&
                    bounds.midY <= frame.maxY + verticalTolerance)
        }
    }
}
