import Foundation
import MoonlitCore

@MainActor
final class MacHeroArtworkProvider: ObservableObject {
    static let shared = MacHeroArtworkProvider()

    @Published private(set) var urls: [String: URL] = [:]

    private var inFlight: Set<String> = []
    private var misses: Set<String> = []
    private var apiKey: String? { MetadataIntegrationStore.shared.effectiveTMDBAPIKey }

    private init() {}

    ///  priority: the addon's own artwork wins when it has one —
    /// TMDB's vote-sorted backdrop is a fallback for titles the addon left
    /// bare, not a universal override. (TMDB's *highest-voted* backdrop isn't
    /// the *newest* one — older art has had more time to accumulate votes —
    /// so always preferring it made hero art skew dated.)
    func heroArtURL(for item: MetaPreview) -> URL? {
        if let native = item.artworkURL(preferring: .landscape) { return native }
        return urls[item.id]
    }

    func prefetch(items: [MetaPreview]) {
        for item in items {
            resolve(item: item)
        }
    }

    private func resolve(item: MetaPreview) {
        let id = item.id
        guard urls[id] == nil, !inFlight.contains(id), !misses.contains(id),
              item.artworkURL(preferring: .landscape) == nil,
              let key = apiKey, !key.isEmpty,
              id.hasPrefix("tt") || id.hasPrefix("tmdb:") else { return }

        inFlight.insert(id)
        Task {
            defer { inFlight.remove(id) }
            do {
                if let url = try await Self.heroBackdropURL(metaId: id, type: item.type, apiKey: key) {
                    urls[id] = url
                } else {
                    misses.insert(id)
                }
            } catch {
                misses.insert(id)
            }
        }
    }

    /// Mirrors the reference hero backdrop selection: fetch the title's TMDB images,
    /// take **backdrops only** (never posters), and use the community favorite —
    /// the one with the most votes (`vote_count`), matching TMDB's own default
    /// image ordering, with `vote_average` as the tiebreaker.
    private static func heroBackdropURL(metaId: String, type: MediaType, apiKey: String) async throws -> URL? {
        guard let (kind, tmdbId) = try await resolveTMDBId(metaId: metaId, type: type, apiKey: apiKey) else {
            return nil
        }
        // Textless backdrops (`include_image_language=null`) keep the hero clean
        // for the logo/title overlay, matching how the reference renders its hero.
        guard let imagesURL = URL(string: "https://api.themoviedb.org/3/\(kind)/\(tmdbId)/images?api_key=\(apiKey)&include_image_language=null") else { return nil }
        let (imageData, _) = try await URLSession.shared.data(from: imagesURL)
        let images = try JSONDecoder().decode(TMDBImagesResponse.self, from: imageData)
        // Match TMDB's own "most popular" ordering: highest vote_count first,
        // with vote_average as the tiebreaker. Sorting purely by vote_average
        // let a single 5-star vote outrank the community favorite.
        guard let best = images.backdrops.max(by: {
            ($0.voteCount ?? 0, $0.voteAverage ?? 0) < ($1.voteCount ?? 0, $1.voteAverage ?? 0)
        }) else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w1280\(best.filePath)")
    }

    /// Resolves a `(kind, tmdbId)` pair from either a native `tmdb:movie:123` /
    /// `tmdb:tv:123` id (used directly, like the reference) or an IMDb `tt…` id (via the
    /// TMDB `find` endpoint).
    private static func resolveTMDBId(metaId: String, type: MediaType, apiKey: String) async throws -> (kind: String, id: Int)? {
        if metaId.hasPrefix("tmdb:") {
            let parts = metaId.split(separator: ":")
            if parts.count == 3, let id = Int(parts[2]) {
                let kind = parts[1] == "tv" ? "tv" : "movie"
                return (kind, id)
            }
            if parts.count == 2, let id = Int(parts[1]) {
                return (type == .movie ? "movie" : "tv", id)
            }
            return nil
        }

        let plainId = metaId.split(separator: ":").first.map(String.init) ?? metaId
        guard let findURL = URL(string: "https://api.themoviedb.org/3/find/\(plainId)?api_key=\(apiKey)&external_source=imdb_id") else { return nil }
        let (findData, _) = try await URLSession.shared.data(from: findURL)
        let find = try JSONDecoder().decode(TMDBFindResponse.self, from: findData)
        if type == .movie {
            guard let id = find.movieResults.first?.id else { return nil }
            return ("movie", id)
        } else {
            guard let id = find.tvResults.first?.id else { return nil }
            return ("tv", id)
        }
    }
}

private struct TMDBFindResponse: Decodable {
    let movieResults: [TMDBFindItem]
    let tvResults: [TMDBFindItem]

    enum CodingKeys: String, CodingKey {
        case movieResults = "movie_results"
        case tvResults = "tv_results"
    }
}

private struct TMDBFindItem: Decodable {
    let id: Int
}

private struct TMDBImagesResponse: Decodable {
    let posters: [TMDBImage]
    let backdrops: [TMDBImage]
}

private struct TMDBImage: Decodable {
    let filePath: String
    let voteAverage: Double?
    let voteCount: Int?

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
    }
}
