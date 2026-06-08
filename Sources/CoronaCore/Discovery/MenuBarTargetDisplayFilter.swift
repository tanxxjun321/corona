import CoreGraphics
import Foundation

public struct MenuBarTargetDisplayFilter: Sendable {
    private let targetDisplayFrame: CGRect
    private let otherDisplayFrames: [CGRect]

    public init(targetDisplayFrame: CGRect, otherDisplayFrames: [CGRect]) {
        self.targetDisplayFrame = targetDisplayFrame
        self.otherDisplayFrames = otherDisplayFrames
    }

    public func itemsOnTargetDisplay(_ items: [MenuBarItem]) -> [MenuBarItem] {
        items.filter { item in
            isInTargetMenuBarBand(item.bounds) && hasTargetDisplayAffinity(item.bounds)
        }
    }

    private func isInTargetMenuBarBand(_ bounds: CGRect) -> Bool {
        let verticalTolerance: CGFloat = 8
        return abs(bounds.minY - targetDisplayFrame.minY) <= verticalTolerance
    }

    private func hasTargetDisplayAffinity(_ bounds: CGRect) -> Bool {
        let targetScore = displayAffinityScore(for: bounds, displayFrame: targetDisplayFrame)
        let bestOtherScore = otherDisplayFrames
            .map { displayAffinityScore(for: bounds, displayFrame: $0) }
            .max() ?? -.greatestFiniteMagnitude
        return targetScore >= bestOtherScore
    }

    private func displayAffinityScore(for bounds: CGRect, displayFrame: CGRect) -> CGFloat {
        let verticalDistance = min(abs(bounds.minY - displayFrame.minY), abs(bounds.maxY - displayFrame.maxY))
        let horizontalOverlap = max(0, min(bounds.maxX, displayFrame.maxX) - max(bounds.minX, displayFrame.minX))
        let horizontalDistance: CGFloat
        if horizontalOverlap > 0 {
            horizontalDistance = 0
        } else {
            horizontalDistance = min(abs(bounds.maxX - displayFrame.minX), abs(bounds.minX - displayFrame.maxX))
        }
        let centerBonus: CGFloat = displayFrame.contains(CGPoint(x: bounds.midX, y: bounds.midY)) ? 1_000 : 0
        return centerBonus - verticalDistance * 10 + horizontalOverlap - horizontalDistance
    }
}
