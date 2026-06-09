import Foundation

public enum LayoutTarget: Codable, Equatable, Sendable {
    case leftOfUID(String)
    case rightOfUID(String)
    case sectionBoundary(MenuBarSection)
}

public struct LayoutMove: Codable, Equatable, Sendable {
    public var itemUID: String
    public var target: LayoutTarget

    public init(itemUID: String, target: LayoutTarget) {
        self.itemUID = itemUID
        self.target = target
    }
}

public struct LayoutPlanner {
    public init() {}

    public func mergedOrder(
        cache: ItemCache,
        preference: LayoutPreference
    ) -> SectionOrder {
        var order = preference.savedOrder
        let currentByUID = Dictionary(uniqueKeysWithValues: cache.allItems.map { item in
            (item.tag.stableIdentifier, item)
        })
        let currentUIDs = Set(currentByUID.keys)
        let knownUIDs = Set(order.visible + order.hidden + order.alwaysHidden)

        for section in MenuBarSection.allCases {
            order[section] = order[section].filter { uid in
                currentUIDs.contains(uid) || knownUIDs.contains(uid)
            }
        }

        let targetForNewItems = normalizedNewItemsSection(preference)
        let newUIDs = cache.allItems
            .map(\.tag.stableIdentifier)
            .filter { !knownUIDs.contains($0) }

        for uid in newUIDs {
            insert(uid, into: targetForNewItems, order: &order, placement: preference.newItemsPlacement)
        }

        return order
    }

    public func nextMove(
        currentOrder: SectionOrder,
        desiredOrder: SectionOrder
    ) -> LayoutMove? {
        nextMove(currentOrder: currentOrder, desiredOrder: desiredOrder, preferredItemUID: nil)
    }

    public func nextMove(
        currentOrder: SectionOrder,
        desiredOrder: SectionOrder,
        preferredItemUID: String?
    ) -> LayoutMove? {
        if let preferredItemUID,
           let move = preferredMove(for: preferredItemUID, currentOrder: currentOrder, desiredOrder: desiredOrder) {
            return move
        }

        if let move = nextVisibleRestorationMove(currentOrder: currentOrder, desiredOrder: desiredOrder) {
            return move
        }

        if let move = nextCrossSectionMove(currentOrder: currentOrder, desiredOrder: desiredOrder) {
            return move
        }

        for section in MenuBarSection.allCases {
            let current = currentOrder[section].filter { desiredOrder[section].contains($0) }
            let desired = desiredOrder[section]

            if let move = nextMoveWithinSection(section: section, current: current, desired: desired) {
                return move
            }
        }

        return nil
    }

    private func preferredMove(
        for uid: String,
        currentOrder: SectionOrder,
        desiredOrder: SectionOrder
    ) -> LayoutMove? {
        guard let currentSection = currentOrder.section(containing: uid),
              let desiredSection = desiredOrder.section(containing: uid) else {
            return nil
        }

        if currentSection != desiredSection {
            return LayoutMove(itemUID: uid, target: target(for: uid, in: desiredSection, desiredOrder: desiredOrder))
        }

        let currentInSection = currentOrder[currentSection].filter { desiredOrder[currentSection].contains($0) }
        guard currentInSection != desiredOrder[desiredSection] else {
            return nil
        }
        return LayoutMove(itemUID: uid, target: target(for: uid, in: desiredSection, desiredOrder: desiredOrder))
    }

    private func target(for uid: String, in section: MenuBarSection, desiredOrder: SectionOrder) -> LayoutTarget {
        let desiredSectionOrder = desiredOrder[section]
        if section == .visible {
            guard let previous = previousUID(before: uid, in: desiredSectionOrder) else {
                if let next = nextUID(after: uid, in: desiredSectionOrder) {
                    return .leftOfUID(next)
                }
                return .sectionBoundary(section)
            }
            return .rightOfUID(previous)
        }
        guard let previous = previousUID(before: uid, in: desiredSectionOrder) else {
            return .sectionBoundary(section)
        }
        return .rightOfUID(previous)
    }

    private func nextVisibleRestorationMove(currentOrder: SectionOrder, desiredOrder: SectionOrder) -> LayoutMove? {
        let currentSectionByUID = sectionMap(currentOrder)

        for uid in desiredOrder.visible where currentSectionByUID[uid] != .visible {
            return LayoutMove(itemUID: uid, target: .sectionBoundary(.visible))
        }

        return nil
    }

    private func normalizedNewItemsSection(_ preference: LayoutPreference) -> MenuBarSection {
        if preference.newItemsSection == .alwaysHidden && !preference.alwaysHiddenEnabled {
            return .hidden
        }
        return preference.newItemsSection
    }

    private func insert(
        _ uid: String,
        into section: MenuBarSection,
        order: inout SectionOrder,
        placement: NewItemsPlacement
    ) {
        switch placement {
        case .append:
            order[section].append(uid)
        case .prepend:
            order[section].insert(uid, at: 0)
        case .leftOf(let anchor):
            let index = order[section].firstIndex(of: anchor) ?? order[section].endIndex
            order[section].insert(uid, at: index)
        case .rightOf(let anchor):
            let index = order[section].firstIndex(of: anchor).map { order[section].index(after: $0) } ?? order[section].endIndex
            order[section].insert(uid, at: index)
        }
    }

    private func nextMoveWithinSection(section: MenuBarSection, current: [String], desired: [String]) -> LayoutMove? {
        guard current != desired else { return nil }

        for desiredIndex in desired.indices {
            let uid = desired[desiredIndex]
            guard current.indices.contains(desiredIndex), current[desiredIndex] != uid else {
                continue
            }

            if desiredIndex == 0 {
                if section == .visible, desired.indices.contains(desired.index(after: desiredIndex)) {
                    return LayoutMove(itemUID: uid, target: .leftOfUID(desired[desired.index(after: desiredIndex)]))
                }
                return LayoutMove(itemUID: uid, target: .sectionBoundary(section))
            }
            return LayoutMove(itemUID: uid, target: .rightOfUID(desired[desiredIndex - 1]))
        }

        return nil
    }

    private func nextCrossSectionMove(currentOrder: SectionOrder, desiredOrder: SectionOrder) -> LayoutMove? {
        let currentSectionByUID = sectionMap(currentOrder)
        let desiredSectionByUID = sectionMap(desiredOrder)

        for section in MenuBarSection.allCases {
            for uid in desiredOrder[section] {
                if currentSectionByUID[uid] != desiredSectionByUID[uid] {
                    if section == .visible {
                        return LayoutMove(itemUID: uid, target: .sectionBoundary(section))
                    }
                    if let previous = previousUID(before: uid, in: desiredOrder[section]) {
                        return LayoutMove(itemUID: uid, target: .rightOfUID(previous))
                    }
                    return LayoutMove(itemUID: uid, target: .sectionBoundary(section))
                }
            }
        }

        return nil
    }

    private func sectionMap(_ order: SectionOrder) -> [String: MenuBarSection] {
        var result: [String: MenuBarSection] = [:]
        for section in MenuBarSection.allCases {
            for uid in order[section] {
                result[uid] = section
            }
        }
        return result
    }

    private func previousUID(before uid: String, in order: [String]) -> String? {
        guard let index = order.firstIndex(of: uid), index > order.startIndex else {
            return nil
        }
        return order[order.index(before: index)]
    }

    private func nextUID(after uid: String, in order: [String]) -> String? {
        guard let index = order.firstIndex(of: uid) else {
            return nil
        }
        let nextIndex = order.index(after: index)
        guard nextIndex < order.endIndex else {
            return nil
        }
        return order[nextIndex]
    }
}
