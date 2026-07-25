import SwiftUI
import MoonlitCore

///  search: a full-screen takeover, not a floating card. The
/// whole screen becomes a dark glass layer (the app stays faintly visible
/// behind it), the search field floats alone as a pill, and every section —
/// recents, jump-to, genres, results — sits directly on that backdrop.
///
/// Speed: local catalog matches paint at 0ms, TMDB paints the moment it
/// returns (~250ms), addon results merge in whenever they arrive. The two
/// network sources are never awaited jointly, and previous results stay on
/// screen while typing instead of blanking to a spinner.
struct MacSearchOverlay: View {
    let onDismiss: () -> Void
    let onSelectMedia: (MetaPreview) -> Void
    var onJumpToTab: (MacMainTab) -> Void = { _ in }

    @StateObject private var searchRepo = SearchRepository.shared
    @StateObject private var addonRepo = AddonRepository.shared
    @StateObject private var tmdbSearch = TMDBSearchService.shared
    @StateObject private var recentSearches = RecentSearchesStore.shared
    @State private var query = ""
    @State private var tmdbResults = TMDBSearchService.Results()
    @State private var localHits: [MetaPreview] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var isSearching = false
    @State private var selectedPerson: PersonSearchResult?
    @FocusState private var fieldFocused: Bool

    @State private var browsingGenre: String?
    @State private var genreFilterTab: MacSearchGenreTab = .all
    @State private var browseMovies: [MetaPreview] = []
    @State private var browseShows: [MetaPreview] = []
    @State private var isBrowsingLoading = false
    @State private var browseTask: Task<Void, Never>?

    private var browseItems: [MetaPreview] {
        MacSearchGenreSelection(movies: browseMovies, shows: browseShows)
            .items(for: genreFilterTab)
    }

    // TMDB first (richest metadata), then instant local hits, then addon
    // results as they arrive — deduped by id so a title upgraded by TMDB
    // doesn't appear twice.
    private var movies: [MetaPreview] {
        var seen = Set<String>()
        return (tmdbResults.movies + localHits.filter { $0.isMovieKind } + searchRepo.results.filter { $0.isMovieKind })
            .filter { seen.insert($0.id).inserted }
    }

    private var series: [MetaPreview] {
        var seen = Set<String>()
        return (tmdbResults.shows + localHits.filter { $0.isShowKind } + searchRepo.results.filter { $0.isShowKind })
            .filter { seen.insert($0.id).inserted }
    }

    private var topMatch: MetaPreview? {
        (movies + series).max { (lhs, rhs) in
            (lhs.popularity ?? 0) < (rhs.popularity ?? 0)
        }
    }

    private var hasAnyResults: Bool {
        !movies.isEmpty || !series.isEmpty || !tmdbResults.people.isEmpty
    }

    private static let genres = GenreCatalog.canonicalGenres

    var body: some View {
        ZStack(alignment: .top) {
            // Full-screen dark glass — the app behind stays faintly visible.
            // No card, no border: everything renders directly on this layer.
            Rectangle()
                .fill(.regularMaterial)
                .overlay(Color.black.opacity(0.52))
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    searchField

                    if let browsingGenre {
                        genreBrowsingContent(browsingGenre)
                    } else if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        emptyStateContent
                    } else if hasAnyResults {
                        resultsContent
                    } else if isSearching {
                        HStack {
                            Spacer()
                            MacStrokeSpinner(size: 28)
                            Spacer()
                        }
                        .padding(.top, 60)
                    } else {
                        noResultsContent
                    }

                    Spacer(minLength: 60)
                }
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 48)
                .padding(.top, 56)
            }
        }
        .sheet(item: $selectedPerson) { person in
            MacActorBioView(name: person.name, tmdbPersonId: person.id, onBack: { selectedPerson = nil })
                .frame(minWidth: 900, minHeight: 650)
        }
        .onAppear { fieldFocused = true }
    }

    // MARK: - Search field (standalone pill, )

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            TextField("Search movies, shows, people, genres, years...", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .foregroundColor(.white)
                .focused($fieldFocused)
                .onChange(of: query) { _, newValue in performSearch(newValue) }
                .onSubmit { performSearch(query) }
            if isSearching && hasAnyResults {
                // Subtle refresh hint — never replaces visible results.
                MacStrokeSpinner(size: 18, color: .white.opacity(0.5))
            }
            if !query.isEmpty {
                Button {
                    query = ""
                    performSearch("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            Text("ESC")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .padding(.horizontal, 22)
        .frame(height: 58)
        .background(Color.white.opacity(0.055), in: Capsule())
        .background {
            Button(action: onDismiss) { EmptyView() }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
        }
    }

    // MARK: - Empty state

    private var emptyStateContent: some View {
        VStack(alignment: .leading, spacing: 30) {
            if !recentSearches.recent.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        sectionLabel("RECENT SEARCHES", icon: "clock")
                        Spacer()
                        Button("Clear History") { recentSearches.clear() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    FlowLayout(spacing: 8, rowSpacing: 8) {
                        ForEach(recentSearches.recent, id: \.self) { term in
                            HStack(spacing: 3) {
                                Button {
                                    query = term
                                    performSearch(term)
                                } label: {
                                    Text(term).font(.system(size: 13, weight: .medium))
                                        .padding(.leading, 15)
                                        .padding(.vertical, 9)
                                }
                                .buttonStyle(.plain)

                                Button("Remove \(term)", systemImage: "xmark") {
                                    recentSearches.remove(term)
                                }
                                .labelStyle(.iconOnly)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white.opacity(0.45))
                                .buttonStyle(.plain)
                                .padding(.trailing, 11)
                                .padding(.vertical, 9)
                            }
                                .foregroundColor(.white.opacity(0.85))
                                .background(Color.white.opacity(0.055), in: Capsule())
                                .fixedSize()
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("JUMP TO", icon: "location")
                FlowLayout(spacing: 8, rowSpacing: 8) {
                    jumpToChip(title: "Home", icon: "house") { onJumpToTab(.home) }
                    jumpToChip(title: "Library", icon: "rectangle.stack") { onJumpToTab(.library) }
                    jumpToChip(title: "Settings", icon: "gear") { onJumpToTab(.settings) }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("TRY A GENRE", icon: "sparkles")
                FlowLayout(spacing: 8, rowSpacing: 8) {
                    ForEach(Self.genres, id: \.self) { genre in
                        Button { browseGenre(genre) } label: {
                            Text(genre)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(Color.white.opacity(0.055), in: Capsule())
                                .fixedSize()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func sectionLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.6)
        }
        .foregroundColor(.white.opacity(0.45))
    }

    private func jumpToChip(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
            }
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, 17)
            .padding(.vertical, 11)
            .background(Color.white.opacity(0.055), in: Capsule())
            .fixedSize()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Genre browsing (stays inside the overlay, not a route change)

    private func genreBrowsingContent(_ genre: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Button {
                    browseTask?.cancel()
                    browsingGenre = nil
                    browseMovies = []
                    browseShows = []
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left")
                        Text("Back")
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.055), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Text("BROWSING")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.45))

                Text(genre)
                    .font(.system(size: 20, weight: .medium, design: .serif))
                    .foregroundColor(.white)
            }

            HStack(spacing: 7) {
                genreFilterPill("All", tab: .all)
                genreFilterPill("Movies", tab: .movies)
                genreFilterPill("Shows", tab: .shows)
            }

            if isBrowsingLoading && browseItems.isEmpty {
                HStack {
                    Spacer()
                    MacStrokeSpinner(size: 28)
                    Spacer()
                }
                .padding(.top, 40)
            } else if browseItems.isEmpty {
                Text("No titles found for \(genre).")
                    .foregroundColor(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 124, maximum: 156), spacing: 12)], spacing: 16) {
                    ForEach(browseItems) { item in
                        Button {
                            recentSearches.record(genre)
                            onSelectMedia(item)
                        } label: {
                            Group {
                                if let url = item.artworkURL(preferring: .portrait) {
                                    CachedAsyncImage(url: url) { img in
                                        img.resizable().scaledToFill()
                                    } placeholder: {
                                        MoonlitTheme.surfaceElevated
                                    }
                                } else {
                                    MoonlitTheme.surfaceElevated
                                }
                            }
                            .aspectRatio(2 / 3, contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl, style: .continuous))
                            .macAutomaticTileGlow(
                                artworkURL: item.artworkURL(preferring: .portrait),
                                cornerRadius: MoonlitTheme.radiusControl
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func genreFilterPill(_ title: String, tab: MacSearchGenreTab) -> some View {
        Button { genreFilterTab = tab } label: {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(genreFilterTab == tab ? .black : .white.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    genreFilterTab == tab ? Color.white : Color.white.opacity(0.055),
                    in: Capsule()
                )
                .fixedSize()
        }
        .buttonStyle(.plain)
    }

    private func browseGenre(_ genre: String) {
        browsingGenre = genre
        genreFilterTab = .all
        browseMovies = []
        browseShows = []
        browseTask?.cancel()
        isBrowsingLoading = true
        browseTask = Task {
            async let movieRails = TMDBDiscoverService.shared.discoverRails(genreName: genre, mediaKind: .movie)
            async let showRails = TMDBDiscoverService.shared.discoverRails(genreName: genre, mediaKind: .series)
            let movies = await movieRails
            let shows = await showRails
            guard !Task.isCancelled else { return }
            browseMovies = dedupedItems(from: movies)
            browseShows = dedupedItems(from: shows)
            isBrowsingLoading = false
        }
    }

    private func dedupedItems(from rails: [GenreCatalog.LoadedBrowseRail]) -> [MetaPreview] {
        MacSearchGenreSelection.deduplicated(rails.flatMap(\.items))
    }

    // MARK: - Results

    private var noResultsContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title)
                .foregroundColor(.white.opacity(0.3))
            Text("No results for \"\(query)\"")
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var resultsContent: some View {
        VStack(alignment: .leading, spacing: 30) {
            if let topMatch {
                topMatchCard(topMatch)
            }

            if !tmdbResults.people.isEmpty {
                peopleRow
            }

            HStack(alignment: .top, spacing: 40) {
                resultColumn(title: "MOVIES", items: movies)
                resultColumn(title: "SERIES", items: series)
            }
        }
    }

    private func topMatchCard(_ item: MetaPreview) -> some View {
        HStack(alignment: .top, spacing: 24) {
            Group {
                if let url = item.artworkURL(preferring: .portrait) {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        MoonlitTheme.surfaceElevated
                    }
                } else {
                    MoonlitTheme.surfaceElevated
                }
            }
            .frame(width: 132, height: 198)
            .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard, style: .continuous))
            .macAutomaticTileGlow(
                artworkURL: item.artworkURL(preferring: .portrait),
                cornerRadius: MoonlitTheme.radiusCard
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("TOP MATCH")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(MoonlitTheme.ratingGold)
                Text(item.name)
                    .font(.system(size: 32, weight: .medium, design: .serif))
                    .foregroundColor(.white)
                HStack(spacing: 8) {
                    Text(item.type == .series ? "Series" : "Movie")
                    if let year = item.releaseInfo { Text("·"); Text(year) }
                    if let rating = item.imdbRating {
                        Text("·")
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").font(.system(size: 10))
                            Text(rating)
                        }
                        .foregroundColor(MoonlitTheme.ratingGold)
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.55))

                if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(3)
                        .padding(.top, 2)
                }

                Button {
                    recentSearches.record(query)
                    onSelectMedia(item)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "play.fill")
                        Text("Open")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func resultColumn(title: String, items: [MetaPreview]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !items.isEmpty {
                sectionLabel(title, icon: title == "MOVIES" ? "film" : "tv")
                ForEach(items.prefix(8)) { item in
                    Button {
                        recentSearches.record(query)
                        onSelectMedia(item)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Group {
                                if let url = item.artworkURL(preferring: .portrait) {
                                    CachedAsyncImage(url: url) { img in
                                        img.resizable().scaledToFill()
                                    } placeholder: {
                                        MoonlitTheme.surfaceElevated
                                    }
                                } else {
                                    MoonlitTheme.surfaceElevated
                                }
                            }
                            .frame(width: 56, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl, style: .continuous))
                            .macAutomaticTileGlow(
                                artworkURL: item.artworkURL(preferring: .portrait),
                                cornerRadius: MoonlitTheme.radiusControl
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    if let year = item.releaseInfo { Text(year) }
                                    if let rating = item.imdbRating {
                                        HStack(spacing: 3) {
                                            Image(systemName: "star.fill").font(.system(size: 9))
                                            Text(rating)
                                        }
                                        .foregroundColor(MoonlitTheme.ratingGold)
                                    }
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                                if let description = item.description, !description.isEmpty {
                                    Text(description)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.55))
                                        .lineLimit(2)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var peopleRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("PEOPLE", icon: "person")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(tmdbResults.people) { person in
                        Button { selectedPerson = person } label: {
                            VStack(spacing: 8) {
                                Group {
                                    if let path = person.profilePath, let url = TMDBPersonService.shared.imageURL(path: path, size: "w185") {
                                        CachedAsyncImage(url: url) { img in
                                            img.resizable().scaledToFill()
                                        } placeholder: {
                                            Circle().fill(Color.white.opacity(0.07))
                                        }
                                    } else {
                                        Circle().fill(Color.white.opacity(0.07))
                                            .overlay(Image(systemName: "person.fill").foregroundColor(.white.opacity(0.3)))
                                    }
                                }
                                .frame(width: 84, height: 84)
                                .clipShape(Circle())

                                Text(person.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .frame(width: 96)
                                if let credit = person.knownFor.first {
                                    Text(credit)
                                        .font(.system(size: 10.5))
                                        .foregroundColor(.white.opacity(0.45))
                                        .lineLimit(1)
                                        .frame(width: 96)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Pipeline

    private func performSearch(_ newValue: String) {
        searchTask?.cancel()
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchRepo.results = []
            tmdbResults = TMDBSearchService.Results()
            localHits = []
            isSearching = false
            return
        }

        // 0ms layer: titles already loaded in memory paint immediately —
        // this is what makes the first keystroke feel instant.
        localHits = localMatches(trimmed)

        // Cached TMDB results (backspacing, retyping) paint immediately too.
        if let cached = tmdbSearch.cachedResults(for: trimmed) {
            tmdbResults = cached
        }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }

            // Addon fan-out runs independently: it publishes into
            // searchRepo.results whenever it finishes and never holds up
            // the TMDB paint below.
            let addonTask = Task {
                await searchRepo.search(query: trimmed, addons: addonRepo.enabledAddons)
            }

            let tmdbFound = await tmdbSearch.search(query: trimmed)
            guard !Task.isCancelled else {
                addonTask.cancel()
                return
            }
            tmdbResults = tmdbFound
            isSearching = false
            _ = await addonTask.value
        }
    }

    /// Synchronous, zero-network: filters the catalog rows already loaded at
    /// startup. Prefix matches rank above substring matches.
    private func localMatches(_ query: String) -> [MetaPreview] {
        let q = query.lowercased()
        guard q.count >= 2 else { return [] }
        var seen = Set<String>()
        return CatalogRepository.shared.allCatalogItems
            .compactMap { item -> (MetaPreview, Int)? in
                guard !item.id.hasPrefix("folder_") else { return nil }
                let name = item.name.lowercased()
                guard name.contains(q), seen.insert(item.id).inserted else { return nil }
                let score = name == q ? 3 : (name.hasPrefix(q) ? 2 : 1)
                return (item, score)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(12)
            .map(\.0)
    }
}

enum MacSearchGenreTab: Hashable {
    case all
    case movies
    case shows
}

struct MacSearchGenreSelection {
    let movies: [MetaPreview]
    let shows: [MetaPreview]

    func items(for tab: MacSearchGenreTab) -> [MetaPreview] {
        switch tab {
        case .all:
            return Self.deduplicated(movies + shows)
        case .movies:
            return Self.deduplicated(movies)
        case .shows:
            return Self.deduplicated(shows)
        }
    }

    static func deduplicated(_ items: [MetaPreview]) -> [MetaPreview] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}
