import Foundation

public struct MenuBarItemIdentityAssigner {
    public init() {}

    public func assignInstanceIndexes(to items: [MenuBarItem]) -> [MenuBarItem] {
        let grouped = Dictionary(grouping: items) { item in
            IdentityGroupKey(namespace: item.tag.namespace, title: item.tag.title)
        }

        var indexedByWindowID: [UInt32: Int?] = [:]
        for (_, group) in grouped {
            let sorted = group.sorted { lhs, rhs in
                if lhs.sourcePID != rhs.sourcePID {
                    return (lhs.sourcePID ?? Int32.max) < (rhs.sourcePID ?? Int32.max)
                }
                return lhs.windowID < rhs.windowID
            }

            if sorted.count == 1 {
                indexedByWindowID[sorted[0].windowID] = nil
            } else {
                for (index, item) in sorted.enumerated() {
                    indexedByWindowID[item.windowID] = index
                }
            }
        }

        return items.map { item in
            var copy = item
            copy.tag.instanceIndex = indexedByWindowID[item.windowID] ?? nil
            return copy
        }
    }
}

private struct IdentityGroupKey: Hashable {
    var namespace: String
    var title: String
}
