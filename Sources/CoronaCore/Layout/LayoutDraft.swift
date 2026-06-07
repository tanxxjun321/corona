import Foundation

public struct LayoutDraft: Equatable, Sendable {
    public private(set) var order: SectionOrder

    public init(order: SectionOrder = SectionOrder()) {
        self.order = order
    }

    public mutating func move(_ uid: String, to section: MenuBarSection) {
        remove(uid)
        order[section].append(uid)
    }

    public mutating func move(_ uid: String, to section: MenuBarSection, at index: Int) {
        let previousSection = order.section(containing: uid)
        let previousIndex = previousSection.flatMap { order[$0].firstIndex(of: uid) }
        remove(uid)
        let adjustedIndex: Int
        if previousSection == section, let previousIndex, previousIndex < index {
            adjustedIndex = index - 1
        } else {
            adjustedIndex = index
        }
        let insertionIndex = max(0, min(adjustedIndex, order[section].count))
        order[section].insert(uid, at: insertionIndex)
    }

    public mutating func moveUp(_ uid: String, in section: MenuBarSection) {
        guard let index = order[section].firstIndex(of: uid), index > order[section].startIndex else {
            return
        }
        order[section].swapAt(index, order[section].index(before: index))
    }

    public mutating func moveDown(_ uid: String, in section: MenuBarSection) {
        guard let index = order[section].firstIndex(of: uid) else { return }
        let next = order[section].index(after: index)
        guard next < order[section].endIndex else { return }
        order[section].swapAt(index, next)
    }

    public mutating func reset(visibleUIDs: [String]) {
        order = SectionOrder(visible: visibleUIDs, hidden: [], alwaysHidden: [])
    }

    private mutating func remove(_ uid: String) {
        for section in MenuBarSection.allCases {
            order[section].removeAll { $0 == uid }
        }
    }
}
