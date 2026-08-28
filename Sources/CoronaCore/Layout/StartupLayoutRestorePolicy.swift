import Foundation

/// Decides whether launch should reconcile the physical menu bar against the
/// saved layout. Any non-empty saved order qualifies — including all-visible
/// layouts, whose on-screen order can still drift — and so does any pending
/// relocation left behind by an interrupted apply (#19).
public enum StartupLayoutRestorePolicy {
    public static func shouldRestore(
        savedOrder: SectionOrder,
        pendingRelocations: [String: PendingRelocation]
    ) -> Bool {
        !savedOrder.isEmpty || !pendingRelocations.isEmpty
    }
}
