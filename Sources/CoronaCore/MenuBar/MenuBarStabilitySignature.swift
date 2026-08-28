import CoreGraphics
import Foundation

/// Coarse, order-independent snapshot of the menu bar's physical layout.
/// Two equal signatures mean the bar did not move between samples; the app
/// layer polls this after mutations (expansion, collapse, item moves) to
/// detect when the bar has settled. Shared by the post-apply settle waits in
/// `MenuBarController` and `MainPanelWindowController`.
public struct MenuBarStabilitySignature: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public var uid: String
        public var x: Int
        public var y: Int
        public var width: Int
        public var height: Int

        public init(uid: String, frame: CGRect) {
            self.uid = uid
            x = Int(frame.minX.rounded())
            y = Int(frame.minY.rounded())
            width = Int(frame.width.rounded())
            height = Int(frame.height.rounded())
        }
    }

    public var items: [Item]

    public init(cache: ItemCache, boundary: SectionBoundary?, displayFrame: CGRect) {
        let visibleItems = cache.allItems.filter { item in
            item.isOnScreen && item.bounds.intersects(displayFrame)
        }
        let boundaryItems = Self.items(for: boundary)

        items = (visibleItems.map(Self.item(for:)) + boundaryItems)
            .sorted { lhs, rhs in
                if lhs.x != rhs.x {
                    return lhs.x < rhs.x
                }
                if lhs.y != rhs.y {
                    return lhs.y < rhs.y
                }
                return lhs.uid < rhs.uid
            }
    }

    private static func item(for item: MenuBarItem) -> Item {
        Item(uid: item.tag.stableIdentifier, frame: item.bounds)
    }

    private static func items(for boundary: SectionBoundary?) -> [Item] {
        guard let boundary else { return [] }
        var items = [Item(uid: "com.ltz.corona.control:hidden", frame: boundary.hiddenControlBounds)]
        if let alwaysHiddenControlBounds = boundary.alwaysHiddenControlBounds {
            items.append(Item(uid: "com.ltz.corona.control:alwaysHidden", frame: alwaysHiddenControlBounds))
        }
        return items
    }
}
