import Foundation

public final class CatalogService: @unchecked Sendable {
    public static let shared = CatalogService()
    private let client = StremioHTTPClient.shared

    private init() {}

    public struct StremioCatalogQuery: Sendable {
        public let type: String
        public let id: String
        public let baseURL: String
        public let extras: [String: String]

        public init(type: String, id: String, baseURL: String, extras: [String: String] = [:]) {
            self.type = type
            self.id = id
            self.baseURL = baseURL
            self.extras = extras
        }

        public func buildURL() -> String {
            if !extras.isEmpty {
                let extraParts = extras
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key.stremioPathEncoded)=\($0.value.stremioPathEncoded)" }
                    .joined(separator: "&")
                return "\(baseURL)/catalog/\(type)/\(id)/\(extraParts).json"
            }
            return "\(baseURL)/catalog/\(type)/\(id).json"
        }
    }

    public func fetchCatalog(query: StremioCatalogQuery) async throws -> [MetaPreview] {
        let url = query.buildURL()
        let addonBase = query.baseURL

        struct RawMeta: Codable {
            let id: String?
            let type: String?
            let name: String?
            let poster: String?
            let img: String?
            let image: String?
            let _rawPosterUrl: String?
            let background: String?
            let landscapePoster: String?
            let banner: String?
            let logo: String?
            let posterShape: String?
            let description: String?
            let releaseInfo: String?
            let releaseDate: String?
            let released: String?
            let runtime: String?
            let popularity: Double?
            let voteCount: Int?
            let imdbRating: String?
            let genres: [String]?
            let status: String?
            let behaviorHints: BehaviorHints?
            let trailerStreams: [RawStream]?
        }
        struct RawStream: Codable {
            let name: String?
            let title: String?
            let description: String?
            let url: String?
            let infoHash: String?
            let fileIdx: Int?
            let externalUrl: String?
            let ytId: String?
            let sources: [String]?
        }
        struct CatalogResponse: Codable {
            let metas: [RawMeta]?
        }

        func mapResponse(_ response: CatalogResponse) -> [MetaPreview] {
            (response.metas ?? []).map { raw in
                MetaPreview(
                    id: raw.id ?? "",
                    type: MediaType(rawValue: raw.type ?? "movie") ?? .movie,
                    name: raw.name ?? "Unknown",
                    // Prefer the btttr poster service for IMDb-id items; fall back to
                    // the addon-proxied poster, then the raw source URL.
                    poster: PosterService.posterURL(forImdbId: raw.id)
                        ?? resolveURL(raw.poster, base: addonBase)
                        ?? resolveURL(raw._rawPosterUrl, base: addonBase)
                        ?? resolveURL(raw.img, base: addonBase)
                        ?? resolveURL(raw.image, base: addonBase),
                    banner: resolveURL(raw.background, base: addonBase)
                        ?? resolveURL(raw.landscapePoster, base: addonBase)
                        ?? resolveURL(raw.banner, base: addonBase),
                    logo: resolveURL(raw.logo, base: addonBase),
                    posterShape: raw.posterShape.flatMap { PosterShape(rawValue: $0) },
                    description: raw.description,
                    releaseInfo: raw.releaseInfo,
                    rawReleaseDate: raw.releaseDate,
                    released: raw.released,
                    runtime: raw.runtime,
                    popularity: raw.popularity,
                    voteCount: raw.voteCount,
                    imdbRating: raw.imdbRating,
                    genres: raw.genres,
                    status: raw.status,
                    behaviorHints: raw.behaviorHints,
                    trailerStreams: raw.trailerStreams?.map {
                        StreamItem(
                            name: $0.name, title: $0.title, description: $0.description,
                            url: $0.url, infoHash: $0.infoHash, fileIdx: $0.fileIdx,
                            externalUrl: $0.externalUrl, ytId: $0.ytId, sources: $0.sources
                        )
                    }
                )
            }
        }

        if let cached = CatalogResponseCache.shared.get(key: url),
           let response = try? JSONDecoder().decode(CatalogResponse.self, from: cached) {
            return mapResponse(response)
        }

        do {
            let text = try await client.getText(url: url)
            if let data = text.data(using: .utf8) {
                CatalogResponseCache.shared.set(key: url, data: data)
                let response = try JSONDecoder().decode(CatalogResponse.self, from: data)
                return mapResponse(response)
            }
            throw StremioError.invalidResponse
        } catch {
            throw error
        }
    }

    private func resolveURL(_ path: String?, base: String) -> String? {
        guard let path = path, !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return path
        }
        let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return "\(trimmedBase)/\(trimmedPath)"
    }

    public func fetchCatalogPaginated(
        query: StremioCatalogQuery,
        skip: Int = 0
    ) async throws -> CatalogResponse {
        var extras = query.extras
        extras["skip"] = String(skip)

        let paginatedQuery = StremioCatalogQuery(
            type: query.type,
            id: query.id,
            baseURL: query.baseURL,
            extras: extras
        )

        let items = try await fetchCatalog(query: paginatedQuery)
        return CatalogResponse(items: items, hasMore: items.count >= 50, page: skip / 50)
    }

    public struct CatalogResponse {
        public let items: [MetaPreview]
        public let hasMore: Bool
        public let page: Int

        public init(items: [MetaPreview], hasMore: Bool, page: Int) {
            self.items = items
            self.hasMore = hasMore
            self.page = page
        }
    }
}

private extension String {
    private static let uriComponentAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return allowed
    }()

    var stremioPathEncoded: String {
        addingPercentEncoding(withAllowedCharacters: Self.uriComponentAllowed) ?? self
    }
}
