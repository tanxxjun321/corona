import CoreGraphics
import Foundation

public struct NotchOverflowPlan: Equatable, Sendable {
    public var order: SectionOrder
    public var overflowUIDs: [String]

    public init(order: SectionOrder, overflowUIDs: [String]) {
        self.order = order
        self.overflowUIDs = overflowUIDs
    }
}

public struct NotchOverflowPlanner: Sendable {
    public init() {}

    public func plan(
        desiredOrder: SectionOrder,
        itemWidths: [String: CGFloat],
        hideableUIDs: Set<String>,
        availableWidth: CGFloat
    ) -> NotchOverflowPlan {
        guard availableWidth >= 0 else {
            return overflowAllHideableVisibleItems(
                desiredOrder: desiredOrder,
                hideableUIDs: hideableUIDs
            )
        }

        var usedWidth: CGFloat = 0
        var overflowUIDs: [String] = []

        for uid in desiredOrder.visible.reversed() {
            let width = itemWidths[uid] ?? 0
            if usedWidth + width <= availableWidth {
                usedWidth += width
                continue
            }

            if hideableUIDs.contains(uid) {
                overflowUIDs.append(uid)
            } else {
                usedWidth += width
            }
        }

        guard !overflowUIDs.isEmpty else {
            return NotchOverflowPlan(order: desiredOrder, overflowUIDs: [])
        }

        overflowUIDs.reverse()
        let overflowSet = Set(overflowUIDs)
        var updated = desiredOrder
        updated.visible = desiredOrder.visible.filter { !overflowSet.contains($0) }
        updated.hidden.append(contentsOf: overflowUIDs.filter { !updated.hidden.contains($0) })
        updated.alwaysHidden.removeAll { overflowSet.contains($0) }

        return NotchOverflowPlan(order: updated, overflowUIDs: overflowUIDs)
    }

    private func overflowAllHideableVisibleItems(
        desiredOrder: SectionOrder,
        hideableUIDs: Set<String>
    ) -> NotchOverflowPlan {
        let overflowUIDs = desiredOrder.visible.filter { hideableUIDs.contains($0) }
        guard !overflowUIDs.isEmpty else {
            return NotchOverflowPlan(order: desiredOrder, overflowUIDs: [])
        }

        var updated = desiredOrder
        updated.visible.removeAll { hideableUIDs.contains($0) }
        updated.hidden.append(contentsOf: overflowUIDs.filter { !updated.hidden.contains($0) })
        updated.alwaysHidden.removeAll { Set(overflowUIDs).contains($0) }
        return NotchOverflowPlan(order: updated, overflowUIDs: overflowUIDs)
    }
}
