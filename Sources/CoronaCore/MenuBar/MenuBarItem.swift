import CoreGraphics
import Foundation

public struct MenuBarItemTag: Codable, Hashable, Sendable {
    public var namespace: String
    public var title: String
    public var instanceIndex: Int?
    public var volatileWindowID: UInt32?

    public init(
        namespace: String,
        title: String,
        instanceIndex: Int? = nil,
        volatileWindowID: UInt32? = nil
    ) {
        self.namespace = namespace
        self.title = title
        self.instanceIndex = instanceIndex
        self.volatileWindowID = volatileWindowID
    }

    public var stableIdentifier: String {
        if let instanceIndex {
            return "\(namespace):\(title):\(instanceIndex)"
        }
        return "\(namespace):\(title)"
    }
}

public struct MenuBarItem: Codable, Equatable, Sendable {
    public var tag: MenuBarItemTag
    public var windowID: UInt32
    public var ownerPID: Int32
    public var sourcePID: Int32?
    public var bounds: CGRect
    public var title: String?
    public var isOnScreen: Bool
    public var isMovable: Bool
    public var canBeHidden: Bool

    public init(
        tag: MenuBarItemTag,
        windowID: UInt32,
        ownerPID: Int32,
        sourcePID: Int32?,
        bounds: CGRect,
        title: String?,
        isOnScreen: Bool,
        isMovable: Bool,
        canBeHidden: Bool
    ) {
        self.tag = tag
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.sourcePID = sourcePID
        self.bounds = bounds
        self.title = title
        self.isOnScreen = isOnScreen
        self.isMovable = isMovable
        self.canBeHidden = canBeHidden
    }
}
