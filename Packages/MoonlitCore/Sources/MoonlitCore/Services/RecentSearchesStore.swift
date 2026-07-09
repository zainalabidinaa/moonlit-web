import Foundation

/// Last ~8 unique search queries, shown as pills in the Search screen's empty
/// (pre-typing) state — mirrors Harbor's recent-searches row.
@MainActor
public final class RecentSearchesStore: ObservableObject {
    public static let shared = RecentSearchesStore()

    @Published public private(set) var recent: [String] = []

    private let defaults: UserDefaults
    private let key = "moonlit.recentSearches"
    private let maxEntries = 8

    public convenience init() {
        self.init(defaults: .standard)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        recent = defaults.stringArray(forKey: key) ?? []
    }

    public func record(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recent.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recent.insert(trimmed, at: 0)
        if recent.count > maxEntries { recent = Array(recent.prefix(maxEntries)) }
        defaults.set(recent, forKey: key)
    }

    public func remove(_ query: String) {
        recent.removeAll { $0 == query }
        defaults.set(recent, forKey: key)
    }

    public func clear() {
        recent = []
        defaults.removeObject(forKey: key)
    }
}
