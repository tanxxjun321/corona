import CoronaCore
import CoreGraphics
import XCTest

final class MenuBarItemCanonicalizerTests: XCTestCase {
    // MARK: - Allowlist

    func testAllowlistedNamespacesAreRenamedToItem0() {
        let namespaces = [
            "cn.futu.Niuniu",
            "com.NeatDownloadManager",
            "com.google.Chrome",
            "com.nssurge.surge-mac",
            "com.tencent.xinWeChat",
            "com.todesktop.230313mzl4w4u92",
        ]

        for (index, namespace) in namespaces.enumerated() {
            let item = makeItem(windowID: UInt32(index + 1), namespace: namespace, title: "Original")

            let result = MenuBarItemCanonicalizer().canonicalized([item])

            XCTAssertEqual(result[0].tag.title, "Item-0", "namespace \(namespace)")
        }
    }

    // MARK: - Fallback

    func testUnknownNamespaceKeepsOriginalTitle() {
        let item = makeItem(windowID: 1, namespace: "com.example.unknown", title: "My Item")

        let result = MenuBarItemCanonicalizer().canonicalized([item])

        XCTAssertEqual(result[0].tag.title, "My Item")
    }

    func testEmptyInputReturnsEmpty() {
        XCTAssertTrue(MenuBarItemCanonicalizer().canonicalized([]).isEmpty)
    }

    func testCanonicalizationPreservesOrderAndNonTitleFields() {
        let first = makeItem(windowID: 7, namespace: "com.example.unknown", title: "A", x: 100, width: 24)
        let second = makeItem(windowID: 3, namespace: "com.google.Chrome", title: "B", x: 50, width: 18)

        let result = MenuBarItemCanonicalizer().canonicalized([first, second])

        XCTAssertEqual(result.map(\.windowID), [7, 3])
        XCTAssertEqual(result[0].bounds, first.bounds)
        XCTAssertEqual(result[0].tag.namespace, first.tag.namespace)
        XCTAssertEqual(result[1].bounds, second.bounds)
        XCTAssertEqual(result[1].tag.title, "Item-0")
    }

    // MARK: - Control center known titles

    func testKnownControlCenterTitlesArePreservedRegardlessOfWidth() {
        let titles = [
            "AudioVideoModule",
            "Battery",
            "BentoBox",
            "Bluetooth",
            "Clock",
            "NowPlaying",
            "UserSwitcher",
            "WiFi",
        ]

        for (index, title) in titles.enumerated() {
            let item = makeItem(
                windowID: UInt32(index + 1),
                namespace: "com.apple.controlcenter",
                title: title,
                width: 20
            )

            let result = MenuBarItemCanonicalizer().canonicalized([item])

            XCTAssertEqual(result[0].tag.title, title)
        }
    }

    // MARK: - Control center width heuristics

    func testControlCenterWidthOf90OrMoreIsClock() {
        XCTAssertEqual(canonicalControlCenterTitle(width: 90), "Clock")
        XCTAssertEqual(canonicalControlCenterTitle(width: 200), "Clock")
    }

    func testControlCenterWidthJustBelow90IsNotClock() {
        XCTAssertEqual(canonicalControlCenterTitle(windowID: 5, width: 89.9), "ControlCenterItem-5")
    }

    func testControlCenterWidthAround42IsBattery() {
        XCTAssertEqual(canonicalControlCenterTitle(width: 42), "Battery")
        XCTAssertEqual(canonicalControlCenterTitle(width: 41.25), "Battery")
        XCTAssertEqual(canonicalControlCenterTitle(width: 42.75), "Battery")
    }

    func testControlCenterWidthOutside42ToleranceFallsBack() {
        XCTAssertEqual(canonicalControlCenterTitle(windowID: 5, width: 41.24), "ControlCenterItem-5")
        XCTAssertEqual(canonicalControlCenterTitle(windowID: 5, width: 42.76), "ControlCenterItem-5")
    }

    func testControlCenterWidthAround34IsBentoBox() {
        XCTAssertEqual(canonicalControlCenterTitle(width: 34), "BentoBox")
    }

    func testControlCenterWidthAround32IsBluetooth() {
        XCTAssertEqual(canonicalControlCenterTitle(width: 32), "Bluetooth")
    }

    func testControlCenterWidthAround48IsAudioVideoModule() {
        XCTAssertEqual(canonicalControlCenterTitle(width: 48), "AudioVideoModule")
    }

    func testUnresolvedControlCenterItemGetsWindowIDBasedTitle() {
        XCTAssertEqual(canonicalControlCenterTitle(windowID: 9, width: 60), "ControlCenterItem-9")
    }

    // MARK: - Control center 33px UserSwitcher / NowPlaying guess

    func test33ItemLeftOfBentoBoxWithoutWiFiIsUserSwitcher() {
        let item33 = makeItem(windowID: 1, namespace: "com.apple.controlcenter", title: "Item", x: 100, width: 33)
        let bentoBox = makeItem(windowID: 2, namespace: "com.apple.controlcenter", title: "Item", x: 200, width: 34)

        let result = MenuBarItemCanonicalizer().canonicalized([item33, bentoBox])

        XCTAssertEqual(result[0].tag.title, "UserSwitcher")
        XCTAssertEqual(result[1].tag.title, "BentoBox")
    }

    func test33ItemRightOfBentoBoxIsNowPlaying() {
        let bentoBox = makeItem(windowID: 1, namespace: "com.apple.controlcenter", title: "Item", x: 100, width: 34)
        let item33 = makeItem(windowID: 2, namespace: "com.apple.controlcenter", title: "Item", x: 300, width: 33)

        let result = MenuBarItemCanonicalizer().canonicalized([bentoBox, item33])

        XCTAssertEqual(result[1].tag.title, "NowPlaying")
    }

    func test33ItemWithoutBentoBoxIsNowPlaying() {
        let item33 = makeItem(windowID: 1, namespace: "com.apple.controlcenter", title: "Item", x: 100, width: 33)

        let result = MenuBarItemCanonicalizer().canonicalized([item33])

        XCTAssertEqual(result[0].tag.title, "NowPlaying")
    }

    func test33ItemBetweenWiFiAndBentoBoxIsUserSwitcher() {
        let wifi = makeItem(windowID: 1, namespace: "com.apple.controlcenter", title: "WiFi", x: 100, width: 20)
        let item33 = makeItem(windowID: 2, namespace: "com.apple.controlcenter", title: "Item", x: 150, width: 33)
        let bentoBox = makeItem(windowID: 3, namespace: "com.apple.controlcenter", title: "Item", x: 200, width: 34)

        let result = MenuBarItemCanonicalizer().canonicalized([wifi, item33, bentoBox])

        XCTAssertEqual(result[1].tag.title, "UserSwitcher")
    }

    func test33ItemLeftOfWiFiIsNowPlaying() {
        let item33 = makeItem(windowID: 1, namespace: "com.apple.controlcenter", title: "Item", x: 250, width: 33)
        let bentoBox = makeItem(windowID: 2, namespace: "com.apple.controlcenter", title: "Item", x: 300, width: 34)
        let wifi = makeItem(windowID: 3, namespace: "com.apple.controlcenter", title: "WiFi", x: 400, width: 20)

        let result = MenuBarItemCanonicalizer().canonicalized([item33, bentoBox, wifi])

        XCTAssertEqual(result[0].tag.title, "NowPlaying")
    }

    func test33GuessWindowIsShadowedByBluetoothAndBentoBoxTolerances() {
        // 32.7 is within Bluetooth's ±0.75 tolerance, 33.3 within BentoBox's;
        // only the narrow (32.75, 33.25) window reaches the 33px guess.
        XCTAssertEqual(canonicalControlCenterTitle(width: 32.7), "Bluetooth")
        XCTAssertEqual(canonicalControlCenterTitle(width: 33.3), "BentoBox")

        let item33 = makeItem(windowID: 1, namespace: "com.apple.controlcenter", title: "Item", x: 100, width: 32.8)
        let bentoBox = makeItem(windowID: 2, namespace: "com.apple.controlcenter", title: "Item", x: 200, width: 34)

        let result = MenuBarItemCanonicalizer().canonicalized([item33, bentoBox])

        XCTAssertEqual(result[0].tag.title, "UserSwitcher")
    }

    // MARK: - Control center 38px WiFi guess

    func testSingle38ItemIsWiFi() {
        XCTAssertEqual(canonicalControlCenterTitle(width: 38), "WiFi")
        XCTAssertEqual(canonicalControlCenterTitle(width: 37.25), "WiFi")
        XCTAssertEqual(canonicalControlCenterTitle(width: 38.75), "WiFi")
    }

    func test38WidthOutsideToleranceFallsBack() {
        XCTAssertEqual(canonicalControlCenterTitle(windowID: 5, width: 37.24), "ControlCenterItem-5")
        XCTAssertEqual(canonicalControlCenterTitle(windowID: 5, width: 38.76), "ControlCenterItem-5")
    }

    func test38ItemRightOfBatteryIsWiFi() {
        let battery = makeItem(windowID: 1, namespace: "com.apple.controlcenter", title: "Item", x: 300, width: 42)
        let item38 = makeItem(windowID: 2, namespace: "com.apple.controlcenter", title: "Item", x: 400, width: 38)

        let result = MenuBarItemCanonicalizer().canonicalized([battery, item38])

        XCTAssertEqual(result[0].tag.title, "Battery")
        XCTAssertEqual(result[1].tag.title, "WiFi")
    }

    func testOnlyRightmost38ItemRightOfBatteryIsWiFi() {
        let left38 = makeItem(windowID: 1, namespace: "com.apple.controlcenter", title: "Item", x: 100, width: 38)
        let battery = makeItem(windowID: 2, namespace: "com.apple.controlcenter", title: "Item", x: 300, width: 42)
        let right38 = makeItem(windowID: 3, namespace: "com.apple.controlcenter", title: "Item", x: 400, width: 38)

        let result = MenuBarItemCanonicalizer().canonicalized([left38, battery, right38])

        XCTAssertEqual(result[0].tag.title, "ControlCenterItem-1")
        XCTAssertEqual(result[2].tag.title, "WiFi")
    }

    func testRightmost38ItemIsWiFiWhenAllAreLeftOfBattery() {
        let left38 = makeItem(windowID: 1, namespace: "com.apple.controlcenter", title: "Item", x: 100, width: 38)
        let right38 = makeItem(windowID: 2, namespace: "com.apple.controlcenter", title: "Item", x: 200, width: 38)
        let battery = makeItem(windowID: 3, namespace: "com.apple.controlcenter", title: "Item", x: 300, width: 42)

        let result = MenuBarItemCanonicalizer().canonicalized([left38, right38, battery])

        XCTAssertEqual(result[0].tag.title, "ControlCenterItem-1")
        XCTAssertEqual(result[1].tag.title, "WiFi")
    }

    // MARK: - iStat Menus

    func testIStatTitleWithKnownPrefixIsPreserved() {
        let item = makeItem(
            windowID: 1,
            namespace: "com.bjango.istatmenus.status",
            title: "com.bjango.istatmenus.weather",
            width: 20
        )

        let result = MenuBarItemCanonicalizer().canonicalized([item])

        XCTAssertEqual(result[0].tag.title, "com.bjango.istatmenus.weather")
    }

    func testIStatWidthAround49IsSensors() {
        XCTAssertEqual(canonicalIStatTitle(width: 49), "com.bjango.istatmenus.sensors")
        XCTAssertEqual(canonicalIStatTitle(width: 48.25), "com.bjango.istatmenus.sensors")
    }

    func testIStatWidthAround77IsNetwork() {
        XCTAssertEqual(canonicalIStatTitle(width: 77), "com.bjango.istatmenus.network")
    }

    func testIStatWidthAround56IsCPU() {
        XCTAssertEqual(canonicalIStatTitle(width: 56), "com.bjango.istatmenus.cpu")
    }

    func testIStatWidthOutsideToleranceKeepsOriginalTitle() {
        XCTAssertEqual(canonicalIStatTitle(width: 49.76), "Extra")
        XCTAssertEqual(canonicalIStatTitle(width: 60), "Extra")
    }

    func testSingle35IStatItemIsDiskUsage() {
        XCTAssertEqual(canonicalIStatTitle(width: 35), "com.bjango.istatmenus.diskusage")
        XCTAssertEqual(canonicalIStatTitle(width: 34.25), "com.bjango.istatmenus.diskusage")
        XCTAssertEqual(canonicalIStatTitle(width: 35.75), "com.bjango.istatmenus.diskusage")
    }

    func testTwo35IStatItemsAreDiskUsageAndMemory() {
        let first = makeItem(windowID: 1, namespace: "com.bjango.istatmenus.status", title: "Extra", x: 100, width: 35)
        let second = makeItem(windowID: 2, namespace: "com.bjango.istatmenus.status", title: "Extra", x: 200, width: 35)

        let result = MenuBarItemCanonicalizer().canonicalized([first, second])

        XCTAssertEqual(result[0].tag.title, "com.bjango.istatmenus.diskusage")
        XCTAssertEqual(result[1].tag.title, "com.bjango.istatmenus.memory")
    }

    func testMiddleOfThree35IStatItemsKeepsOriginalTitle() {
        let first = makeItem(windowID: 1, namespace: "com.bjango.istatmenus.status", title: "Extra", x: 100, width: 35)
        let middle = makeItem(windowID: 2, namespace: "com.bjango.istatmenus.status", title: "Extra", x: 200, width: 35)
        let last = makeItem(windowID: 3, namespace: "com.bjango.istatmenus.status", title: "Extra", x: 300, width: 35)

        let result = MenuBarItemCanonicalizer().canonicalized([first, middle, last])

        XCTAssertEqual(result[0].tag.title, "com.bjango.istatmenus.diskusage")
        XCTAssertEqual(result[1].tag.title, "Extra")
        XCTAssertEqual(result[2].tag.title, "com.bjango.istatmenus.memory")
    }

    // MARK: - Helpers

    private func canonicalControlCenterTitle(windowID: UInt32 = 1, width: CGFloat) -> String {
        let item = makeItem(
            windowID: windowID,
            namespace: "com.apple.controlcenter",
            title: "Item",
            width: width
        )
        return MenuBarItemCanonicalizer().canonicalized([item])[0].tag.title
    }

    private func canonicalIStatTitle(width: CGFloat) -> String {
        let item = makeItem(
            windowID: 1,
            namespace: "com.bjango.istatmenus.status",
            title: "Extra",
            width: width
        )
        return MenuBarItemCanonicalizer().canonicalized([item])[0].tag.title
    }

    private func makeItem(
        windowID: UInt32,
        namespace: String,
        title: String,
        x: CGFloat = 0,
        width: CGFloat = 20
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: namespace, title: title, volatileWindowID: windowID),
            windowID: windowID,
            ownerPID: 1,
            sourcePID: 1,
            bounds: CGRect(x: x, y: 0, width: width, height: 24),
            title: title,
            isOnScreen: true,
            isMovable: true,
            canBeHidden: true
        )
    }
}
