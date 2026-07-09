import Foundation

/// Fetches award wins/nominations for titles from Wikidata (no API key needed),
/// so movie posters and detail views can show "Academy Award Winner · 3 wins ·
/// 5 nominations" style badges — mirrors how Harbor sources award metadata.
///
/// Coexists with `AwardIndex`: `AwardIndex` is instant, collection-curated, and
/// winner-only (one body per title); this service is authoritative for counts
/// and nominations once it loads, and the UI prefers it when available.
@MainActor
public final class AwardsMetadataService: ObservableObject {
    public static let shared = AwardsMetadataService()

    @Published public private(set) var summaries: [String: AwardSummary] = [:]

    private var inFlight: Set<String> = []
    private var pendingQueue: [String] = []
    private var activeCount = 0
    private let maxConcurrent = 2
    private let staleInterval: TimeInterval = 30 * 24 * 60 * 60
    private let maxEntries = 500

    private let cacheURL: URL? = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return dir?.appendingPathComponent("moonlit-awards-metadata.json")
    }()

    private init() {
        if let url = cacheURL, let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(AwardsMetadataCache.self, from: data) {
            summaries = decoded.entries
        }
    }

    /// The cached summary for a title, or `nil` if not fetched yet. Accepts
    /// episode ids like `tt123:1:2` — the series part is used.
    public func summary(forId id: String) -> AwardSummary? {
        summaries[Self.plainId(id)]
    }

    /// Queues titles for background fetching (e.g. the items in a hero carousel).
    /// Respects `maxConcurrent` so a burst of hero items doesn't hammer Wikidata.
    public func prefetch(ids: [String]) {
        for id in ids {
            let plainId = Self.plainId(id)
            guard plainId.hasPrefix("tt"), !isFresh(plainId), !inFlight.contains(plainId),
                  !pendingQueue.contains(plainId) else { continue }
            pendingQueue.append(plainId)
        }
        drainQueue()
    }

    /// Fetches a single title immediately (used when opening its detail screen).
    public func fetch(id: String) async {
        let plainId = Self.plainId(id)
        guard plainId.hasPrefix("tt") else { return }
        if isFresh(plainId) {
            touch(plainId)
            return
        }
        guard !inFlight.contains(plainId) else { return }
        inFlight.insert(plainId)
        await performFetch(plainId: plainId)
        inFlight.remove(plainId)
        drainQueue()
    }

    private func drainQueue() {
        while activeCount < maxConcurrent, !pendingQueue.isEmpty {
            let plainId = pendingQueue.removeFirst()
            guard !inFlight.contains(plainId) else { continue }
            inFlight.insert(plainId)
            activeCount += 1
            Task {
                await performFetch(plainId: plainId)
                activeCount -= 1
                inFlight.remove(plainId)
                drainQueue()
            }
        }
    }

    private func isFresh(_ plainId: String) -> Bool {
        guard let summary = summaries[plainId] else { return false }
        return Date().timeIntervalSince(summary.fetchedAt) < staleInterval
    }

    private func touch(_ plainId: String) {
        summaries[plainId]?.lastAccessedAt = Date()
    }

    private func performFetch(plainId: String) async {
        do {
            let summary = try await Self.queryWikidata(imdbId: plainId)
            summaries[plainId] = summary
            persist()
        } catch {
            // Cache a negative result too, so a title with no awards doesn't
            // get re-queried every launch.
            if summaries[plainId] == nil {
                summaries[plainId] = AwardSummary(titleId: plainId)
                persist()
            }
        }
    }

    private func persist() {
        guard let cacheURL else { return }
        var entries = summaries
        if entries.count > maxEntries {
            let sortedByRecency = entries.sorted { $0.value.lastAccessedAt > $1.value.lastAccessedAt }
            entries = Dictionary(uniqueKeysWithValues: sortedByRecency.prefix(maxEntries).map { ($0.key, $0.value) })
        }
        let cache = AwardsMetadataCache(version: 1, entries: entries)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private static func plainId(_ id: String) -> String {
        id.split(separator: ":").first.map(String.init) ?? id
    }

    private static func queryWikidata(imdbId: String) async throws -> AwardSummary {
        let sparql = """
        SELECT ?kind ?awardLabel ?year WHERE {
          ?film wdt:P345 "\(imdbId)" .
          { ?film p:P166 ?s . ?s ps:P166 ?award . OPTIONAL { ?s pq:P585 ?date } BIND("win" AS ?kind) }
          UNION
          { ?film p:P1411 ?s . ?s ps:P1411 ?award . OPTIONAL { ?s pq:P585 ?date } BIND("nom" AS ?kind) }
          BIND(YEAR(?date) AS ?year)
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        }
        """
        guard let encoded = sparql.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://query.wikidata.org/sparql?format=json&query=\(encoded)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Moonlit/1.0 (https://moonlit.app; contact@moonlit.app)", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode(WikidataResponse.self, from: data)

        var wins: [AwardEntry] = []
        var nominations: [AwardEntry] = []
        for binding in decoded.results.bindings {
            guard let body = AwardBody.classify(label: binding.awardLabel.value) else { continue }
            let category = AwardBody.category(from: binding.awardLabel.value, body: body)
            let year = binding.year.flatMap { Int($0.value) }
            let entry = AwardEntry(body: body, category: category, year: year)
            if binding.kind.value == "win" {
                wins.append(entry)
            } else {
                nominations.append(entry)
            }
        }
        return AwardSummary(titleId: imdbId, wins: wins, nominations: nominations)
    }
}

private struct AwardsMetadataCache: Codable {
    let version: Int
    let entries: [String: AwardSummary]
}

private struct WikidataResponse: Decodable {
    let results: WikidataResults
}

private struct WikidataResults: Decodable {
    let bindings: [WikidataBinding]
}

private struct WikidataBinding: Decodable {
    let kind: WikidataValue
    let awardLabel: WikidataValue
    let year: WikidataValue?
}

private struct WikidataValue: Decodable {
    let value: String
}
