import SwiftUI
import MoonlitCore

struct SearchScreen: View {
    @StateObject private var searchRepo = SearchRepository.shared
    @StateObject private var addonRepo = AddonRepository.shared
    @StateObject private var tmdbSearch = TMDBSearchService.shared
    @StateObject private var recentSearches = RecentSearchesStore.shared
    @State private var query = ""
    @State private var selectedMedia: MetaPreview?
    @State private var selectedPerson: PersonSearchResult?
    @StateObject private var catalogRepo = CatalogRepository.shared
    @StateObject private var collectionRepo = CollectionRepository.shared
    @State private var selectedGenre: String?
    @State private var selectedYear: Int?
    @State private var searchTask: Task<Void, Never>?
    @State private var tmdbResults = TMDBSearchService.Results()
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool

    /// Movies/shows found via the addon catalog search that TMDB's multi-search
    /// didn't already surface (dedup by id so the same title isn't listed twice).
    private var movies: [MetaPreview] {
        merge(tmdbResults.movies, searchRepo.results.filter { $0.type == .movie })
    }

    private var shows: [MetaPreview] {
        merge(tmdbResults.shows, searchRepo.results.filter { $0.type == .series })
    }

    private var hasAnyResults: Bool {
        !movies.isEmpty || !shows.isEmpty || !tmdbResults.people.isEmpty
    }

    private func merge(_ primary: [MetaPreview], _ secondary: [MetaPreview]) -> [MetaPreview] {
        var seen = Set(primary.map(\.id))
        return primary + secondary.filter { seen.insert($0.id).inserted }
    }

    /// Sampled from the reference recording at 1206x2622. Pinned rather than left
    /// to `.ultraThinMaterial` alone: a material resolves against whatever sits
    /// behind it, so the same code read light grey over Home and near-black inside
    /// a plain tab. The material still supplies the blur; the 0.94 overlay fixes
    /// the colour without going dead flat.
    private static let sheetFill = Color(red: 0.196, green: 0.204, blue: 0.204)   // #323434
    private static let fieldFill = Color(red: 0.125, green: 0.133, blue: 0.133)   // #202222
    private static let placeholderGrey = Color(red: 0.557, green: 0.565, blue: 0.561) // #8E908F

    /// iOS 26 supplies the search field itself (the tab bar morphs into it), so the
    /// hand-built capsule and the large title are only drawn on the iOS 18 path.
    #if os(tvOS)
    private var usesSystemSearchField: Bool { false }
    #else
    private var usesSystemSearchField: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                MoonlitTheme.background.ignoresSafeArea()
                sheetBackground

                VStack(spacing: 0) {
                    if !usesSystemSearchField {
                        Text("Search")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.top, 24)
                    }
                if isSearching {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(0..<8, id: \.self) { _ in
                                SearchResultRowShimmer()
                            }
                        }
                        .padding(.horizontal)
                    }
                } else if !hasAnyResults && !query.isEmpty {
                    Spacer()
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "No results found",
                        message: "Try a different search term, a person's name, or a genre"
                    )
                    Spacer()
                } else if hasAnyResults {
                    resultsList
                } else {
                    modalEmptyState
                }
                    if !usesSystemSearchField {
                        searchField
                    }
                }
            }
            .modifier(SystemSearchFieldModifier(query: $query, enabled: usesSystemSearchField))
            .onChange(of: query) { _, newValue in performSearch(newValue) }
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .navigationDestination(item: $selectedMedia) { media in
                DetailScreen(mediaId: media.id, type: media.type.rawValue, name: media.name)
            }
            .navigationDestination(item: $selectedPerson) { person in
                ActorBioScreen(name: person.name, tmdbPersonId: person.id, characterName: nil, showName: "")
            }
            .navigationDestination(item: $selectedGenre) { genre in
                GenreHubScreen(genre: genre, mediaKind: .movie)
            }
            .navigationDestination(item: $selectedYear) { year in
                YearBrowseScreen(year: year)
            }
        }
        #if os(tvOS)
        .searchable(text: $query, placement: .automatic)
        #endif
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(MoonlitTheme.textTertiary)
            TextField("Search movies, shows, people...", text: $query)
                .foregroundColor(.white)
                .focused($searchFocused)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(MoonlitTheme.textTertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Color.black.opacity(0.42), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    /// Flat neutral sheet with 40pt top corners, square at the bottom.
    private var sheetBackground: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 40,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 40,
            style: .continuous
        )
        .fill(.ultraThinMaterial)
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 40,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 40,
                style: .continuous
            )
            .fill(Self.sheetFill.opacity(0.94))
        )
        .ignoresSafeArea(edges: .bottom)
    }

    /// The empty state is the feature: rather than a magnifier and a prompt, the
    /// screen is a browsable surface — recent terms, then genre and year grids
    /// built from data already in memory. Nothing here fetches on appear.
    private var modalEmptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !recentSearches.recent.isEmpty {
                    browseSectionHeader("Recent", size: 17)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recentSearches.recent, id: \.self) { term in
                                Button(term) { query = term }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 8)
                                    .glassCapsule(interactive: true)
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                }

                if !browseGenres.isEmpty {
                    browseSectionHeader("Browse by Genre")
                    LazyVGrid(columns: browseColumns, spacing: 12) {
                        ForEach(browseGenres, id: \.id) { genre in
                            Button {
                                selectedGenre = genre.name
                            } label: {
                                BrowseTile(title: genre.name, posters: posters(forGenre: genre.name))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                }

                browseSectionHeader("Movies by Year")
                LazyVGrid(columns: browseColumns, spacing: 12) {
                    ForEach(browseYears, id: \.self) { year in
                        Button {
                            selectedYear = year
                        } label: {
                            BrowseTile(title: String(year), posters: posters(forYear: year))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)

                Spacer().frame(height: 40)
            }
        }
    }

    private var browseColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    /// Canonical genres, sourced the same way the Home browse menu sources them.
    private var browseGenres: [GenreCatalog.Genre] {
        GenreCatalog.genres(in: collectionRepo.organized)
    }

    /// Twenty years back from the current one, newest first.
    private var browseYears: [Int] {
        let thisYear = Calendar.current.component(.year, from: Date())
        return Array((thisYear - 19)...thisYear).reversed()
    }

    private func browseSectionHeader(_ text: String, size: CGFloat = 20) -> some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 11)
    }

    /// Up to three posters from already-loaded catalog items tagged with this
    /// genre. Read-only — the tile renders a flat label if nothing is loaded yet.
    private func posters(forGenre genre: String) -> [String] {
        var seen = Set<String>()
        var found: [String] = []
        for row in catalogRepo.catalogRows {
            for item in row.items where !item.id.hasPrefix("folder_") {
                guard item.genres?.contains(where: { $0.caseInsensitiveCompare(genre) == .orderedSame }) == true,
                      let poster = PosterService.posterURL(forImdbId: item.id) ?? item.poster,
                      seen.insert(poster).inserted else { continue }
                found.append(poster)
                if found.count == 3 { return found }
            }
        }
        return found
    }

    private func posters(forYear year: Int) -> [String] {
        var seen = Set<String>()
        var found: [String] = []
        for row in catalogRepo.catalogRows {
            for item in row.items where !item.id.hasPrefix("folder_") {
                guard item.releaseInfo?.hasPrefix(String(year)) == true,
                      let poster = PosterService.posterURL(forImdbId: item.id) ?? item.poster,
                      seen.insert(poster).inserted else { continue }
                found.append(poster)
                if found.count == 3 { return found }
            }
        }
        return found
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if !tmdbResults.people.isEmpty {
                    peopleSection
                }
                if !movies.isEmpty {
                    section(title: "Movies", items: movies)
                }
                if !shows.isEmpty {
                    section(title: "TV Shows", items: shows)
                }
            }
            .padding(.bottom, 20)
        }
        .refreshable { performSearch(query) }
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("People")
                .font(.headline).foregroundColor(.white)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(tmdbResults.people) { person in
                        PersonSearchRow(person: person)
                            .onTapGesture { selectedPerson = person }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func section(title: String, items: [MetaPreview]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline).foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.top, 6)
            VStack(spacing: 0) {
                ForEach(items) { item in
                    SearchResultRow(item: item)
                        .onTapGesture { selectedMedia = item }
                    if item.id != items.last?.id {
                        Divider().background(Color.white.opacity(0.06)).padding(.leading, 72)
                    }
                }
            }
            .padding(.horizontal)
            .glassCard(cornerRadius: MoonlitTheme.radiusCard)
            .padding(.horizontal)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()
            if !recentSearches.recent.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent Searches")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(MoonlitTheme.textSecondary)
                        .padding(.horizontal, 16)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recentSearches.recent, id: \.self) { term in
                                Button { query = term } label: {
                                    HStack(spacing: 6) {
                                        Text(term)
                                            .font(.caption.weight(.semibold))
                                        Button {
                                            recentSearches.remove(term)
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8, weight: .bold))
                                        }
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .glassCapsule(interactive: true)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            EmptyStateView(
                icon: "magnifyingglass",
                title: "Discover content",
                message: "Search for movies, shows, and people"
            )
            Spacer()
        }
    }

    private func performSearch(_ newValue: String) {
        searchTask?.cancel()
        guard !newValue.isEmpty else {
            searchRepo.results = []
            tmdbResults = TMDBSearchService.Results()
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            async let addonResults: Void = searchRepo.search(query: newValue, addons: addonRepo.enabledAddons)
            async let tmdb = tmdbSearch.search(query: newValue)
            _ = await addonResults
            let tmdbFound = await tmdb
            guard !Task.isCancelled else { return }
            tmdbResults = tmdbFound
            isSearching = false
            recentSearches.record(newValue)
        }
    }
}

// MARK: - Browse tile

/// A browse tile: two or three posters fanned across the top, label beneath.
/// The fan is what makes the grid read as stacks worth opening rather than a
/// file browser — but it degrades to a plain labelled tile when nothing has
/// loaded yet, which is the normal state for a second or two after a cold launch.
private struct BrowseTile: View {
    let title: String
    let posters: [String]
    #if os(tvOS)
    @Environment(\.isFocused) var isFocused
    #endif

    private static let angles: [Double] = [-9, 4, 13]
    private static let offsets: [CGFloat] = [-16, 4, 23]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if posters.isEmpty {
                    Image(systemName: "square.stack")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.white.opacity(0.22))
                } else {
                    ForEach(Array(posters.prefix(3).enumerated()), id: \.offset) { index, poster in
                        posterCard(poster)
                            .rotationEffect(.degrees(Self.angles[index]))
                            .offset(x: Self.offsets[index])
                            .zIndex(index == 1 ? 2 : 1)
                    }
                }
            }
            .frame(height: 78)
            .padding(.top, 16)

            Spacer(minLength: 6)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        #if os(tvOS)
        .scaleEffect(isFocused ? 1.03 : 1.0)
        .animation(.easeOut(duration: 0.1), value: isFocused)
        #endif
    }

    @ViewBuilder
    private func posterCard(_ poster: String) -> some View {
        Group {
            if let url = URL(string: poster) {
                CachedAsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        Color.white.opacity(0.08)
                    }
                }
            } else {
                Color.white.opacity(0.08)
            }
        }
        .frame(width: 46, height: 68)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.55), radius: 6, y: 3)
    }
}

// MARK: - Year browse

/// Popular titles from a single release year, opened from the Search grid.
private struct YearBrowseScreen: View {
    let year: Int

    @State private var items: [MetaPreview] = []
    @State private var isLoading = true
    @State private var selected: MetaPreview?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            if isLoading && items.isEmpty {
                ProgressView().tint(.white).padding(.top, 60)
            } else if items.isEmpty {
                Text("Nothing found for \(String(year))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(items) { item in
                        Button { selected = item } label: {
                            posterTile(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .background(MoonlitTheme.background.ignoresSafeArea())
        .navigationTitle(String(year))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .navigationDestination(item: $selected) { item in
            DetailScreen(mediaId: item.id, type: item.type.rawValue, name: item.name)
        }
        .task(id: year) {
            isLoading = true
            items = await TMDBDiscoverService.shared.discoverByYear(year: year, mediaKind: .movie)
            isLoading = false
        }
    }

    private func posterTile(_ item: MetaPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let urlStr = PosterService.posterURL(forImdbId: item.id) ?? item.poster,
                   let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        } else {
                            Color.white.opacity(0.06)
                        }
                    }
                } else {
                    Color.white.opacity(0.06)
                }
            }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl, style: .continuous))

            Text(item.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - System search field

/// Attaches `.searchable` only on iOS 26, where the search tab's bar becomes the
/// field. On iOS 18 it is a no-op and `SearchScreen` draws its own capsule.
private struct SystemSearchFieldModifier: ViewModifier {
    @Binding var query: String
    let enabled: Bool

    func body(content: Content) -> some View {
#if os(iOS)
        if #available(iOS 26.0, *), enabled {
            content.searchable(
                text: $query,
                placement: .toolbar,
                prompt: Text("Search…").foregroundColor(MoonlitTheme.textTertiary)
            )
        } else {
            content
        }
#else
        content
#endif
    }
}

// MARK: - Person row

private struct PersonSearchRow: View {
    let person: PersonSearchResult
    #if os(tvOS)
    @Environment(\.isFocused) var isFocused
    #endif

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let path = person.profilePath, let url = TMDBPersonService.shared.imageURL(path: path, size: "w185") {
                    CachedAsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        } else {
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(Circle())

            Text(person.name)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: 96)

            if let knownFor = person.knownFor.first {
                Text(knownFor)
                    .font(.caption2)
                    .foregroundColor(MoonlitTheme.textTertiary)
                    .lineLimit(1)
                    .frame(width: 96)
            }
        }
        #if os(tvOS)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.1), value: isFocused)
        #endif
    }

    private var placeholder: some View {
        Circle()
            .fill(Color.white.opacity(0.08))
            .overlay(Image(systemName: "person.fill").foregroundColor(.white.opacity(0.3)))
    }
}

// MARK: - List row

private struct SearchResultRow: View {
    let item: MetaPreview
    @AppStorage(PosterService.Key.rating) private var posterRating = true
    #if os(tvOS)
    @Environment(\.isFocused) var isFocused
    #endif

    private var isMovie: Bool { item.type == .movie }
    private var typeColor: Color { isMovie ? MoonlitTheme.accent : Color(red: 0.4, green: 0.7, blue: 1.0) }

    var body: some View {
        HStack(spacing: 14) {
            // Poster thumbnail
            Group {
                let posterURL = PosterService.posterURL(forImdbId: item.id) ?? item.poster
                if let urlStr = posterURL, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        } else {
                            posterPlaceholder
                        }
                    }
                } else {
                    posterPlaceholder
                }
            }
            .frame(width: 52, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)

            // Text content
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    // Type badge
                    HStack(spacing: 4) {
                        Image(systemName: isMovie ? "film.fill" : "tv.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text(isMovie ? "Movie" : "Series")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(typeColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(typeColor.opacity(0.15), in: Capsule())

                    // IMDb rating — hidden when the poster already bakes it in.
                    if let rating = item.imdbRating, !rating.isEmpty, !posterRating {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.yellow)
                            Text(rating)
                                .font(.caption.weight(.medium))
                                .foregroundColor(MoonlitTheme.textSecondary)
                        }
                    }

                    // Year
                    if let year = item.releaseInfo, !year.isEmpty {
                        Text(year)
                            .font(.caption)
                            .foregroundColor(MoonlitTheme.textTertiary)
                    }
                }
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(MoonlitTheme.textTertiary.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        #if os(tvOS)
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.1), value: isFocused)
        #endif
    }

    private var posterPlaceholder: some View {
        LinearGradient(
            colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)],
            startPoint: .top, endPoint: .bottom
        )
        .overlay(
            Image(systemName: isMovie ? "film" : "tv")
                .font(.body)
                .foregroundColor(MoonlitTheme.textTertiary)
        )
    }
}

// MARK: - Shimmer row

private struct SearchResultRowShimmer: View {
    var body: some View {
        HStack(spacing: 12) {
            ShimmerCard(width: 44, height: 62, cornerRadius: MoonlitTheme.radiusSmall)
            VStack(alignment: .leading, spacing: 6) {
                ShimmerCard(width: 180, height: 14, cornerRadius: MoonlitTheme.radiusSmall)
                ShimmerCard(width: 90, height: 11, cornerRadius: MoonlitTheme.radiusSmall)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
