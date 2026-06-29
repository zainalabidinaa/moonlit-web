import Foundation
import OSLog

private let logger = Logger(subsystem: "ai.moonlit.MoonlitCore", category: "CollectionOrganizer")

public final class CollectionOrganizerStore: @unchecked Sendable {
    public static let shared = CollectionOrganizerStore()

    private let cacheURL: URL
    private let session: URLSession
    private let cacheTTL: TimeInterval = 86400

    public convenience init() {
        let cacheDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MoonlitHomeLayout", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        self.init(
            cacheURL: cacheDir.appendingPathComponent("home-organizer.json"),
            session: .shared
        )
    }

    init(cacheURL: URL, session: URLSession) {
        self.cacheURL = cacheURL
        self.session = session
    }

    public func cachedOrBundledLayout(bundledData: Data) throws -> OrganizedCollections {
        if let cachedData = try? Data(contentsOf: cacheURL),
           let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
           let modDate = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modDate) < cacheTTL,
           let cached = try? CollectionOrganizerParser.parse(jsonData: cachedData),
           !cached.collections.isEmpty {
            return cached
        }
        return try CollectionOrganizerParser.parse(jsonData: bundledData)
    }

    public func refresh(remoteURL: URL?) async -> OrganizedCollections? {
        guard let remoteURL else { return nil }
        do {
            let (data, response) = try await session.data(from: remoteURL)
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("home-organizer fetch: not an HTTP response")
                return nil
            }
            guard httpResponse.statusCode == 200 else {
                logger.error("home-organizer fetch: HTTP \(httpResponse.statusCode)")
                try? FileManager.default.removeItem(at: cacheURL)
                return nil
            }
            let parsed = try CollectionOrganizerParser.parse(jsonData: data)
            try? data.write(to: cacheURL, options: .atomic)
            logger.info("home-organizer refreshed successfully (\(parsed.collections.count) collections)")
            return parsed
        } catch {
            logger.error("home-organizer fetch failed: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: cacheURL)
            return nil
        }
    }
}
