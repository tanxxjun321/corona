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
        return NSImage(cgImage: cgImage, size: item.bounds.size)
    }

    private func fallbackImage(for item: MenuBarItem) -> NSImage {
        if let applicationIcon = applicationIcon(for: item) {
            return applicationIcon
        }

        let symbolName = item.isOnScreen ? "app.dashed" : "questionmark.app.dashed"
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: item.title ?? item.tag.title)
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
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
