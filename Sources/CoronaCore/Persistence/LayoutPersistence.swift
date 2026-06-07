import Foundation

public protocol LayoutPersistenceStore {
    func loadSavedSectionOrder() -> SectionOrder
    func saveSavedSectionOrder(_ order: SectionOrder)
    func loadKnownItemIdentifiers() -> Set<String>
    func saveKnownItemIdentifiers(_ identifiers: Set<String>)
}

public final class UserDefaultsLayoutPersistenceStore: LayoutPersistenceStore {
    private enum Key {
        static let savedSectionOrder = "ItemManager.savedSectionOrder.v1"
        static let knownItemIdentifiers = "ItemManager.knownItemIdentifiers"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadSavedSectionOrder() -> SectionOrder {
        guard let data = defaults.data(forKey: Key.savedSectionOrder),
              let order = try? decoder.decode(SectionOrder.self, from: data) else {
            return SectionOrder()
        }
        return order
    }

    public func saveSavedSectionOrder(_ order: SectionOrder) {
        guard let data = try? encoder.encode(order) else { return }
        defaults.set(data, forKey: Key.savedSectionOrder)
    }

    public func loadKnownItemIdentifiers() -> Set<String> {
        Set(defaults.stringArray(forKey: Key.knownItemIdentifiers) ?? [])
    }

    public func saveKnownItemIdentifiers(_ identifiers: Set<String>) {
        defaults.set(Array(identifiers).sorted(), forKey: Key.knownItemIdentifiers)
    }
}
