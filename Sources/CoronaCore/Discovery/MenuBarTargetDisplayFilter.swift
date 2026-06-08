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
            isInTargetMenuBarBand(item.bounds) && !isInOtherDisplay(item.bounds)
        }
    }

    private func isInTargetMenuBarBand(_ bounds: CGRect) -> Bool {
        let verticalTolerance: CGFloat = 96
        return abs(bounds.minY - targetDisplayFrame.minY) <= verticalTolerance ||
            abs(bounds.maxY - targetDisplayFrame.maxY) <= verticalTolerance ||
            (bounds.midY >= targetDisplayFrame.minY - verticalTolerance &&
                bounds.midY <= targetDisplayFrame.minY + verticalTolerance) ||
            (bounds.midY >= targetDisplayFrame.maxY - verticalTolerance &&
                bounds.midY <= targetDisplayFrame.maxY + verticalTolerance)
    }

    private func isInOtherDisplay(_ bounds: CGRect) -> Bool {
        otherDisplayFrames.contains { frame in
            bounds.intersects(frame) || frame.contains(CGPoint(x: bounds.midX, y: bounds.midY))
        }
    }
}
