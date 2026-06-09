import AppKit
import CoreGraphics
import Darwin
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
        if Self.shouldUseAXOrderedDiscovery,
           let axSnapshot = Self.axOrderedSnapshot(
            rawWindows: rawWindows,
            targetDisplay: targetDisplay,
            allDisplayFrames: allDisplayFrames,
            targetDisplayFrames: targetDisplayFrames
        ) {
            return axSnapshot
        }

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
        let canonicalCandidates = MenuBarItemCanonicalizer()
            .canonicalized(resolvedCandidates)
            .map(Self.applyingMovementPolicy)
        let assigned = MenuBarItemIdentityAssigner().assignInstanceIndexes(to: canonicalCandidates)
        let rejectedByNonTargetDisplay = menuBarCandidates.count - targetDisplayCandidates.count
        let rejectedAsDuplicate = targetDisplayCandidates.count - uniqueCandidates.count
        CoronaDebugLog.verbose("discovery.snapshot targetDisplay=\(targetDisplay.id) targetFrame=\(targetDisplay.frame.debugDescription) rawWindows=\(rawWindows.count) candidates=\(menuBarCandidates.count) rejectedNonTargetDisplay=\(rejectedByNonTargetDisplay) rejectedDuplicate=\(rejectedAsDuplicate) assigned=\(assigned.count) axSourcePID=\(Self.shouldResolveSourcePIDs)")
        CoronaDebugLog.verbose("discovery.assigned uids=\(assigned.map { "\($0.tag.stableIdentifier)@\($0.bounds.debugDescription)" })")
        for item in assigned {
            CoronaDebugLog.verbose("discovery.item uid=\(item.tag.stableIdentifier) ownerPID=\(item.ownerPID) sourcePID=\(item.sourcePID.map(String.init) ?? "nil") bounds=\(item.bounds.debugDescription) title=\(item.title ?? "nil") onScreen=\(item.isOnScreen) canBeHidden=\(item.canBeHidden) movable=\(item.isMovable)")
        }
        return MenuBarSnapshot(displayID: targetDisplay.id, items: assigned)
    }

    private static func axOrderedSnapshot(
        rawWindows: [[String: Any]],
        targetDisplay: TargetDisplay,
        allDisplayFrames: [CGRect],
        targetDisplayFrames: [CGRect]
    ) -> MenuBarSnapshot? {
        let axRecords = AXOrderedMenuBarScanner().records(on: targetDisplay.frame)
        guard !axRecords.isEmpty else {
            CoronaDebugLog.verbose("discovery.ax fallback reason=emptyAXTree")
            return nil
        }

        let cgCandidates = rawWindows.compactMap { info in
            DirectMenuBarDiscoveryProvider().makeMenuBarItem(from: info, displayFrames: targetDisplayFrames)
        }
        let targetDisplayCandidates = MenuBarTargetDisplayFilter(
            targetDisplayFrame: targetDisplay.frame,
            otherDisplayFrames: allDisplayFrames.filter { !$0.equalTo(targetDisplay.frame) }
        ).itemsOnTargetDisplay(cgCandidates)
        let uniqueCandidates = MenuBarDisplayDuplicateFilter(
            primaryDisplayFrame: targetDisplay.frame,
            displayFrames: targetDisplayFrames
        ).uniqueItems(from: targetDisplayCandidates)

        var unmatchedWindows = uniqueCandidates
        let matchedPairs = axRecords.compactMap { record -> (AXOrderedMenuBarScanner.AXRecord, MenuBarItem)? in
            guard let match = bestWindowMatch(for: record, candidates: unmatchedWindows) else {
                return nil
            }
            unmatchedWindows.removeAll { $0.windowID == match.windowID }
            return (record, match)
        }

        let minimumUsefulMatchCount = min(uniqueCandidates.count, max(3, uniqueCandidates.count / 2))
        guard matchedPairs.count >= minimumUsefulMatchCount else {
            CoronaDebugLog.verbose("discovery.ax fallback reason=lowMatchCount matched=\(matchedPairs.count) required=\(minimumUsefulMatchCount) cgCandidates=\(uniqueCandidates.count)")
            return nil
        }

        let items = matchedPairs.enumerated().map { orderedIndex, pair -> MenuBarItem in
            let record = pair.0
            let match = pair.1
            let namespace = record.bundleIdentifier ?? match.tag.namespace
            let displayTitle = record.title ?? match.title ?? record.applicationName ?? "Status Item"
            if abs(record.bounds.midX - match.bounds.midX) > 2 || abs(record.bounds.width - match.bounds.width) > 2 {
                CoronaDebugLog.verbose("discovery.ax boundsOverride uid=\(namespace):item-\(orderedIndex) cg=\(match.bounds.debugDescription) ax=\(record.bounds.debugDescription)")
            }

            return Self.applyingMovementPolicy(MenuBarItem(
                tag: MenuBarItemTag(
                    namespace: namespace,
                    title: "item-\(orderedIndex)",
                    volatileWindowID: match.windowID
                ),
                windowID: match.windowID,
                ownerPID: match.ownerPID,
                sourcePID: record.sourcePID,
                bounds: record.bounds,
                title: displayTitle,
                isOnScreen: match.isOnScreen,
                isMovable: match.isMovable,
                canBeHidden: match.canBeHidden
            ))
        }

        let rejectedByNonTargetDisplay = cgCandidates.count - targetDisplayCandidates.count
        let rejectedAsDuplicate = targetDisplayCandidates.count - uniqueCandidates.count
        CoronaDebugLog.verbose("discovery.ax phase2 rawWindows=\(rawWindows.count) cgCandidates=\(cgCandidates.count) rejectedNonTargetDisplay=\(rejectedByNonTargetDisplay) rejectedDuplicate=\(rejectedAsDuplicate) matched=\(items.count) unmatchedAX=\(axRecords.count - matchedPairs.count) unmatchedWindows=\(unmatchedWindows.count)")
        CoronaDebugLog.verbose("discovery.ax phase3 assigned uids=\(items.map { "\($0.tag.stableIdentifier)@\($0.bounds.debugDescription)" })")

        return MenuBarSnapshot(displayID: targetDisplay.id, items: items)
    }

    private static func bestWindowMatch(
        for record: AXOrderedMenuBarScanner.AXRecord,
        candidates: [MenuBarItem]
    ) -> MenuBarItem? {
        let center = CGPoint(x: record.bounds.midX, y: record.bounds.midY)
        return candidates
            .map { candidate -> (item: MenuBarItem, score: CGFloat) in
                let candidateCenter = CGPoint(x: candidate.bounds.midX, y: candidate.bounds.midY)
                let distance = hypot(center.x - candidateCenter.x, center.y - candidateCenter.y)
                let pidPenalty: CGFloat = candidate.ownerPID == record.sourcePID || candidate.sourcePID == record.sourcePID ? 0 : 24
                let sizePenalty = abs(candidate.bounds.width - record.bounds.width) * 0.25
                    + abs(candidate.bounds.height - record.bounds.height) * 0.25
                return (candidate, distance + pidPenalty + sizePenalty)
            }
            .filter { $0.score <= 36 }
            .min { $0.score < $1.score }?
            .item
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

        return Self.applyingMovementPolicy(MenuBarItem(
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
        ))
    }

    private func resolvedItem(_ item: MenuBarItem, sourcePID: Int32?) -> MenuBarItem {
        let sourceApplication = sourcePID.flatMap { NSRunningApplication(processIdentifier: $0) }
        let sourceBundleIdentifier = sourceApplication?.bundleIdentifier
        let namespace = sourceBundleIdentifier ?? item.tag.namespace

        return Self.applyingMovementPolicy(MenuBarItem(
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
            canBeHidden: item.canBeHidden
        ))
    }

    private static func applyingMovementPolicy(_ item: MenuBarItem) -> MenuBarItem {
        var copy = item
        guard copy.tag.namespace.hasPrefix("com.apple.") else {
            return copy
        }

        let titleCandidates = Set([copy.tag.title, copy.title].compactMap { $0 })
        let isImmovableAppleMenuExtra =
            copy.tag.namespace == "com.apple.controlcenter" &&
            (!titleCandidates.isDisjoint(with: ["Clock", "BentoBox"]))

        copy.isMovable = !isImmovableAppleMenuExtra
        copy.canBeHidden = !isImmovableAppleMenuExtra
        return copy
    }

    private static func displayFrames() -> [CGRect] {
        BuiltInMenuBarDisplay.activeDisplayFrames()
    }

    private static func targetMenuBarDisplay() -> TargetDisplay {
        let target = BuiltInMenuBarDisplay.target()
        return TargetDisplay(id: target.id, frame: target.frame)
    }

    private static var shouldResolveSourcePIDs: Bool {
        ProcessInfo.processInfo.environment["CORONA_RESOLVE_AX_MENU_BAR_SOURCE_PIDS"] == "1"
    }

    private static var shouldUseAXOrderedDiscovery: Bool {
        ProcessInfo.processInfo.environment["CORONA_ENABLE_AX_ORDERED_DISCOVERY"] == "1"
    }
}

private struct TargetDisplay {
    var id: CGDirectDisplayID
    var frame: CGRect
}
