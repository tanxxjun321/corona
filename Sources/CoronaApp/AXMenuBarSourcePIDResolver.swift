import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

/// Shared, defensive readers for AX-returned values. A misbehaving third-party
/// app can answer an AX query with a value of an unexpected type; every cast
/// below is guarded by a CoreFoundation type-ID check so malformed responses
/// degrade that item's handling instead of crashing Corona.
private enum AXMenuBarElement {
    static func extrasMenuBar(for pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &value)
        guard error == .success, let value else {
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            CoronaDebugLog.log("discovery.ax malformedAXValue attribute=AXExtrasMenuBar pid=\(pid) typeID=\(CFGetTypeID(value))")
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == CFArrayGetTypeID() else {
            return []
        }
        return (unsafeDowncast(value, to: CFArray.self) as [CFTypeRef]).compactMap { child in
            guard CFGetTypeID(child) == AXUIElementGetTypeID() else {
                CoronaDebugLog.log("discovery.ax malformedAXValue attribute=AXChildren typeID=\(CFGetTypeID(child))")
                return nil
            }
            return unsafeDowncast(child, to: AXUIElement.self)
        }
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionAXValue = axValue(positionValue, attribute: kAXPositionAttribute),
              let sizeAXValue = axValue(sizeValue, attribute: kAXSizeAttribute) else {
            return nil
        }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &origin),
              AXValueGetValue(sizeAXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    private static func axValue(_ value: CFTypeRef?, attribute: String) -> AXValue? {
        guard let value else {
            return nil
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            CoronaDebugLog.log("discovery.ax malformedAXValue attribute=\(attribute) typeID=\(CFGetTypeID(value))")
            return nil
        }
        return unsafeDowncast(value, to: AXValue.self)
    }
}

struct AXMenuBarSourcePIDResolver {
    func resolveSourcePIDs(for items: [MenuBarItem]) -> [UInt32: Int32] {
        guard AXIsProcessTrusted(), !items.isEmpty else {
            return [:]
        }

        var unresolved = Dictionary(uniqueKeysWithValues: items.map { ($0.windowID, $0.bounds) })
        var result: [UInt32: Int32] = [:]

        for app in NSWorkspace.shared.runningApplications {
            guard !unresolved.isEmpty else { break }
            let pid = app.processIdentifier
            guard let extrasMenuBar = AXMenuBarElement.extrasMenuBar(for: pid) else {
                continue
            }

            for child in AXMenuBarElement.children(of: extrasMenuBar) {
                guard let frame = AXMenuBarElement.frame(of: child) else { continue }
                let center = CGPoint(x: frame.midX, y: frame.midY)
                guard let match = unresolved.first(where: { _, bounds in
                    distance(from: center, to: CGPoint(x: bounds.midX, y: bounds.midY)) <= 1.5
                }) else {
                    continue
                }

                result[match.key] = pid
                unresolved.removeValue(forKey: match.key)
            }
        }

        return result
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}

struct AXOrderedMenuBarScanner {
    struct AXRecord {
        var sourcePID: Int32
        var bundleIdentifier: String?
        var applicationName: String?
        var title: String?
        var bounds: CGRect
        var axOrdinal: Int
        var globalOrdinal: Int
    }

    func records(on targetDisplayFrame: CGRect) -> [AXRecord] {
        guard AXIsProcessTrusted() else {
            CoronaDebugLog.log("discovery.ax phase1 skipped accessibilityNotTrusted")
            return []
        }

        var records: [AXRecord] = []
        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            guard let extrasMenuBar = AXMenuBarElement.extrasMenuBar(for: pid) else {
                continue
            }

            let children = AXMenuBarElement.children(of: extrasMenuBar)
            for (index, child) in children.enumerated() {
                guard let frame = AXMenuBarElement.frame(of: child),
                      isFiniteMenuBarBounds(frame),
                      isInMenuBarBand(frame, targetDisplayFrame: targetDisplayFrame) else {
                    continue
                }

                records.append(
                    AXRecord(
                        sourcePID: pid,
                        bundleIdentifier: app.bundleIdentifier,
                        applicationName: app.localizedName,
                        title: title(of: child) ?? app.localizedName,
                        bounds: frame,
                        axOrdinal: index,
                        globalOrdinal: records.count
                    )
                )
            }
        }

        let sorted = records
            .sorted { lhs, rhs in
                if abs(lhs.bounds.midX - rhs.bounds.midX) > 0.5 {
                    return lhs.bounds.midX < rhs.bounds.midX
                }
                if lhs.sourcePID != rhs.sourcePID {
                    return lhs.sourcePID < rhs.sourcePID
                }
                return lhs.axOrdinal < rhs.axOrdinal
            }
            .enumerated()
            .map { index, record in
                var copy = record
                copy.globalOrdinal = index
                return copy
            }

        CoronaDebugLog.verbose("discovery.ax phase1 records=\(sorted.count) order=\(sorted.map { "\($0.bundleIdentifier ?? $0.applicationName ?? "pid.\($0.sourcePID)"):item-\($0.globalOrdinal)@\($0.bounds.debugDescription)" })")
        return sorted
    }

    private func title(of element: AXUIElement) -> String? {
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXRoleDescriptionAttribute] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
                  let title = value as? String,
                  !title.isEmpty else {
                continue
            }
            return title
        }
        return nil
    }

    private func isFiniteMenuBarBounds(_ bounds: CGRect) -> Bool {
        bounds.width > 0
            && bounds.height > 0
            && bounds.origin.x.isFinite
            && bounds.origin.y.isFinite
            && bounds.size.width.isFinite
            && bounds.size.height.isFinite
    }

    private func isInMenuBarBand(_ bounds: CGRect, targetDisplayFrame: CGRect) -> Bool {
        let menuBarHeight = max(22, min(40, bounds.height + 8))
        let band = CGRect(
            x: targetDisplayFrame.minX - 160,
            y: targetDisplayFrame.minY - 4,
            width: targetDisplayFrame.width + 320,
            height: menuBarHeight + 12
        )
        return band.intersects(bounds) || band.contains(CGPoint(x: bounds.midX, y: bounds.midY))
    }
}
