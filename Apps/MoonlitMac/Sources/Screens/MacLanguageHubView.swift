import SwiftUI
import MoonlitCore

struct MacLanguageHubView: View {
    let iso: String
    let name: String
    let onBack: () -> Void
    let onSelectMedia: (MetaPreview) -> Void

    @StateObject private var addonRepo = AddonRepository.shared
    @State private var featuredTVRails: [GenreCatalog.LoadedBrowseRail] = []
    @State private var featuredMovieRails: [GenreCatalog.LoadedBrowseRail] = []
    @State private var tvRails: [GenreCatalog.LoadedBrowseRail] = []
    @State private var movieRails: [GenreCatalog.LoadedBrowseRail] = []
    @State private var isLoading = true

    var body: some View {
        ZStack(alignment: .top) {
            MacFusionAmbientBackground(
                ambientColor: .clear,
                ambientColor2: .clear,
                isEnabled: true
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 56) {
                    header

                    if featuredTVRails.isEmpty && featuredMovieRails.isEmpty && tvRails.isEmpty && movieRails.isEmpty && !isLoading {
                        emptyState
                    }

                    if !featuredTVRails.isEmpty || !featuredMovieRails.isEmpty {
                        sectionHeader("Featured")
                        ForEach(featuredTVRails + featuredMovieRails) { rail in
                            railView(rail: rail)
                        }
                    }

                    if !tvRails.isEmpty {
                        sectionHeader("Series")
                        ForEach(tvRails) { rail in
                            railView(rail: rail)
                        }
                    }

                    if !movieRails.isEmpty {
                        sectionHeader("Movies")
                        ForEach(movieRails) { rail in
                            railView(rail: rail)
                        }
                    }

                    Spacer().frame(height: 48)
                }
            }
            .ignoresSafeArea(.container, edges: .top)
            .task {
                guard isLoading else { return }
                await loadRails()
            }

            if isLoading && featuredTVRails.isEmpty && featuredMovieRails.isEmpty && tvRails.isEmpty && movieRails.isEmpty {
                MacLoadingView(size: 44)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(MoonlitTheme.background)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 21, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 32)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LANGUAGE")
                .font(.system(size: 13, weight: .bold))
                .tracking(6)
                .foregroundColor(.white.opacity(0.42))
                .padding(.horizontal, 32)
            Text(name)
                .font(.system(size: 60, weight: .bold, design: .serif))
                .foregroundColor(.white)
                .padding(.horizontal, 32)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.3))
            Text("No content found for \(name)")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func railView(rail: GenreCatalog.LoadedBrowseRail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(rail.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 32)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(rail.items) { item in
                        Button { onSelectMedia(item) } label: {
                            PosterCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Rail definitions

    private enum RailFilter {
        case language(String)
        case country(String)
    }

    private struct RailDef {
        let title: String
        let kind: String
        let filter: RailFilter
        let params: [String: String]
    }

    private static let arabPool = "EG,LB,SY,SA,AE,KW,QA,JO,IQ,MA,DZ,TN,YE,SD,BH,OM,PS"

    private static let generalRailDefs: [RailDef] = [
        .init(title: "Popular",     kind: "both", filter: .language(""), params: ["sort_by": "popularity.desc", "vote_count.gte": "30"]),
        .init(title: "Top Rated",   kind: "both", filter: .language(""), params: ["sort_by": "vote_average.desc", "vote_count.gte": "50"]),
        .init(title: "New Releases", kind: "both", filter: .language(""), params: ["sort_by": "primary_release_date.desc", "vote_count.gte": "5"]),
        .init(title: "Hidden Gems", kind: "both", filter: .language(""), params: ["sort_by": "vote_average.desc", "vote_count.gte": "15", "vote_count.lte": "300", "vote_average.gte": "7.0"]),
        .init(title: "Classics",    kind: "both", filter: .language(""), params: ["sort_by": "vote_average.desc", "vote_count.gte": "20", "vote_average.gte": "7.0", "release_date.lte": "2000-12-31"]),
    ]

    private var effectiveGeneralDefs: [RailDef] {
        if iso == "ar" {
            return [
                .init(title: "Popular",     kind: "both", filter: .language(""), params: ["sort_by": "popularity.desc", "vote_count.gte": "15"]),
                .init(title: "Top Rated",   kind: "both", filter: .language(""), params: ["sort_by": "vote_average.desc", "vote_count.gte": "30"]),
                .init(title: "New Releases", kind: "both", filter: .language(""), params: ["sort_by": "primary_release_date.desc", "vote_count.gte": "3"]),
                .init(title: "Hidden Gems", kind: "both", filter: .language(""), params: ["sort_by": "vote_average.desc", "vote_count.gte": "10", "vote_count.lte": "300", "vote_average.gte": "6.5"]),
                .init(title: "Classics",    kind: "both", filter: .language(""), params: ["sort_by": "vote_average.desc", "vote_count.gte": "10", "vote_average.gte": "6.5", "release_date.lte": "2000-12-31"]),
            ]
        }
        return Self.generalRailDefs
    }

    private static let languageSpecificDefs: [String: [RailDef]] = [
        "ko": [
            .init(title: "K-Drama",           kind: "tv",    filter: .language(""), params: ["with_genres": "18", "sort_by": "popularity.desc", "vote_count.gte": "30"]),
            .init(title: "Korean Horror",     kind: "movie", filter: .language(""), params: ["with_genres": "27", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Korean Action",     kind: "movie", filter: .language(""), params: ["with_genres": "28", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Korean Thriller",   kind: "movie", filter: .language(""), params: ["with_genres": "53", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Korean Romance",    kind: "movie", filter: .language(""), params: ["with_genres": "10749", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Korean Comedy",     kind: "movie", filter: .language(""), params: ["with_genres": "35", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
        ],
        "ja": [
            .init(title: "Anime",            kind: "tv",    filter: .language(""), params: ["with_genres": "16", "sort_by": "popularity.desc", "vote_count.gte": "50"]),
            .init(title: "Japanese Horror",  kind: "movie", filter: .language(""), params: ["with_genres": "27", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Japanese Crime",   kind: "movie", filter: .language(""), params: ["with_genres": "80", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Japanese Sci-Fi",  kind: "movie", filter: .language(""), params: ["with_genres": "878", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Japanese Drama",   kind: "tv",    filter: .language(""), params: ["with_genres": "18", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
        ],
        "hi": [
            .init(title: "Indian Drama",     kind: "movie", filter: .language(""), params: ["with_genres": "18", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Indian Romance",   kind: "movie", filter: .language(""), params: ["with_genres": "10749", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Indian Action",    kind: "movie", filter: .language(""), params: ["with_genres": "28", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Indian Comedy",    kind: "movie", filter: .language(""), params: ["with_genres": "35", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Indian Thriller",  kind: "movie", filter: .language(""), params: ["with_genres": "53", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
        ],
        "fr": [
            .init(title: "French Thriller",  kind: "movie", filter: .language(""), params: ["with_genres": "53", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "French Comedy",    kind: "movie", filter: .language(""), params: ["with_genres": "35", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "French Drama",     kind: "movie", filter: .language(""), params: ["with_genres": "18", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
        ],
        "es": [
            .init(title: "Spanish Thriller", kind: "movie", filter: .language(""), params: ["with_genres": "53", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Spanish Horror",   kind: "movie", filter: .language(""), params: ["with_genres": "27", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Spanish Comedy",   kind: "movie", filter: .language(""), params: ["with_genres": "35", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
        ],
        "ar": [
            .init(title: "Egyptian Cinema",           kind: "movie", filter: .country("EG"), params: ["sort_by": "popularity.desc", "vote_count.gte": "10"]),
            .init(title: "Levant Drama",              kind: "tv",    filter: .country("LB,SY,JO,PS"), params: ["sort_by": "popularity.desc"]),
            .init(title: "Gulf Cinema",               kind: "movie", filter: .country("SA,AE,KW,QA,OM,BH"), params: ["sort_by": "popularity.desc"]),
            .init(title: "Iraqi Cinema",              kind: "movie", filter: .country("IQ"), params: ["sort_by": "popularity.desc"]),
            .init(title: "Maghreb Cinema",            kind: "movie", filter: .country("MA,DZ,TN"), params: ["sort_by": "popularity.desc"]),
            .init(title: "Sudanese & Yemeni Cinema",  kind: "movie", filter: .country("SD,YE"), params: ["sort_by": "popularity.desc"]),
            .init(title: "Ramadan Series",            kind: "tv",    filter: .country(arabPool), params: ["sort_by": "popularity.desc"]),
            .init(title: "Arab Classics",             kind: "movie", filter: .language(""), params: ["sort_by": "vote_average.desc", "vote_count.gte": "10", "vote_average.gte": "6.5", "release_date.lte": "2000-12-31"]),
            .init(title: "Arab Comedy",               kind: "movie", filter: .language(""), params: ["with_genres": "35", "sort_by": "popularity.desc", "vote_count.gte": "10"]),
            .init(title: "Arab Thrillers",            kind: "movie", filter: .language(""), params: ["with_genres": "53", "sort_by": "popularity.desc", "vote_count.gte": "10"]),
            .init(title: "Religious & Historical",    kind: "movie", filter: .language(""), params: ["with_genres": "36", "sort_by": "popularity.desc", "vote_count.gte": "10"]),
        ],
        "de": [
            .init(title: "German Thriller",  kind: "movie", filter: .language(""), params: ["with_genres": "53", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "German Crime",     kind: "movie", filter: .language(""), params: ["with_genres": "80", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "German Drama",     kind: "movie", filter: .language(""), params: ["with_genres": "18", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
        ],
        "it": [
            .init(title: "Italian Drama",    kind: "movie", filter: .language(""), params: ["with_genres": "18", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Italian Comedy",   kind: "movie", filter: .language(""), params: ["with_genres": "35", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Italian Crime",    kind: "movie", filter: .language(""), params: ["with_genres": "80", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
        ],
        "pt": [
            .init(title: "Brazilian Cinema", kind: "movie", filter: .language(""), params: ["with_genres": "18", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Brazilian Comedy", kind: "movie", filter: .language(""), params: ["with_genres": "35", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
        ],
        "tr": [
            .init(title: "Turkish Drama",    kind: "tv",    filter: .language(""), params: ["with_genres": "18", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Turkish Romance",  kind: "tv",    filter: .language(""), params: ["with_genres": "10749", "sort_by": "popularity.desc", "vote_count.gte": "10"]),
            .init(title: "Turkish Action",   kind: "movie", filter: .language(""), params: ["with_genres": "28", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
        ],
        "sv": [
            .init(title: "Nordic Noir",      kind: "tv",    filter: .country("SE,NO,DK,FI,IS"), params: ["with_genres": "80,53", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Nordic Crime",     kind: "movie", filter: .country("SE,NO,DK,FI,IS"), params: ["with_genres": "80", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Nordic Drama",     kind: "tv",    filter: .country("SE,NO,DK,FI,IS"), params: ["with_genres": "18", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
        ],
        "ru": [
            .init(title: "Russian Sci-Fi",   kind: "movie", filter: .language(""), params: ["with_genres": "878", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Russian Drama",    kind: "movie", filter: .language(""), params: ["with_genres": "18", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Russian War",      kind: "movie", filter: .language(""), params: ["with_genres": "10752", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
        ],
        "pl": [
            .init(title: "Polish Drama",     kind: "movie", filter: .language(""), params: ["with_genres": "18", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Polish Thriller",  kind: "movie", filter: .language(""), params: ["with_genres": "53", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Polish Crime",     kind: "movie", filter: .language(""), params: ["with_genres": "80", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
        ],
        "th": [
            .init(title: "Thai Horror",      kind: "movie", filter: .language(""), params: ["with_genres": "27", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Thai Drama",       kind: "tv",    filter: .language(""), params: ["with_genres": "18", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Thai Action",      kind: "movie", filter: .language(""), params: ["with_genres": "28", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
        ],
        "nl": [
            .init(title: "Dutch Drama",      kind: "movie", filter: .language(""), params: ["with_genres": "18", "sort_by": "popularity.desc", "vote_count.gte": "20"]),
            .init(title: "Dutch Documentary", kind: "movie", filter: .language(""), params: ["with_genres": "99", "sort_by": "popularity.desc", "vote_count.gte": "10"]),
        ],
    ]

    // MARK: - Loading

    private func loadRails() async {
        guard let key = MetadataIntegrationStore.shared.effectiveTMDBAPIKey, !key.isEmpty else {
            isLoading = false
            return
        }

        let generalDefs = effectiveGeneralDefs
        let specificDefs = Self.languageSpecificDefs[iso] ?? []

        let tvDefs = generalDefs.filter { $0.kind == "both" || $0.kind == "tv" }
        let movieDefs = generalDefs.filter { $0.kind == "both" || $0.kind == "movie" }
        let featuredTVDefs = specificDefs.filter { $0.kind == "tv" }
        let featuredMovieDefs = specificDefs.filter { $0.kind == "movie" }

        async let tvResults = fetchRails(kind: "tv", apiKey: key, defs: tvDefs)
        async let movieResults = fetchRails(kind: "movie", apiKey: key, defs: movieDefs)
        async let featuredTVResults = fetchRails(kind: "tv", apiKey: key, defs: featuredTVDefs)
        async let featuredMovieResults = fetchRails(kind: "movie", apiKey: key, defs: featuredMovieDefs)

        let (tv, mov, featuredTV, featuredMovies) = await (tvResults, movieResults, featuredTVResults, featuredMovieResults)
        tvRails = tv
        movieRails = mov
        featuredTVRails = featuredTV
        featuredMovieRails = featuredMovies
        isLoading = false
    }

    private func fetchRails(kind: String, apiKey: String, defs: [RailDef]) async -> [GenreCatalog.LoadedBrowseRail] {
        // Fire every rail definition's request at once instead of awaiting them
        // one at a time — this loop was the main cause of slow hub loads.
        let indexed = await withTaskGroup(of: (Int, GenreCatalog.LoadedBrowseRail?).self) { group in
            for (index, def) in defs.enumerated() {
                var params = def.params
                switch def.filter {
                case .language:
                    params["with_original_language"] = iso
                case .country(let codes):
                    params["with_origin_country"] = codes
                }
                group.addTask {
                    let items = await Self.fetchItems(kind: kind, apiKey: apiKey, params: params)
                    guard !items.isEmpty else { return (index, nil) }
                    let id = "lang-\(kind)-\(def.title.replacingOccurrences(of: " ", with: "-").lowercased())"
                    return (index, GenreCatalog.LoadedBrowseRail(id: id, title: def.title, items: items))
                }
            }
            var collected: [(Int, GenreCatalog.LoadedBrowseRail?)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }
        return indexed.sorted { $0.0 < $1.0 }.compactMap { $0.1 }
    }

    // `static` so `fetchRails` can call these from inside a `withTaskGroup`
    // closure without capturing `self` — MacLanguageHubView is a non-Sendable
    // View struct, and neither function touches instance state.
    private static func fetchItems(kind: String, apiKey: String, params: [String: String]) async -> [MetaPreview] {
        let base = "https://api.themoviedb.org/3"
        var components = URLComponents(string: "\(base)/discover/\(kind)")
        var queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
        queryItems.append(contentsOf: params.map { URLQueryItem(name: $0.key, value: $0.value) })
        components?.queryItems = queryItems
        guard let url = components?.url else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(LanguageDiscoverResponse.self, from: data)
            return await resolveImdbIds(decoded.results.prefix(20).map { $0 }, kind: kind, apiKey: apiKey)
        } catch {
            return []
        }
    }

    private static func resolveImdbIds(_ items: [LanguageDiscoverItem], kind: String, apiKey: String) async -> [MetaPreview] {
        return await withTaskGroup(of: MetaPreview?.self) { group in
            for item in items.prefix(20) {
                group.addTask {
                    let base = "https://api.themoviedb.org/3"
                    guard let url = URL(string: "\(base)/\(kind)/\(item.id)/external_ids?api_key=\(apiKey)"),
                          let (data, _) = try? await URLSession.shared.data(from: url),
                          let decoded = try? JSONDecoder().decode(TMDBExternalIds.self, from: data),
                          let imdbId = decoded.imdbId else { return nil }
                    return item.asMetaPreview(id: imdbId, kind: kind)
                }
            }
            var results: [MetaPreview] = []
            for await preview in group {
                if let preview { results.append(preview) }
            }
            return results
        }
    }
}

private struct LanguageDiscoverResponse: Decodable {
    let results: [LanguageDiscoverItem]
}

private struct LanguageDiscoverItem: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let popularity: Double?
    let voteAverage: Double?
    let voteCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, name, popularity
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
    }

    func asMetaPreview(id: String, kind: String) -> MetaPreview {
        let tmdbPoster = backdropPath.map { "https://image.tmdb.org/t/p/w500\($0)" }
            ?? posterPath.map { "https://image.tmdb.org/t/p/w500\($0)" }
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

private struct TMDBExternalIds: Decodable {
    let imdbId: String?
    enum CodingKeys: String, CodingKey { case imdbId = "imdb_id" }
}
