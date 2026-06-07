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
        hiddenControlItem = NSStatusBar.system.statusItem(withLength: Constants.hiddenLength)
        alwaysHiddenControlItem = NSStatusBar.system.statusItem(withLength: Constants.hiddenLength)
        configureControlItem(hiddenControlItem)
        configureControlItem(alwaysHiddenControlItem)
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
}
