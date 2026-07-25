import Foundation

public struct EpisodeStillKey: Hashable, Sendable {
    public let season: Int
    public let episode: Int

    public init(season: Int, episode: Int) {
        self.season = season
        self.episode = episode
    }
}

@MainActor
public class MetaRepository: ObservableObject {
    public static let shared = MetaRepository()

    @Published public var detail: MetaDetail?
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var isShowingStaleDetail = false
    @Published public var cachedDetailUpdatedAt: Date?

    private let metaService = MetaService.shared
    private let integrationStore = MetadataIntegrationStore.shared
    private var cachedTVDBToken: String?
    private var cachedTVDBKey: String?
    private let cacheDefaults = UserDefaults.standard

    private init() {}

    public func fetchDetail(type: String, id: String, addons: [AddonManifest]) async -> MetaDetail? {
        for addon in addons {
            guard addon.canHandleMeta(type: type, id: id),
                  let baseURL = addon.transportUrl,
                  let detail = try? await metaService.fetchMeta(type: type, id: id, baseURL: baseURL) else {
                continue
            }
            return await enrichWithMetadataProviders(detail: detail)
        }
        return nil
    }

    public func loadDetail(type: String, id: String, addons: [AddonManifest]) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard NetworkMonitor.shared.isConnected else {
            if restoreCachedDetail(type: type, id: id) {
                errorMessage = nil
            } else {
                errorMessage = "No internet connection"
            }
            return
        }

        detail = nil
        isShowingStaleDetail = false
        cachedDetailUpdatedAt = nil
        var lastError: Error?

        for addon in addons {
            guard addon.canHandleMeta(type: type, id: id),
                  let baseURL = addon.transportUrl else { continue }

            do {
                let detail = try await metaService.fetchMeta(type: type, id: id, baseURL: baseURL)
                let enriched = await enrichWithMetadataProviders(detail: detail)
                self.detail = enriched
                self.isShowingStaleDetail = false
                self.cachedDetailUpdatedAt = nil
                cacheDetail(enriched, type: type, id: id)
                return
            } catch {
                lastError = error
                print("[Moonlit] Meta fetch failed: addon=\(addon.name) type=\(type) id=\(id) baseURL=\(baseURL) error=\(error)")
                continue
            }
        }

        if addons.isEmpty {
            errorMessage = "No metadata addons are enabled"
        } else if restoreCachedDetail(type: type, id: id) {
            errorMessage = nil
        } else if let lastError {
            let friendlyMessage: String
            if let stremioError = lastError as? StremioError {
                friendlyMessage = stremioError.localizedDescription
            } else if lastError is URLError {
                friendlyMessage = "Check your internet connection and try again"
            } else {
                friendlyMessage = "Addon unavailable (\(lastError.localizedDescription))"
            }
            errorMessage = "Could not load details from any addon (\(friendlyMessage))"
        } else {
            errorMessage = "Could not load details from any addon"
        }
    }

    private struct CachedMetaDetail: Codable {
        let detail: MetaDetail
        let updatedAt: Date
    }

    private func cacheKey(type: String, id: String) -> String {
        "moonlit.cachedMetaDetail.\(type).\(id)"
    }

    private func cacheDetail(_ detail: MetaDetail, type: String, id: String) {
        let cached = CachedMetaDetail(detail: detail, updatedAt: Date())
        if let data = try? JSONEncoder().encode(cached) {
            cacheDefaults.set(data, forKey: cacheKey(type: type, id: id))
        }
    }

    @discardableResult
    private func restoreCachedDetail(type: String, id: String) -> Bool {
        guard let data = cacheDefaults.data(forKey: cacheKey(type: type, id: id)),
              let cached = try? JSONDecoder().decode(CachedMetaDetail.self, from: data) else {
            return false
        }
        detail = cached.detail
        isShowingStaleDetail = true
        cachedDetailUpdatedAt = cached.updatedAt
        return true
    }

    private func enrichWithMetadataProviders(detail: MetaDetail) async -> MetaDetail {
        var enriched = detail

        let idParts = detail.id.split(separator: ":").map(String.init)
        var tmdbId: String?
        if idParts.count >= 2, idParts[0] == "tmdb" {
            tmdbId = idParts[1]
        } else if detail.id.hasPrefix("tt") {
            tmdbId = await findTMDBId(forIMDBId: detail.id)
        }

        if let tmdbId {
            enriched = await fetchTMDBDetails(tmdbId: tmdbId, type: detail.type.rawValue, detail: enriched)
        }

        if detail.type == .series {
            let seasons = enriched.seasons ?? []
            let hasEpisodes = seasons.contains { $0.episodes?.isEmpty == false }
            if hasEpisodes {
                let tvdbStills = await fetchTVDBEpisodeStills(imdbId: detail.id, detail: enriched)
                var tmdbStills: [EpisodeStillKey: String] = [:]
                var tmdbRatings: [EpisodeStillKey: Double] = [:]
                if let tmdbId {
                    (tmdbStills, tmdbRatings) = await fetchTMDBEpisodeStills(tmdbId: tmdbId, detail: enriched)
                }
                enriched = Self.mergeEpisodeStills(
                    into: enriched,
                    tvdbStills: tvdbStills,
                    tmdbStills: tmdbStills,
                    tmdbRatings: tmdbRatings
                )
            }
        }

        return enriched
    }

    private func findTMDBId(forIMDBId imdbId: String) async -> String? {
        guard let tmdbApiKey = integrationStore.effectiveTMDBAPIKey else {
            NSLog("[Moonlit][TMDB] no API key configured, skipping enrichment for %@", imdbId)
            return nil
        }
        let url = "https://api.themoviedb.org/3/find/\(imdbId)?api_key=\(tmdbApiKey)&external_source=imdb_id"
        guard let apiURL = URL(string: url) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: apiURL)
            struct FindResponse: Codable {
                let tv_results: [TMDBResult]?
                let movie_results: [TMDBResult]?
            }
            struct TMDBResult: Codable { let id: Int }
            let response = try JSONDecoder().decode(FindResponse.self, from: data)
            let tvId = response.tv_results?.first?.id
            let movieId = response.movie_results?.first?.id
            if let id = tvId ?? movieId {
                let kind = tvId != nil ? "tv" : "movie"
                NSLog("[Moonlit][TMDB] resolved %@ → tmdb:%@ (%@)", imdbId, String(id), kind)
                return String(id)
            }
            NSLog("[Moonlit][TMDB] no results for %@ — tv=%ld movie=%ld", imdbId, response.tv_results?.count ?? 0, response.movie_results?.count ?? 0)
        } catch {
            NSLog("[Moonlit][TMDB] request failed for %@: %@", imdbId, error.localizedDescription)
        }
        return nil
    }

    private struct TMDBEpisodeData {
        let stillPath: String?
        let voteAverage: Double?
    }

    private func fetchTMDBSeasonEpisodeStills(tmdbId: String, seasonNumber: Int) async -> [Int: TMDBEpisodeData] {
        guard let tmdbApiKey = integrationStore.effectiveTMDBAPIKey else {
            NSLog("[Moonlit][TMDB] no API key — skipping season %ld stills for tmdb:%@", seasonNumber, tmdbId)
            return [:]
        }
        let url = "https://api.themoviedb.org/3/tv/\(tmdbId)/season/\(seasonNumber)?api_key=\(tmdbApiKey)"
        guard let apiURL = URL(string: url) else { return [:] }
        do {
            let (data, _) = try await URLSession.shared.data(from: apiURL)
            struct SeasonResponse: Codable { let episodes: [TMDBEpisode]? }
            struct TMDBEpisode: Codable {
                let episode_number: Int
                let still_path: String?
                let vote_average: Double?
            }
            let response = try JSONDecoder().decode(SeasonResponse.self, from: data)
            var episodes: [Int: TMDBEpisodeData] = [:]
            for ep in response.episodes ?? [] {
                let still = ep.still_path.map { "https://image.tmdb.org/t/p/w400\($0)" }
                let rating = (ep.vote_average ?? 0) > 0 ? ep.vote_average : nil
                episodes[ep.episode_number] = TMDBEpisodeData(stillPath: still, voteAverage: rating)
            }
            return episodes
        } catch {
            NSLog("[Moonlit][TMDB] season %ld stills fetch failed for tmdb:%@: %@", seasonNumber, tmdbId, error.localizedDescription)
            return [:]
        }
    }

    /// Full credits for a single episode: the cast (main cast followed by guest
    /// stars, with the guest ids called out) plus the episode's own director(s)
    /// and writer(s) parsed from the TMDB `crew` array.
    public struct EpisodeCredits: Sendable {
        public let cast: [Person]
        public let guestStarIDs: Set<String>
        public let directors: [String]
        public let writers: [String]

        public static let empty = EpisodeCredits(cast: [], guestStarIDs: [], directors: [], writers: [])
    }

    /// Fetches the cast + guest stars for a single episode, lazily — used by the
    /// episode info panel, not called during the normal detail/stills enrichment
    /// pass (which would mean one extra TMDB request per episode on every load).
    public func fetchEpisodeGuestStars(seriesId: String, season: Int, episode: Int) async -> [Person] {
        await fetchEpisodeCredits(seriesId: seriesId, season: season, episode: episode).cast
    }

    /// Like `fetchEpisodeGuestStars`, but also surfaces which people are guest
    /// stars and the episode's own director(s)/writer(s) from the `crew` array.
    public func fetchEpisodeCredits(seriesId: String, season: Int, episode: Int) async -> EpisodeCredits {
        guard let tmdbApiKey = integrationStore.effectiveTMDBAPIKey else {
            NSLog("[Moonlit][TMDB] no API key — skipping episode credits for %@ S%ldE%ld", seriesId, season, episode)
            return .empty
        }

        let tmdbId: String
        if seriesId.hasPrefix("tmdb:") {
            tmdbId = String(seriesId.dropFirst("tmdb:".count))
        } else if let resolved = await findTMDBId(forIMDBId: seriesId) {
            tmdbId = resolved
        } else {
            return .empty
        }

        let url = "https://api.themoviedb.org/3/tv/\(tmdbId)/season/\(season)/episode/\(episode)/credits?api_key=\(tmdbApiKey)"
        guard let apiURL = URL(string: url) else { return .empty }
        do {
            let (data, _) = try await URLSession.shared.data(from: apiURL)
            struct TMDBEpisodeCast: Codable {
                let id: Int
                let name: String
                let character: String?
                let profile_path: String?
            }
            struct TMDBEpisodeCrew: Codable {
                let name: String
                let job: String?
                let department: String?
            }
            struct CreditsResponse: Codable {
                let cast: [TMDBEpisodeCast]?
                let guest_stars: [TMDBEpisodeCast]?
                let crew: [TMDBEpisodeCrew]?
            }
            let response = try JSONDecoder().decode(CreditsResponse.self, from: data)

            func person(_ member: TMDBEpisodeCast) -> Person {
                Person(
                    id: String(member.id),
                    name: member.name,
                    photo: member.profile_path.map { "https://image.tmdb.org/t/p/w185\($0)" },
                    character: member.character
                )
            }
            let castMembers = (response.cast ?? []).map(person)
            let guestMembers = (response.guest_stars ?? []).map(person)

            let crew = response.crew ?? []
            func dedup(_ names: [String]) -> [String] {
                var seen = Set<String>(), out: [String] = []
                for name in names where !name.isEmpty && seen.insert(name).inserted { out.append(name) }
                return out
            }
            let directors = dedup(crew.filter { $0.job == "Director" }.map(\.name))
            let writers = dedup(crew.filter { $0.job == "Writer" || $0.department == "Writing" }.map(\.name))

            return EpisodeCredits(
                cast: castMembers + guestMembers,
                guestStarIDs: Set(guestMembers.map(\.id)),
                directors: directors,
                writers: writers
            )
        } catch {
            NSLog("[Moonlit][TMDB] episode credits fetch failed for tmdb:%@ S%ldE%ld: %@", tmdbId, season, episode, error.localizedDescription)
            return .empty
        }
    }

    /// Fetches the high-res episode poster (still_path at original size) from
    /// TMDB — used by the episode info panel to show a sharp hero backdrop.
    public func fetchEpisodePoster(seriesId: String, season: Int, episode: Int) async -> String? {
        guard let tmdbApiKey = integrationStore.effectiveTMDBAPIKey else { return nil }

        let tmdbId: String
        if seriesId.hasPrefix("tmdb:") {
            tmdbId = String(seriesId.dropFirst("tmdb:".count))
        } else if let resolved = await findTMDBId(forIMDBId: seriesId) {
            tmdbId = resolved
        } else {
            return nil
        }

        let url = "https://api.themoviedb.org/3/tv/\(tmdbId)/season/\(season)/episode/\(episode)?api_key=\(tmdbApiKey)&append_to_response=images"
        guard let apiURL = URL(string: url) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: apiURL)
            struct EpisodeResponse: Codable { let still_path: String? }
            let response = try JSONDecoder().decode(EpisodeResponse.self, from: data)
            return response.still_path.map { "https://image.tmdb.org/t/p/original\($0)" }
        } catch {
            NSLog("[Moonlit][TMDB] episode poster fetch failed for tmdb:%@ S%ldE%ld: %@", tmdbId, season, episode, error.localizedDescription)
            return nil
        }
    }

    private func fetchTMDBEpisodeStills(
        tmdbId: String, detail: MetaDetail
    ) async -> (stills: [EpisodeStillKey: String], ratings: [EpisodeStillKey: Double]) {
        guard let seasons = detail.seasons, !seasons.isEmpty else {
            NSLog("[Moonlit][TMDB] episode stills skipped for tmdb:%@ — no seasons on detail", tmdbId)
            return ([:], [:])
        }

        // Fetch every season concurrently — a sequential loop meant a show with many
        // seasons (or one slow TMDB response) could stall stills for every episode.
        var allStills: [EpisodeStillKey: String] = [:]
        var allRatings: [EpisodeStillKey: Double] = [:]
        await withTaskGroup(of: (Int, [Int: TMDBEpisodeData]).self) { group in
            for season in seasons {
                group.addTask {
                    (season.number, await self.fetchTMDBSeasonEpisodeStills(tmdbId: tmdbId, seasonNumber: season.number))
                }
            }
            for await (seasonNumber, episodes) in group {
                for (episode, data) in episodes {
                    let key = EpisodeStillKey(season: seasonNumber, episode: episode)
                    if let still = data.stillPath { allStills[key] = still }
                    if let rating = data.voteAverage { allRatings[key] = rating }
                }
            }
        }
        NSLog("[Moonlit][TMDB] episode stills resolved %ld for tmdb:%@ across %ld season(s)", allStills.count, tmdbId, seasons.count)
        return (allStills, allRatings)
    }

    private func fetchTVDBEpisodeStills(imdbId: String, detail: MetaDetail) async -> [EpisodeStillKey: String] {
        guard detail.type == .series,
              imdbId.hasPrefix("tt"),
              let apiKey = integrationStore.effectiveTVDBAPIKey,
              let token = await tvdbToken(apiKey: apiKey),
              let seriesId = await findTVDBSeriesId(forIMDBId: imdbId, token: token),
              let seasons = detail.seasons else {
            return [:]
        }

        var allStills: [EpisodeStillKey: String] = [:]
        await withTaskGroup(of: [EpisodeStillKey: String].self) { group in
            for season in seasons {
                group.addTask {
                    await self.fetchTVDBSeasonEpisodeStills(seriesId: seriesId, seasonNumber: season.number, token: token)
                }
            }
            for await stills in group {
                allStills.merge(stills) { current, _ in current }
            }
        }
        return allStills
    }

    private func tvdbToken(apiKey: String) async -> String? {
        if cachedTVDBKey == apiKey, let cachedTVDBToken {
            return cachedTVDBToken
        }

        guard let url = URL(string: "https://api4.thetvdb.com/v4/login") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(TVDBLoginRequest(apikey: apiKey))

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(TVDBLoginResponse.self, from: data)
            cachedTVDBKey = apiKey
            cachedTVDBToken = response.data.token
            return response.data.token
        } catch {
            return nil
        }
    }

    private func findTVDBSeriesId(forIMDBId imdbId: String, token: String) async -> Int? {
        guard let url = URL(string: "https://api4.thetvdb.com/v4/search/remoteid/\(imdbId)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(TVDBRemoteIDResponse.self, from: data)
            return response.data.compactMap(\.series?.id).first
        } catch {
            return nil
        }
    }

    private func fetchTVDBSeasonEpisodeStills(seriesId: Int, seasonNumber: Int, token: String) async -> [EpisodeStillKey: String] {
        var components = URLComponents(string: "https://api4.thetvdb.com/v4/series/\(seriesId)/episodes/default")
        components?.queryItems = [
            URLQueryItem(name: "page", value: "0"),
            URLQueryItem(name: "season", value: String(seasonNumber))
        ]
        guard let url = components?.url else { return [:] }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(TVDBEpisodesResponse.self, from: data)
            var stills: [EpisodeStillKey: String] = [:]
            for episode in response.data.episodes {
                guard let image = episode.image?.nilIfBlank else { continue }
                stills[EpisodeStillKey(
                    season: episode.seasonNumber ?? seasonNumber,
                    episode: episode.number
                )] = image
            }
            return stills
        } catch {
            return [:]
        }
    }

    nonisolated public static func mergeEpisodeStills(
        into detail: MetaDetail,
        tvdbStills: [EpisodeStillKey: String],
        tmdbStills: [EpisodeStillKey: String],
        tmdbRatings: [EpisodeStillKey: Double] = [:]
    ) -> MetaDetail {
        guard let seasons = detail.seasons, !seasons.isEmpty else { return detail }

        let updatedSeasons = seasons.map { season -> Season in
            guard let episodes = season.episodes else { return season }
            let updatedEpisodes = episodes.map { episode -> MetaVideo in
                guard let episodeNumber = episode.episode else {
                    return episode
                }
                let key = EpisodeStillKey(season: season.number, episode: episodeNumber)
                let still = tvdbStills[key] ?? tmdbStills[key] ?? episode.thumbnail
                return MetaVideo(
                    id: episode.id, title: episode.title, released: episode.released, thumbnail: still,
                    season: episode.season, episode: episode.episode, overview: episode.overview,
                    runtime: episode.runtime, streams: episode.streams, trailerStreams: episode.trailerStreams,
                    voteAverage: tmdbRatings[key] ?? episode.voteAverage
                )
            }
            return Season(
                id: season.id, number: season.number, name: season.name,
                poster: season.poster, episodes: updatedEpisodes
            )
        }

        return MetaDetail(
            id: detail.id, type: detail.type, name: detail.name,
            poster: detail.poster, rawPosterUrl: detail.rawPosterUrl, background: detail.background,
            logo: detail.logo, description: detail.description,
            releaseInfo: detail.releaseInfo, status: detail.status,
            imdbRating: detail.imdbRating, ageRating: detail.ageRating,
            runtime: detail.runtime, genres: detail.genres,
            director: detail.director, writer: detail.writer, cast: detail.cast,
            trailers: detail.trailers, trailerStreams: detail.trailerStreams,
            videos: detail.videos, seasons: updatedSeasons,
            links: detail.links, moreLikeThis: detail.moreLikeThis,
            collectionItems: detail.collectionItems,
            recommendations: detail.recommendations,
            creators: detail.creators, producers: detail.producers,
            cinematographers: detail.cinematographers, composers: detail.composers, editors: detail.editors,
            backdropGallery: detail.backdropGallery, posterGallery: detail.posterGallery, logoGallery: detail.logoGallery,
            firstAirDate: detail.firstAirDate, lastAirDate: detail.lastAirDate,
            networks: detail.networks, studios: detail.studios, countries: detail.countries,
            originalLanguage: detail.originalLanguage, voteCount: detail.voteCount,
            tagline: detail.tagline, budget: detail.budget, revenue: detail.revenue,
            videoClips: detail.videoClips
        )
    }

    // MARK: - Crew job → category mapping

    private static let writerJobs: Set<String> = [
        "Writer", "Screenplay", "Story", "Teleplay", "Author", "Novel", "Original Story", "Original Series Creator"
    ]
    private static let producerJobs: Set<String> = ["Producer", "Executive Producer"]
    private static let cinematographyJobs: Set<String> = ["Director of Photography", "Cinematography"]
    private static let musicJobs: Set<String> = ["Original Music Composer", "Music"]

    private static func dedupedByName(_ people: [Person]) -> [Person] {
        var seen = Set<String>()
        return people.filter { seen.insert($0.name).inserted }
    }

    private func fetchTMDBDetails(tmdbId: String, type: String, detail: MetaDetail) async -> MetaDetail {
        guard let tmdbApiKey = integrationStore.effectiveTMDBAPIKey else { return detail }
        let mediaType = type == "series" ? "tv" : "movie"
        let url = "https://api.themoviedb.org/3/\(mediaType)/\(tmdbId)?api_key=\(tmdbApiKey)&append_to_response=credits,videos,similar,recommendations,images&include_image_language=null,en"
        guard let apiURL = URL(string: url) else { return detail }

        struct TMDBListPage: Codable { let results: [TMDBListItem]? }
        struct TMDBCompany: Codable { let name: String }
        struct TMDBLanguage: Codable { let english_name: String? }
        struct TMDBCreator: Codable { let id: Int; let name: String; let profile_path: String? }
        struct TMDBImageEntry: Codable { let file_path: String }
        struct TMDBImages: Codable {
            let backdrops: [TMDBImageEntry]?
            let posters: [TMDBImageEntry]?
            let logos: [TMDBImageEntry]?
        }
        struct TMDBVideoEntry: Codable {
            let id: String
            let name: String
            let type: String
            let site: String
            let key: String
        }
        struct TMDBVideos: Codable { let results: [TMDBVideoEntry]? }
        struct TMDBResponse: Codable {
            let poster_path: String?
            let backdrop_path: String?
            let vote_average: Double?
            let vote_count: Int?
            let overview: String?
            let status: String?
            let genres: [TMDBGenre]?
            let credits: TMDBCredits?
            let similar: TMDBListPage?
            let recommendations: TMDBListPage?
            let images: TMDBImages?
            let videos: TMDBVideos?
            let first_air_date: String?
            let last_air_date: String?
            let release_date: String?
            let networks: [TMDBCompany]?
            let production_companies: [TMDBCompany]?
            let production_countries: [TMDBCompany]?
            let spoken_languages: [TMDBLanguage]?
            let created_by: [TMDBCreator]?
            let original_language: String?
            let tagline: String?
            let budget: Int?
            let revenue: Int?
        }
        struct TMDBGenre: Codable { let name: String }
        struct TMDBCredits: Codable { let cast: [TMDBCast]?; let crew: [TMDBCrewMember]? }
        struct TMDBCast: Codable {
            let id: Int
            let name: String
            let profile_path: String?
            let character: String?
        }
        struct TMDBCrewMember: Codable {
            let id: Int
            let name: String
            let job: String
            let profile_path: String?
        }

        let tmdb: TMDBResponse
        do {
            let (data, _) = try await URLSession.shared.data(from: apiURL)
            tmdb = try JSONDecoder().decode(TMDBResponse.self, from: data)
        } catch {
            NSLog("[Moonlit][TMDB] detail fetch failed for %@:%@: %@", mediaType, tmdbId, error.localizedDescription)
            return detail
        }

        func person(_ id: Int, _ name: String, _ profilePath: String?, _ character: String? = nil) -> Person {
            Person(id: String(id), name: name, photo: TMDBPersonService.shared.imageURL(path: profilePath, size: "w185")?.absoluteString, character: character)
        }

        let coherentRating: String? = {
            if let avg = tmdb.vote_average, tmdb.vote_count != nil {
                return String(format: "%.1f", avg)
            }
            return nil
        }()

        let crew = tmdb.credits?.crew ?? []
        let directors = detail.director ?? {
            let people = crew.filter { $0.job == "Director" }.map { person($0.id, $0.name, $0.profile_path) }
            return Self.dedupedByName(people)
        }()
        let writers = detail.writer ?? {
            let people = crew.filter { Self.writerJobs.contains($0.job) }.map { person($0.id, $0.name, $0.profile_path) }
            return Self.dedupedByName(people)
        }()
        let producers = Self.dedupedByName(
            crew.filter { Self.producerJobs.contains($0.job) }.map { person($0.id, $0.name, $0.profile_path) }
        )
        let cinematographers = Self.dedupedByName(
            crew.filter { Self.cinematographyJobs.contains($0.job) }.map { person($0.id, $0.name, $0.profile_path) }
        )
        let composers = Self.dedupedByName(
            crew.filter { Self.musicJobs.contains($0.job) }.map { person($0.id, $0.name, $0.profile_path) }
        )
        let editors = Self.dedupedByName(
            crew.filter { $0.job == "Editor" }.map { person($0.id, $0.name, $0.profile_path) }
        )
        let creators = Self.dedupedByName(
            (tmdb.created_by ?? []).map { person($0.id, $0.name, $0.profile_path) }
        )

        async let resolvedSimilar = resolveToIMDbPreviews(tmdb.similar?.results ?? [], mediaType: mediaType, apiKey: tmdbApiKey)
        async let resolvedRecommendations = resolveToIMDbPreviews(tmdb.recommendations?.results ?? [], mediaType: mediaType, apiKey: tmdbApiKey)
        let similarResolved = await resolvedSimilar
        let recommendationsResolved = await resolvedRecommendations

        return MetaDetail(
            id: detail.id, type: detail.type, name: detail.name,
            poster: detail.poster ?? tmdb.poster_path.map { "https://image.tmdb.org/t/p/w780\($0)" },
            rawPosterUrl: detail.rawPosterUrl,
            background: detail.background ?? tmdb.backdrop_path.map { "https://image.tmdb.org/t/p/w1280\($0)" },
            logo: detail.logo,
            description: tmdb.overview ?? detail.description,
            releaseInfo: detail.releaseInfo,
            status: detail.status ?? tmdb.status,
            imdbRating: coherentRating ?? detail.imdbRating ?? tmdb.vote_average.map { String(format: "%.1f", $0) },
            ageRating: detail.ageRating, runtime: detail.runtime,
            genres: detail.genres ?? tmdb.genres?.map { $0.name },
            director: directors, writer: writers,
            cast: tmdb.credits?.cast?.map { person($0.id, $0.name, $0.profile_path, $0.character) } ?? detail.cast,
            trailers: detail.trailers, trailerStreams: detail.trailerStreams,
            videos: detail.videos, seasons: detail.seasons,
            links: detail.links,
            moreLikeThis: (similarResolved.isEmpty ? nil : similarResolved) ?? detail.moreLikeThis,
            collectionItems: detail.collectionItems,
            recommendations: recommendationsResolved.isEmpty ? nil : recommendationsResolved,
            creators: creators.isEmpty ? nil : creators,
            producers: producers.isEmpty ? nil : producers,
            cinematographers: cinematographers.isEmpty ? nil : cinematographers,
            composers: composers.isEmpty ? nil : composers,
            editors: editors.isEmpty ? nil : editors,
            backdropGallery: tmdb.images?.backdrops?.prefix(24).map { "https://image.tmdb.org/t/p/w780\($0.file_path)" },
            posterGallery: tmdb.images?.posters?.prefix(24).map { "https://image.tmdb.org/t/p/w342\($0.file_path)" },
            logoGallery: tmdb.images?.logos?.prefix(12).map { "https://image.tmdb.org/t/p/w500\($0.file_path)" },
            firstAirDate: tmdb.first_air_date ?? tmdb.release_date,
            lastAirDate: tmdb.last_air_date,
            networks: tmdb.networks?.map(\.name),
            studios: tmdb.production_companies?.map(\.name),
            countries: tmdb.production_countries?.map(\.name),
            originalLanguage: tmdb.original_language.flatMap { Locale.current.localizedString(forLanguageCode: $0) }
                ?? detail.originalLanguage,
            voteCount: tmdb.vote_count,
            tagline: detail.tagline ?? tmdb.tagline,
            budget: tmdb.budget.flatMap { $0 > 0 ? $0 : nil },
            revenue: tmdb.revenue.flatMap { $0 > 0 ? $0 : nil },
            videoClips: tmdb.videos?.results?
                .filter { $0.site == "YouTube" }
                .map { TMDBVideoClip(id: $0.id, name: $0.name, type: $0.type, youtubeKey: $0.key) }
        )
    }

    /// Resolves TMDB list items (similar/recommendations) to real IMDb ids so
    /// stream lookups and everything downstream (awards, watch progress) keep
    /// working off the app's IMDb-id-centric model.
    private func resolveToIMDbPreviews(
        _ items: [TMDBListItem], mediaType: String, apiKey: String
    ) async -> [MetaPreview] {
        guard !items.isEmpty else { return [] }
        let resolvedType: MediaType = mediaType == "tv" ? .series : .movie
        return await withTaskGroup(of: MetaPreview?.self) { group in
            for item in items.prefix(20) {
                group.addTask {
                    let extURL = "https://api.themoviedb.org/3/\(mediaType)/\(item.id)/external_ids?api_key=\(apiKey)"
                    guard let url = URL(string: extURL),
                          let (extData, _) = try? await URLSession.shared.data(from: url),
                          let json = try? JSONSerialization.jsonObject(with: extData) as? [String: Any],
                          let imdbId = json["imdb_id"] as? String,
                          imdbId.hasPrefix("tt") else { return nil }
                    return MetaPreview(
                        id: imdbId,
                        type: resolvedType,
                        name: item.title ?? item.name ?? "",
                        poster: item.poster_path.map { "https://image.tmdb.org/t/p/w500\($0)" },
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

private struct TMDBListItem: Codable {
    let id: Int
    let title: String?
    let name: String?
    let poster_path: String?
    let vote_average: Double?
}

private struct TVDBLoginRequest: Encodable {
    let apikey: String
}

private struct TVDBLoginResponse: Decodable {
    struct DataPayload: Decodable {
        let token: String
    }

    let data: DataPayload
}

private struct TVDBRemoteIDResponse: Decodable {
    struct Result: Decodable {
        struct Series: Decodable {
            let id: Int
        }

        let series: Series?
    }

    let data: [Result]
}

private struct TVDBEpisodesResponse: Decodable {
    struct DataPayload: Decodable {
        let episodes: [Episode]
    }

    struct Episode: Decodable {
        let image: String?
        let number: Int
        let seasonNumber: Int?
    }

    let data: DataPayload
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
