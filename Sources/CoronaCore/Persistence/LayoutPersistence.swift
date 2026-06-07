import Foundation

public protocol LayoutPersistenceStore {
    func loadSavedSectionOrder() -> SectionOrder
    func saveSavedSectionOrder(_ order: SectionOrder)
    func loadKnownItemIdentifiers() -> Set<String>
    func saveKnownItemIdentifiers(_ identifiers: Set<String>)
    func loadPendingRelocations() -> [String: PendingRelocation]
    func savePendingRelocation(_ relocation: PendingRelocation?, for uid: String)
}

public final class UserDefaultsLayoutPersistenceStore: LayoutPersistenceStore {
    private enum Key {
        static let savedSectionOrder = "ItemManager.savedSectionOrder.v1"
        static let knownItemIdentifiers = "ItemManager.knownItemIdentifiers"
        static let pendingRelocations = "ItemManager.pendingRelocations.v1"
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

    public func loadPendingRelocations() -> [String: PendingRelocation] {
        let raw = defaults.dictionary(forKey: Key.pendingRelocations) as? [String: String] ?? [:]
        return raw.reduce(into: [String: PendingRelocation]()) { result, entry in
            if let relocation = PendingRelocation(rawValue: entry.value) {
                result[entry.key] = relocation
            }
        }
    }

    public func savePendingRelocation(_ relocation: PendingRelocation?, for uid: String) {
        var raw = defaults.dictionary(forKey: Key.pendingRelocations) as? [String: String] ?? [:]
        raw[uid] = relocation?.rawValue
        defaults.set(raw, forKey: Key.pendingRelocations)
    }
}
