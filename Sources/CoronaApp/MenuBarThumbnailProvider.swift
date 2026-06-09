import AppKit
import CoreGraphics
import UniformTypeIdentifiers

enum MenuBarVisualCaptureGate {
    private static let lock = NSLock()
    private static var suspensionCount = 0

    static var isSuspended: Bool {
        lock.lock()
        defer { lock.unlock() }
        return suspensionCount > 0
    }

    @discardableResult
    static func acquire(reason: String) -> Token {
        lock.lock()
        suspensionCount += 1
        let count = suspensionCount
        lock.unlock()
        CoronaDebugLog.verbose("visualCapture.suspended reason=\(reason) count=\(count)")
        return Token(reason: reason)
    }

    fileprivate static func release(reason: String) {
        lock.lock()
        suspensionCount = max(0, suspensionCount - 1)
        let count = suspensionCount
        lock.unlock()
        CoronaDebugLog.verbose("visualCapture.resumed reason=\(reason) count=\(count)")
    }

    struct Token {
        private let reason: String
        private var isReleased = false

        fileprivate init(reason: String) {
            self.reason = reason
        }

        mutating func release() {
            guard !isReleased else { return }
            isReleased = true
            MenuBarVisualCaptureGate.release(reason: reason)
        }
    }
}

protocol MenuBarThumbnailProviding {
    func thumbnailResult(for item: MenuBarItem) -> MenuBarThumbnailResult
}

extension MenuBarThumbnailProviding {
    func thumbnail(for item: MenuBarItem) -> NSImage {
        thumbnailResult(for: item).image
    }
}

struct MenuBarThumbnailResult {
    var image: NSImage
    var isPixelPreview: Bool
}

struct MenuBarThumbnailProvider: MenuBarThumbnailProviding {
    private let settingsStore: SettingsStore
    private let permissionChecker: SystemPermissionChecker
    private let skyLightImageProvider = SkyLightWindowImageProvider()

    init(settingsStore: SettingsStore, permissionChecker: SystemPermissionChecker) {
        self.settingsStore = settingsStore
        self.permissionChecker = permissionChecker
    }

    func thumbnailResult(for item: MenuBarItem) -> MenuBarThumbnailResult {
        let settings = settingsStore.load()
        let permissions = permissionChecker.snapshot()
        guard !MenuBarVisualCaptureGate.isSuspended else {
            return MenuBarThumbnailResult(image: fallbackImage(for: item), isPixelPreview: false)
        }
        guard settings.enableScreenRecordingPreviews,
              permissions.canShowPixelPreviews,
              let image = windowImage(for: item) else {
            return MenuBarThumbnailResult(image: fallbackImage(for: item), isPixelPreview: false)
        }
        return MenuBarThumbnailResult(image: image, isPixelPreview: true)
    }

    private func windowImage(for item: MenuBarItem) -> NSImage? {
        let windowID = CGWindowID(item.windowID)
        let options: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]

        if let cgImage = CGWindowListCreateImage(
            item.bounds,
            .optionIncludingWindow,
            windowID,
            options
        ), hasVisibleContent(cgImage) {
            return NSImage(cgImage: cgImage, size: item.bounds.size)
        }

        if let cgImage = skyLightImageProvider.image(for: windowID, bounds: item.bounds, options: options),
           hasVisibleContent(cgImage) {
            return NSImage(cgImage: cgImage, size: item.bounds.size)
        }

        if let cgImage = skyLightImageProvider.image(for: windowID, bounds: .null, options: options),
           hasVisibleContent(cgImage) {
            return NSImage(cgImage: cgImage, size: item.bounds.size)
        }

        return nil
    }

    private func fallbackImage(for item: MenuBarItem) -> NSImage {
        let width = max(item.bounds.width, 1)
        let height = max(item.bounds.height, 1)
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size)
        let title = item.title ?? item.tag.title
        let appIcon = applicationIcon(for: item)

        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        if let appIcon {
            drawAppIcon(appIcon, in: NSRect(origin: .zero, size: size))
        } else if width >= 34, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            drawMenuBarTitle(title, in: NSRect(origin: .zero, size: size))
        } else {
            drawFallbackGlyph(in: NSRect(origin: .zero, size: size), description: title)
        }

        image.unlockFocus()
        image.isTemplate = appIcon == nil
        return image
    }

    private func applicationIcon(for item: MenuBarItem) -> NSImage? {
        if let sourcePID = item.sourcePID,
           let icon = NSRunningApplication(processIdentifier: sourcePID)?.icon {
            return icon
        }
        if let icon = NSRunningApplication(processIdentifier: item.ownerPID)?.icon {
            return icon
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.tag.namespace) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
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

    private func drawMenuBarTitle(_ title: String, in rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuBarFont(ofSize: 0),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let textSize = title.size(withAttributes: attributes)
        let textRect = NSRect(
            x: rect.minX + 4,
            y: rect.minY + max((rect.height - textSize.height) / 2, 0),
            width: max(rect.width - 8, 1),
            height: min(textSize.height, rect.height)
        )
        title.draw(in: textRect, withAttributes: attributes)
    }

    private func drawAppIcon(_ icon: NSImage, in rect: NSRect) {
        let iconSide = min(rect.width, rect.height, 22)
        let iconRect = NSRect(
            x: rect.midX - iconSide / 2,
            y: rect.midY - iconSide / 2,
            width: iconSide,
            height: iconSide
        )
        icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private func drawFallbackGlyph(in rect: NSRect, description: String) {
        guard let symbol = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: description) else {
            return
        }

        let glyphSize = min(rect.width, rect.height, 18)
        let glyphRect = NSRect(
            x: rect.midX - glyphSize / 2,
            y: rect.midY - glyphSize / 2,
            width: glyphSize,
            height: glyphSize
        )
        NSColor.labelColor.set()
        symbol.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1)
    }
}
