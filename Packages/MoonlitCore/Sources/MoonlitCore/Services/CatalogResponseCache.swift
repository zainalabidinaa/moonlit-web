import Foundation

public final class CatalogResponseCache: @unchecked Sendable {
    public static let shared = CatalogResponseCache()

    private static let defaultTTL: TimeInterval = 30 * 60
    private static let trendingTTL: TimeInterval = 2 * 3600
    private static let staticTTL: TimeInterval = 6 * 3600

    private let lock = NSLock()
    private var memory: [String: Entry] = [:]
    private let diskURL: URL = {
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MoonlitCatalogCache")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("catalogs.json")
    }()

    private struct Entry: Codable {
        var data: Data
        var timestamp: Date
    }

    private static func ttlFor(key: String) -> TimeInterval {
        let lower = key.lowercased()
        let staticPatterns = ["genre=", "language=", "/genre/", "/language/", "with_genres", "with_original_language"]
        let trendingPatterns = ["/top", "/popular", "/trending", "/featured"]
        for pattern in staticPatterns where lower.contains(pattern) { return staticTTL }
        for pattern in trendingPatterns where lower.contains(pattern) { return trendingTTL }
        return defaultTTL
    }

    private init() {
        loadFromDisk()
    }

    private func loadFromDisk() {
        lock.lock()
        defer { lock.unlock() }
        guard let fileData = try? Data(contentsOf: diskURL),
              let dict = try? JSONDecoder().decode([String: Entry].self, from: fileData) else { return }
        memory = dict
    }

    private func saveToDisk() {
        lock.lock()
        let snapshot = memory
        lock.unlock()
        DispatchQueue.global(qos: .utility).async { [diskURL] in
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: diskURL, options: .atomic)
        }
    }

    public func get(key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = memory[key] else { return nil }
        guard Date().timeIntervalSince(entry.timestamp) < Self.ttlFor(key: key) else {
            memory[key] = nil
            return nil
        }
        return entry.data
    }

    public func set(key: String, data: Data) {
        lock.lock()
        memory[key] = Entry(data: data, timestamp: Date())
        let now = Date()
        memory = memory.filter { now.timeIntervalSince($0.value.timestamp) < Self.ttlFor(key: $0.key) }
        lock.unlock()
        saveToDisk()
    }

    public func clear() {
        lock.lock()
        memory = [:]
        lock.unlock()
        try? FileManager.default.removeItem(at: diskURL)
    }
}
