import AppKit
import CoreGraphics
import Darwin
import CoronaCore
import XCTest

final class RealMenuBarE2ETests: XCTestCase {
    private static var didPrepareCoronaApp = false
    private static let coronaBundleIdentifier = "com.ltz.corona"
    private static let collapseHiddenSectionsNotification = Notification.Name("com.ltz.corona.e2e.collapseHiddenSections")

    func testFetchesCurrentScreenRealMenuBarItems() throws {
        try requireRealMenuBarE2E()

        let snapshot = try RealMenuBarProbe().snapshot()

        XCTAssertFalse(snapshot.allItems.isEmpty, "Expected at least one real menu bar item on the target display.")
        XCTAssertNoDuplicateStableIdentifiers(snapshot.allItems)
        XCTAssertAllItemsLookValid(snapshot.allItems)
        XCTAssertNoKnownInvalidArtifacts(snapshot.allItems)
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
        XCTAssertNoKnownInvalidArtifacts(snapshot.visibleItems)
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
        XCTAssertNoKnownInvalidArtifacts(snapshot.hiddenItems)
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

    func testSnapshotPartitionsRemainStableAfterControlCenterSettles() throws {
        try requireRealMenuBarE2E()

        let first = try RealMenuBarProbe().snapshot()
        Thread.sleep(forTimeInterval: 1)
        let second = try RealMenuBarProbe().snapshot()

        XCTAssertEqual(
            first.visibleStableIdentifiers,
            second.visibleStableIdentifiers,
            """
            Visible menu bar partition changed between snapshots.
            first=\(first.visibleStableIdentifiers)
            second=\(second.visibleStableIdentifiers)
            """
        )
        XCTAssertEqual(
            first.hiddenStableIdentifiers,
            second.hiddenStableIdentifiers,
            """
            Hidden menu bar partition changed between snapshots.
            first=\(first.hiddenStableIdentifiers)
            second=\(second.hiddenStableIdentifiers)
            """
        )
        XCTAssertEqual(
            first.allStableIdentifiers,
            second.allStableIdentifiers,
            """
            All discovered menu bar items changed between snapshots.
            first=\(first.allStableIdentifiers)
            second=\(second.allStableIdentifiers)
            """
        )
    }

    func testSavedHiddenIntentMatchesPhysicalMenuBarState() throws {
        try requireRealMenuBarE2E()

        let savedOrder = try loadCoronaSavedSectionOrder()
        try XCTSkipIf(
            savedOrder.hidden.isEmpty && savedOrder.alwaysHidden.isEmpty,
            "No saved hidden or always hidden items to verify."
        )

        let snapshot = try RealMenuBarProbe().snapshot()
        let physicalVisible = Set(snapshot.visibleStableIdentifiers)
        let savedHidden = Set(savedOrder.hidden)
        let savedAlwaysHidden = Set(savedOrder.alwaysHidden)
        let hiddenStillVisible = savedHidden.intersection(physicalVisible).sorted()
        let alwaysHiddenStillVisible = savedAlwaysHidden.intersection(physicalVisible).sorted()

        XCTAssertTrue(
            hiddenStillVisible.isEmpty,
            """
            Saved hidden items are still physically visible after Corona collapsed the hidden section.
            visible=\(hiddenStillVisible)
            savedHidden=\(savedOrder.hidden)
            physicalVisible=\(snapshot.visibleStableIdentifiers)
            """
        )
        XCTAssertTrue(
            alwaysHiddenStillVisible.isEmpty,
            """
            Saved always hidden items are still physically visible after Corona collapsed the hidden section.
            visible=\(alwaysHiddenStillVisible)
            savedAlwaysHidden=\(savedOrder.alwaysHidden)
            physicalVisible=\(snapshot.visibleStableIdentifiers)
            """
        )
    }

    private func requireRealMenuBarE2E() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CORONA_RUN_REAL_MENUBAR_E2E"] == "1",
            "Set CORONA_RUN_REAL_MENUBAR_E2E=1 to run real menu bar E2E tests."
        )
        try prepareCoronaAppForRealMenuBarE2E()
        collapseCoronaHiddenSectionsForE2E()
    }

    private func prepareCoronaAppForRealMenuBarE2E() throws {
        guard !Self.didPrepareCoronaApp else { return }
        Self.didPrepareCoronaApp = true

        for app in NSRunningApplication.runningApplications(withBundleIdentifier: Self.coronaBundleIdentifier) {
            app.terminate()
        }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline,
              !NSRunningApplication.runningApplications(withBundleIdentifier: Self.coronaBundleIdentifier).isEmpty {
            Thread.sleep(forTimeInterval: 0.1)
        }

        let appURL = try XCTUnwrap(
            coronaAppURL(),
            "Build Corona.app before running real E2E tests. Set CORONA_E2E_APP_PATH or build the Xcode Debug app first."
        )
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.environment = ProcessInfo.processInfo.environment.merging([
            "CORONA_ENABLE_E2E_CONTROL": "1"
        ]) { _, new in new }

        let launchExpectation = expectation(description: "Launch Corona for real menu bar E2E")
        var launchError: Error?
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            launchError = error
            launchExpectation.fulfill()
        }
        wait(for: [launchExpectation], timeout: 5)
        if let launchError {
            throw launchError
        }

        let launchDeadline = Date().addingTimeInterval(5)
        while Date() < launchDeadline,
              NSRunningApplication.runningApplications(withBundleIdentifier: Self.coronaBundleIdentifier).isEmpty {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertFalse(
            NSRunningApplication.runningApplications(withBundleIdentifier: Self.coronaBundleIdentifier).isEmpty,
            "Corona.app did not launch for real menu bar E2E."
        )
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func coronaAppURL() -> URL? {
        if let override = ProcessInfo.processInfo.environment["CORONA_E2E_APP_PATH"],
           !override.isEmpty {
            let url = URL(fileURLWithPath: NSString(string: override).expandingTildeInPath)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        if let derivedDataApp = latestDerivedDataCoronaAppURL() {
            return derivedDataApp
        }

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            root.appendingPathComponent(".build/xcode-check/Debug/Corona.app"),
            root.appendingPathComponent(".build/app/Corona.app"),
            root.appendingPathComponent(".build/xcode-build/Release/Corona.app")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func latestDerivedDataCoronaAppURL() -> URL? {
        let derivedDataRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
        guard let projectDirectories = try? FileManager.default.contentsOfDirectory(
            at: derivedDataRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let candidates = projectDirectories
            .filter { $0.lastPathComponent.hasPrefix("Corona-") }
            .map { $0.appendingPathComponent("Build/Products/Debug/Corona.app") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted { lhs, rhs in
                modificationDate(for: lhs) > modificationDate(for: rhs)
            }
        return candidates.first
    }

    private func modificationDate(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    private func collapseCoronaHiddenSectionsForE2E() {
        DistributedNotificationCenter.default().postNotificationName(
            Self.collapseHiddenSectionsNotification,
            object: "CoronaE2E",
            userInfo: nil,
            deliverImmediately: true
        )
        Thread.sleep(forTimeInterval: 0.35)
    }

    private func loadCoronaSavedSectionOrder() throws -> SectionOrder {
        let defaults = UserDefaults(suiteName: "com.ltz.corona")
        let data = defaults?.data(forKey: "ItemManager.savedSectionOrder.v1")
        return try JSONDecoder().decode(SectionOrder.self, from: XCTUnwrap(data))
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

    private func XCTAssertNoKnownInvalidArtifacts(
        _ items: [MenuBarItem],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for item in items {
            let uid = item.tag.stableIdentifier
            XCTAssertFalse(uid.contains("com.ltz.corona"), "Corona status controls must not be discovered as managed menu bar items: \(item)", file: file, line: line)
            XCTAssertFalse(
                uid == "com.apple.TextInputMenuAgent:Item-0" && item.bounds.height < 30,
                "TextInputMenuAgent subview artifact must not be discovered as a menu bar item: \(item)",
                file: file,
                line: line
            )
            XCTAssertFalse(
                item.tag.namespace == "com.apple.controlcenter" && item.bounds.height < 30,
                "ControlCenter ViewBridge subview artifact must not be discovered as a menu bar item: \(item)",
                file: file,
                line: line
            )
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
        print(output)
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

        var allStableIdentifiers: [String] {
            allItems.map(\.tag.stableIdentifier)
        }

        var visibleStableIdentifiers: [String] {
            visibleItems.map(\.tag.stableIdentifier)
        }

        var hiddenStableIdentifiers: [String] {
            hiddenItems.map(\.tag.stableIdentifier)
        }
    }

    func snapshot() throws -> Snapshot {
        let targetDisplay = Self.targetMenuBarDisplay()
        let allDisplayFrames = Self.displayFrames()
        let rawWindows = PrivateMenuBarWindowListProbe().windowDescriptions()
            ?? CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
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
        let canonicalItems = MenuBarItemCanonicalizer().canonicalized(uniqueItems)
        let assignedItems = MenuBarItemIdentityAssigner()
            .assignInstanceIndexes(to: canonicalItems)
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
        guard bundleIdentifier != "com.ltz.corona" else {
            return nil
        }
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

private struct PrivateMenuBarWindowListProbe {
    private typealias CGSConnectionID = Int32
    private typealias GetConnectionFn = @convention(c) () -> CGSConnectionID
    private typealias GetWindowCountFn = @convention(c) (CGSConnectionID, CGSConnectionID, UnsafeMutablePointer<Int32>) -> CGError
    private typealias GetMenuBarWindowListFn = @convention(c) (
        CGSConnectionID,
        CGSConnectionID,
        Int32,
        UnsafeMutablePointer<CGWindowID>,
        UnsafeMutablePointer<Int32>
    ) -> CGError

    private static let skyLightPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

    func windowDescriptions() -> [[String: Any]]? {
        guard let windowIDs = windowIDs(), !windowIDs.isEmpty else {
            return nil
        }
        var pointers: [UnsafeRawPointer?] = windowIDs.compactMap { windowID in
            UnsafeRawPointer(bitPattern: UInt(windowID))
        }
        guard !pointers.isEmpty else {
            return nil
        }
        var callbacks = CFArrayCallBacks(version: 0, retain: nil, release: nil, copyDescription: nil, equal: nil)
        guard let array = CFArrayCreate(nil, &pointers, pointers.count, &callbacks) else {
            return nil
        }
        return CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]]
    }

    private func windowIDs() -> [CGWindowID]? {
        guard let handle = dlopen(Self.skyLightPath, RTLD_NOW),
              let mainConnectionSymbol = dlsym(handle, "CGSMainConnectionID"),
              let getWindowCountSymbol = dlsym(handle, "CGSGetWindowCount"),
              let getMenuBarListSymbol = dlsym(handle, "CGSGetProcessMenuBarWindowList") else {
            return nil
        }

        let mainConnection = unsafeBitCast(mainConnectionSymbol, to: GetConnectionFn.self)
        let getWindowCount = unsafeBitCast(getWindowCountSymbol, to: GetWindowCountFn.self)
        let getMenuBarWindowList = unsafeBitCast(getMenuBarListSymbol, to: GetMenuBarWindowListFn.self)
        let connection = mainConnection()

        var count: Int32 = 0
        guard getWindowCount(connection, 0, &count) == .success, count > 0 else {
            return nil
        }

        var list = [CGWindowID](repeating: 0, count: Int(count))
        guard getMenuBarWindowList(connection, 0, count, &list, &count) == .success else {
            return nil
        }

        return Array(list.prefix(Int(count)))
    }
}
