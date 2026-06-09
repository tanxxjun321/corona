import CoreGraphics
import Foundation

public struct MenuBarItemCanonicalizer: Sendable {
    private let singleItemNamespaces: Set<String> = [
        "cn.futu.Niuniu",
        "com.NeatDownloadManager",
        "com.google.Chrome",
        "com.nssurge.surge-mac",
        "com.tencent.xinWeChat",
        "com.todesktop.230313mzl4w4u92",
    ]

    public init() {}

    public func canonicalized(_ items: [MenuBarItem]) -> [MenuBarItem] {
        let controlCenterTitles = canonicalControlCenterTitles(for: items)
        let iStatTitles = canonicalIStatTitles(for: items)

        return items.map { item in
            var copy = item
            if let title = controlCenterTitles[item.windowID] ?? iStatTitles[item.windowID] {
                copy.tag.title = title
            } else if singleItemNamespaces.contains(item.tag.namespace) {
                copy.tag.title = "Item-0"
            }
            return copy
        }
    }

    private func canonicalControlCenterTitles(for items: [MenuBarItem]) -> [UInt32: String] {
        let controlCenterItems = items
            .filter { $0.tag.namespace == "com.apple.controlcenter" }
            .sorted { lhs, rhs in
                if abs(lhs.bounds.minX - rhs.bounds.minX) > 0.5 {
                    return lhs.bounds.minX < rhs.bounds.minX
                }
                return lhs.windowID < rhs.windowID
            }
        guard !controlCenterItems.isEmpty else { return [:] }

        var result: [UInt32: String] = [:]
        for item in controlCenterItems {
            if isKnownControlCenterTitle(item.tag.title) {
                result[item.windowID] = item.tag.title
            }
        }

        let unresolved = controlCenterItems.filter { result[$0.windowID] == nil }
        let rightmost = unresolved.sorted { lhs, rhs in
            if abs(lhs.bounds.maxX - rhs.bounds.maxX) > 0.5 {
                return lhs.bounds.maxX > rhs.bounds.maxX
            }
            return lhs.windowID < rhs.windowID
        }

        for item in unresolved {
            let width = item.bounds.width
            if width >= 90 {
                result[item.windowID] = "Clock"
            } else if approximately(width, 42) {
                result[item.windowID] = "Battery"
            } else if approximately(width, 34) {
                result[item.windowID] = "BentoBox"
            } else if approximately(width, 32) {
                result[item.windowID] = "Bluetooth"
            } else if approximately(width, 48) {
                result[item.windowID] = "AudioVideoModule"
            }
        }

        let unresolved33 = unresolved
            .filter { result[$0.windowID] == nil && approximately($0.bounds.width, 33) }
            .sorted { $0.bounds.minX < $1.bounds.minX }
        let bentoBox = controlCenterItems.first { result[$0.windowID] == "BentoBox" }
        let wifi = controlCenterItems.first { result[$0.windowID] == "WiFi" }
        for item in unresolved33 {
            if let bentoBox,
               item.bounds.maxX <= bentoBox.bounds.minX + 1,
               wifi == nil || item.bounds.minX >= wifi!.bounds.maxX - 1 {
                result[item.windowID] = "UserSwitcher"
            } else {
                result[item.windowID] = "NowPlaying"
            }
        }

        let unresolved38 = unresolved
            .filter { result[$0.windowID] == nil && approximately($0.bounds.width, 38) }
            .sorted { $0.bounds.minX < $1.bounds.minX }
        if let wifi = unresolved38.last(where: { item in
            guard let battery = controlCenterItems.first(where: { result[$0.windowID] == "Battery" }) else {
                return true
            }
            return item.bounds.minX > battery.bounds.minX
        }) ?? unresolved38.last {
            result[wifi.windowID] = "WiFi"
        }

        for item in rightmost where result[item.windowID] == nil {
            result[item.windowID] = "ControlCenterItem-\(item.windowID)"
        }
        return result
    }

    private func canonicalIStatTitles(for items: [MenuBarItem]) -> [UInt32: String] {
        let iStatItems = items
            .filter { $0.tag.namespace == "com.bjango.istatmenus.status" }
            .sorted { lhs, rhs in
                if abs(lhs.bounds.minX - rhs.bounds.minX) > 0.5 {
                    return lhs.bounds.minX < rhs.bounds.minX
                }
                return lhs.windowID < rhs.windowID
            }
        guard !iStatItems.isEmpty else { return [:] }

        var result: [UInt32: String] = [:]
        for item in iStatItems {
            if item.tag.title.hasPrefix("com.bjango.istatmenus.") {
                result[item.windowID] = item.tag.title
            }
        }

        for item in iStatItems where result[item.windowID] == nil {
            let width = item.bounds.width
            if approximately(width, 49) {
                result[item.windowID] = "com.bjango.istatmenus.sensors"
            } else if approximately(width, 77) {
                result[item.windowID] = "com.bjango.istatmenus.network"
            } else if approximately(width, 56) {
                result[item.windowID] = "com.bjango.istatmenus.cpu"
            }
        }

        let unresolved35 = iStatItems
            .filter { result[$0.windowID] == nil && approximately($0.bounds.width, 35) }
            .sorted { $0.bounds.minX < $1.bounds.minX }
        if let disk = unresolved35.first {
            result[disk.windowID] = "com.bjango.istatmenus.diskusage"
        }
        if unresolved35.count > 1, let memory = unresolved35.last {
            result[memory.windowID] = "com.bjango.istatmenus.memory"
        }

        return result
    }

    private func isKnownControlCenterTitle(_ title: String) -> Bool {
        [
            "AudioVideoModule",
            "Battery",
            "BentoBox",
            "Bluetooth",
            "Clock",
            "NowPlaying",
            "UserSwitcher",
            "WiFi",
        ].contains(title)
    }

    private func approximately(_ value: CGFloat, _ expected: CGFloat) -> Bool {
        abs(value - expected) <= 0.75
    }
}
