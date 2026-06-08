import CoreGraphics
import Darwin
import Foundation

struct PrivateMenuBarWindowListProvider {
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
        guard let handle = dlopen(Self.skyLightPath, RTLD_NOW) else {
            CoronaDebugLog.verbose("privateMenuBarWindows.dlopen failed")
            return nil
        }

        guard let mainConnectionSymbol = dlsym(handle, "CGSMainConnectionID"),
              let getWindowCountSymbol = dlsym(handle, "CGSGetWindowCount"),
              let getMenuBarListSymbol = dlsym(handle, "CGSGetProcessMenuBarWindowList") else {
            CoronaDebugLog.verbose("privateMenuBarWindows.symbols unavailable")
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
            CoronaDebugLog.verbose("privateMenuBarWindows.list failed")
            return nil
        }

        let result = Array(list.prefix(Int(count)))
        CoronaDebugLog.log("privateMenuBarWindows.ids count=\(result.count)")
        return result
    }
}
