import SwiftUI
import MoonlitCore

/// A sectioned "genre room": franchise/sub-genre/decade folder rails aggregated by
/// `GenreCatalog`, plus the bundled browse rails (New / Popular / Top …). Tapping a
/// folder tile opens the existing folder view; tapping a media tile opens detail.
struct MacGenreHubView: View {
    let genre: String
    var mediaKind: MediaType? = nil
    let onBack: () -> Void
    let onSelectMedia: (MetaPreview) -> Void
    let onSelectFolder: (CatalogRow) -> Void

    @StateObject private var catalogRepo = CatalogRepository.shared
    @StateObject private var collectionRepo = CollectionRepository.shared
    @StateObject private var addonRepo = AddonRepository.shared

    @State private var browseRails: [GenreCatalog.LoadedBrowseRail] = []
    @State private var collectionRails: [GenreCatalog.LoadedBrowseRail] = []
    @State private var expandedSectionRails: [GenreCatalog.LoadedBrowseRail] = []
    @State private var isLoading = true
    @State private var voteFilter: VoteCountFilter = .any
    @State private var heroBackdrop: URL?

    enum VoteCountFilter: String, CaseIterable, Identifiable {
        case any = "Any"
        case under100 = "< 100"
        case from100to500 = "100–500"
        case from500to1k = "500–1K"
        case over1k = "1K+"

        var id: String { rawValue }

        func matches(_ item: MetaPreview) -> Bool {
            switch self {
            case .any: return true
            case .under100: return (item.voteCount ?? 0) < 100
            case .from100to500: return (100...500).contains(item.voteCount ?? 0)
            case .from500to1k: return (500...1000).contains(item.voteCount ?? 0)
            case .over1k: return (item.voteCount ?? 0) > 1000
            }
        }
    }

    private var filteredBrowseRails: [GenreCatalog.LoadedBrowseRail] {
        guard voteFilter != .any else { return browseRails }
        return browseRails.compactMap { rail in
            let filtered = rail.items.filter(voteFilter.matches)
            guard !filtered.isEmpty else { return nil }
            return GenreCatalog.LoadedBrowseRail(id: rail.id, title: rail.title, items: filtered)
        }
    }

    private var filteredCollectionRails: [GenreCatalog.LoadedBrowseRail] {
        guard voteFilter != .any else { return collectionRails }
        return collectionRails.compactMap { rail in
            let filtered = rail.items.filter(voteFilter.matches)
            guard !filtered.isEmpty else { return nil }
            return GenreCatalog.LoadedBrowseRail(id: rail.id, title: rail.title, items: filtered)
        }
    }

    // Computed live from collectionRepo so sections update automatically when
    // the background Supabase refresh populates the Horror sub-collections.
    private var sectionRows: [CatalogRow] {
        GenreCatalog.sections(for: genre, in: collectionRepo.organized).map { $0.asRow() }
    }

    var body: some View {
        ZStack(alignment: .top) {
            MacFusionAmbientBackground(
                ambientColor: .clear,
                ambientColor2: .clear,
                isEnabled: true
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 64) {
                    header

                    if !browseRails.isEmpty {
                        voteFilterRow
                            .padding(.horizontal, 40)
                    }

                    if sectionRows.isEmpty && filteredBrowseRails.isEmpty && filteredCollectionRails.isEmpty && !isLoading {
                        emptyState
                    }

                    ForEach(filteredBrowseRails) { rail in
                        genreRail(
                            row: CatalogRow(id: rail.id, title: displayTitle(for: rail.title), items: rail.items, tileShape: "poster"),
                            subtitle: subtitle(for: rail.title),
                            onTap: tap(_:)
                        )
                    }

                    ForEach(sectionRows) { row in
                        genreRail(
                            row: row,
                            subtitle: "SPOTLIGHT",
                            onTap: tap(_:)
                        )
                    }

                    ForEach(filteredCollectionRails) { rail in
                        genreRail(
                            row: CatalogRow(id: rail.id, title: rail.title, items: rail.items, tileShape: "poster"),
                            subtitle: rail.subtitle ?? "COLLECTION",
                            onTap: tap(_:)
                        )
                    }

                    if isLoading {
                        MacLoadingView(size: 40)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    }

                    Spacer().frame(height: 48)
                }
                .padding(.top, 16)
            }
            .task(id: genre) { await load() }

            HStack {
                Button { onBack() } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .macDarkGlassCapsule(interactive: true)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 48)
        }
        .background(MoonlitTheme.background)
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            // Cinematic backdrop for the genre (falls back to the plain text
            // header when TMDB has no art, so bare genres still look intentional).
            if let heroBackdrop {
                CachedAsyncImage(url: heroBackdrop) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
                .frame(height: 440)
                .frame(maxWidth: .infinity)
                .clipped()

                LinearGradient(
                    stops: [
                        .init(color: MoonlitTheme.background.opacity(0.0), location: 0.0),
                        .init(color: MoonlitTheme.background.opacity(0.55), location: 0.5),
                        .init(color: MoonlitTheme.background, location: 1.0),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 440)

                LinearGradient(
                    stops: [
                        .init(color: MoonlitTheme.background.opacity(0.70), location: 0.0),
                        .init(color: .clear, location: 0.55),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 440)
            }

            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "tag")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.70))
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.08), in: Circle())

                    Text("GENRE")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(7)
                        .foregroundColor(.white.opacity(0.40))
                }

                HStack(spacing: 18) {
                    Text(genre)
                        .font(.system(size: 66, weight: .semibold, design: .serif))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white.opacity(0.70))
                        .frame(width: 54, height: 54)
                        .background(Color.white.opacity(0.055), in: Circle())
                }

                Text(description(for: genre))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.58))
                    .lineSpacing(8)
                    .frame(maxWidth: 860, alignment: .leading)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, heroBackdrop != nil ? 34 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var voteFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(VoteCountFilter.allCases) { filter in
                    MacPillButton(
                        title: filter.rawValue,
                        isSelected: voteFilter == filter
                    ) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            voteFilter = filter
                        }
                    }
                }
            }
        }
    }

    private func genreRail(
        row: CatalogRow,
        subtitle: String,
        onTap: @escaping (MetaPreview) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(row.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.system(size: 13, weight: .bold))
                    .tracking(6)
                    .foregroundColor(.white.opacity(0.32))
            }
            .padding(.horizontal, 40)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 24) {
                    ForEach(row.items) { item in
                        MediaCard(item: item, row: row)
                            .onTapGesture { onTap(item) }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 10)
            }
        }
    }

    private var emptyState: some View {
        Text("Nothing here yet")
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
    }

    private func tap(_ item: MetaPreview) {
        if item.id.hasPrefix("folder_") {
            let fallback = CatalogRow(
                id: item.id, title: item.name, items: [],
                tileShape: item.posterShape?.rawValue ?? "poster",
                coverImage: item.artworkString(preferring: .portrait),
                heroBackdrop: item.backdrop
            )
            onSelectFolder(catalogRepo.allFolderRows[item.id] ?? fallback)
        } else {
            onSelectMedia(item)
        }
    }

    private func displayTitle(for title: String) -> String {
        switch title {
        case "Trending \(genre)": return "Trending in \(genre)"
        case "New \(genre)": return "Recent \(genre)"
        case "Top Rated \(genre)": return "Top Rated \(genre)"
        case "Top of all time": return "Top Rated \(genre)"
        case "Top of the year": return "Best \(genre) This Year"
        case "Popular": return "Popular \(genre)"
        case "New": return "Recent \(genre)"
        default: return title
        }
    }

    private func subtitle(for title: String) -> String {
        switch title {
        case let value where value.contains("Trending") || value == "Popular":
            return "WHAT'S HOT RIGHT NOW"
        case let value where value.contains("Top Rated") || value == "Top of all time":
            return "ALL-TIME BESTS"
        case let value where value.contains("New") || value == "Top of the year":
            return "RECENTLY ADDED"
        case "Hidden Gems":
            return "QUIET GEMS"
        default:
            return "SPOTLIGHT"
        }
    }

    private func description(for genre: String) -> String {
        let lower = genre.lowercased()
        switch GenreCatalog.normalize(genre) {
        case "action":
            return "The best action movies and series, layered by mood. Browse trending, dive into a director's run, sort by decade, find quiet gems."
        case "horror":
            return "The best \(lower) movies and series, from new nightmares to cult favorites and long-running franchises."
        case "comedy":
            return "The best \(lower) movies and series, from comfort watches to sharp, chaotic crowd favorites."
        case "drama":
            return "The best \(lower) movies and series, from acclaimed essentials to emotional discoveries."
        case "sci-fi":
            return "The best \(lower) movies and series, from future worlds to strange experiments and cerebral classics."
        default:
            return "The best \(lower) movies and series, layered by mood. Browse trending, dive into collections, sort by era, find quiet gems."
        }
    }

    private func load() async {
        isLoading = true
        async let hero = TMDBTileBackdropFetcher.fetchGenreBackdrops(genre: genre)
        let hub = await catalogRepo.loadGenreHub(
            genre: genre,
            collectionRepo: collectionRepo,
            addons: addonRepo.enabledAddons,
            mediaKind: mediaKind
        )
        browseRails = hub.browse
        collectionRails = hub.collectionRails
        heroBackdrop = (await hero).first
        isLoading = false
    }
}

struct MacStreamingServiceView: View {
    let row: CatalogRow
    let onBack: () -> Void
    let onSelectMedia: (MetaPreview) -> Void

    @StateObject private var catalogRepo = CatalogRepository.shared
    @StateObject private var collectionRepo = CollectionRepository.shared
    @StateObject private var addonRepo = AddonRepository.shared
    @State private var selectedCategory: ServiceCategory = .all
    @State private var isLoading = false
    @State private var unavailableReason: FolderLoadUnavailableReason?
    @State private var discoverMovies: [MetaPreview] = []
    @State private var discoverShows: [MetaPreview] = []

    private enum ServiceCategory: String, CaseIterable, Identifiable {
        case all = "All"
        case movies = "Movies"
        case tvShows = "TV Shows"
        case documentaries = "Documentaries"
        case animation = "Animation"
        case family = "Kids & Family"
        case action = "Action"
        case comedy = "Comedy"
        case drama = "Drama"
        case horror = "Horror"
        case sciFi = "Sci-Fi & Fantasy"
        case thriller = "Thriller"
        case romance = "Romance"

        var id: String { rawValue }

        func matches(_ item: MetaPreview) -> Bool {
            switch self {
            case .all:
                return true
            case .movies:
                return item.isMovieKind
            case .tvShows:
                return item.isShowKind
            case .documentaries:
                return item.genres?.contains("Documentary") == true
            case .animation:
                return item.genres?.contains("Animation") == true
            case .family:
                return item.genres?.contains("Family") == true || item.genres?.contains("Kids") == true
            case .action:
                return item.genres?.contains("Action") == true
            case .comedy:
                return item.genres?.contains("Comedy") == true
            case .drama:
                return item.genres?.contains("Drama") == true
            case .horror:
                return item.genres?.contains("Horror") == true
            case .sciFi:
                return item.genres?.contains("Sci-Fi") == true || item.genres?.contains("Science Fiction") == true || item.genres?.contains("Fantasy") == true
            case .thriller:
                return item.genres?.contains("Thriller") == true
            case .romance:
                return item.genres?.contains("Romance") == true
            }
        }
    }

    private var displayRow: CatalogRow {
        catalogRepo.allFolderRows[CatalogRepository.normalizedFolderId(row.id)] ?? row
    }

    private var serviceName: String {
        collectionRepo.streamingServiceName(forFolderRowId: row.id) ?? row.title
    }

    private var brandTint: Color {
        switch GenreCatalog.normalize(serviceName) {
        case let s where s.contains("netflix"): return Color(hex: "#E50914")
        case let s where s.contains("disney"): return Color(hex: "#0E47A1")
        case let s where s.contains("hulu"): return Color(hex: "#1CE783")
        case let s where s.contains("prime"): return Color(hex: "#00A8E1")
        case let s where s.contains("apple"): return .white
        case let s where s.contains("max") || s.contains("hbo"): return Color(hex: "#9B6CFF")
        case let s where s.contains("paramount"): return Color(hex: "#0064FF")
        case let s where s.contains("peacock"): return Color(hex: "#FF7112")
        case let s where s.contains("crunchyroll"): return Color(hex: "#F47521")
        default: return MoonlitTheme.harborGold
        }
    }

    private var filteredItems: [MetaPreview] {
        displayRow.items.filter(selectedCategory.matches)
    }

    /// In-library ids (from the addon-catalog folder) — used to tag items that
    /// only came from TMDB discover as "Discover" rather than confirmed-available.
    private var libraryIds: Set<String> {
        Set(displayRow.items.map(\.id))
    }

    private var movieItems: [MetaPreview] {
        let base = displayRow.items.filter(\.isMovieKind)
        let extra = discoverMovies.filter { !libraryIds.contains($0.id) }
        return base + extra
    }

    private var showItems: [MetaPreview] {
        let base = displayRow.items.filter(\.isShowKind)
        let extra = discoverShows.filter { !libraryIds.contains($0.id) }
        return base + extra
    }

    var body: some View {
        ZStack(alignment: .top) {
            MacFusionAmbientBackground(
                ambientColor: .clear,
                ambientColor2: .clear,
                isEnabled: true
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    categoryPills

                    if isLoading && displayRow.items.isEmpty {
                        MacLoadingView(size: 40)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if selectedCategory == .all {
                        serviceRail(title: "Top 10 Movies on \(serviceName)", items: Array(movieItems.prefix(10)), ranked: true)
                        serviceRail(title: "More Movies", items: Array(movieItems.dropFirst(10).prefix(24)), ranked: false)
                        serviceRail(title: "Top 10 Series on \(serviceName)", items: Array(showItems.prefix(10)), ranked: true)
                        serviceRail(title: "More Series", items: Array(showItems.dropFirst(10).prefix(24)), ranked: false)
                    } else if filteredItems.isEmpty {
                        emptyState
                    } else {
                        posterGrid(items: filteredItems)
                    }

                    Spacer().frame(height: 48)
                }
                .padding(.top, 16)
            }
            .task(id: row.id) { await load() }

            HStack {
                Button { onBack() } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .macDarkGlassCapsule(interactive: true)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 48)
        }
        .background(MoonlitTheme.background)
    }

    private var header: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                stops: [
                    .init(color: brandTint.opacity(0.42), location: 0.0),
                    .init(color: brandTint.opacity(0.20), location: 0.45),
                    .init(color: MoonlitTheme.background, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: MoonlitTheme.background.opacity(0.85), location: 0.0),
                        .init(color: .clear, location: 0.55),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 280)

            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("POPULAR ON")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(5)
                        .foregroundColor(MoonlitTheme.harborGold.opacity(0.85))

                    if let logo = displayRow.titleLogo.flatMap(URL.init) {
                        CachedAsyncImage(url: logo) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            Text(serviceName)
                                .font(.system(size: 56, weight: .semibold, design: .serif))
                        }
                        .frame(maxWidth: 360, maxHeight: 72, alignment: .leading)
                    } else {
                        Text(serviceName)
                            .font(.system(size: 62, weight: .semibold, design: .serif))
                            .foregroundColor(.white)
                    }

                    Text("The most-watched movies and series on \(serviceName) right now.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.62))
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 8)
            // Fill the full hero height and hug the bottom edge so the header
            // content sits directly above the category pills instead of leaving
            // a slab of dead gradient (the old minHeight:240 vs 280 mismatch).
            .frame(maxWidth: .infinity, minHeight: 280, alignment: .bottomLeading)
        }
    }

    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(ServiceCategory.allCases) { category in
                    MacPillButton(
                        title: category.rawValue,
                        isSelected: selectedCategory == category
                    ) {
                        withAnimation(.easeInOut(duration: 0.16)) { selectedCategory = category }
                    }
                }
            }
            .padding(.horizontal, 40)
        }
        .overlay(Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1), alignment: .bottom)
    }

    @ViewBuilder
    private func serviceRail(title: String, items: [MetaPreview], ranked: Bool) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)

                ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 22) {
                        let libraryIds = libraryIds
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ZStack(alignment: .topLeading) {
                                MediaCard(item: item, width: 154, height: 231)
                                    .onTapGesture { onSelectMedia(item) }
                                if !libraryIds.contains(item.id) {
                                    Text("DISCOVER")
                                        .font(.system(size: 9, weight: .bold))
                                        .tracking(0.5)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .background(.black.opacity(0.6), in: Capsule())
                                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75))
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                        .padding(8)
                                }
                                if ranked {
                                    Text("\(index + 1)")
                                        .font(.system(size: 24, weight: .black))
                                        .foregroundColor(.white)
                                        .frame(width: 46, height: 46)
                                        .background(
                                            RadialGradient(
                                                colors: [Color.black.opacity(0.55), Color.black.opacity(0.82)],
                                                center: .topLeading, startRadius: 2, endRadius: 46
                                            ),
                                            in: Circle()
                                        )
                                        .overlay(Circle().strokeBorder(MoonlitTheme.harborGold.opacity(0.5), lineWidth: 1.2))
                                        .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                                        .offset(x: -8, y: -8)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private func posterGrid(items: [MetaPreview]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 154), spacing: 22)], spacing: 28) {
            ForEach(items) { item in
                MediaCard(item: item, width: 154, height: 231)
                    .onTapGesture { onSelectMedia(item) }
            }
        }
        .padding(.horizontal, 40)
    }

    private var emptyState: some View {
        Text(unavailableReason?.rawValue ?? "Nothing here yet")
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white.opacity(0.52))
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
    }

    private func load() async {
        async let folderLoad: FolderLoadResult? = {
            guard displayRow.items.isEmpty else { return nil }
            isLoading = true
            return await catalogRepo.loadFolderItems(
                folderId: row.id,
                collectionRepo: collectionRepo,
                addons: addonRepo.enabledAddons
            )
        }()
        async let movieDiscover = TMDBDiscoverService.shared.discoverByProvider(serviceName: serviceName, mediaKind: .movie)
        async let showDiscover = TMDBDiscoverService.shared.discoverByProvider(serviceName: serviceName, mediaKind: .series)

        let (result, movies, shows) = await (folderLoad, movieDiscover, showDiscover)
        if case .unavailable(let reason)? = result {
            unavailableReason = reason
        }
        discoverMovies = movies.first?.items ?? []
        discoverShows = shows.first?.items ?? []
        isLoading = false
    }
}
