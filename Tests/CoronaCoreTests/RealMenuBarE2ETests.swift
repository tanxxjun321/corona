import AppKit
import CoreGraphics
import CoronaCore
import XCTest

final class RealMenuBarE2ETests: XCTestCase {
    func testFetchesCurrentScreenRealMenuBarItems() throws {
        try requireRealMenuBarE2E()

        let snapshot = try RealMenuBarProbe().snapshot()

        XCTAssertFalse(snapshot.allItems.isEmpty, "Expected at least one real menu bar item on the target display.")
        XCTAssertNoDuplicateStableIdentifiers(snapshot.allItems)
        XCTAssertAllItemsLookValid(snapshot.allItems)
        assertExpectedIdentifiers(
            environmentKey: "CORONA_EXPECT_REAL_MENUBAR_UIDS",
            arePresentIn: snapshot.allItems,
            label: "real menu bar"
        )
        printItems(snapshot.allItems, label: "real menu bar items")
    }

    func testFetchesVisibleMenuBarItems() throws {
        try requireRealMenuBarE2E()

        let snapshot = try RealMenuBarProbe().snapshot()

        XCTAssertFalse(snapshot.visibleItems.isEmpty, "Expected at least one physically visible menu bar item.")
        XCTAssertNoDuplicateStableIdentifiers(snapshot.visibleItems)
        XCTAssertAllItemsLookValid(snapshot.visibleItems)
        XCTAssertTrue(
            snapshot.visibleItems.allSatisfy {
                snapshot.targetDisplayFrame.intersects($0.bounds)
                    && $0.isOnScreen
                    && RealMenuBarProbe.isInMenuBarTopBand($0.bounds, displayFrame: snapshot.targetDisplayFrame)
            },
            "Visible menu bar items must be onscreen, intersect the target display, and stay in the menu bar top band."
        )
        assertExpectedIdentifiers(
            environmentKey: "CORONA_EXPECT_VISIBLE_MENUBAR_UIDS",
            arePresentIn: snapshot.visibleItems,
            label: "visible menu bar"
        )
        printItems(snapshot.visibleItems, label: "visible menu bar items")
    }

    func testFetchesHiddenMenuBarItems() throws {
        try requireRealMenuBarE2E()

        let snapshot = try RealMenuBarProbe().snapshot()
        let allUIDs = Set(snapshot.allItems.map(\.tag.stableIdentifier))
        let visibleUIDs = Set(snapshot.visibleItems.map(\.tag.stableIdentifier))
        let hiddenUIDs = Set(snapshot.hiddenItems.map(\.tag.stableIdentifier))

        XCTAssertNoDuplicateStableIdentifiers(snapshot.hiddenItems)
        XCTAssertAllItemsLookValid(snapshot.hiddenItems)
        XCTAssertTrue(visibleUIDs.isDisjoint(with: hiddenUIDs), "Visible and hidden physical partitions must not overlap.")
        XCTAssertEqual(visibleUIDs.union(hiddenUIDs), allUIDs, "Visible + hidden physical partitions must cover all discovered items.")

        if ProcessInfo.processInfo.environment["CORONA_EXPECT_HIDDEN_MENU_BAR_ITEMS"] == "1" {
            XCTAssertFalse(snapshot.hiddenItems.isEmpty, "Expected at least one physically hidden menu bar item.")
        }
        assertExpectedIdentifiers(
            environmentKey: "CORONA_EXPECT_HIDDEN_MENUBAR_UIDS",
            arePresentIn: snapshot.hiddenItems,
            label: "hidden menu bar"
        )
        printItems(snapshot.hiddenItems, label: "hidden menu bar items")
    }

    private func requireRealMenuBarE2E() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CORONA_RUN_REAL_MENUBAR_E2E"] == "1",
            "Set CORONA_RUN_REAL_MENUBAR_E2E=1 to run real menu bar E2E tests."
        )
    }

    private func XCTAssertNoDuplicateStableIdentifiers(
        _ items: [MenuBarItem],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let identifiers = items.map(\.tag.stableIdentifier)
        XCTAssertEqual(
            Set(identifiers).count,
            identifiers.count,
            "Expected stable identifiers to be unique: \(identifiers)",
            file: file,
            line: line
        )
    }

    private func XCTAssertAllItemsLookValid(
        _ items: [MenuBarItem],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for item in items {
            XCTAssertFalse(item.tag.namespace.isEmpty, "Invalid namespace for \(item)", file: file, line: line)
            XCTAssertFalse(item.tag.title.isEmpty, "Invalid title for \(item)", file: file, line: line)
            XCTAssertFalse(item.bounds.isNull, "Invalid null bounds for \(item)", file: file, line: line)
            XCTAssertFalse(item.bounds.isInfinite, "Invalid infinite bounds for \(item)", file: file, line: line)
            XCTAssertGreaterThan(item.bounds.width, 0, "Invalid width for \(item)", file: file, line: line)
            XCTAssertGreaterThan(item.bounds.height, 0, "Invalid height for \(item)", file: file, line: line)
            XCTAssertLessThanOrEqual(item.bounds.height, 80, "Unexpectedly tall menu bar item \(item)", file: file, line: line)
        }
    }

    private func assertExpectedIdentifiers(
        environmentKey: String,
        arePresentIn items: [MenuBarItem],
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expected = ProcessInfo.processInfo.environment[environmentKey, default: ""]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !expected.isEmpty else { return }

        let actual = Set(items.map(\.tag.stableIdentifier))
        let missing = expected.filter { !actual.contains($0) }
        XCTAssertTrue(
            missing.isEmpty,
            "Missing expected \(label) identifiers: \(missing). Actual: \(actual.sorted())",
            file: file,
            line: line
        )
    }

    private func printItems(_ items: [MenuBarItem], label: String) {
        let lines = items.map { item in
            "\(item.tag.stableIdentifier) window=\(item.windowID) ownerPID=\(item.ownerPID) sourcePID=\(item.sourcePID.map(String.init) ?? "nil") onScreen=\(item.isOnScreen) bounds=\(item.bounds)"
        }
        let output = "[RealMenuBarE2E] \(label) count=\(items.count)\n" + lines.joined(separator: "\n")
        XCTContext.runActivity(named: output) { _ in }
    }
}

private struct RealMenuBarProbe {
    struct Snapshot {
        var targetDisplayID: CGDirectDisplayID
        var targetDisplayFrame: CGRect
        var allItems: [MenuBarItem]
        var visibleItems: [MenuBarItem]
        var hiddenItems: [MenuBarItem]
    }

    func snapshot() throws -> Snapshot {
        let targetDisplay = Self.targetMenuBarDisplay()
        let allDisplayFrames = Self.displayFrames()
        let rawWindows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
            ?? []
        let candidates = rawWindows.compactMap { makeMenuBarItem(from: $0, displayFrame: targetDisplay.frame) }
        let targetItems = MenuBarTargetDisplayFilter(
            targetDisplayFrame: targetDisplay.frame,
            otherDisplayFrames: allDisplayFrames.filter { !$0.equalTo(targetDisplay.frame) }
        ).itemsOnTargetDisplay(candidates)
        let uniqueItems = MenuBarDisplayDuplicateFilter(
            primaryDisplayFrame: targetDisplay.frame,
            displayFrames: [targetDisplay.frame]
        ).uniqueItems(from: targetItems)
        let assignedItems = MenuBarItemIdentityAssigner()
            .assignInstanceIndexes(to: uniqueItems)
            .sorted { lhs, rhs in
                if abs(lhs.bounds.minX - rhs.bounds.minX) > 0.5 {
                    return lhs.bounds.minX < rhs.bounds.minX
                }
                return lhs.windowID < rhs.windowID
            }

        let visibleItems = assignedItems.filter { isPhysicallyVisible($0, on: targetDisplay.frame) }
        let hiddenItems = assignedItems.filter { !isPhysicallyVisible($0, on: targetDisplay.frame) }

        return Snapshot(
            targetDisplayID: targetDisplay.id,
            targetDisplayFrame: targetDisplay.frame,
            allItems: assignedItems,
            visibleItems: visibleItems,
            hiddenItems: hiddenItems
        )
    }

    private func makeMenuBarItem(from info: [String: Any], displayFrame: CGRect) -> MenuBarItem? {
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
            displayFrames: [displayFrame]
        ) else {
            return nil
        }

        let namespace = bundleIdentifier ?? ownerName ?? "pid.\(ownerPID)"
        let displayTitle = title ?? ownerName ?? "Status Item"
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
            isOnScreen: (info[kCGWindowIsOnscreen as String] as? Bool) ?? true,
            isMovable: !isSystemItem,
            canBeHidden: !isSystemItem
        )
    }

    private func isPhysicallyVisible(_ item: MenuBarItem, on displayFrame: CGRect) -> Bool {
        item.isOnScreen && item.bounds.intersects(displayFrame)
    }

    static func isInMenuBarTopBand(_ bounds: CGRect, displayFrame: CGRect) -> Bool {
        abs(bounds.minY - displayFrame.minY) <= 8
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

    private static func targetMenuBarDisplay() -> (id: CGDirectDisplayID, frame: CGRect) {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            let id = CGMainDisplayID()
            return (id, CGDisplayBounds(id))
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, nil) == .success else {
            let id = CGMainDisplayID()
            return (id, CGDisplayBounds(id))
        }

        let id: CGDirectDisplayID
        if let builtInDisplayID = displays.first(where: { CGDisplayIsBuiltin($0) != 0 }) {
            id = builtInDisplayID
        } else {
            id = CGMainDisplayID()
        }
        return (id, CGDisplayBounds(id))
    }
}
