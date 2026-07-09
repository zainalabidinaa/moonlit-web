import Foundation

/// A person aggregated across an award's winning titles, with the number of
/// winners they appear in (their "N×" badge) and one representative title.
public struct AwardPerson: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let profilePath: String?
    public let count: Int
    public let representativeTitle: String?

    public var profileURL: URL? {
        profilePath.flatMap { URL(string: "https://image.tmdb.org/t/p/w300\($0)") }
    }
}

public struct AwardPeople: Sendable {
    public var actors: [AwardPerson]
    public var directors: [AwardPerson]
    public var writers: [AwardPerson]

    public static let empty = AwardPeople(actors: [], directors: [], writers: [])
    public var isEmpty: Bool { actors.isEmpty && directors.isEmpty && writers.isEmpty }
}

/// Aggregates the actors / directors / writers behind an award's winning titles
/// by querying TMDB credits (mirrors Harbor's award-page people rails). Bounded
/// and best-effort — returns whatever it can and an empty result on failure.
public actor AwardPeopleService {
    public static let shared = AwardPeopleService()

    private let base = "https://api.themoviedb.org/3"
    private var cache: [String: AwardPeople] = [:]

    public func people(forWinners winners: [MetaPreview], cacheKey: String, limit: Int = 22) async -> AwardPeople {
        if let cached = cache[cacheKey] { return cached }
        guard let key = await MetadataIntegrationStore.shared.effectiveTMDBAPIKey, !key.isEmpty else {
            return .empty
        }

        struct Tally { var count = 0; var name = ""; var profile: String?; var title: String? }
        var actorTally: [String: Tally] = [:]
        var directorTally: [String: Tally] = [:]
        var writerTally: [String: Tally] = [:]

        let subset = Array(winners.prefix(limit))
        // Bounded concurrency to avoid hammering TMDB.
        await withTaskGroup(of: Credits?.self) { group in
            for film in subset {
                group.addTask { [self] in await self.credits(for: film, apiKey: key) }
            }
            for await credits in group {
                guard let credits else { continue }
                // Top 3 billed cast per winner.
                for cast in credits.cast.prefix(3) {
                    var t = actorTally[cast.id] ?? Tally()
                    t.count += 1; t.name = cast.name; t.profile = cast.profilePath
                    if t.title == nil { t.title = credits.title }
                    actorTally[cast.id] = t
                }
                for crew in credits.crew {
                    if crew.job == "Director" {
                        var t = directorTally[crew.id] ?? Tally()
                        t.count += 1; t.name = crew.name; t.profile = crew.profilePath
                        if t.title == nil { t.title = credits.title }
                        directorTally[crew.id] = t
                    } else if crew.job == "Writer" || crew.job == "Screenplay" || crew.job == "Story" {
                        var t = writerTally[crew.id] ?? Tally()
                        t.count += 1; t.name = crew.name; t.profile = crew.profilePath
                        if t.title == nil { t.title = credits.title }
                        writerTally[crew.id] = t
                    }
                }
            }
        }

        func rank(_ tally: [String: Tally], _ max: Int) -> [AwardPerson] {
            tally.map { AwardPerson(id: $0.key, name: $0.value.name, profilePath: $0.value.profile,
                                    count: $0.value.count, representativeTitle: $0.value.title) }
                .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
                .prefix(max)
                .map { $0 }
        }

        let result = AwardPeople(
            actors: rank(actorTally, 12),
            directors: rank(directorTally, 12),
            writers: rank(writerTally, 12)
        )
        cache[cacheKey] = result
        return result
    }

    // MARK: - TMDB fetching

    private struct Credits { let title: String?; let cast: [Member]; let crew: [Member] }
    private struct Member { let id: String; let name: String; let job: String; let profilePath: String? }

    private func credits(for film: MetaPreview, apiKey: String) async -> Credits? {
        let isTV = film.type == .series || film.type == .tv
        guard let tmdbId = await resolveTMDBId(for: film, isTV: isTV, apiKey: apiKey) else { return nil }
        let kind = isTV ? "tv" : "movie"
        guard let url = URL(string: "\(base)/\(kind)/\(tmdbId)/credits?api_key=\(apiKey)") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        func members(_ arr: Any?) -> [Member] {
            (arr as? [[String: Any]])?.compactMap { d in
                guard let id = d["id"] as? Int, let name = d["name"] as? String else { return nil }
                return Member(id: String(id), name: name,
                              job: (d["job"] as? String) ?? "", profilePath: d["profile_path"] as? String)
            } ?? []
        }
        return Credits(title: film.name, cast: members(json["cast"]), crew: members(json["crew"]))
    }

    private func resolveTMDBId(for film: MetaPreview, isTV: Bool, apiKey: String) async -> Int? {
        // Ids come in a few shapes: raw imdb ("tt123"), "tmdb:123", or numeric.
        let raw = film.id
        if raw.hasPrefix("tmdb:"), let n = Int(raw.dropFirst(5)) { return n }
        if let n = Int(raw) { return n }
        guard raw.hasPrefix("tt") else { return nil }
        guard let url = URL(string: "\(base)/find/\(raw)?external_source=imdb_id&api_key=\(apiKey)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let key = isTV ? "tv_results" : "movie_results"
        if let arr = json[key] as? [[String: Any]], let first = arr.first, let id = first["id"] as? Int {
            return id
        }
        // Fall back to the other media kind if the primary bucket was empty.
        let alt = isTV ? "movie_results" : "tv_results"
        if let arr = json[alt] as? [[String: Any]], let first = arr.first, let id = first["id"] as? Int {
            return id
        }
        return nil
    }
}
