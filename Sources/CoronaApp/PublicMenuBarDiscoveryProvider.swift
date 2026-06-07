import AppKit
import CoreGraphics
import CoronaCore
import Foundation

typealias PublicMenuBarDiscoveryProvider = DirectMenuBarDiscoveryProvider

struct DirectMenuBarDiscoveryProvider: MenuBarDiscoveryProvider {
    var capability: DiscoveryCapability {
        .directFull
    }

    func snapshot() async throws -> MenuBarSnapshot {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return MenuBarSnapshot(displayID: nil, items: [])
        }

        let menuBarCandidates = rawWindows.compactMap(makeMenuBarItem)
        let assigned = MenuBarItemIdentityAssigner().assignInstanceIndexes(to: menuBarCandidates)
        CoronaDebugLog.log("discovery.snapshot rawWindows=\(rawWindows.count) candidates=\(menuBarCandidates.count) assigned=\(assigned.count)")
        for item in assigned {
            CoronaDebugLog.log("discovery.item uid=\(item.tag.stableIdentifier) ownerPID=\(item.ownerPID) sourcePID=\(item.sourcePID.map(String.init) ?? "nil") bounds=\(item.bounds.debugDescription) title=\(item.title ?? "nil") movable=\(item.isMovable)")
        }
        return MenuBarSnapshot(displayID: CGMainDisplayID(), items: assigned)
    }

    private func makeMenuBarItem(from info: [String: Any]) -> MenuBarItem? {
        guard let windowID = info[kCGWindowNumber as String] as? UInt32,
              let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
              let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else {
            return nil
        }

        let ownerName = info[kCGWindowOwnerName as String] as? String
        let title = (info[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 }

        guard ownerPID != Int32(ProcessInfo.processInfo.processIdentifier) else {
            return nil
        }
        guard ownerName != "Window Server", title != "Menubar" else {
            return nil
        }
        guard isLikelyMenuBarWindow(bounds: bounds) else {
            return nil
        }

        let bundleIdentifier = NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier
        guard bundleIdentifier != Bundle.main.bundleIdentifier else {
            return nil
        }

        let namespace = bundleIdentifier ?? ownerName ?? "pid.\(ownerPID)"
        let displayTitle = title ?? ownerName ?? "Status Item"
        let isOnScreen = (info[kCGWindowIsOnscreen as String] as? Bool) ?? true

        let isSystemItem = bundleIdentifier?.hasPrefix("com.apple.") == true

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
            canBeHidden: !isSystemItem
        )
    }

    private func isLikelyMenuBarWindow(bounds: CGRect) -> Bool {
        guard bounds.width > 0, bounds.height > 0, bounds.height <= 40 else {
            return false
        }

        let mainDisplayFrame = CGDisplayBounds(CGMainDisplayID())
        return abs(bounds.minY - mainDisplayFrame.minY) <= 2
            || abs(bounds.maxY - mainDisplayFrame.maxY) <= 2
    }
}
