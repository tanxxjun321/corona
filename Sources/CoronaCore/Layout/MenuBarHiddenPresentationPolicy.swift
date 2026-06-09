import Foundation

public struct MenuBarHiddenPresentationPolicy: Sendable {
    public init() {}

    public func displayedHiddenUIDs(
        savedOrder: SectionOrder,
        cache: ItemCache
    ) -> [String] {
        let itemByUID = Set(cache.allItems.map(\.tag.stableIdentifier))
        let savedHiddenUIDs = savedOrder.hidden.filter { itemByUID.contains($0) }
        let physicalHiddenUIDs = cache.hiddenItems.map(\.tag.stableIdentifier)

        var seen = Set<String>()
        var result: [String] = []
        for uid in savedHiddenUIDs + physicalHiddenUIDs where !seen.contains(uid) {
            seen.insert(uid)
            result.append(uid)
        }
        return result
    }
}
