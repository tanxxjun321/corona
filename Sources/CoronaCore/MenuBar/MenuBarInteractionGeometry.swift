import CoreGraphics
import Foundation

public struct MenuBarInteractionGeometry: Sendable {
    public init() {}

    public func statusItemTriggerFrame(
        itemBounds: [CGRect],
        screenFrame: CGRect,
        edge: MenuBarEdge = .top,
        menuBarThickness: CGFloat = 40,
        horizontalPadding: CGFloat = 28
    ) -> CGRect? {
        let rightRegionWidth = min(max(screenFrame.width * 0.45, 360), 900)
        let rightRegionMinX = screenFrame.maxX - rightRegionWidth
        let edgeFrame: CGRect
        switch edge {
        case .top:
            edgeFrame = CGRect(
                x: rightRegionMinX,
                y: screenFrame.maxY - menuBarThickness,
                width: rightRegionWidth,
                height: menuBarThickness
            )
        case .bottom:
            edgeFrame = CGRect(
                x: rightRegionMinX,
                y: screenFrame.minY,
                width: rightRegionWidth,
                height: menuBarThickness
            )
        }

        let visibleRightItems = itemBounds.filter { bounds in
            bounds.width > 1
                && bounds.height > 1
                && bounds.intersects(edgeFrame)
        }
        guard let first = visibleRightItems.first else { return nil }

        let union = visibleRightItems.dropFirst().reduce(first) { partialResult, bounds in
            partialResult.union(bounds)
        }
        return CGRect(
            x: max(screenFrame.minX, union.minX - horizontalPadding),
            y: edgeFrame.minY,
            width: min(screenFrame.maxX, union.maxX + horizontalPadding) - max(screenFrame.minX, union.minX - horizontalPadding),
            height: edgeFrame.height
        )
    }

    public func isPointInStatusItemTriggerZone(
        _ point: CGPoint,
        itemBounds: [CGRect],
        screenFrame: CGRect,
        menuBarThickness: CGFloat = 40,
        horizontalPadding: CGFloat = 28
    ) -> Bool {
        if let topFrame = statusItemTriggerFrame(
            itemBounds: itemBounds,
            screenFrame: screenFrame,
            edge: .top,
            menuBarThickness: menuBarThickness,
            horizontalPadding: horizontalPadding
        ), topFrame.contains(point) {
            return true
        }

        if let bottomFrame = statusItemTriggerFrame(
            itemBounds: itemBounds,
            screenFrame: screenFrame,
            edge: .bottom,
            menuBarThickness: menuBarThickness,
            horizontalPadding: horizontalPadding
        ), bottomFrame.contains(point) {
            return true
        }

        return false
    }
}

public enum MenuBarEdge: Sendable {
    case top
    case bottom
}
