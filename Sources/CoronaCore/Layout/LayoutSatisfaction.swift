import Foundation

/// A saved item whose physical section differs from the section the saved
/// layout expects it in.
public struct LayoutSectionMismatch: Equatable, Sendable {
    public var uid: String
    public var expectedSection: MenuBarSection
    public var actualSection: MenuBarSection?

    public init(uid: String, expectedSection: MenuBarSection, actualSection: MenuBarSection?) {
        self.uid = uid
        self.expectedSection = expectedSection
        self.actualSection = actualSection
    }
}

/// A section whose physical left-to-right order of saved, order-manageable
/// items differs from the saved relative order.
public struct LayoutOrderMismatch: Equatable, Sendable {
    public var section: MenuBarSection
    public var expectedUIDs: [String]
    public var actualUIDs: [String]

    public init(section: MenuBarSection, expectedUIDs: [String], actualUIDs: [String]) {
        self.section = section
        self.expectedUIDs = expectedUIDs
        self.actualUIDs = actualUIDs
    }
}

/// The outcome of comparing the physical menu bar against the saved order.
/// "Satisfied" means section membership *and* relative order both match.
public struct LayoutSatisfactionReport: Equatable, Sendable {
    public var sectionMismatches: [LayoutSectionMismatch]
    public var orderMismatches: [LayoutOrderMismatch]

    public init(
        sectionMismatches: [LayoutSectionMismatch],
        orderMismatches: [LayoutOrderMismatch]
    ) {
        self.sectionMismatches = sectionMismatches
        self.orderMismatches = orderMismatches
    }

    public var isSatisfied: Bool {
        sectionMismatches.isEmpty && orderMismatches.isEmpty
    }
}

/// Pure comparison between the physical menu bar state and the saved order.
/// Used by the post-apply satisfaction guard and reused by the reconciliation
/// state machine's deviation detection.
public struct LayoutSatisfactionEvaluator {
    public init() {}

    /// Compares `cache` (physical truth) against `savedOrder` (desired truth).
    ///
    /// Section check: a uid saved in `section` is expected in `section` when
    /// its physical item is movable and can be hidden; a movable item that
    /// cannot be hidden is expected in `.visible`. Saved uids missing from the
    /// cache, or whose items are not movable, are skipped.
    ///
    /// Order check: within each section, the physical sequence restricted to
    /// items that are expected in that section and satisfy
    /// `isOrderManageable` must equal the saved order restricted the same way
    /// (subsequence comparison). Items outside the saved order — new items,
    /// unmanaged system modules such as Control Center extras, and Corona's
    /// own control items — never affect the comparison, and neither do items
    /// the caller's predicate marks as not order-manageable.
    public func report(
        cache: ItemCache,
        savedOrder: SectionOrder,
        isOrderManageable: (MenuBarItem) -> Bool
    ) -> LayoutSatisfactionReport {
        let itemByUID = Dictionary(uniqueKeysWithValues: cache.allItems.map { ($0.tag.stableIdentifier, $0) })
        var actualSectionByUID: [String: MenuBarSection] = [:]
        for section in MenuBarSection.allCases {
            for item in cache.items(in: section) {
                actualSectionByUID[item.tag.stableIdentifier] = section
            }
        }

        var expectedSectionByUID: [String: MenuBarSection] = [:]
        var sectionMismatches: [LayoutSectionMismatch] = []
        for section in MenuBarSection.allCases {
            for uid in savedOrder[section] {
                guard let item = itemByUID[uid], item.isMovable else { continue }
                let targetSection: MenuBarSection = item.canBeHidden ? section : .visible
                expectedSectionByUID[uid] = targetSection
                if actualSectionByUID[uid] != targetSection {
                    sectionMismatches.append(LayoutSectionMismatch(
                        uid: uid,
                        expectedSection: targetSection,
                        actualSection: actualSectionByUID[uid]
                    ))
                }
            }
        }

        var orderMismatches: [LayoutOrderMismatch] = []
        for section in MenuBarSection.allCases {
            let expectedUIDs = savedOrder[section].filter { uid in
                guard expectedSectionByUID[uid] == section, let item = itemByUID[uid] else { return false }
                return isOrderManageable(item)
            }
            let expectedSet = Set(expectedUIDs)
            let actualUIDs = cache.items(in: section)
                .filter { expectedSet.contains($0.tag.stableIdentifier) && isOrderManageable($0) }
                .map(\.tag.stableIdentifier)
            if actualUIDs != expectedUIDs {
                orderMismatches.append(LayoutOrderMismatch(
                    section: section,
                    expectedUIDs: expectedUIDs,
                    actualUIDs: actualUIDs
                ))
            }
        }

        return LayoutSatisfactionReport(
            sectionMismatches: sectionMismatches,
            orderMismatches: orderMismatches
        )
    }
}

private extension ItemCache {
    func items(in section: MenuBarSection) -> [MenuBarItem] {
        switch section {
        case .visible:
            return visibleItems
        case .hidden:
            return hiddenItems
        case .alwaysHidden:
            return alwaysHiddenItems
        }
    }
}
