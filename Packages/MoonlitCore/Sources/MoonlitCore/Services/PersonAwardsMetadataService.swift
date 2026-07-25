import Foundation

/// Person-scoped sibling of `AwardsMetadataService` — same Wikidata source,
/// same `AwardBody`/`AwardEntry`/`AwardSummary` shapes and the same
/// `MacAwardsRecognitionSection` renders both, but keyed off a person's IMDb
/// id instead of a title's, and each entry carries the work it was won/
/// nominated for since a person's awards span multiple titles.
@MainActor
public final class PersonAwardsMetadataService: ObservableObject {
    public static let shared = PersonAwardsMetadataService()

    @Published public private(set) var summaries: [String: AwardSummary] = [:]

    private var inFlight: Set<String> = []
    private let staleInterval: TimeInterval = 30 * 24 * 60 * 60
    private let maxEntries = 500

    private let cacheURL: URL? = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return dir?.appendingPathComponent("moonlit-person-awards-metadata.json")
    }()

    private init() {
        if let url = cacheURL, let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(PersonAwardsCache.self, from: data) {
            summaries = decoded.entries
        }
    }

    public func summary(forImdbId imdbId: String) -> AwardSummary? {
        summaries[imdbId]
    }

    public func fetch(imdbId: String) async {
        guard imdbId.hasPrefix("nm") || imdbId.hasPrefix("tt") else { return }
        if let existing = summaries[imdbId], Date().timeIntervalSince(existing.fetchedAt) < staleInterval {
            summaries[imdbId]?.lastAccessedAt = Date()
            return
        }
        guard !inFlight.contains(imdbId) else { return }
        inFlight.insert(imdbId)
        defer { inFlight.remove(imdbId) }
        do {
            let summary = try await Self.queryWikidata(imdbId: imdbId)
            summaries[imdbId] = summary
            persist()
        } catch {
            if summaries[imdbId] == nil {
                summaries[imdbId] = AwardSummary(titleId: imdbId)
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
        let cache = PersonAwardsCache(version: 1, entries: entries)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private static func queryWikidata(imdbId: String) async throws -> AwardSummary {
        let sparql = """
        SELECT ?kind ?awardLabel ?year ?workLabel WHERE {
          ?person wdt:P345 "\(imdbId)" .
          { ?person p:P166 ?s . ?s ps:P166 ?award . OPTIONAL { ?s pq:P585 ?date } OPTIONAL { ?s pq:P1686 ?work } BIND("win" AS ?kind) }
          UNION
          { ?person p:P1411 ?s . ?s ps:P1411 ?award . OPTIONAL { ?s pq:P585 ?date } OPTIONAL { ?s pq:P1686 ?work } BIND("nom" AS ?kind) }
          BIND(YEAR(?date) AS ?year)
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        }
        LIMIT 200
        """
        guard let encoded = sparql.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://query.wikidata.org/sparql?format=json&query=\(encoded)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Moonlit/1.0 (https://moonlit.app; contact@moonlit.app)", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode(PersonWikidataResponse.self, from: data)

        var wins: [AwardEntry] = []
        var nominations: [AwardEntry] = []
        for binding in decoded.results.bindings {
            guard let body = AwardBody.classify(label: binding.awardLabel.value) else { continue }
            let category = AwardBody.category(from: binding.awardLabel.value, body: body)
            let year = binding.year.flatMap { Int($0.value) }
            let entry = AwardEntry(body: body, category: category, year: year, workTitle: binding.workLabel?.value)
            if binding.kind.value == "win" {
                wins.append(entry)
            } else {
                nominations.append(entry)
            }
        }
        return AwardSummary(titleId: imdbId, wins: wins, nominations: nominations)
    }
}

private struct PersonAwardsCache: Codable {
    let version: Int
    let entries: [String: AwardSummary]
}

private struct PersonWikidataResponse: Decodable {
    let results: PersonWikidataResults
}

private struct PersonWikidataResults: Decodable {
    let bindings: [PersonWikidataBinding]
}

private struct PersonWikidataBinding: Decodable {
    let kind: PersonWikidataValue
    let awardLabel: PersonWikidataValue
    let year: PersonWikidataValue?
    let workLabel: PersonWikidataValue?
}

private struct PersonWikidataValue: Decodable {
    let value: String
}
