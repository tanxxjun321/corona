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
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let rawWindows = PrivateMenuBarWindowListProvider().windowDescriptions()
            ?? CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return MenuBarSnapshot(displayID: nil, items: [])
        }

        let targetDisplay = Self.targetMenuBarDisplay()
        let allDisplayFrames = Self.displayFrames()
        let targetDisplayFrames = [targetDisplay.frame]
        let menuBarCandidates = rawWindows.compactMap { makeMenuBarItem(from: $0, displayFrames: targetDisplayFrames) }
        let targetDisplayCandidates = MenuBarTargetDisplayFilter(
            targetDisplayFrame: targetDisplay.frame,
            otherDisplayFrames: allDisplayFrames.filter { !$0.equalTo(targetDisplay.frame) }
        ).itemsOnTargetDisplay(menuBarCandidates)
        let uniqueCandidates = MenuBarDisplayDuplicateFilter(
            primaryDisplayFrame: targetDisplay.frame,
            displayFrames: targetDisplayFrames
        ).uniqueItems(from: targetDisplayCandidates)
        let sourcePIDByWindowID = Self.shouldResolveSourcePIDs
            ? AXMenuBarSourcePIDResolver().resolveSourcePIDs(for: uniqueCandidates)
            : [:]
        let resolvedCandidates = uniqueCandidates.map { item in
            resolvedItem(item, sourcePID: sourcePIDByWindowID[item.windowID] ?? item.sourcePID)
        }
        let assigned = MenuBarItemIdentityAssigner().assignInstanceIndexes(to: resolvedCandidates)
        CoronaDebugLog.log("discovery.snapshot rawWindows=\(rawWindows.count) targetDisplay=\(targetDisplay.id) candidates=\(menuBarCandidates.count) target=\(targetDisplayCandidates.count) unique=\(uniqueCandidates.count) assigned=\(assigned.count) axSourcePID=\(Self.shouldResolveSourcePIDs)")
        for item in assigned {
            CoronaDebugLog.verbose("discovery.item uid=\(item.tag.stableIdentifier) ownerPID=\(item.ownerPID) sourcePID=\(item.sourcePID.map(String.init) ?? "nil") bounds=\(item.bounds.debugDescription) title=\(item.title ?? "nil") onScreen=\(item.isOnScreen) canBeHidden=\(item.canBeHidden) movable=\(item.isMovable)")
        }
        return MenuBarSnapshot(displayID: targetDisplay.id, items: assigned)
    }

    private func makeMenuBarItem(from info: [String: Any], displayFrames: [CGRect]) -> MenuBarItem? {
        guard let windowID = info[kCGWindowNumber as String] as? UInt32,
              let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
              let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
              let layer = info[kCGWindowLayer as String] as? Int else {
            return nil
        }

        let ownerName = info[kCGWindowOwnerName as String] as? String
        let title = (info[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 }

        let bundleIdentifier = NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier
        let filter = MenuBarWindowCandidateFilter(
            currentProcessID: Int32(ProcessInfo.processInfo.processIdentifier),
            mainBundleIdentifier: Bundle.main.bundleIdentifier,
            bundleIdentifierForPID: { pid in
                NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            }
        )
        guard filter.isMenuBarItemCandidate(
            MenuBarWindowCandidate(
                ownerPID: ownerPID,
                ownerName: ownerName,
                title: title,
                bounds: bounds,
                layer: layer
            ),
            displayFrames: displayFrames
        ) else {
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

    private func resolvedItem(_ item: MenuBarItem, sourcePID: Int32?) -> MenuBarItem {
        let sourceApplication = sourcePID.flatMap { NSRunningApplication(processIdentifier: $0) }
        let sourceBundleIdentifier = sourceApplication?.bundleIdentifier
        let namespace = sourceBundleIdentifier ?? item.tag.namespace
        let isSystemItem = sourceBundleIdentifier?.hasPrefix("com.apple.") == true

        return MenuBarItem(
            tag: MenuBarItemTag(
                namespace: namespace,
                title: item.tag.title,
                volatileWindowID: item.windowID
            ),
            windowID: item.windowID,
            ownerPID: item.ownerPID,
            sourcePID: sourcePID,
            bounds: item.bounds,
            title: item.title,
            isOnScreen: item.isOnScreen,
            isMovable: item.isMovable,
            canBeHidden: !isSystemItem
        )
    }

    private static func displayFrames() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return [CGDisplayBounds(CGMainDisplayID())]
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, nil) == .success else {
            return [CGDisplayBounds(CGMainDisplayID())]
        }
        return displays.map(CGDisplayBounds)
    }

    private static func targetMenuBarDisplay() -> TargetDisplay {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            let id = CGMainDisplayID()
            return TargetDisplay(id: id, frame: CGDisplayBounds(id))
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, nil) == .success else {
            let id = CGMainDisplayID()
            return TargetDisplay(id: id, frame: CGDisplayBounds(id))
        }

        let displayID: CGDirectDisplayID
        if let builtInDisplayID = displays.first(where: { CGDisplayIsBuiltin($0) != 0 }) {
            displayID = builtInDisplayID
        } else {
            displayID = CGMainDisplayID()
        }
        return TargetDisplay(id: displayID, frame: CGDisplayBounds(displayID))
    }

    private static var shouldResolveSourcePIDs: Bool {
        ProcessInfo.processInfo.environment["CORONA_RESOLVE_AX_MENU_BAR_SOURCE_PIDS"] == "1"
    }
}

private struct TargetDisplay {
    var id: CGDirectDisplayID
    var frame: CGRect
}
