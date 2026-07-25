import Foundation

/// A person result from TMDB `/search/multi` — used for the Search screen's
/// "People" row. Tapping one opens `ActorBioScreen`/`MacActorBioView` directly
/// via `tmdbId`, no name-based lookup needed.
public struct PersonSearchResult: Identifiable, Sendable, Hashable {
    public let id: Int
    public let name: String
    public let profilePath: String?
    public let knownFor: [String]

    public init(id: Int, name: String, profilePath: String?, knownFor: [String]) {
        self.id = id
        self.name = name
        self.profilePath = profilePath
        self.knownFor = knownFor
    }
}

/// TMDB `/search/multi` — a single call covering movies, TV shows, and people,
/// sectioned for the Search screen. Movie/TV results carry TMDB ids; those are
/// resolved to real IMDb ids (via the shared resolver in `TMDBDiscoverService`)
/// so tapping a result opens the same IMDb-id-centric detail screen as
/// everything else in the app. Runs alongside the existing addon-catalog
/// `SearchRepository` search, which remains the only source for titles TMDB
/// doesn't index.
@MainActor
public final class TMDBSearchService: ObservableObject {
    public static let shared = TMDBSearchService()

    public struct Results {
        public var movies: [MetaPreview]
        public var shows: [MetaPreview]
        public var people: [PersonSearchResult]

        public init(movies: [MetaPreview] = [], shows: [MetaPreview] = [], people: [PersonSearchResult] = []) {
            self.movies = movies
            self.shows = shows
            self.people = people
        }
    }

    private let base = "https://api.themoviedb.org/3"
    private var apiKey: String? { MetadataIntegrationStore.shared.effectiveTMDBAPIKey }

    // Session-scoped query cache so backspacing/retyping ("silos" → "silo")
    // repaints instantly instead of re-hitting the network. Insertion-order
    // eviction keeps it bounded.
    private var queryCache: [String: Results] = [:]
    private var queryCacheOrder: [String] = []
    private let queryCacheLimit = 50

    private init() {}

    public func cachedResults(for query: String) -> Results? {
        queryCache[Self.normalizedQuery(query)]
    }

    public func search(query: String) async -> Results {
        guard let apiKey, !apiKey.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(base)/search/multi?api_key=\(apiKey)&query=\(encoded)&include_adult=false") else {
            return Results()
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(TMDBMultiSearchResponse.self, from: data)
            let mapped = await mapResults(decoded.results ?? [], apiKey: apiKey)
            storeInCache(query: query, results: mapped)
            return mapped
        } catch {
            // Fall back to a cached hit if the network failed mid-typing.
            return cachedResults(for: query) ?? Results()
        }
    }

    private func storeInCache(query: String, results: Results) {
        let key = Self.normalizedQuery(query)
        if queryCache[key] == nil {
            queryCacheOrder.append(key)
            if queryCacheOrder.count > queryCacheLimit {
                queryCache.removeValue(forKey: queryCacheOrder.removeFirst())
            }
        }
        queryCache[key] = results
    }

    private static func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func mapResults(_ items: [TMDBMultiSearchItem], apiKey: String) async -> Results {
        var results = Results()
        results.people = items
            .filter { $0.media_type == "person" }
            .prefix(10)
            .map {
                PersonSearchResult(
                    id: $0.id,
                    name: $0.name ?? "Unknown",
                    profilePath: $0.profile_path,
                    knownFor: ($0.known_for ?? []).compactMap { $0.title ?? $0.name }.prefix(2).map { $0 }
                )
            }

        let movieItems = items.filter { $0.media_type == "movie" }
        let showItems = items.filter { $0.media_type == "tv" }

        async let movies = resolveToPreviews(movieItems, kind: "movie", apiKey: apiKey)
        async let shows = resolveToPreviews(showItems, kind: "tv", apiKey: apiKey)
        results.movies = await movies
        results.shows = await shows

        TMDBDiscoverService.shared.persistCache()
        return results
    }

    private func resolveToPreviews(_ items: [TMDBMultiSearchItem], kind: String, apiKey: String) async -> [MetaPreview] {
        guard !items.isEmpty else { return [] }
        let type: MediaType = kind == "movie" ? .movie : .series
        return await withTaskGroup(of: MetaPreview?.self) { group in
            for item in items.prefix(20) {
                group.addTask {
                    guard let imdbId = await TMDBDiscoverService.shared.resolveImdbId(tmdbId: item.id, kind: kind, apiKey: apiKey) else { return nil }
                    return MetaPreview(
                        id: imdbId,
                        type: type,
                        name: item.title ?? item.name ?? "",
                        poster: item.poster_path.map { "https://image.tmdb.org/t/p/w500\($0)" },
                        releaseInfo: (item.release_date ?? item.first_air_date).flatMap { $0.split(separator: "-").first.map(String.init) },
                        popularity: item.popularity,
                        imdbRating: item.vote_average.map { String(format: "%.1f", $0) }
                    )
                }
            }
            var out: [MetaPreview] = []
            for await item in group { if let item { out.append(item) } }
            return out
        }
    }
}

private struct TMDBMultiSearchResponse: Decodable {
    let results: [TMDBMultiSearchItem]?
}

private struct TMDBMultiSearchItem: Decodable {
    let id: Int
    let media_type: String?
    let title: String?
    let name: String?
    let poster_path: String?
    let profile_path: String?
    let release_date: String?
    let first_air_date: String?
    let vote_average: Double?
    let popularity: Double?
    let known_for: [TMDBKnownForItem]?
}

private struct TMDBKnownForItem: Decodable {
    let title: String?
    let name: String?
}
