import AppKit
import CoreGraphics

enum MenuBarAppearanceSampler {
    private struct CacheEntry {
        var color: NSColor
        var sampledAt: Date
    }

    private static var cache: [CGDirectDisplayID: CacheEntry] = [:]
    private static let cacheLifetime: TimeInterval = 0.75

    static func backgroundColor(displayID: CGDirectDisplayID?) -> NSColor {
        let id = displayID ?? CGMainDisplayID()
        if let entry = cache[id], Date().timeIntervalSince(entry.sampledAt) < cacheLifetime {
            return entry.color
        }

        let color = sampledBackgroundColor(displayID: id) ?? fallbackColor()
        cache[id] = CacheEntry(color: color, sampledAt: Date())
        return color
    }

    static func backgroundColor(screen: NSScreen?) -> NSColor {
        backgroundColor(displayID: displayID(for: screen))
    }

    static func displayID(for screen: NSScreen?) -> CGDirectDisplayID? {
        guard let screen else { return nil }
        return screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private static func sampledBackgroundColor(displayID: CGDirectDisplayID) -> NSColor? {
        let width = max(1, Int(CGDisplayPixelsWide(displayID)))
        let sampleY = 4
        let sampleXs = [
            max(0, min(width - 1, Int(Double(width) * 0.18))),
            max(0, min(width - 1, Int(Double(width) * 0.50))),
            max(0, min(width - 1, Int(Double(width) * 0.82)))
        ]

        let colors = sampleXs.compactMap { x -> NSColor? in
            guard let image = CGDisplayCreateImage(
                displayID,
                rect: CGRect(x: x, y: sampleY, width: 1, height: 1)
            ) else {
                return nil
            }
            let bitmap = NSBitmapImageRep(cgImage: image)
            return bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB)
        }

        guard !colors.isEmpty else { return nil }
        let components = colors.reduce((r: CGFloat.zero, g: CGFloat.zero, b: CGFloat.zero, a: CGFloat.zero)) { partial, color in
            (
                partial.r + color.redComponent,
                partial.g + color.greenComponent,
                partial.b + color.blueComponent,
                partial.a + color.alphaComponent
            )
        }
        let count = CGFloat(colors.count)
        return NSColor(
            deviceRed: components.r / count,
            green: components.g / count,
            blue: components.b / count,
            alpha: max(components.a / count, 1)
        )
    }

    private static func fallbackColor() -> NSColor {
        NSColor.windowBackgroundColor.withAlphaComponent(0.92)
    }
}
