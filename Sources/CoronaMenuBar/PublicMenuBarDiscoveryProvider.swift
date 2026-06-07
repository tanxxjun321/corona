import CoreGraphics
import CoronaCore
import Foundation

struct PublicMenuBarDiscoveryProvider: MenuBarDiscoveryProvider {
    var capability: DiscoveryCapability {
        .appStoreFallback
    }

    func snapshot() async throws -> MenuBarSnapshot {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return MenuBarSnapshot(displayID: nil, items: [])
        }

        let menuBarCandidates = rawWindows.compactMap(makeMenuBarItem)
        let assigned = MenuBarItemIdentityAssigner().assignInstanceIndexes(to: menuBarCandidates)
        return MenuBarSnapshot(displayID: CGMainDisplayID(), items: assigned)
    }

    private func makeMenuBarItem(from info: [String: Any]) -> MenuBarItem? {
        guard let windowID = info[kCGWindowNumber as String] as? UInt32,
              let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
              let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else {
            return nil
        }

        guard isLikelyMenuBarWindow(bounds: bounds) else {
            return nil
        }

        let ownerName = info[kCGWindowOwnerName as String] as? String
        let title = (info[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let namespace = ownerName ?? "pid.\(ownerPID)"
        let displayTitle = title ?? ownerName ?? "Status Item"
        let isOnScreen = (info[kCGWindowIsOnscreen as String] as? Bool) ?? true

        return MenuBarItem(
            tag: MenuBarItemTag(
                namespace: namespace,
                title: displayTitle,
                volatileWindowID: windowID
            ),
            windowID: windowID,
            ownerPID: ownerPID,
            sourcePID: ownerPID,
            bounds: bounds,
            title: title,
            isOnScreen: isOnScreen,
            isMovable: true,
            canBeHidden: true
        )
    }

    private func isLikelyMenuBarWindow(bounds: CGRect) -> Bool {
        guard bounds.width > 0, bounds.height > 0, bounds.height <= 40 else {
            return false
        }

        let displays = NSScreenFrameProvider.displayFrames()
        return displays.contains { frame in
            abs(bounds.minY - frame.minY) <= 2 || abs(bounds.maxY - frame.maxY) <= 2
        }
    }
}

private enum NSScreenFrameProvider {
    static func displayFrames() -> [CGRect] {
        CGGetActiveDisplayList(0, nil, nil)
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = Array(repeating: CGDirectDisplayID(), count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        return displays.map(CGDisplayBounds)
    }
}
