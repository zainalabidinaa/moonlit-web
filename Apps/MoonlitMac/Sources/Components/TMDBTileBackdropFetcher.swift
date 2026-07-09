import Foundation
import MoonlitCore

enum TMDBTileBackdropFetcher {
    private static let base = "https://api.themoviedb.org/3"
    private static let imageBase = "https://image.tmdb.org/t/p/w780"

    static func fetchGenreBackdrops(genre name: String) async -> [URL] {
        guard let key = await MetadataIntegrationStore.shared.effectiveTMDBAPIKey, !key.isEmpty,
              let genreId = TMDBGenreIDs.id(for: name, mediaKind: .movie) else { return [] }

        return await fetchBackdrops(
            kind: "movie",
            apiKey: key,
            params: [
                "with_genres": "\(genreId)",
                "sort_by": "popularity.desc",
                "vote_count.gte": "50",
            ]
        )
    }

    static func fetchLanguageBackdrops(language iso: String) async -> [URL] {
        guard let key = await MetadataIntegrationStore.shared.effectiveTMDBAPIKey, !key.isEmpty else { return [] }

        return await fetchBackdrops(
            kind: "tv",
            apiKey: key,
            params: [
                "with_original_language": iso,
                "sort_by": "popularity.desc",
                "vote_count.gte": "150",
            ]
        )
    }

    private static func fetchBackdrops(kind: String, apiKey: String, params: [String: String]) async -> [URL] {
        var components = URLComponents(string: "\(base)/discover/\(kind)")
        var queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
        queryItems.append(contentsOf: params.map { URLQueryItem(name: $0.key, value: $0.value) })
        components?.queryItems = queryItems
        guard let url = components?.url else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(TileBackdropResponse.self, from: data)
            return decoded.results
                .prefix(3)
                .compactMap { $0.backdropPath ?? $0.posterPath }
                .map { URL(string: "\(imageBase)\($0)") }
                .compactMap { $0 }
        } catch {
            return []
        }
    }
}

private struct TileBackdropResponse: Decodable {
    let results: [TileBackdropItem]
}

private struct TileBackdropItem: Decodable {
    let posterPath: String?
    let backdropPath: String?

    enum CodingKeys: String, CodingKey {
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
    }
}
