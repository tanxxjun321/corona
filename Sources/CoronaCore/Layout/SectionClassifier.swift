import CoreGraphics
import Foundation

public struct SectionBoundary: Equatable, Sendable {
    public var hiddenControlBounds: CGRect
    public var alwaysHiddenControlBounds: CGRect?

    public init(
        hiddenControlBounds: CGRect,
        alwaysHiddenControlBounds: CGRect? = nil
    ) {
        self.hiddenControlBounds = hiddenControlBounds
        self.alwaysHiddenControlBounds = alwaysHiddenControlBounds
    }
}

public struct SectionClassifier {
    public init() {}

    public func classify(
        itemBounds: CGRect,
        boundary: SectionBoundary
    ) -> MenuBarSection {
        if let alwaysHiddenControlBounds = boundary.alwaysHiddenControlBounds,
           itemBounds.maxX <= alwaysHiddenControlBounds.minX {
            return .alwaysHidden
        }

        if itemBounds.maxX <= boundary.hiddenControlBounds.minX {
            return .hidden
        }

        return .visible
    }

    public func classify(
        items: [MenuBarItem],
        boundary: SectionBoundary
    ) -> [UInt32: MenuBarSection] {
        Dictionary(uniqueKeysWithValues: items.map { item in
            (item.windowID, classify(itemBounds: item.bounds, boundary: boundary))
        })
    }
}
