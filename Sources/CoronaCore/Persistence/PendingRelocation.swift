import Foundation

public enum PendingRelocation: Codable, Equatable, Sendable {
    case section(MenuBarSection)
    case waitForRelaunch(windowID: UInt32, section: MenuBarSection)

    public init?(rawValue: String) {
        if let section = MenuBarSection(rawValue: rawValue) {
            self = .section(section)
            return
        }

        let prefix = "waitForRelaunch:"
        guard rawValue.hasPrefix(prefix) else {
            return nil
        }

        let parts = rawValue.dropFirst(prefix.count).split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let windowID = UInt32(parts[0]),
              let section = MenuBarSection(rawValue: parts[1]) else {
            return nil
        }

        self = .waitForRelaunch(windowID: windowID, section: section)
    }

    public var rawValue: String {
        switch self {
        case .section(let section):
            return section.rawValue
        case .waitForRelaunch(let windowID, let section):
            return "waitForRelaunch:\(windowID):\(section.rawValue)"
        }
    }

    public func shouldAttemptRecovery(currentWindowID: UInt32?) -> Bool {
        switch self {
        case .section:
            return true
        case .waitForRelaunch(let windowID, _):
            return currentWindowID != windowID
        }
    }

    public var targetSection: MenuBarSection {
        switch self {
        case .section(let section):
            return section
        case .waitForRelaunch(_, let section):
            return section
        }
    }
}
