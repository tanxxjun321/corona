import CoreGraphics
import Darwin
import Foundation

struct SkyLightWindowImageProvider {
    private typealias CreateImageFromArrayFn = @convention(c) (
        CGRect,
        CFArray,
        CGWindowImageOption
    ) -> Unmanaged<CGImage>?

    private static let skyLightPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

    private static let createImageFromArray: CreateImageFromArrayFn? = {
        guard let handle = dlopen(skyLightPath, RTLD_NOW) else {
            CoronaDebugLog.verbose("skyLightWindowImage.dlopen failed")
            return nil
        }
        guard let symbol = dlsym(handle, "SLWindowListCreateImageFromArray") else {
            CoronaDebugLog.verbose("skyLightWindowImage.symbol unavailable")
            return nil
        }
        return unsafeBitCast(symbol, to: CreateImageFromArrayFn.self)
    }()

    func image(for windowID: CGWindowID, bounds: CGRect, options: CGWindowImageOption) -> CGImage? {
        guard let createImageFromArray = Self.createImageFromArray,
              let windowArray = windowArray(for: windowID) else {
            return nil
        }

        let captureBounds = bounds.isNull || bounds.isEmpty ? CGRect.null : bounds
        return createImageFromArray(captureBounds, windowArray, options)?.takeRetainedValue()
    }

    private func windowArray(for windowID: CGWindowID) -> CFArray? {
        guard let pointer = UnsafeRawPointer(bitPattern: UInt(windowID)) else {
            return nil
        }
        var pointers: [UnsafeRawPointer?] = [pointer]
        var callbacks = CFArrayCallBacks(
            version: 0,
            retain: nil,
            release: nil,
            copyDescription: nil,
            equal: nil
        )
        return CFArrayCreate(nil, &pointers, pointers.count, &callbacks)
    }
}
