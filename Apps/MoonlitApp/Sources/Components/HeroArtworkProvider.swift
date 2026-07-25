import Foundation
import MoonlitCore

/// Resolves textless (language-neutral) TMDB portrait posters for hero items,
/// so the overlaid title logo isn't duplicated by text baked into the art.
/// Falls back to the addon-provided poster when no TMDB key or no match.
///
/// iOS hero art is always portrait (raw poster) — only macOS and web use
/// landscape/backdrop art in their hero treatments.
@MainActor
final class HeroArtworkProvider: ObservableObject {
    static let shared = HeroArtworkProvider()

    /// Resolved TMDB `file_path` per item id (size-agnostic). Rendered through the
    /// `TMDBPosterURL` ladder so a failed size can step down.
    @Published private(set) var posterPaths: [String: String] = [:]

    private var inFlight: Set<String> = []
    private var misses: Set<String> = []
    private var apiKey: String? { MetadataIntegrationStore.shared.effectiveTMDBAPIKey }

    private init() {}

    /// Best single hero art URL for the item: the highest resolved textless-TMDB
    /// poster size, or nil if none is resolved yet. Ambient/color consumers supply
    /// their own fallback for the nil case.
    func heroArtURL(for item: MetaPreview) -> URL? {
        heroArtCandidates(for: item).first
    }

    /// Ordered hero art URLs, best first: the textless TMDB size ladder
    /// (`w780 → w500 → w342`) once resolved, otherwise empty. The addon (btttr)
    /// portrait poster is intentionally NOT used here — it bakes in title text that
    /// clashes with the overlaid logo, so the hero shows its placeholder until the
    /// clean textless poster resolves and then fades it in.
    func heroArtCandidates(for item: MetaPreview) -> [URL] {
        if let path = posterPaths[item.id] {
            return TMDBPosterURL.candidates(filePath: path)
        }
        return []
    }

    func prefetch(items: [MetaPreview]) {
        for item in items { resolve(item: item) }
    }

    private func resolve(item: MetaPreview) {
        let id = item.id
        guard posterPaths[id] == nil, !inFlight.contains(id), !misses.contains(id),
              let key = apiKey, !key.isEmpty,
              id.hasPrefix("tt") else { return }
        inFlight.insert(id)
        Task {
            defer { inFlight.remove(id) }
            do {
                if let path = try await Self.textlessPosterPath(imdbId: id, type: item.type, apiKey: key) {
                    posterPaths[id] = path
                } else {
                    misses.insert(id)
                }
            } catch {
                misses.insert(id)
            }
        }
    }

    /// Resolves the highest-`vote_average` language-neutral (textless) TMDB poster
    /// `file_path`. Posters only — a landscape backdrop would crop wrong in the
    /// portrait hero — so an absent textless poster yields the addon fallback.
    private static func textlessPosterPath(imdbId: String, type: MediaType, apiKey: String) async throws -> String? {
        // The id may be an episode id like "tt123:1:2" — use the series part.
        let plainId = imdbId.split(separator: ":").first.map(String.init) ?? imdbId
        guard let findURL = URL(string: "https://api.themoviedb.org/3/find/\(plainId)?api_key=\(apiKey)&external_source=imdb_id") else { return nil }
        let (findData, _) = try await URLSession.shared.data(from: findURL)
        let find = try JSONDecoder().decode(TMDBFindResponse.self, from: findData)

        let tmdbId: Int?
        let kind: String
        if type == .movie {
            tmdbId = find.movieResults.first?.id
            kind = "movie"
        } else {
            tmdbId = find.tvResults.first?.id
            kind = "tv"
        }
        guard let tmdbId else { return nil }

        guard let imagesURL = URL(string: "https://api.themoviedb.org/3/\(kind)/\(tmdbId)/images?api_key=\(apiKey)&include_image_language=null") else { return nil }
        let (imgData, _) = try await URLSession.shared.data(from: imagesURL)
        let images = try JSONDecoder().decode(TMDBImagesResponse.self, from: imgData)
        guard let best = images.posters.max(by: { ($0.voteAverage ?? 0) < ($1.voteAverage ?? 0) }) else { return nil }
        return best.filePath
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

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case voteAverage = "vote_average"
    }
}
