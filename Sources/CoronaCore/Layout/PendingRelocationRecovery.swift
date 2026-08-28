import Foundation

/// Planning helpers for resuming pending relocations after an interrupted
/// apply (#19).
public enum PendingRelocationRecovery {
    /// Deterministic processing order for pending records: Dictionary
    /// iteration order is unspecified, so recoveries run sorted by uid.
    public static func sortedUIDs(_ pending: [String: PendingRelocation]) -> [String] {
        pending.keys.sorted()
    }

    /// Builds the order that moves `uid` into `targetSection` at its saved
    /// position — right before the first item the saved order places after
    /// it — instead of blindly prepending to the section. A uid unknown to
    /// the saved order lands at the end of the section.
    public static func recoveryOrder(
        uid: String,
        targetSection: MenuBarSection,
        currentOrder: SectionOrder,
        savedOrder: SectionOrder
    ) -> SectionOrder {
        var order = currentOrder
        for section in MenuBarSection.allCases {
            order[section].removeAll { $0 == uid }
        }
        let sectionItems = order[targetSection]
        let savedSection = savedOrder[targetSection]
        let insertionIndex = sectionItems.firstIndex { other in
            guard let uidIndex = savedSection.firstIndex(of: uid),
                  let otherIndex = savedSection.firstIndex(of: other) else {
                return false
            }
            return otherIndex > uidIndex
        } ?? sectionItems.count
        order[targetSection].insert(uid, at: insertionIndex)
        return order
    }
}
