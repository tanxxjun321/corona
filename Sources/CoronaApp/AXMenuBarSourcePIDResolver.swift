import ApplicationServices
import AppKit
import CoreGraphics
import CoronaCore
import Foundation

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
            guard let extrasMenuBar = extrasMenuBar(for: pid) else {
                continue
            }

            for child in children(of: extrasMenuBar) {
                guard let frame = frame(of: child) else { continue }
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

    private func extrasMenuBar(for pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &value)
        guard error == .success else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionAXValue = positionValue,
              let sizeAXValue = sizeValue else {
            return nil
        }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue((positionAXValue as! AXValue), .cgPoint, &origin),
              AXValueGetValue((sizeAXValue as! AXValue), .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}
