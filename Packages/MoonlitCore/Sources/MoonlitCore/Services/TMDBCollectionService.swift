import Foundation

public struct TMDBWatchProvider: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let logoPath: String?

    public var logoURL: URL? {
        guard let logoPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w92\(logoPath)")
    }
}

/// A movie's franchise collection and where-to-watch providers — both come
/// off the same TMDB movie-detail call (`append_to_response=watch/providers`),
/// so they're fetched together even though the UI shows them separately.
public struct MovieExtras: Sendable {
    public let collectionId: Int?
    public let collectionName: String?
    public let providers: [TMDBWatchProvider]
}

public struct TMDBCollectionDetail: Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let overview: String?
    public let backdropPath: String?
    public let parts: [MetaPreview]
}

@MainActor
public final class TMDBCollectionService {
    public static let shared = TMDBCollectionService()

    private let base = "https://api.themoviedb.org/3"
    private var apiKey: String? { MetadataIntegrationStore.shared.effectiveTMDBAPIKey }

    private var tmdbIdCache: [String: Int] = [:]
    private var extrasCache: [Int: MovieExtras] = [:]
    private var collectionCache: [Int: TMDBCollectionDetail] = [:]

    private init() {}

    public func resolveTmdbMovieId(imdbId: String) async -> Int? {
        if let cached = tmdbIdCache[imdbId] { return cached }
        guard let key = apiKey, !key.isEmpty,
              let url = URL(string: "\(base)/find/\(imdbId)?api_key=\(key)&external_source=imdb_id") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(FindResponse.self, from: data),
              let id = decoded.movie_results.first?.id else { return nil }
        tmdbIdCache[imdbId] = id
        return id
    }

    /// Region-agnostic: reads whichever region TMDB resolves for the request
    /// (typically the API's default/US) rather than the user's own region,
    /// since Moonlit doesn't collect one for this purpose yet.
    public func movieExtras(tmdbId: Int, region: String = "US") async -> MovieExtras? {
        if let cached = extrasCache[tmdbId] { return cached }
        guard let key = apiKey, !key.isEmpty,
              let url = URL(string: "\(base)/movie/\(tmdbId)?api_key=\(key)&append_to_response=watch/providers") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(MovieDetailResponse.self, from: data) else { return nil }
        let regionProviders = decoded.watch_providers?.results[region]
        let providers = ((regionProviders?.flatrate ?? []) + (regionProviders?.free ?? []))
            .reduce(into: [TMDBWatchProvider]()) { acc, p in
                if !acc.contains(where: { $0.id == p.provider_id }) {
                    acc.append(TMDBWatchProvider(id: p.provider_id, name: p.provider_name, logoPath: p.logo_path))
                }
            }
        let extras = MovieExtras(
            collectionId: decoded.belongs_to_collection?.id,
            collectionName: decoded.belongs_to_collection?.name,
            providers: providers
        )
        extrasCache[tmdbId] = extras
        return extras
    }

    public func collection(id: Int) async -> TMDBCollectionDetail? {
        if let cached = collectionCache[id] { return cached }
        guard let key = apiKey, !key.isEmpty,
              let url = URL(string: "\(base)/collection/\(id)?api_key=\(key)") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(CollectionResponse.self, from: data) else { return nil }
        let parts = decoded.parts
            .sorted { ($0.release_date ?? "") < ($1.release_date ?? "") }
            .map { part in
                MetaPreview(
                    id: "tmdb:movie:\(part.id)",
                    type: .movie,
                    name: part.title,
                    poster: part.poster_path.map { "https://image.tmdb.org/t/p/w500\($0)" },
                    releaseInfo: part.release_date.map { String($0.prefix(4)) }
                )
            }
        let detail = TMDBCollectionDetail(
            id: decoded.id, name: decoded.name, overview: decoded.overview,
            backdropPath: decoded.backdrop_path, parts: parts
        )
        collectionCache[id] = detail
        return detail
    }
}

private struct FindResponse: Decodable {
    let movie_results: [MovieResult]
    struct MovieResult: Decodable { let id: Int }
}

private struct MovieDetailResponse: Decodable {
    let belongs_to_collection: BelongsToCollection?
    let watch_providers: WatchProvidersWrapper?

    struct BelongsToCollection: Decodable {
        let id: Int
        let name: String
    }
    struct WatchProvidersWrapper: Decodable {
        let results: [String: RegionProviders]
    }
    struct RegionProviders: Decodable {
        let flatrate: [ProviderRaw]?
        let free: [ProviderRaw]?
    }
    struct ProviderRaw: Decodable {
        let provider_id: Int
        let provider_name: String
        let logo_path: String?
    }
}

private struct CollectionResponse: Decodable {
    let id: Int
    let name: String
    let overview: String?
    let backdrop_path: String?
    let parts: [Part]

    struct Part: Decodable {
        let id: Int
        let title: String
        let poster_path: String?
        let release_date: String?
    }
}
