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

    func heroArtURL(for item: MetaPreview) -> URL? {
        if let url = urls[item.id] { return url }
        return item.artworkURL(preferring: .landscape)
    }

    func prefetch(items: [MetaPreview]) {
        for item in items {
            resolve(item: item)
        }
    }

    private func resolve(item: MetaPreview) {
        let id = item.id
        guard urls[id] == nil, !inFlight.contains(id), !misses.contains(id),
              let key = apiKey, !key.isEmpty,
              id.hasPrefix("tt") else { return }

        inFlight.insert(id)
        Task {
            defer { inFlight.remove(id) }
            do {
                if let url = try await Self.textlessPosterURL(imdbId: id, type: item.type, apiKey: key) {
                    urls[id] = url
                } else {
                    misses.insert(id)
                }
            } catch {
                misses.insert(id)
            }
        }
    }

    private static func textlessPosterURL(imdbId: String, type: MediaType, apiKey: String) async throws -> URL? {
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
        let (imageData, _) = try await URLSession.shared.data(from: imagesURL)
        let images = try JSONDecoder().decode(TMDBImagesResponse.self, from: imageData)
        let candidates = images.backdrops.isEmpty ? images.posters : images.backdrops
        guard let best = candidates.max(by: { ($0.voteAverage ?? 0) < ($1.voteAverage ?? 0) }) else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/original\(best.filePath)")
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
