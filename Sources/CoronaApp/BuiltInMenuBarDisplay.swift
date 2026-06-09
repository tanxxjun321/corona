import AppKit
import CoreGraphics

enum BuiltInMenuBarDisplay {
    struct Target {
        var id: CGDirectDisplayID
        var frame: CGRect
    }

    static func target() -> Target {
        let id = targetDisplayID()
        return Target(id: id, frame: CGDisplayBounds(id))
    }

    static func activeDisplayFrames() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return [target().frame]
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, nil) == .success else {
            return [target().frame]
        }
        return displays.map(CGDisplayBounds)
    }

    static func displayID(for screen: NSScreen?) -> CGDirectDisplayID? {
        screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { self.displayID(for: $0) == displayID }
    }

    private static func targetDisplayID() -> CGDirectDisplayID {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return CGMainDisplayID()
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, nil) == .success else {
            return CGMainDisplayID()
        }

        return displays.first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }
}
