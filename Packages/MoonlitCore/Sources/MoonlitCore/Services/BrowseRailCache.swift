import Foundation

public final class BrowseRailCache: @unchecked Sendable {
    public static let shared = BrowseRailCache()

    private static let ttl: TimeInterval = 24 * 3600

    private let lock = NSLock()
    private var memory: [String: Entry] = [:]

    private let diskURL: URL = {
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MoonlitBrowseRails")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("rails.json")
    }()

    private struct Entry: Codable {
        let rails: [GenreCatalog.LoadedBrowseRail]
        let timestamp: Date
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

    public func get(key: String) -> [GenreCatalog.LoadedBrowseRail]? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = memory[key] else { return nil }
        guard Date().timeIntervalSince(entry.timestamp) < Self.ttl else {
            memory[key] = nil
            return nil
        }
        return entry.rails
    }

    public func set(key: String, rails: [GenreCatalog.LoadedBrowseRail]) {
        lock.lock()
        memory[key] = Entry(rails: rails, timestamp: Date())
        lock.unlock()
        saveToDisk()
    }
}
