import SwiftUI
import MoonlitCore

/// Harbor-style search: a floating overlay card (not a persistent tab) with a
/// top search field, recent searches / jump-to / genre shortcuts when empty,
/// and a "Top Match" hero plus Movies/Series columns once there's a query.
struct MacSearchOverlay: View {
    let onDismiss: () -> Void
    let onSelectMedia: (MetaPreview) -> Void
    var onSelectGenre: (String) -> Void = { _ in }
    var onJumpToTab: (MacMainTab) -> Void = { _ in }

    @StateObject private var searchRepo = SearchRepository.shared
    @StateObject private var addonRepo = AddonRepository.shared
    @StateObject private var tmdbSearch = TMDBSearchService.shared
    @StateObject private var recentSearches = RecentSearchesStore.shared
    @State private var query = ""
    @State private var tmdbResults = TMDBSearchService.Results()
    @State private var searchTask: Task<Void, Never>?
    @State private var isSearching = false
    @State private var selectedPerson: PersonSearchResult?
    @FocusState private var fieldFocused: Bool

    private var movies: [MetaPreview] {
        var seen = Set<String>()
        return (tmdbResults.movies + searchRepo.results.filter { $0.isMovieKind })
            .filter { seen.insert($0.id).inserted }
    }

    private var series: [MetaPreview] {
        var seen = Set<String>()
        return (tmdbResults.shows + searchRepo.results.filter { $0.isShowKind })
            .filter { seen.insert($0.id).inserted }
    }

    private var topMatch: MetaPreview? {
        (movies + series).max { (lhs, rhs) in
            (lhs.popularity ?? 0) < (rhs.popularity ?? 0)
        }
    }

    private static let genres = GenreCatalog.canonicalGenres

    var body: some View {
        ZStack(alignment: .top) {
            MacFusionAmbientBackground(
                ambientColor: .clear,
                ambientColor2: .clear,
                isEnabled: true
            )
            ZStack {
                Color.black.opacity(0.65)
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }

                VStack {
                    card
                        .frame(maxWidth: 1100)
                        .padding(.top, 90)
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 40)
            }
        }
        .background(MoonlitTheme.background)
        .sheet(item: $selectedPerson) { person in
            MacActorBioView(name: person.name, tmdbPersonId: person.id, onBack: { selectedPerson = nil })
                .frame(minWidth: 500, minHeight: 500)
        }
        .onAppear { fieldFocused = true }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    if isSearching {
                        HStack {
                            Spacer()
                            ProgressView().tint(.white)
                            Spacer()
                        }
                        .padding(.top, 60)
                    } else if query.isEmpty {
                        emptyStateContent
                    } else if movies.isEmpty && series.isEmpty && tmdbResults.people.isEmpty {
                        noResultsContent
                    } else {
                        resultsContent
                    }
                }
                .padding(24)
            }
            .frame(maxHeight: 640)
        }
        .background(MoonlitTheme.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.5))
            TextField("Search movies, shows, people, genres, years...", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .focused($fieldFocused)
                .onChange(of: query) { _, newValue in performSearch(newValue) }
                .onSubmit { performSearch(query) }
            if !query.isEmpty {
                Button {
                    query = ""
                    tmdbResults = TMDBSearchService.Results()
                    searchRepo.results = []
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
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .overlay(Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1), alignment: .bottom)
        .background {
            Button(action: onDismiss) { EmptyView() }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
        }
    }

    // MARK: - Empty state

    private var emptyStateContent: some View {
        VStack(alignment: .leading, spacing: 28) {
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
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recentSearches.recent, id: \.self) { term in
                                Button { query = term; performSearch(term) } label: {
                                    HStack(spacing: 6) {
                                        Text(term).font(.system(size: 13, weight: .semibold))
                                        Button { recentSearches.remove(term) } label: {
                                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(Color.white.opacity(0.08), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("JUMP TO", icon: "location")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    jumpToChip(title: "Home", icon: "house") { onJumpToTab(.home) }
                    jumpToChip(title: "Library", icon: "rectangle.stack") { onJumpToTab(.library) }
                    jumpToChip(title: "Settings", icon: "gear") { onJumpToTab(.settings) }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("TRY A GENRE", icon: "sparkles")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                    ForEach(Self.genres, id: \.self) { genre in
                        Button { onSelectGenre(genre) } label: {
                            Text(genre)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .frame(maxWidth: .infinity)
                                .background(Color.white.opacity(0.06), in: Capsule())
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
                .font(.system(size: 12, weight: .bold))
                .tracking(1)
        }
        .foregroundColor(.white.opacity(0.5))
    }

    private func jumpToChip(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 28) {
            if let topMatch {
                topMatchCard(topMatch)
            }

            if !tmdbResults.people.isEmpty {
                peopleRow
            }

            HStack(alignment: .top, spacing: 32) {
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
            .frame(width: 140, height: 210)
            .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("TOP MATCH")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .foregroundColor(MoonlitTheme.harborGold)
                Text(item.name)
                    .font(.system(size: 30, weight: .semibold, design: .serif))
                    .foregroundColor(.white)
                HStack(spacing: 8) {
                    Text(item.type == .series ? "Series" : "Movie")
                    if let year = item.releaseInfo { Text("•"); Text(year) }
                    if let rating = item.imdbRating {
                        Text("•")
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").font(.system(size: 10))
                            Text(rating)
                        }
                        .foregroundColor(MoonlitTheme.harborGold)
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.6))

                if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(3)
                        .padding(.top, 2)
                }

                Button {
                    recentSearches.record(query)
                    onSelectMedia(item)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text("Open")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func resultColumn(title: String, items: [MetaPreview]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !items.isEmpty {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.5))
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
                                        .foregroundColor(MoonlitTheme.harborGold)
                                    }
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                                if let description = item.description, !description.isEmpty {
                                    Text(description)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var peopleRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("PEOPLE", icon: "person")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(tmdbResults.people) { person in
                        Button { selectedPerson = person } label: {
                            VStack(spacing: 8) {
                                Group {
                                    if let path = person.profilePath, let url = TMDBPersonService.shared.imageURL(path: path, size: "w185") {
                                        CachedAsyncImage(url: url) { img in
                                            img.resizable().scaledToFill()
                                        } placeholder: {
                                            Circle().fill(Color.white.opacity(0.08))
                                        }
                                    } else {
                                        Circle().fill(Color.white.opacity(0.08))
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
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
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
        }
    }
}
