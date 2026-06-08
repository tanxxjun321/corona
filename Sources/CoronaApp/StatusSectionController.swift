import AppKit

enum StatusSectionVisibility {
    case shown
    case hidden
}

final class StatusSectionController {
    private enum Constants {
        static let compactLength: CGFloat = 10
        static let hiddenLength: CGFloat = 10_000
    }

    private let hiddenControlItem: NSStatusItem
    private let alwaysHiddenControlItem: NSStatusItem
    private var spacerItems: [NSStatusItem] = []

    private(set) var hiddenVisibility: StatusSectionVisibility = .hidden
    private(set) var alwaysHiddenVisibility: StatusSectionVisibility = .hidden

    init() {
        hiddenControlItem = NSStatusBar.system.statusItem(withLength: Constants.compactLength)
        alwaysHiddenControlItem = NSStatusBar.system.statusItem(withLength: Constants.compactLength)
        configureControlItem(hiddenControlItem)
        configureControlItem(alwaysHiddenControlItem)
        apply(visibility: hiddenVisibility, to: hiddenControlItem)
        alwaysHiddenControlItem.isVisible = false
    }

    func setHiddenSectionVisible(_ visible: Bool) {
        hiddenVisibility = visible ? .shown : .hidden
        apply(visibility: hiddenVisibility, to: hiddenControlItem)
    }

    func setAlwaysHiddenSectionEnabled(_ enabled: Bool) {
        alwaysHiddenControlItem.isVisible = enabled
        if enabled {
            apply(visibility: alwaysHiddenVisibility, to: alwaysHiddenControlItem)
        }
    }

    func setAlwaysHiddenSectionVisible(_ visible: Bool) {
        alwaysHiddenVisibility = visible ? .shown : .hidden
        apply(visibility: alwaysHiddenVisibility, to: alwaysHiddenControlItem)
    }

    func ensureSpacerCoverage(displayWidth: CGFloat) {
        let requiredCount = max(0, Int(ceil(displayWidth / Constants.hiddenLength)) - 1)
        while spacerItems.count < requiredCount {
            let item = NSStatusBar.system.statusItem(withLength: Constants.hiddenLength)
            configureControlItem(item)
            spacerItems.append(item)
        }
        while spacerItems.count > requiredCount {
            let item = spacerItems.removeLast()
            NSStatusBar.system.removeStatusItem(item)
        }
    }

    func currentBoundary() -> SectionBoundary? {
        guard let hiddenBounds = statusItemBounds(hiddenControlItem),
              isUsableBoundaryBounds(hiddenBounds) else {
            return nil
        }

        let alwaysHiddenBounds: CGRect?
        if alwaysHiddenControlItem.isVisible {
            guard let bounds = statusItemBounds(alwaysHiddenControlItem),
                  isUsableBoundaryBounds(bounds),
                  isDistinctBoundary(bounds, from: hiddenBounds) else {
                return nil
            }
            alwaysHiddenBounds = bounds
        } else {
            alwaysHiddenBounds = nil
        }

        return SectionBoundary(
            hiddenControlBounds: hiddenBounds,
            alwaysHiddenControlBounds: alwaysHiddenBounds
        )
    }

    func boundaryItems() -> [MenuBarSection: MenuBarItem] {
        guard currentBoundary() != nil else { return [:] }

        var result: [MenuBarSection: MenuBarItem] = [:]
        if let hidden = controlItem(hiddenControlItem, title: "hiddenControl") {
            result[.visible] = hidden
            result[.hidden] = hidden
        }
        if alwaysHiddenControlItem.isVisible,
           let alwaysHidden = controlItem(alwaysHiddenControlItem, title: "alwaysHiddenControl") {
            if let hidden = result[.hidden], alwaysHidden.bounds.minX > hidden.bounds.minX {
                result[.visible] = alwaysHidden
            }
            result[.alwaysHidden] = alwaysHidden
        }
        return result
    }

    private func configureControlItem(_ item: NSStatusItem) {
        item.button?.image = nil
        item.button?.title = ""
        item.button?.alphaValue = 0
        item.button?.isEnabled = false
    }

    private func apply(visibility: StatusSectionVisibility, to item: NSStatusItem) {
        switch visibility {
        case .shown:
            item.length = Constants.compactLength
            item.button?.alphaValue = 0.35
            item.button?.isEnabled = true
        case .hidden:
            item.length = Constants.hiddenLength
            item.button?.alphaValue = 0
            item.button?.isEnabled = false
        }
    }

    private func statusItemBounds(_ item: NSStatusItem) -> CGRect? {
        item.button?.window?.frame
    }

    private func isUsableBoundaryBounds(_ bounds: CGRect) -> Bool {
        !bounds.isNull && !bounds.isInfinite && bounds.width > 0 && bounds.height > 0
    }

    private func isDistinctBoundary(_ lhs: CGRect, from rhs: CGRect) -> Bool {
        abs(lhs.midX - rhs.midX) > 0.5
    }

    private func controlItem(_ item: NSStatusItem, title: String) -> MenuBarItem? {
        guard let window = item.button?.window else { return nil }
        return MenuBarItem(
            tag: MenuBarItemTag(
                namespace: "com.ltz.corona.control",
                title: title,
                volatileWindowID: UInt32(window.windowNumber)
            ),
            windowID: UInt32(window.windowNumber),
            ownerPID: Int32(ProcessInfo.processInfo.processIdentifier),
            sourcePID: Int32(ProcessInfo.processInfo.processIdentifier),
            bounds: window.frame,
            title: title,
            isOnScreen: true,
            isMovable: false,
            canBeHidden: false
        )
    }
}
