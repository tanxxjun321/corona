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
        guard !isGenericControlCenterContainer(candidate) else { return false }
        guard !isControlCenterSubviewArtifact(candidate) else { return false }
        guard !isTextInputSubviewArtifact(candidate) else { return false }
        guard !isLeftEdgeControlCenterArtifact(candidate, displayFrames: displayFrames) else { return false }
        guard isStatusItemLayer(candidate.layer) else { return false }
        guard isStatusItemSized(candidate.bounds, displayFrames: displayFrames) else { return false }
        return isInMenuBarVerticalBand(candidate.bounds, displayFrames: displayFrames)
            && isInStatusItemHorizontalRegion(candidate.bounds, displayFrames: displayFrames)
    }

    private func isGenericControlCenterContainer(_ candidate: MenuBarWindowCandidate) -> Bool {
        guard candidate.title?.isEmpty ?? true else { return false }
        guard candidate.bounds.height < 30 else { return false }
        // Match by bundle identifier: the owner name is localized per system
        // language, the bundle identifier is not.
        return bundleIdentifierForPID(candidate.ownerPID) == "com.apple.controlcenter"
    }

    private func isLeftEdgeControlCenterArtifact(_ candidate: MenuBarWindowCandidate, displayFrames: [CGRect]) -> Bool {
        let isControlCenter = bundleIdentifierForPID(candidate.ownerPID) == "com.apple.controlcenter"
        guard isControlCenter else { return false }

        return displayFrames.contains { frame in
            abs(candidate.bounds.minY - frame.minY) <= 8 &&
                candidate.bounds.minX >= frame.minX - 1 &&
                candidate.bounds.minX <= frame.minX + 1 &&
                candidate.bounds.maxX < frame.midX
        }
    }

    private func isControlCenterSubviewArtifact(_ candidate: MenuBarWindowCandidate) -> Bool {
        let isControlCenter = bundleIdentifierForPID(candidate.ownerPID) == "com.apple.controlcenter"
        guard isControlCenter else { return false }

        return candidate.bounds.height < 30
    }

    private func isTextInputSubviewArtifact(_ candidate: MenuBarWindowCandidate) -> Bool {
        let ownerName = candidate.ownerName ?? ""
        let bundleIdentifier = bundleIdentifierForPID(candidate.ownerPID)
        let isTextInputAgent = ownerName == "TextInputMenuAgent" ||
            bundleIdentifier == "com.apple.TextInputMenuAgent"
        guard isTextInputAgent else { return false }

        return candidate.bounds.height < 30
    }

    private func isStatusItemLayer(_ layer: Int) -> Bool {
        layer >= 20 && layer <= 30
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
            let verticalTolerance: CGFloat = 8
            return abs(bounds.minY - frame.minY) <= verticalTolerance
        }
    }

    private func isInStatusItemHorizontalRegion(_ bounds: CGRect, displayFrames: [CGRect]) -> Bool {
        displayFrames.contains { frame in
            guard abs(bounds.minY - frame.minY) <= 8 else { return false }

            if !bounds.intersects(frame) {
                return true
            }

            let minimumStatusItemX = frame.minX + frame.width * 0.25
            return bounds.maxX >= minimumStatusItemX
        }
    }
}
