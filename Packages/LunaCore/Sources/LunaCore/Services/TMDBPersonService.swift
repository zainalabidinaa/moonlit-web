import Foundation

@MainActor
public final class TMDBPersonService {
    public static let shared = TMDBPersonService()

    private let base = "https://api.themoviedb.org/3"
    private var apiKey: String? { MetadataIntegrationStore.shared.effectiveTMDBAPIKey }

    private var detailCache: [Int: PersonDetails] = [:]
    private var nameToId: [String: Int] = [:]

    private init() {}

    public func personDetails(id: Int) async throws -> PersonDetails {
        if let cached = detailCache[id] { return cached }
        guard let key = apiKey, !key.isEmpty else { throw TMDBPersonError.noAPIKey }
        let urlString = "\(base)/person/\(id)?api_key=\(key)&append_to_response=combined_credits,images"
        guard let url = URL(string: urlString) else { throw TMDBPersonError.badURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        let raw = try JSONDecoder().decode(TMDBPersonResponse.self, from: data)
        let person = mapToPerson(raw)
        detailCache[id] = person
        return person
    }

    public func personId(forName name: String) async throws -> Int? {
        if let cached = nameToId[name] { return cached }
        guard let key = apiKey, !key.isEmpty else { return nil }
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        guard let url = URL(string: "\(base)/search/person?api_key=\(key)&query=\(encoded)") else { return nil }
        let (data, _) = try await URLSession.shared.data(from: url)
        let result = try JSONDecoder().decode(TMDBPersonSearchResponse.self, from: data)
        let id = result.results.first?.id
        if let id { nameToId[name] = id }
        return id
    }

    public func backdrop(for credit: PersonCredit) async -> String? {
        guard let key = apiKey, !key.isEmpty else { return credit.posterPath }
        let path = credit.mediaType == "movie"
            ? "\(base)/movie/\(credit.id)?api_key=\(key)"
            : "\(base)/tv/\(credit.id)?api_key=\(key)"
        guard let url = URL(string: path) else { return credit.posterPath }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONDecoder().decode(TMDBMediaBackdropResponse.self, from: data)
            return json.backdropPath ?? credit.posterPath
        } catch { return credit.posterPath }
    }

    public func imageURL(path: String?, size: String = "w185") -> URL? {
        guard let path else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }

    public func clearCache() { detailCache.removeAll(); nameToId.removeAll() }

    private func mapToPerson(_ raw: TMDBPersonResponse) -> PersonDetails {
        let cast = (raw.combinedCredits?.cast ?? []).map { mapCredit($0, mediaType: $0.mediaType ?? "movie") }
        let crew = (raw.combinedCredits?.crew ?? []).map { mapCredit($0, mediaType: $0.mediaType ?? "movie") }
        var profiles = (raw.images?.profiles ?? []).map(\.filePath)
        if profiles.isEmpty, let main = raw.profilePath { profiles = [main] }
        return PersonDetails(id: raw.id, name: raw.name, biography: raw.biography ?? "",
                             birthday: raw.birthday, placeOfBirth: raw.placeOfBirth,
                             alsoKnownAs: raw.alsoKnownAs ?? [], profilePath: raw.profilePath,
                             profileImages: profiles,
                             knownForDepartment: raw.knownForDepartment,
                             imdbId: raw.imdbId, credits: PersonCredits(cast: cast, crew: crew))
    }

    private func mapCredit(_ raw: TMDBCreditResponse, mediaType: String) -> PersonCredit {
        PersonCredit(id: raw.id, title: raw.title ?? raw.name ?? "Unknown", mediaType: mediaType,
                     character: raw.character, job: raw.job,
                     releaseDate: raw.releaseDate ?? raw.firstAirDate,
                     posterPath: raw.posterPath, backdropPath: nil,
                     voteAverage: raw.voteAverage, voteCount: raw.voteCount,
                     episodeCount: raw.episodeCount, popularity: raw.popularity)
    }
}

public enum TMDBPersonError: Error {
    case noAPIKey
    case badURL
    case notFound
}

private struct TMDBPersonResponse: Decodable {
    let id: Int
    let name: String
    let biography: String?
    let birthday: String?
    let placeOfBirth: String?
    let alsoKnownAs: [String]?
    let profilePath: String?
    let knownForDepartment: String?
    let imdbId: String?
    let combinedCredits: TMDBCombinedCredits?
    let images: TMDBPersonImages?
    enum CodingKeys: String, CodingKey {
        case id, name, biography, birthday, images
        case placeOfBirth = "place_of_birth"
        case alsoKnownAs = "also_known_as"
        case profilePath = "profile_path"
        case knownForDepartment = "known_for_department"
        case imdbId = "imdb_id"
        case combinedCredits = "combined_credits"
    }
}

private struct TMDBPersonImages: Decodable {
    let profiles: [TMDBProfileImage]?
}

private struct TMDBProfileImage: Decodable {
    let filePath: String
    enum CodingKeys: String, CodingKey { case filePath = "file_path" }
}

private struct TMDBCombinedCredits: Decodable {
    let cast: [TMDBCreditResponse]?
    let crew: [TMDBCreditResponse]?
}

private struct TMDBCreditResponse: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let character: String?
    let job: String?
    let mediaType: String?
    let releaseDate: String?
    let firstAirDate: String?
    let posterPath: String?
    let voteAverage: Double?
    let voteCount: Int?
    let episodeCount: Int?
    let popularity: Double?
    enum CodingKeys: String, CodingKey {
        case id, title, name, character, job, popularity
        case mediaType = "media_type"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case episodeCount = "episode_count"
    }
}

private struct TMDBPersonSearchResponse: Decodable {
    let results: [TMDBPersonSearchResult]
}

private struct TMDBPersonSearchResult: Decodable { let id: Int }

private struct TMDBMediaBackdropResponse: Decodable {
    let backdropPath: String?
    enum CodingKeys: String, CodingKey { case backdropPath = "backdrop_path" }
}
