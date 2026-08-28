import Foundation

/// Step budget for a full layout apply.
///
/// The budget scales with the number of manageable items because converging a
/// layout costs roughly one step per move and each item can require both a
/// section move and an in-section reordering. `stepsPerManageableItem` (4)
/// doubles that worst case to leave headroom for verification-driven extra
/// steps. The `floor` (20) keeps small layouts — and pending-relocation
/// recovery rounds, which share the budget — from being starved when only a
/// handful of items are present.
public enum LayoutApplyStepBudget {
    public static let floor = 20
    public static let stepsPerManageableItem = 4

    public static func stepLimit(manageableItemCount: Int) -> Int {
        max(floor, stepsPerManageableItem * max(0, manageableItemCount))
    }
}
