import AppKit
import CoronaCore

struct MenuBarVisualItem: Identifiable {
    var id: String { uid }
    var uid: String
    var title: String
    var owner: String
    var bounds: CGRect
    var position: Int
    var desiredSection: MenuBarSection
    var physicalSection: MenuBarSection
    var isMovable: Bool
    var isSystemItem: Bool
    var thumbnail: NSImage

    var isHidden: Bool {
        desiredSection != .visible
    }

    var needsApply: Bool {
        isMovable && desiredSection != physicalSection
    }
}

struct MenuBarVisualSnapshot {
    var items: [MenuBarVisualItem]

    var visibleItems: [MenuBarVisualItem] {
        items.filter { $0.desiredSection == .visible }
    }

    var hiddenItems: [MenuBarVisualItem] {
        items.filter { $0.desiredSection != .visible }
    }
}

@MainActor
struct MenuBarVisualSnapshotProvider {
    var thumbnailProvider: MenuBarThumbnailProviding

    func snapshot(
        cache: ItemCache,
        desiredOrder: SectionOrder
    ) -> MenuBarVisualSnapshot {
        let physicalSectionByUID = Self.sectionMap(for: cache)
        let desiredSectionByUID = Self.sectionMap(for: desiredOrder)
        let orderedItems = cache.allItems
            .filter { !MenuBarController.isCoronaSelfIdentifier($0.tag.stableIdentifier) }
            .sorted(by: Self.displaySort)

        let visualItems = orderedItems.enumerated().map { index, item in
            let uid = item.tag.stableIdentifier
            let desiredSection = desiredSectionByUID[uid] ?? physicalSectionByUID[uid] ?? .visible
            let isUserHideable = item.isMovable && item.canBeHidden
            return MenuBarVisualItem(
                uid: uid,
                title: item.title ?? item.tag.title,
                owner: item.tag.namespace,
                bounds: item.bounds,
                position: index + 1,
                desiredSection: desiredSection,
                physicalSection: physicalSectionByUID[uid] ?? .visible,
                isMovable: isUserHideable,
                isSystemItem: !item.canBeHidden,
                thumbnail: thumbnailProvider.thumbnail(for: item)
            )
        }

        return MenuBarVisualSnapshot(items: visualItems)
    }

    private static func sectionMap(for cache: ItemCache) -> [String: MenuBarSection] {
        var result: [String: MenuBarSection] = [:]
        for item in cache.visibleItems {
            result[item.tag.stableIdentifier] = .visible
        }
        for item in cache.hiddenItems {
            result[item.tag.stableIdentifier] = .hidden
        }
        for item in cache.alwaysHiddenItems {
            result[item.tag.stableIdentifier] = .alwaysHidden
        }
        return result
    }

    private static func sectionMap(for order: SectionOrder) -> [String: MenuBarSection] {
        var result: [String: MenuBarSection] = [:]
        for section in MenuBarSection.allCases {
            for uid in order[section] {
                result[uid] = section
            }
        }
        return result
    }

    private static func displaySort(_ lhs: MenuBarItem, _ rhs: MenuBarItem) -> Bool {
        if lhs.bounds.minX != rhs.bounds.minX {
            return lhs.bounds.minX < rhs.bounds.minX
        }
        return lhs.windowID < rhs.windowID
    }
}
