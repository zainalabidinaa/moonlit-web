import Foundation
import CryptoKit

public final class CatalogResponseCache: @unchecked Sendable {
    public static let shared = CatalogResponseCache(directory: CatalogResponseCache.defaultDirectory())

    private static let defaultTTL: TimeInterval = 30 * 60
    private static let trendingTTL: TimeInterval = 2 * 3600
    private static let staticTTL: TimeInterval = 6 * 3600

    private let lock = NSLock()
    private var memory: [String: Entry] = [:]
    private let directory: URL
    private let saveQueue = DispatchQueue(label: "app.trymoonlit.CatalogResponseCache.save")

    private struct Entry: Codable {
        var data: Data
        var timestamp: Date
    }

    private static func defaultDirectory() -> URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MoonlitCatalogCache")
    }

    private static func ttlFor(key: String) -> TimeInterval {
        let lower = key.lowercased()
        let staticPatterns = ["genre=", "language=", "/genre/", "/language/", "with_genres", "with_original_language"]
        let trendingPatterns = ["/top", "/popular", "/trending", "/featured"]
        for pattern in staticPatterns where lower.contains(pattern) { return staticTTL }
        for pattern in trendingPatterns where lower.contains(pattern) { return trendingTTL }
        return defaultTTL
    }

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        pruneOrphanedTempFiles()
        loadFromDisk()
    }

    /// Each entry gets its own file, named by a hash of its key, so a `set()`
    /// only ever encodes and writes the bytes for that one entry instead of
    /// the whole cache.
    private func fileURL(forKey key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(hex).json")
    }

    /// `Data.write(options: .atomic)` writes to a `<name>.sb-<random>` temp
    /// file then renames it over the destination. If the process dies mid-write
    /// (e.g. the crash this cache used to cause) that temp file is orphaned
    /// forever, so sweep them on every launch.
    private func pruneOrphanedTempFiles() {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return }
        for url in entries where url.lastPathComponent.contains(".sb-") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func loadFromDisk() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return }
        let decoder = JSONDecoder()
        var loaded: [String: Entry] = [:]
        for url in files where url.pathExtension == "json" {
            guard let fileData = try? Data(contentsOf: url),
                  let keyed = try? decoder.decode(KeyedEntry.self, from: fileData) else { continue }
            loaded[keyed.key] = Entry(data: keyed.data, timestamp: keyed.timestamp)
        }
        lock.lock()
        memory = loaded
        lock.unlock()
    }

    private struct KeyedEntry: Codable {
        var key: String
        var data: Data
        var timestamp: Date
    }

    public func get(key: String) -> Data? {
        lock.lock()
        guard let entry = memory[key] else { lock.unlock(); return nil }
        guard Date().timeIntervalSince(entry.timestamp) < Self.ttlFor(key: key) else {
            memory[key] = nil
            lock.unlock()
            saveQueue.async { [directory, key] in
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(
                    CatalogResponseCache.fileName(forKey: key)))
            }
            return nil
        }
        lock.unlock()
        return entry.data
    }

    private static func fileName(forKey key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".json"
    }

    public func set(key: String, data: Data) {
        set(key: key, data: data, now: Date())
    }

    func set(key: String, data: Data, now: Date) {
        let entry = Entry(data: data, timestamp: now)
        lock.lock()
        memory[key] = entry
        lock.unlock()

        let url = fileURL(forKey: key)
        saveQueue.async {
            guard let encoded = try? JSONEncoder().encode(
                KeyedEntry(key: key, data: entry.data, timestamp: entry.timestamp)) else { return }
            try? encoded.write(to: url, options: .atomic)
        }
    }

    public func clear() {
        lock.lock()
        memory = [:]
        lock.unlock()
        saveQueue.async { [directory] in
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// Test-only hook to synchronize with the async save queue.
    func drainSaveQueueForTesting(_ completion: @escaping @Sendable () -> Void) {
        saveQueue.async { completion() }
    }
}
