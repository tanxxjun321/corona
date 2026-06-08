import CoreGraphics
import Foundation

public struct MenuBarDisplayDuplicateFilter: Sendable {
    private let primaryDisplayFrame: CGRect
    private let displayFrames: [CGRect]

    public init(primaryDisplayFrame: CGRect, displayFrames: [CGRect]) {
        self.primaryDisplayFrame = primaryDisplayFrame
        self.displayFrames = displayFrames.isEmpty ? [primaryDisplayFrame] : displayFrames
    }

    public func uniqueItems(from items: [MenuBarItem]) -> [MenuBarItem] {
        var selected: [DuplicateKey: MenuBarItem] = [:]
        var selectedScore: [DuplicateKey: DisplayScore] = [:]

        for item in items {
            let displayFrame = displayFrame(for: item.bounds)
            let key = duplicateKey(for: item, displayFrame: displayFrame)
            let score = score(for: item.bounds, displayFrame: displayFrame)

            guard let existingScore = selectedScore[key] else {
                selected[key] = item
                selectedScore[key] = score
                continue
            }

            if score.isPreferred(over: existingScore) {
                selected[key] = item
                selectedScore[key] = score
            }
        }

        return items.compactMap { item in
            let displayFrame = displayFrame(for: item.bounds)
            let key = duplicateKey(for: item, displayFrame: displayFrame)
            return selected[key]?.windowID == item.windowID ? item : nil
        }
    }

    private func displayFrame(for bounds: CGRect) -> CGRect {
        displayFrames.max { lhs, rhs in
            displayAffinityScore(for: bounds, displayFrame: lhs) < displayAffinityScore(for: bounds, displayFrame: rhs)
        } ?? primaryDisplayFrame
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
        return -verticalDistance * 10 + horizontalOverlap - horizontalDistance
    }

    private func duplicateKey(for item: MenuBarItem, displayFrame: CGRect) -> DuplicateKey {
        DuplicateKey(
            namespace: item.tag.namespace,
            title: item.tag.title,
            sourcePID: item.sourcePID,
            ownerPID: item.ownerPID,
            widthBucket: Int((item.bounds.width / 2).rounded()),
            heightBucket: Int((item.bounds.height / 2).rounded()),
            rightOffsetBucket: Int(((displayFrame.maxX - item.bounds.midX) / 6).rounded())
        )
    }

    private func score(for bounds: CGRect, displayFrame: CGRect) -> DisplayScore {
        DisplayScore(
            isPrimaryDisplay: displayFrame.equalTo(primaryDisplayFrame),
            isOnDisplay: bounds.intersects(displayFrame),
            area: bounds.width * bounds.height
        )
    }
}

private struct DuplicateKey: Hashable {
    var namespace: String
    var title: String
    var sourcePID: Int32?
    var ownerPID: Int32
    var widthBucket: Int
    var heightBucket: Int
    var rightOffsetBucket: Int
}

private struct DisplayScore: Equatable {
    var isPrimaryDisplay: Bool
    var isOnDisplay: Bool
    var area: CGFloat

    func isPreferred(over other: DisplayScore) -> Bool {
        if isPrimaryDisplay != other.isPrimaryDisplay {
            return isPrimaryDisplay
        }
        if isOnDisplay != other.isOnDisplay {
            return isOnDisplay
        }
        return area > other.area
    }
}
