import AppKit
import CoreGraphics
import CoronaCore
import UniformTypeIdentifiers

protocol MenuBarThumbnailProviding {
    func thumbnail(for item: MenuBarItem) -> NSImage
}

struct MenuBarThumbnailProvider: MenuBarThumbnailProviding {
    private let settingsStore: SettingsStore
    private let permissionChecker: SystemPermissionChecker

    init(settingsStore: SettingsStore, permissionChecker: SystemPermissionChecker) {
        self.settingsStore = settingsStore
        self.permissionChecker = permissionChecker
    }

    func thumbnail(for item: MenuBarItem) -> NSImage {
        let settings = settingsStore.load()
        let permissions = permissionChecker.snapshot()
        guard settings.enableScreenRecordingPreviews,
              permissions.canShowPixelPreviews,
              let image = windowImage(for: item) else {
            return fallbackImage(for: item)
        }
        return image
    }

    private func windowImage(for item: MenuBarItem) -> NSImage? {
        guard let cgImage = CGWindowListCreateImage(
            item.bounds,
            .optionIncludingWindow,
            CGWindowID(item.windowID),
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            return nil
        }
        guard hasVisibleContent(cgImage) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: item.bounds.size)
    }

    private func fallbackImage(for item: MenuBarItem) -> NSImage {
        if let symbolName = fallbackSymbolName(for: item),
           let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: item.title ?? item.tag.title) {
            return symbol
        }

        if let applicationIcon = applicationIcon(for: item) {
            return applicationIcon
        }

        return initialBadge(for: item)
    }

    private func hasVisibleContent(_ image: CGImage) -> Bool {
        let width = 16
        let height = 16
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return true
        }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var visiblePixels = 0
        for offset in stride(from: 3, to: pixels.count, by: 4) where pixels[offset] > 12 {
            visiblePixels += 1
            if visiblePixels >= 4 {
                return true
            }
        }
        return false
    }

    private func fallbackSymbolName(for item: MenuBarItem) -> String? {
        let haystack = "\(item.tag.namespace) \(item.tag.title) \(item.title ?? "")".lowercased()
        let mappings: [(String, String)] = [
            ("wifi", "wifi"),
            ("wi-fi", "wifi"),
            ("bluetooth", "bluetooth"),
            ("battery", "battery.100"),
            ("power", "battery.100"),
            ("sound", "speaker.wave.2.fill"),
            ("volume", "speaker.wave.2.fill"),
            ("audio", "speaker.wave.2.fill"),
            ("display", "display"),
            ("screen", "display"),
            ("monitor", "display"),
            ("keyboard", "keyboard"),
            ("input", "keyboard"),
            ("clock", "clock"),
            ("date", "calendar"),
            ("time", "clock"),
            ("control center", "switch.2"),
            ("controlcentre", "switch.2"),
            ("now playing", "play.circle.fill"),
            ("media", "play.circle.fill"),
            ("cpu", "cpu"),
            ("memory", "memorychip"),
            ("network", "network"),
            ("vpn", "lock.shield"),
            ("sync", "arrow.triangle.2.circlepath"),
            ("download", "arrow.down.circle.fill"),
            ("upload", "arrow.up.circle.fill")
        ]
        return mappings.first { haystack.contains($0.0) }?.1
    }

    private func initialBadge(for item: MenuBarItem) -> NSImage {
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size)
        let title = item.title ?? item.tag.title
        let initial = title.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? "?"

        image.lockFocus()
        NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 5, yRadius: 5).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = initial.size(withAttributes: attributes)
        initial.draw(
            at: NSPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
            withAttributes: attributes
        )
        image.unlockFocus()
        return image
    }

    private func applicationIcon(for item: MenuBarItem) -> NSImage? {
        let pid = item.sourcePID ?? item.ownerPID
        guard let application = NSRunningApplication(processIdentifier: pid) else {
            return nil
        }

        if let icon = application.icon {
            return icon
        }

        if let bundleURL = application.bundleURL {
            return NSWorkspace.shared.icon(forFile: bundleURL.path)
        }

        return nil
    }
}
