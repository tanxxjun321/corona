import Foundation

public struct SectionOrder: Codable, Equatable, Sendable {
    public var visible: [String]
    public var hidden: [String]
    public var alwaysHidden: [String]

    public init(
        visible: [String] = [],
        hidden: [String] = [],
        alwaysHidden: [String] = []
    ) {
        self.visible = visible
        self.hidden = hidden
        self.alwaysHidden = alwaysHidden
    }

    public subscript(section: MenuBarSection) -> [String] {
        get {
            switch section {
            case .visible:
                return visible
            case .hidden:
                return hidden
            case .alwaysHidden:
                return alwaysHidden
            }
        }
        set {
            switch section {
            case .visible:
                visible = newValue
            case .hidden:
                hidden = newValue
            case .alwaysHidden:
                alwaysHidden = newValue
            }
        }
    }
}

public enum NewItemsPlacement: Codable, Equatable, Sendable {
    case append
    case prepend
    case leftOf(String)
    case rightOf(String)
}

public struct LayoutPreference: Codable, Equatable, Sendable {
    public var savedOrder: SectionOrder
    public var newItemsSection: MenuBarSection
    public var newItemsPlacement: NewItemsPlacement
    public var alwaysHiddenEnabled: Bool

    public init(
        savedOrder: SectionOrder = SectionOrder(),
        newItemsSection: MenuBarSection = .hidden,
        newItemsPlacement: NewItemsPlacement = .append,
        alwaysHiddenEnabled: Bool = false
    ) {
        self.savedOrder = savedOrder
        self.newItemsSection = newItemsSection
        self.newItemsPlacement = newItemsPlacement
        self.alwaysHiddenEnabled = alwaysHiddenEnabled
    }
}
