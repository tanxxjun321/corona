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
    private let logger: any DiagnosticLogging

    public init(logger: any DiagnosticLogging = DisabledDiagnosticLogger()) {
        self.logger = logger
    }

    public func classify(
        itemBounds: CGRect,
        boundary: SectionBoundary
    ) -> MenuBarSection {
        guard let alwaysHiddenControlBounds = boundary.alwaysHiddenControlBounds else {
            if itemBounds.maxX <= boundary.hiddenControlBounds.minX {
                return .hidden
            }
            return .visible
        }

        if alwaysHiddenControlBounds.minX < boundary.hiddenControlBounds.minX {
            if itemBounds.maxX <= alwaysHiddenControlBounds.minX {
                return .alwaysHidden
            }

            if itemBounds.maxX <= boundary.hiddenControlBounds.minX {
                return .hidden
            }

            return .visible
        }

        if itemBounds.maxX <= boundary.hiddenControlBounds.minX {
            return .alwaysHidden
        }

        if itemBounds.maxX <= alwaysHiddenControlBounds.minX {
            return .hidden
        }

        return .visible
    }

    public func classify(
        items: [MenuBarItem],
        boundary: SectionBoundary
    ) -> [UInt32: MenuBarSection] {
        // Items come from system-provided snapshots; duplicate window IDs
        // must degrade to first-wins instead of crashing.
        var sections: [UInt32: MenuBarSection] = [:]
        var duplicateWindowIDs: [UInt32] = []
        for item in items {
            guard sections[item.windowID] == nil else {
                duplicateWindowIDs.append(item.windowID)
                continue
            }
            sections[item.windowID] = classify(itemBounds: item.bounds, boundary: boundary)
        }
        if !duplicateWindowIDs.isEmpty {
            logger.log(.warning("SectionClassifier dropped items with duplicate window IDs (first wins): \(duplicateWindowIDs.map(String.init).joined(separator: ", "))"))
        }
        return sections
    }
}
