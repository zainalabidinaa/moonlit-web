import SwiftUI
import MoonlitCore
import AppKit

struct MacMediaBrowseView: View {
    let mediaKind: MediaType
    let onSelectMedia: (MetaPreview) -> Void
    var onSelectFolder: ((CatalogRow) -> Void)?

    @EnvironmentObject var profileManager: ProfileManager
    @Environment(\.openWindow) private var openWindow
    @StateObject private var catalogRepo = CatalogRepository.shared
    @StateObject private var addonRepo = AddonRepository.shared
    @StateObject private var collectionRepo = CollectionRepository.shared
    @StateObject private var libraryRepo = LibraryRepository.shared
    @StateObject private var heroStore = HeroPreferenceStore.shared

    @State private var heroIndex = 0
    @State private var selectedGenre: String?
    @State private var browseRails: [GenreCatalog.LoadedBrowseRail] = []
    @State private var creativeRails: [GenreCatalog.LoadedBrowseRail] = []
    @State private var collectionRails: [GenreCatalog.LoadedBrowseRail] = []
    @State private var isLoadingRails = false
    @State private var isGenrePopoverPresented = false
    @State private var ambientColor: Color = .clear
    @State private var ambientColor2: Color = .clear
    @AppStorage("moonlit.cinematicModeEnabled") private var cinematicModeEnabled = true

    private var mediaTypeFilter: String { mediaKind == .movie ? "movie" : "series" }
    private var browseNoun: String { mediaKind == .movie ? "Movies" : "Series" }

    private let mainRowNames: Set<String> = [
        "Popular Movies", "Popular TV Shows",
        "Trending Movies", "Trending TV Shows",
        "Popular Shows", "Trending Shows",
        "Latest", "Top Rated"
    ]

    private var featuredItems: [MetaPreview] {
        let allRows = catalogRepo.catalogRows
        let heroRows: [CatalogRow]
        if heroStore.rowOrder.isEmpty {
            let defaults = allRows.filter { mainRowNames.contains($0.title) }
            heroRows = defaults.isEmpty ? allRows : defaults
        } else {
            let enabledOrdered = heroStore.rowOrder
                .filter { heroStore.isEnabled(rowTitle: $0) }
                .compactMap { title in allRows.first { $0.title == title } }
            let missing = allRows.filter {
                mainRowNames.contains($0.title) &&
                !heroStore.rowOrder.contains($0.title) &&
                heroStore.isEnabled(rowTitle: $0.title)
            }
            let computed = enabledOrdered + missing
            let defaults = allRows.filter { mainRowNames.contains($0.title) }
            heroRows = computed.isEmpty ? (defaults.isEmpty ? allRows : defaults) : computed
        }

        var seen = Set<String>()
        var candidates: [MetaPreview] = []
        for row in heroRows {
            var taken = 0
            let filtered = row.items.filter { item in
                !item.id.hasPrefix("folder_") &&
                (mediaKind == .movie ? item.isMovieKind : item.isShowKind)
            }
            for item in filtered.sorted(by: { ($0.popularity ?? 0) > ($1.popularity ?? 0) })
                where !seen.contains(item.id) {
                guard taken < 8, candidates.count < 20 else { break }
                seen.insert(item.id)
                candidates.append(item)
                taken += 1
            }
        }
        return candidates
    }

    private var availableGenres: [String] {
        TMDBGenreIDs.availableGenres(for: mediaKind)
    }

    @State private var collectionFolderRow: CatalogRow?

    var body: some View {
        ZStack(alignment: .top) {
            MacFusionAmbientBackground(
                ambientColor: ambientColor,
                ambientColor2: ambientColor2,
                isEnabled: cinematicModeEnabled,
                intensity: 0.6
            )
            .animation(.easeInOut(duration: 0.9), value: ambientColor)
            .animation(.easeInOut(duration: 0.9), value: ambientColor2)
            .animation(.easeInOut(duration: 0.35), value: cinematicModeEnabled)

            ScrollView {
            VStack(spacing: 0) {
                if !featuredItems.isEmpty {
                    HomeHero(
                        items: featuredItems,
                        currentIndex: $heroIndex,
                        onWatchNow: { item in onSelectMedia(item) },
                        onToggleLibrary: { item in
                            Task {
                                guard let profile = profileManager.currentProfile else { return }
                                await libraryRepo.toggleLibrary(
                                    profileId: profile.id,
                                    mediaId: item.id,
                                    mediaType: item.type.rawValue,
                                    name: item.name,
                                    poster: item.poster
                                )
                            }
                        },
                        ambientColor: ambientColor,
                        ambientColor2: ambientColor2
                        )
                        .task(id: "\(heroIndex)-\(cinematicModeEnabled)") {
                            await updateAmbientColorIfNeeded()
                        }
                        .onChange(of: heroIndex) { _, _ in
                            Task { await updateAmbientColorIfNeeded() }
                        }
                    }

                    genrePillRow
                        .padding(.top, featuredItems.isEmpty ? 96 : 14)

                    if let folderRow = collectionFolderRow, selectedGenre == nil {
                        folderTileSection(row: folderRow)
                    }

                    ForEach(browseRails) { rail in
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(displayTitle(for: rail.title))
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)

                                Text(subtitle(for: rail.title))
                                    .font(.system(size: 13, weight: .bold))
                                    .tracking(6)
                                    .foregroundColor(.white.opacity(0.32))
                            }
                            .padding(.horizontal, 32)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 22) {
                                    ForEach(rail.items) { item in
                                        MediaCard(item: item, width: 154, height: 231)
                                            .onTapGesture { onSelectMedia(item) }
                                    }
                                }
                                .padding(.horizontal, 32)
                                .padding(.vertical, 10)
                            }
                        }
                        .padding(.bottom, 48)
                    }

                    if !creativeRails.isEmpty {
                        ForEach(creativeRails) { rail in
                            VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(rail.title)
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(.white)

                                    Text("CURATED")
                                        .font(.system(size: 13, weight: .bold))
                                        .tracking(6)
                                        .foregroundColor(.white.opacity(0.32))
                                }
                                .padding(.horizontal, 32)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 22) {
                                        ForEach(rail.items) { item in
                                            MediaCard(item: item, width: 154, height: 231)
                                                .onTapGesture { onSelectMedia(item) }
                                        }
                                    }
                                    .padding(.horizontal, 32)
                                    .padding(.vertical, 10)
                                }
                            }
                            .padding(.bottom, 48)
                        }
                    }

                    if !collectionRails.isEmpty {
                        ForEach(collectionRails) { rail in
                            VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(rail.title)
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(.white)

                                    Text(rail.subtitle ?? "COLLECTION")
                                        .font(.system(size: 13, weight: .bold))
                                        .tracking(6)
                                        .foregroundColor(.white.opacity(0.32))
                                }
                                .padding(.horizontal, 32)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 22) {
                                        ForEach(rail.items) { item in
                                            MediaCard(item: item, width: 154, height: 231)
                                                .onTapGesture { onSelectMedia(item) }
                                        }
                                    }
                                    .padding(.horizontal, 32)
                                    .padding(.vertical, 10)
                                }
                            }
                            .padding(.bottom, 48)
                        }
                    }

                    if isLoadingRails {
                        MacLoadingView(size: 40)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if selectedGenre != nil && browseRails.isEmpty && creativeRails.isEmpty && collectionRails.isEmpty {
                        Text("Nothing found for \(selectedGenre ?? "")")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    }

                    Spacer().frame(height: 48)
                }
            }
            .ignoresSafeArea(edges: .top)
        }  // ZStack
        .background(MoonlitTheme.background)
        .task {
            guard let profile = profileManager.currentProfile else { return }
            catalogRepo.isLoading = true
            await addonRepo.loadAddons(profileId: profile.id)
            await libraryRepo.loadLibrary(profileId: profile.id)
            await reloadCatalogRows()
            let cacheKey = "browse:\(mediaTypeFilter):all"
            if let cached = BrowseRailCache.shared.get(key: cacheKey), !cached.isEmpty {
                browseRails = cached
            } else {
                await loadDefaultRails()
                BrowseRailCache.shared.set(key: cacheKey, rails: browseRails)
            }
            await updateAmbientColorIfNeeded()
        }
        .onChange(of: heroStore.revision) { _, _ in
            heroIndex = 0
        }
    }

    private var genrePillRow: some View {
        HStack(spacing: 12) {
            Text("Browse \(browseNoun)")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)

            Button {
                isGenrePopoverPresented.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text(selectedGenre ?? "All")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .macDarkGlassCapsule(interactive: true)
            .popover(isPresented: $isGenrePopoverPresented, arrowEdge: .bottom) {
                genreGridPopover
                    .preferredColorScheme(.dark)
            }
        }
        .padding(.horizontal, 32)
    }

    private var genreGridPopover: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 4)

        return LazyVGrid(columns: columns, spacing: 5) {
            genreGridCell(title: "All", isSelected: selectedGenre == nil) {
                selectedGenre = nil
                isGenrePopoverPresented = false
                Task { await loadDefaultRails() }
            }
            ForEach(availableGenres, id: \.self) { genre in
                genreGridCell(title: genre, isSelected: selectedGenre == genre) {
                    selectedGenre = genre
                    isGenrePopoverPresented = false
                    Task { await loadGenreRails(genre) }
                }
            }
        }
        .padding(14)
        .frame(width: 380)
        .macDarkGlassCard(cornerRadius: 12)
    }

    private func genreGridCell(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .black : .white.opacity(0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? MoonlitTheme.harborGold : Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }

    private func loadDefaultRails() async {
        let cacheKey = "browse:\(mediaTypeFilter):all"
        isLoadingRails = true
        async let rails = TMDBDiscoverService.shared.discoverGeneral(mediaKind: mediaKind)
        async let folderRow = loadCollectionFolderRow(genre: nil)
        let (r, fr) = await (rails, folderRow)
        browseRails = r
        creativeRails = []
        collectionRails = []
        collectionFolderRow = fr
        BrowseRailCache.shared.set(key: cacheKey, rails: r)
        isLoadingRails = false
    }

    private func loadGenreRails(_ genre: String) async {
        let cacheKey = "browse:\(mediaTypeFilter):\(GenreCatalog.normalize(genre))"
        if let cached = BrowseRailCache.shared.get(key: cacheKey), !cached.isEmpty {
            browseRails = cached
            creativeRails = []
            collectionRails = []
            collectionFolderRow = nil
            isLoadingRails = false
            return
        }
        isLoadingRails = true
        async let rails = TMDBDiscoverService.shared.discoverRails(genreName: genre, mediaKind: mediaKind)
        async let creative = TMDBDiscoverService.shared.discoverCreativeRails(genreName: genre, mediaKind: mediaKind)
        async let collections = catalogRepo.loadCollectionRails(genre: genre, collectionRepo: collectionRepo, addons: addonRepo.enabledAddons, mediaKind: mediaKind)
        let (r, c, cl) = await (rails, creative, collections)
        browseRails = r
        creativeRails = c
        collectionRails = cl
        collectionFolderRow = nil
        BrowseRailCache.shared.set(key: cacheKey, rails: r)
        isLoadingRails = false
    }

    private func loadCollectionFolderRow(genre: String?) async -> CatalogRow? {
        let org = collectionRepo.organized
        let key = genre.map(GenreCatalog.normalize)
        let collectionNames: [String] = mediaKind == .series
            ? ["series universes"] : ["film collections"]

        for cname in collectionNames {
            guard let collection = org.collections.first(where: {
                GenreCatalog.normalize($0.name) == cname
            }) else { continue }

            let folders = org.folders
                .filter { $0.collectionId == collection.id }
                .sorted { $0.sortOrder < $1.sortOrder }

            let targetFolders: [DBFolder] = folders.filter { folder in
                let n = GenreCatalog.normalize(folder.name)
                let words = n.split(separator: " ")
                if let key {
                    return words.first.map(String.init) == key
                }
                let first = words.first.map(String.init) ?? ""
                return !["collection", "collections", "franchise", "franchises", "universe", "universes"].contains(first)
            }

            guard !targetFolders.isEmpty else { continue }

            let tiles = targetFolders.map { folder -> MetaPreview in
                let cover = folder.coverImage ?? folder.heroBackdrop ?? folder.titleLogo
                return MetaPreview(
                    id: "folder_\(folder.id)",
                    type: .movie,
                    name: folder.name,
                    poster: cover,
                    banner: folder.coverImage ?? folder.heroBackdrop,
                    logo: folder.titleLogo,
                    posterShape: PosterShape(rawValue: folder.tileShape ?? "") ?? .landscape,
                    backdrop: folder.heroBackdrop
                )
            }

            return CatalogRow(
                id: "collection-folder-row-\(cname)",
                title: collection.name,
                items: tiles,
                tileShape: targetFolders.first?.tileShape ?? "landscape"
            )
        }
        return nil
    }

    private func folderTileSection(row: CatalogRow) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(row.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                Text("COLLECTIONS")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(6)
                    .foregroundColor(.white.opacity(0.32))
            }
            .padding(.horizontal, 32)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(row.items) { item in
                        MediaCard(item: item, width: 220, height: 124)
                            .onTapGesture {
                                let fid = item.id.hasPrefix("folder_")
                                    ? String(item.id.dropFirst("folder_".count))
                                    : item.id
                                let folderRow = CatalogRow(
                                    id: "folder_\(fid)",
                                    title: item.name,
                                    items: [],
                                    tileShape: "landscape"
                                )
                                guard let resolved = catalogRepo.allFolderRows[folderRow.id]
                                        ?? catalogRepo.allFolderRows.first(where: { $0.key.hasPrefix(fid) })?.value
                                else { return }
                                onSelectFolder?(resolved)
                            }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 10)
            }
        }
        .padding(.bottom, 48)
    }

    private func reloadCatalogRows() async {
        let collectionsChanged = await loadGlobalOrganizer()
        guard collectionsChanged || catalogRepo.catalogRows.isEmpty else { return }
        if collectionRepo.collections.isEmpty {
            await catalogRepo.loadAllCatalogs(addons: addonRepo.enabledAddons)
        } else {
            await catalogRepo.loadFromCollections(
                collectionRepo: collectionRepo,
                addons: addonRepo.enabledAddons,
                mode: .replaceCache
            )
        }
    }

    private func loadGlobalOrganizer() async -> Bool {
        guard let bundledURL = Bundle.main.url(forResource: "home-organizer", withExtension: "json"),
              let bundledData = try? Data(contentsOf: bundledURL),
              let organized = try? CollectionOrganizerStore.shared.cachedOrBundledLayout(bundledData: bundledData) else {
            return await collectionRepo.refreshForCatalogRows()
        }
        let before = collectionRepo.collections.count
        if collectionRepo.collections.isEmpty {
            collectionRepo.apply(organized)
        }
        return collectionRepo.collections.count != before || !collectionRepo.collections.isEmpty
    }

    private func displayTitle(for title: String) -> String {
        if !title.contains(browseNoun), title != "Hidden Gems" {
            return "\(title) \(browseNoun)"
        }
        return title
    }

    private func subtitle(for title: String) -> String {
        if title.contains("Popular") || title.contains("Trending") {
            return "WHAT'S HOT RIGHT NOW"
        } else if title.contains("Top Rated") || title.contains("Top Rated") {
            return "ALL-TIME BESTS"
        } else if title.contains("New Release") || title.contains("Recent") {
            return "RECENTLY ADDED"
        } else if title == "Hidden Gems" {
            return "QUIET GEMS"
        }
        return "SPOTLIGHT"
    }

    private func updateAmbientColorIfNeeded() async {
        guard cinematicModeEnabled,
              featuredItems.indices.contains(heroIndex) else {
            ambientColor = .clear
            ambientColor2 = .clear
            return
        }
        let item = featuredItems[heroIndex]
        guard let url = MacHeroArtworkProvider.shared.heroArtURL(for: item)
                ?? item.artworkURL(preferring: .landscape) else {
            ambientColor = .clear
            ambientColor2 = .clear
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = NSImage(data: data),
                  let (c1, c2) = image.moonlitAmbientColors() else { return }
            ambientColor = c1.moonlitBoostedForAmbient
            ambientColor2 = c2.moonlitBoostedForAmbient
        } catch {
            ambientColor = .clear
            ambientColor2 = .clear
        }
    }
}
