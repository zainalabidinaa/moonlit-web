import Foundation

/// Builds  curated rails for a genre's dedicated browse screen —
/// Trending, Top Rated, New, Hidden Gems, and a "companion" rail for the other
/// media kind (e.g. a "Trending Action Series" rail on the Action *movies*
/// screen) — each backed by its own `TMDB /discover` query.
///
/// TMDB discover results carry TMDB ids, but the rest of the app (playback,
/// watch progress, awards) is keyed by IMDb id, so every result's IMDb id is
/// resolved via `/external_ids` with bounded concurrency and cached to disk
/// forever (a title's IMDb id never changes). Results with no IMDb id (rare —
/// mostly obscure titles) are dropped since nothing in the app can act on them.
///
/// Returns no rails when no TMDB key is configured — callers should already
/// have an addon-catalog-driven fallback (see `CatalogRepository.loadGenreHub`).
@MainActor
public final class TMDBDiscoverService: ObservableObject {
    public static let shared = TMDBDiscoverService()

    private let base = "https://api.themoviedb.org/3"
    private var apiKey: String? { MetadataIntegrationStore.shared.effectiveTMDBAPIKey }

    /// "movie:12345" / "tv:12345" → imdb id (or "" for a confirmed miss).
    private var imdbIdCache: [String: String] = [:]
    private let resolveConcurrency = 6

    private let cacheURL: URL? = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return dir?.appendingPathComponent("moonlit-tmdb-imdb-map.json")
    }()

    private init() {
        if let url = cacheURL, let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            imdbIdCache = decoded
        }
    }

    public func discoverRails(genreName: String, mediaKind: MediaType) async -> [GenreCatalog.LoadedBrowseRail] {
        guard let key = apiKey, !key.isEmpty,
              let genreId = TMDBGenreIDs.id(for: genreName, mediaKind: mediaKind) else { return [] }

        let kind = mediaKind == .movie ? "movie" : "tv"

        async let trending = fetchItems(kind: kind, apiKey: key, params: [
            "with_genres": "\(genreId)", "sort_by": "popularity.desc", "vote_count.gte": "50",
        ])
        async let topRated = fetchItems(kind: kind, apiKey: key, params: [
            "with_genres": "\(genreId)", "sort_by": "vote_average.desc", "vote_count.gte": "400",
        ])
        async let recent = fetchItems(kind: kind, apiKey: key, params: [
            "with_genres": "\(genreId)", "sort_by": "primary_release_date.desc",
            "vote_count.gte": "10", "primary_release_date.lte": Self.today,
        ])
        async let hiddenGems = fetchItems(kind: kind, apiKey: key, params: [
            "with_genres": "\(genreId)", "sort_by": "vote_average.desc",
            "vote_count.gte": "50", "vote_count.lte": "300",
        ])

        let (trendingItems, topRatedItems, recentItems, hiddenGemItems) =
            await (trending, topRated, recent, hiddenGems)

        persistCache()

        var rails: [GenreCatalog.LoadedBrowseRail] = []
        if !trendingItems.isEmpty {
            rails.append(.init(id: "tmdb-trending", title: "Trending \(genreName)", items: trendingItems))
        }
        if !topRatedItems.isEmpty {
            rails.append(.init(id: "tmdb-top-rated", title: "Top Rated \(genreName)", items: topRatedItems))
        }
        if !recentItems.isEmpty {
            rails.append(.init(id: "tmdb-recent", title: "New \(genreName)", items: recentItems))
        }
        if !hiddenGemItems.isEmpty {
            rails.append(.init(id: "tmdb-hidden-gems", title: "Hidden Gems", items: hiddenGemItems))
        }
        return rails
    }

    /// Popular titles released in a single year, for the Search screen's
    /// "Movies by Year" grid. Returns [] with no TMDB key configured, which the
    /// caller renders as an empty year rather than an error.
    public func discoverByYear(year: Int, mediaKind: MediaType = .movie) async -> [MetaPreview] {
        guard let key = apiKey, !key.isEmpty else { return [] }
        let kind = mediaKind == .movie ? "movie" : "tv"
        let yearParam = mediaKind == .movie ? "primary_release_year" : "first_air_date_year"
        let items = await fetchItems(kind: kind, apiKey: key, params: [
            yearParam: "\(year)",
            "sort_by": "popularity.desc",
            "vote_count.gte": "20",
        ])
        persistCache()
        return items
    }

    /// Titles not yet released, soonest first — used as the paywall marquee's
    /// fallback when the viewing user has no library items yet.
    public func discoverUpcoming(mediaKind: MediaType) async -> [MetaPreview] {
        guard let key = apiKey, !key.isEmpty else { return [] }
        let kind = mediaKind == .movie ? "movie" : "tv"
        let params = UpcomingReleasesQuery.parameters(mediaKind: mediaKind, today: Self.today)
        let items = await fetchItems(kind: kind, apiKey: key, params: params)
        persistCache()
        return items
    }

    /// Fusion-style "More Like This": titles that share this title's genres, via a
    /// TMDB Discover query (the two most specific genres AND-joined so results stay
    /// on-topic — Breaking Bad → Crime + Drama, not just any Drama), ranked by how
    /// well-known they are. Excludes the source title. Returns [] with no TMDB key
    /// or no mappable genre.
    public func discoverSimilar(genres: [String], mediaKind: MediaType, excludingImdbId: String?) async -> [MetaPreview] {
        guard let key = apiKey, !key.isEmpty else { return [] }
        let genreIds = genres.compactMap { TMDBGenreIDs.id(for: $0, mediaKind: mediaKind) }
        guard !genreIds.isEmpty else { return [] }
        let kind = mediaKind == .movie ? "movie" : "tv"
        let genreParam = genreIds.prefix(2).map(String.init).joined(separator: ",")
        var items = await fetchItems(kind: kind, apiKey: key, params: [
            "with_genres": genreParam,
            "sort_by": "vote_count.desc",
            "vote_count.gte": mediaKind == .movie ? "300" : "150",
        ])
        persistCache()
        if let excludingImdbId { items.removeAll { $0.id == excludingImdbId } }
        return items
    }

    /// Default "All" browse rails for a media kind (no genre selected) — the
    /// Movies/Series tabs show these when no genre pill is active.
    public func discoverGeneral(mediaKind: MediaType) async -> [GenreCatalog.LoadedBrowseRail] {
        guard let key = apiKey, !key.isEmpty else { return [] }
        let kind = mediaKind == .movie ? "movie" : "tv"
        let dateField = mediaKind == .movie ? "primary_release_date" : "first_air_date"
        let noun = mediaKind == .movie ? "Movies" : "Series"

        async let popular = fetchItems(kind: kind, apiKey: key, params: [
            "sort_by": "popularity.desc", "vote_count.gte": "80",
        ])
        async let topRated = fetchItems(kind: kind, apiKey: key, params: [
            "sort_by": "vote_average.desc", "vote_count.gte": "800",
        ])
        async let recent = fetchItems(kind: kind, apiKey: key, params: [
            "sort_by": "\(dateField).desc", "vote_count.gte": "15",
            "\(dateField).lte": Self.today,
        ])
        async let hiddenGems = fetchItems(kind: kind, apiKey: key, params: [
            "sort_by": "vote_average.desc", "vote_count.gte": "20",
            "vote_count.lte": "150",
        ])
        async let trending = fetchItems(kind: kind, apiKey: key, params: [
            "sort_by": "popularity.desc", "vote_count.gte": "100",
        ])

        let (popularItems, topRatedItems, recentItems, hiddenGemItems, trendingItems) =
            await (popular, topRated, recent, hiddenGems, trending)
        persistCache()

        var rails: [GenreCatalog.LoadedBrowseRail] = []
        if !trendingItems.isEmpty { rails.append(.init(id: "gen-trending", title: "Trending \(noun)", items: trendingItems)) }
        if !popularItems.isEmpty { rails.append(.init(id: "gen-popular", title: "Popular \(noun)", items: popularItems)) }
        if !topRatedItems.isEmpty { rails.append(.init(id: "gen-top", title: "Top Rated \(noun)", items: topRatedItems)) }
        if !hiddenGemItems.isEmpty { rails.append(.init(id: "gen-hidden-gems", title: "Hidden Gems", items: hiddenGemItems)) }
        if !recentItems.isEmpty { rails.append(.init(id: "gen-new", title: "New Releases", items: recentItems)) }
        return rails
    }

    /// Hand-authored, keyword-driven "creative" rails per genre — Martial Arts for
    /// Action, Zombies for Horror, Mindfucks for Mystery, etc. Returns an empty
    /// array when the genre has no creative mapping or all queries return empty.
    public func discoverCreativeRails(genreName: String, mediaKind: MediaType) async -> [GenreCatalog.LoadedBrowseRail] {
        guard let key = apiKey, !key.isEmpty else { return [] }
        let specs = Self.creativeRailSpecs(for: genreName)
        guard !specs.isEmpty else { return [] }
        let kind = mediaKind == .movie ? "movie" : "tv"

        let results: [GenreCatalog.LoadedBrowseRail] = await withTaskGroup(of: GenreCatalog.LoadedBrowseRail?.self) { group in
            for spec in specs {
                group.addTask {
                    var params = spec.params
                    if params["sort_by"] == nil { params["sort_by"] = "popularity.desc" }
                    let items = await self.fetchItems(kind: kind, apiKey: key, params: params)
                    guard !items.isEmpty else { return nil }
                    return .init(id: "creative-\(spec.id)", title: spec.title, items: items)
                }
            }
            var out: [GenreCatalog.LoadedBrowseRail] = []
            for await rail in group {
                if let rail { out.append(rail) }
            }
            return out
        }
        persistCache()
        return results
    }

    private struct CreativeRailSpec { let id: String; let title: String; let params: [String: String] }

    /// Maps a genre to multiple signature themed rails via TMDB keyword/genre queries.
    /// Keyword ids are verified against TMDB's live keyword list.
    private static func creativeRailSpecs(for genre: String) -> [CreativeRailSpec] {
        switch GenreCatalog.normalize(genre) {
        case "action":
            return [
                .init(id: "martial-arts", title: "Martial Arts & Mayhem",
                      params: ["with_keywords": "779", "vote_count.gte": "40"]),
                .init(id: "blockbuster", title: "Blockbuster Action",
                      params: ["with_genres": "28", "vote_count.gte": "300", "sort_by": "revenue.desc"]),
                .init(id: "action-thriller", title: "Action Thrillers",
                      params: ["with_genres": "28,53", "vote_count.gte": "100"]),
            ]
        case "adventure":
            return [
                .init(id: "treasure", title: "Treasure Hunts",
                      params: ["with_keywords": "9882", "vote_count.gte": "30"]),
                .init(id: "survival", title: "Survival Against Nature",
                      params: ["with_keywords": "9717", "vote_count.gte": "40"]),
                .init(id: "historical", title: "Historical Adventures",
                      params: ["with_genres": "12,36", "vote_count.gte": "60"]),
            ]
        case "animation":
            return [
                .init(id: "anime", title: "Anime",
                      params: ["with_keywords": "210024", "vote_count.gte": "40"]),
                .init(id: "pixar-dw", title: "Pixar & DreamWorks Gems",
                      params: ["with_genres": "16,10751", "vote_average.gte": "7.2", "vote_count.gte": "200", "sort_by": "vote_average.desc"]),
                .init(id: "adult-animation", title: "Adult Animation",
                      params: ["with_genres": "16", "vote_count.gte": "80", "sort_by": "vote_average.desc",
                               "without_genres": "10751", "with_runtime.gte": "60"]),
            ]
        case "comedy":
            return [
                .init(id: "standup", title: "Stand-Up & Specials",
                      params: ["with_keywords": "9716"]),
                .init(id: "action-comedy", title: "Action Comedies",
                      params: ["with_genres": "28,35", "vote_count.gte": "100"]),
                .init(id: "satire", title: "Satire & Dark Humor",
                      params: ["with_genres": "35", "vote_count.gte": "80",
                               "sort_by": "vote_average.desc"]),
            ]
        case "crime":
            return [
                .init(id: "heists", title: "Heists & Capers",
                      params: ["with_keywords": "10051", "vote_count.gte": "40"]),
                .init(id: "noir", title: "Film Noir & Neo-Noir",
                      params: ["with_keywords": "10223", "vote_count.gte": "30"]),
                .init(id: "crime-thriller", title: "Crime Thrillers",
                      params: ["with_genres": "80,53", "vote_count.gte": "80",
                               "sort_by": "vote_average.desc"]),
            ]
        case "documentary":
            return [
                .init(id: "true-crime-doc", title: "True Crime Docs",
                      params: ["with_keywords": "12995", "vote_count.gte": "20"]),
                .init(id: "nature-doc", title: "Nature & Wildlife",
                      params: ["with_keywords": "1907", "vote_count.gte": "20"]),
                .init(id: "music-doc", title: "Music & Concert Films",
                      params: ["with_keywords": "1638", "vote_count.gte": "20"]),
            ]
        case "drama":
            return [
                .init(id: "true-story", title: "Based on a True Story",
                      params: ["with_keywords": "9672", "vote_count.gte": "100"]),
                .init(id: "coming-of-age", title: "Coming of Age",
                      params: ["with_keywords": "1909", "vote_count.gte": "60"]),
                .init(id: "biopic", title: "Biographical Dramas",
                      params: ["with_keywords": "1701", "vote_count.gte": "50",
                               "sort_by": "vote_average.desc"]),
            ]
        case "family":
            return [
                .init(id: "feelgood", title: "Feel-Good Family",
                      params: ["with_genres": "10751", "vote_count.gte": "50"]),
                .init(id: "family-animation", title: "Animated Family",
                      params: ["with_genres": "16,10751", "vote_average.gte": "7",
                               "vote_count.gte": "150", "sort_by": "vote_average.desc"]),
            ]
        case "fantasy":
            return [
                .init(id: "superheroes", title: "Superhero Sagas",
                      params: ["with_keywords": "9715", "vote_count.gte": "60"]),
                .init(id: "fairy-tales", title: "Fairy Tales Retold",
                      params: ["with_keywords": "3205", "vote_count.gte": "30"]),
                .init(id: "fantasy-adventure", title: "Fantasy Adventures",
                      params: ["with_genres": "14,12", "vote_count.gte": "100",
                               "sort_by": "vote_average.desc"]),
            ]
        case "history":
            return [
                .init(id: "biopics", title: "Biographical Epics",
                      params: ["with_keywords": "1701", "vote_count.gte": "50",
                               "sort_by": "vote_average.desc"]),
                .init(id: "wwii", title: "WWII Stories",
                      params: ["with_keywords": "1964", "vote_count.gte": "60"]),
                .init(id: "ancient", title: "Ancient Worlds",
                      params: ["with_genres": "36", "vote_count.gte": "50",
                               "sort_by": "vote_average.desc"]),
            ]
        case "horror":
            return [
                .init(id: "zombies", title: "Zombies & the Undead",
                      params: ["with_keywords": "12377", "vote_count.gte": "30"]),
                .init(id: "slasher", title: "Slashers",
                      params: ["with_keywords": "12338", "vote_count.gte": "30"]),
                .init(id: "haunted", title: "Haunted Houses",
                      params: ["with_keywords": "14796", "vote_count.gte": "20"]),
                .init(id: "found-footage", title: "Found Footage",
                      params: ["with_keywords": "10170", "vote_count.gte": "20"]),
            ]
        case "music":
            return [
                .init(id: "music-doc", title: "Music Documentaries",
                      params: ["with_keywords": "1638", "vote_count.gte": "20"]),
                .init(id: "music-drama", title: "Music Dramas",
                      params: ["with_genres": "18", "with_keywords": "1638",
                               "vote_count.gte": "40", "sort_by": "vote_average.desc"]),
            ]
        case "mystery":
            return [
                .init(id: "detective", title: "Detectives & Sleuths",
                      params: ["with_keywords": "4275", "vote_count.gte": "40"]),
                .init(id: "conspiracy", title: "Conspiracy Theories",
                      params: ["with_keywords": "13015", "vote_count.gte": "30"]),
                .init(id: "mystery-thriller", title: "Mindfucks & Twists",
                      params: ["with_genres": "9648,53", "vote_count.gte": "80",
                               "sort_by": "vote_average.desc"]),
            ]
        case "romance":
            return [
                .init(id: "romcoms", title: "Rom-Coms",
                      params: ["with_genres": "10749,35", "vote_count.gte": "60"]),
                .init(id: "drama-romance", title: "Romantic Dramas",
                      params: ["with_genres": "10749,18", "vote_count.gte": "80",
                               "sort_by": "vote_average.desc"]),
                .init(id: "forbidden-love", title: "Forbidden Love",
                      params: ["with_keywords": "9888", "vote_count.gte": "30"]),
            ]
        case "sci-fi":
            return [
                .init(id: "time-travel", title: "Time-Travel & Beyond",
                      params: ["with_keywords": "4379", "vote_count.gte": "40"]),
                .init(id: "aliens", title: "Alien Encounters",
                      params: ["with_keywords": "9951", "vote_count.gte": "40"]),
                .init(id: "cyberpunk", title: "Cyberpunk",
                      params: ["with_keywords": "4563", "vote_count.gte": "30"]),
                .init(id: "space-opera", title: "Space Operas",
                      params: ["with_keywords": "10014", "vote_count.gte": "50"]),
                .init(id: "ai", title: "Artificial Intelligence",
                      params: ["with_keywords": "4565", "vote_count.gte": "40"]),
            ]
        case "thriller":
            return [
                .init(id: "dystopia", title: "Dystopian Futures",
                      params: ["with_keywords": "4458", "vote_count.gte": "40"]),
                .init(id: "kidnapping", title: "Kidnapped",
                      params: ["with_keywords": "1879", "vote_count.gte": "30"]),
                .init(id: "serial-killer", title: "Serial Killers",
                      params: ["with_keywords": "197951", "vote_count.gte": "30"]),
                .init(id: "psycho", title: "Psychological Thrills",
                      params: ["with_genres": "53", "vote_count.gte": "100",
                               "sort_by": "vote_average.desc"]),
            ]
        case "war":
            return [
                .init(id: "wwii", title: "WWII Stories",
                      params: ["with_keywords": "1964", "vote_count.gte": "50"]),
                .init(id: "vietnam", title: "Vietnam War",
                      params: ["with_keywords": "2315", "vote_count.gte": "30"]),
                .init(id: "war-classics", title: "War Classics",
                      params: ["with_genres": "10752", "vote_count.gte": "100",
                               "sort_by": "vote_average.desc"]),
            ]
        case "western":
            return [
                .init(id: "gunslingers", title: "Gunslingers",
                      params: ["with_genres": "37", "vote_count.gte": "40"]),
                .init(id: "western-classics", title: "Western Classics",
                      params: ["with_genres": "37", "vote_count.gte": "60",
                               "sort_by": "vote_average.desc"]),
            ]
        default:
            return []
        }
    }

    /// Popular movies/series available on a given streaming service, used to
    /// augment the macOS streaming-service page beyond what's in the user's
    /// addon-catalog folders. Mirrors `discoverRails` structurally.
    public func discoverByProvider(serviceName: String, mediaKind: MediaType) async -> [GenreCatalog.LoadedBrowseRail] {
        guard let key = apiKey, !key.isEmpty,
              let providerId = TMDBProviderIDs.id(for: serviceName) else { return [] }

        let kind = mediaKind == .movie ? "movie" : "tv"
        let items = await fetchItems(kind: kind, apiKey: key, params: [
            "with_watch_providers": "\(providerId)", "watch_region": "US",
            "sort_by": "popularity.desc", "vote_count.gte": "20",
        ])
        persistCache()
        guard !items.isEmpty else { return [] }
        let title = mediaKind == .movie ? "Popular Movies" : "Popular Series"
        return [.init(id: "tmdb-provider-\(kind)", title: title, items: items)]
    }

    /// Season-labeled trailers for a TV show, e.g. "Season 2 Trailer" — the
    /// generic trailer addon used elsewhere has no season metadata, so this
    /// resolves the IMDb id to a TMDB id and pulls each season's own videos.
    public func seasonTrailers(imdbId: String, seasonNumbers: [Int]) async -> [TMDBSeasonTrailer] {
        guard let key = apiKey, !key.isEmpty, !seasonNumbers.isEmpty,
              let tmdbId = await resolveTmdbId(imdbId: imdbId, kind: "tv", apiKey: key) else { return [] }

        return await withTaskGroup(of: [TMDBSeasonTrailer].self) { group in
            for season in seasonNumbers {
                group.addTask { await self.fetchSeasonVideos(tmdbId: tmdbId, season: season, apiKey: key) }
            }
            var all: [TMDBSeasonTrailer] = []
            for await result in group { all.append(contentsOf: result) }
            return all.sorted { $0.season > $1.season }
        }
    }

    /// Real-thumbnail trailers for a movie — the generic addon trailer has no
    /// reliable thumbnail (only sometimes carries a YouTube id), so this pulls
    /// straight from TMDB's own `/movie/{id}/videos` the same way `seasonTrailers`
    /// does for shows.
    public func movieTrailers(imdbId: String) async -> [TMDBSeasonTrailer] {
        guard let key = apiKey, !key.isEmpty,
              let tmdbId = await resolveTmdbId(imdbId: imdbId, kind: "movie", apiKey: key) else { return [] }
        guard let url = URL(string: "\(base)/movie/\(tmdbId)/videos?api_key=\(key)") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(TMDBVideosResponse.self, from: data)
            return decoded.results
                .filter { $0.site == "YouTube" && ($0.type == "Trailer" || $0.type == "Teaser") }
                .map { TMDBSeasonTrailer(season: 0, name: $0.type, youtubeKey: $0.key) }
        } catch {
            return []
        }
    }

    private func resolveTmdbId(imdbId: String, kind: String, apiKey: String) async -> Int? {
        guard let url = URL(string: "\(base)/find/\(imdbId)?api_key=\(apiKey)&external_source=imdb_id") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(TMDBFindResponse.self, from: data)
            return kind == "tv" ? decoded.tvResults.first?.id : decoded.movieResults.first?.id
        } catch {
            return nil
        }
    }

    private func fetchSeasonVideos(tmdbId: Int, season: Int, apiKey: String) async -> [TMDBSeasonTrailer] {
        guard let url = URL(string: "\(base)/tv/\(tmdbId)/season/\(season)/videos?api_key=\(apiKey)") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(TMDBVideosResponse.self, from: data)
            return decoded.results
                .filter { $0.site == "YouTube" && ($0.type == "Trailer" || $0.type == "Teaser") }
                .map { TMDBSeasonTrailer(season: season, name: "Season \(season) \($0.type)", youtubeKey: $0.key) }
        } catch {
            return []
        }
    }

    private static var today: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func fetchItems(kind: String, apiKey: String, params: [String: String]) async -> [MetaPreview] {
        var components = URLComponents(string: "\(base)/discover/\(kind)")
        var queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
        queryItems.append(contentsOf: params.map { URLQueryItem(name: $0.key, value: $0.value) })
        components?.queryItems = queryItems
        guard let url = components?.url else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(TMDBDiscoverResponse.self, from: data)
            return await resolve(decoded.results.prefix(20).map { $0 }, kind: kind, apiKey: apiKey)
        } catch {
            return []
        }
    }

    /// Resolves TMDB ids to IMDb ids with `resolveConcurrency` in flight at a
    /// time, preserving TMDB's original (popularity/rating) ordering.
    private func resolve(_ items: [TMDBDiscoverItem], kind: String, apiKey: String) async -> [MetaPreview] {
        var results: [Int: MetaPreview] = [:]
        var index = 0
        while index < items.count {
            let chunk = items[index..<min(index + resolveConcurrency, items.count)]
            await withTaskGroup(of: (Int, MetaPreview?).self) { group in
                for (offset, item) in chunk.enumerated() {
                    let absoluteIndex = index + offset
                    group.addTask {
                        let imdbId = await self.resolveImdbId(tmdbId: item.id, kind: kind, apiKey: apiKey)
                        guard let imdbId else { return (absoluteIndex, nil) }
                        return (absoluteIndex, item.asMetaPreview(id: imdbId, kind: kind))
                    }
                }
                for await (idx, preview) in group {
                    if let preview { results[idx] = preview }
                }
            }
            index += resolveConcurrency
        }
        return results.keys.sorted().compactMap { results[$0] }
    }

    /// Shared with `TMDBSearchService` so both keep using the same persisted
    /// tmdbId→imdbId cache instead of duplicating the resolution logic.
    func resolveImdbId(tmdbId: Int, kind: String, apiKey: String) async -> String? {
        let cacheKey = "\(kind):\(tmdbId)"
        if let cached = imdbIdCache[cacheKey] { return cached.isEmpty ? nil : cached }
        guard let url = URL(string: "\(base)/\(kind)/\(tmdbId)/external_ids?api_key=\(apiKey)") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let decoded = try JSONDecoder().decode(TMDBExternalIdsResponse.self, from: data)
            guard let entry = Self.imdbCacheEntry(statusCode: statusCode, imdbId: decoded.imdbId) else { return nil }
            imdbIdCache[cacheKey] = entry
            return decoded.imdbId
        } catch {
            return nil
        }
    }

    /// The value to persist in the tmdbId→imdbId cache, or nil for "don't cache".
    /// Only a 200 counts as a confirmed answer — TMDB error bodies (429 rate
    /// limit, 401) decode as `imdbId: nil` and would otherwise be cached forever
    /// as a miss, permanently hiding the title from collection folders.
    nonisolated static func imdbCacheEntry(statusCode: Int, imdbId: String?) -> String? {
        guard statusCode == 200 else { return nil }
        return imdbId ?? ""
    }

    func persistCache() {
        guard let cacheURL, let data = try? JSONEncoder().encode(imdbIdCache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}

private struct TMDBDiscoverResponse: Decodable {
    let results: [TMDBDiscoverItem]
}

private struct TMDBDiscoverItem: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let posterPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let popularity: Double?
    let voteAverage: Double?
    let voteCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, name, popularity
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
    }

    func asMetaPreview(id: String, kind: String) -> MetaPreview {
        let tmdbPoster = posterPath.map { "https://image.tmdb.org/t/p/w500\($0)" }
        return MetaPreview(
            id: id,
            type: kind == "movie" ? .movie : .series,
            name: title ?? name ?? "Unknown",
            poster: PosterService.posterURL(forImdbId: id) ?? tmdbPoster,
            releaseInfo: (releaseDate ?? firstAirDate).flatMap { $0.split(separator: "-").first.map(String.init) },
            popularity: popularity,
            voteCount: voteCount,
            imdbRating: voteAverage.map { String(format: "%.1f", $0) }
        )
    }
}

private struct TMDBExternalIdsResponse: Decodable {
    let imdbId: String?
    enum CodingKeys: String, CodingKey { case imdbId = "imdb_id" }
}

public struct TMDBSeasonTrailer: Sendable, Identifiable {
    public let id = UUID()
    public let season: Int
    public let name: String
    public let youtubeKey: String

    public var youtubeWatchURL: URL? { URL(string: "https://www.youtube.com/watch?v=\(youtubeKey)") }
}

private struct TMDBFindResponse: Decodable {
    let movieResults: [TMDBFindItem]
    let tvResults: [TMDBFindItem]
    enum CodingKeys: String, CodingKey {
        case movieResults = "movie_results"
        case tvResults = "tv_results"
    }
}

private struct TMDBFindItem: Decodable { let id: Int }

private struct TMDBVideosResponse: Decodable { let results: [TMDBVideoItem] }

private struct TMDBVideoItem: Decodable {
    let key: String
    let site: String
    let type: String
}
