import SwiftUI
import UIKit
import CoreImage
import MoonlitCore
import OSLog

struct HomeScreen: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var roleManager: RoleManager
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var catalogRepo = CatalogRepository.shared
    @StateObject private var collectionRepo = CollectionRepository.shared
    @StateObject private var homeRepo = HomeRepository.shared
    @StateObject private var addonRepo = AddonRepository.shared
    @StateObject private var preferenceStore = CollectionDisplayPreferenceStore.shared
    @StateObject private var rowStyleStore = CollectionRowDisplayStyleStore.shared
    @StateObject private var heroStore = HeroPreferenceStore.shared
    @StateObject private var libraryRepo = LibraryRepository.shared
    @StateObject private var recsService = RecommendationsService.shared
    @StateObject private var watchProgressRepo = WatchProgressRepository.shared
    @State private var selectedMedia: MetaPreview?
    @State private var showDetail = false
    @State private var cwDetailTarget: MetaPreview? = nil
    @State private var showCWDetail = false
    @State private var selectedFolder: CatalogRow? = nil
    @State private var showFolder = false
    @State private var selectedGenre: String? = nil
    @State private var selectedGenreMediaKind: MediaType? = nil
    @State private var showGenre = false
    @State private var selectedRecRow: CatalogRow? = nil
    @State private var showRecFolder = false
    @State private var categoryState = HomeCategoryState()
    // Stable snapshots of the browse menu's genre lists. The menu must not read
    // catalogRepo directly: a background catalog refresh landing mid-interaction
    // changes the menu's content, rebuilding the toolbar item and tearing down the
    // live UIMenu — which collapses any open submenu. See refreshMenuGenres().
    @State private var menuMovieGenres: [String] = []
    @State private var menuShowGenres: [String] = []

    private var categoryGenres: [String] {
        availableHomeGenres(in: catalogRepo.catalogRows, category: categoryState.category)
    }

    private var visibleCatalogRows: [CatalogRow] {
        switch categoryState.category {
        case .featured:
            return catalogRepo.catalogRows.compactMap { filteredHomeRow($0, filter: categoryState) }
        case .movies:
            return catalogRepo.rows(for: .movies, collectionRepo: collectionRepo)
                .compactMap { filteredHomeRow($0, filter: categoryState) }
        case .shows:
            return catalogRepo.rows(for: .series, collectionRepo: collectionRepo)
                .compactMap { filteredHomeRow($0, filter: categoryState) }
        }
    }

    /// Display rows with because_you_watched merged into one folder tile
    private var recsDisplayRows: [RecommendationRow] {
        let watchedIds = watchProgressRepo.watchedMediaIds
        func notWatched(_ item: MetaPreview) -> Bool {
            let baseId = item.id.split(separator: ":").first.map(String.init) ?? item.id
            return !watchedIds.contains(item.id) && !watchedIds.contains(baseId)
        }
        var result: [RecommendationRow] = []
        var becauseRows: [RecommendationRow] = []
        for row in recsService.rows {
            let filtered = row.items.filter(notWatched)
            guard !filtered.isEmpty else { continue }
            let filteredRow = RecommendationRow(
                rowType: row.rowType,
                rowTitle: row.rowTitle,
                coverImage: row.coverImage,
                sortOrder: row.sortOrder,
                items: filtered
            )
            if row.rowType == "because_you_watched" {
                becauseRows.append(filteredRow)
            } else {
                result.append(filteredRow)
            }
        }
        if !becauseRows.isEmpty {
            let first = becauseRows[0]
            result.append(RecommendationRow(
                rowType: "because_you_watched",
                rowTitle: "Because You Watched...",
                coverImage: first.coverImage,
                sortOrder: first.sortOrder,
                items: becauseRows.flatMap { $0.items }
            ))
        }
        return result
    }
    @State private var playerLaunch: PlayerLaunch?
    @State private var streamSelectionLaunch: PlayerLaunch?
    @State private var showFreeUpgradeAlert = false
    @State private var ambientColor: Color = .clear
    @State private var ambientColor2: Color = .clear
    @State private var heroScroll: CGFloat = 0
    @State private var heroScrollBase: CGFloat? = nil
    @AppStorage("moonlit.cinematicModeEnabled") private var cinematicModeEnabled = true
    @AppStorage("moonlit.guestMode") private var guestMode = false

    private let mainRowNames: Set<String> = [
        "Popular Movies", "Popular TV Shows",
        "Trending Movies", "Trending TV Shows",
        "Popular Shows", "Trending Shows",
        "Latest", "Top Rated"
    ]

    private var featuredItems: [MetaPreview] {
        // Narrow to the active category BEFORE resolving hero rows. The selector
        // has no notion of categoryState, so handing it every row lets a movie
        // catalog win under Shows — and the category filter below then strips it
        // to nothing, leaving Shows with no hero at all.
        let scopedRows: [CatalogRow]
        switch categoryState.category {
        case .featured:
            scopedRows = catalogRepo.catalogRows
        case .movies:
            scopedRows = catalogRepo.rows(for: .movies, collectionRepo: collectionRepo)
        case .shows:
            scopedRows = catalogRepo.rows(for: .series, collectionRepo: collectionRepo)
        }
        // Fusion-style hero source: the user-selected catalog if set, else a
        // single trending/popular catalog, else the legacy named-row fallback.
        // The pinned hero is a Featured-page choice — a hero pinned to a movie
        // catalog must not govern Shows.
        let heroRows = HeroCatalogSelector.heroRows(
            from: scopedRows.compactMap { filteredHomeRow($0, filter: categoryState) },
            selectedId: categoryState.category == .featured ? heroStore.heroCatalogId : nil,
            fallbackNamedTitles: Array(mainRowNames)
        )
        // A single selected catalog may fill the carousel; a blend is capped per
        // row so one row can't dominate.
        let totalCap = 20
        let perRowCap = heroRows.count == 1 ? totalCap : 8
        var seen = Set<String>()
        var candidates: [MetaPreview] = []
        for row in heroRows {
            let rowItems = row.items
                .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
            var taken = 0
            for item in rowItems where !seen.contains(item.id) && matchesHomeCategory(item, filter: categoryState) {
                guard taken < perRowCap, candidates.count < totalCap else { break }
                seen.insert(item.id)
                candidates.append(item)
                taken += 1
            }
        }
        return candidates
    }

    @State private var heroIndex = 0

    /// Free accounts never receive Moonlit's curated default catalogs or the
    /// cinematic hero. They only see catalogs from addons they installed
    /// themselves; with none installed they get a "No content found" empty state.
    private var isFreeAccount: Bool {
        profileManager.currentProfile?.role == "free"
    }

    private var catalogMetadataAddons: [AddonManifest] {
        addonRepo.enabledAddons.filter { !$0.hasResource("stream") }
    }

    private var catalogAddonsForCurrentMode: [AddonManifest] {
        if isFreeAccount { return freeUserCatalogAddons }
        return profileManager.currentProfile == nil && guestMode ? catalogMetadataAddons : addonRepo.enabledAddons
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let metrics = ResponsiveMetrics(for: geo.size.width)
                ZStack {
                    FusionAmbientBackground(
                        ambientColor: ambientColor,
                        ambientColor2: ambientColor2,
                        isEnabled: cinematicModeEnabled,
                        heroHeight: ParallaxHero.heroHeight,
                        screenHeight: geo.size.height,
                        scrollOffset: heroScroll
                    )
                    .animation(.easeInOut(duration: 0.9), value: ambientColor)
                    .animation(.easeInOut(duration: 0.9), value: ambientColor2)
                    .animation(.easeInOut(duration: 0.35), value: cinematicModeEnabled)

                    ScrollView {
                        VStack(spacing: 0) {
                            if !featuredItems.isEmpty && !isFreeAccount {
                                ParallaxHero(
                                    items: featuredItems,
                                    currentIndex: $heroIndex,
                                    metrics: metrics,
                                    onWatchNow: { item in
                                        selectedMedia = item
                                        showDetail = true
                                    },
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
                                    }
                                )
                                .task(id: "\(heroIndex)-\(cinematicModeEnabled)") {
                                    await updateAmbientColorIfNeeded()
                                }
                                .onChange(of: heroIndex) { _, _ in
                                    Task { await updateAmbientColorIfNeeded() }
                                }

                                Color.clear
                                    .frame(height: 8)
                                    .onChange(of: categoryState) { _, _ in heroIndex = 0 }
                            }

                    // Continue Watching
                    if !homeRepo.continueWatchingItems.isEmpty {
                    ContinueWatchingRow(
                        items: homeRepo.continueWatchingItems,
                        onTap: { item in
                            let decodedId = item.mediaId.removingPercentEncoding ?? item.mediaId
                            let cachedSource: LastPlaybackSource? = profileManager.currentProfile.flatMap { profile in
                                let ids = [decodedId, item.parentMediaId].compactMap { $0 }
                                return ids.lazy.compactMap { LastPlaybackSourceStore.shared.source(profileId: profile.id, mediaId: $0) }.first
                            }
                            presentPlayback(
                                PlayerLaunch(
                                title: item.name,
                                sourceUrl: cachedSource?.sourceUrl ?? "",
                                sourceHeaders: cachedSource?.sourceHeaders,
                                logo: item.logo,
                                poster: item.poster,
                                episodeThumbnail: item.thumbnail,
                                background: item.background,
                                seasonNumber: item.seasonNumber,
                                episodeNumber: item.episodeNumber,
                                streamTitle: cachedSource?.streamTitle ?? item.episodeTitle,
                                providerName: cachedSource?.providerName,
                                contentType: item.mediaType == "movie" ? .movie : .series,
                                videoId: decodedId,
                                parentMetaId: item.parentMediaId,
                                parentMetaType: item.parentMediaId == nil ? nil : item.mediaType,
                                initialPositionMs: item.resumePositionMs
                                )
                            )
                        },
                        onShowDetail: { item in
                            let rawId = item.parentMediaId ?? item.mediaId
                            let cleanId = rawId.components(separatedBy: ":").first ?? rawId
                            let mediaType = MediaType(rawValue: item.mediaType) ?? .series
                            cwDetailTarget = MetaPreview(id: cleanId, type: mediaType, name: item.name, poster: item.poster, logo: item.logo)
                            showCWDetail = true
                        },
                        metrics: metrics
                        )
                        .padding(.top, 16)
                    }

                #if os(macOS)
                // For You — Personalized Recommendations
                if !recsService.rows.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("For You")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 10) {
                                ForEach(recsDisplayRows) { row in
                                    Button {
                                        let catalogRow = CatalogRow(
                                            id: row.id,
                                            title: row.rowTitle,
                                            items: row.items,
                                            tileShape: "landscape",
                                            coverImage: row.coverImage
                                        )
                                        selectedRecRow = catalogRow
                                        showRecFolder = true
                                    } label: {
                                        FolderCell(row: CatalogRow(
                                            id: row.id,
                                            title: row.rowTitle,
                                            items: row.items,
                                            tileShape: "landscape",
                                            coverImage: row.coverImage
                                        ), onTap: { _ in })
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.top, 16)
                }
                #endif

                    if !catalogRepo.catalogRows.isEmpty {
                        LazyVStack(spacing: 28) {
                            ForEach(visibleCatalogRows) { row in
                                CollectionRowContainer(row: row, style: rowStyleStore.style(forRowTitle: row.title), onTap: { item in
                                    if item.id.hasPrefix("folder_"),
                                       let genre = collectionRepo.genreName(forFolderRowId: item.id) {
                                        selectedGenre = genre
                                        showGenre = true
                                    } else if item.id.hasPrefix("folder_") {
                                        selectedFolder = catalogRepo.allFolderRows[item.id] ?? CatalogRow(
                                            id: item.id,
                                            title: item.name,
                                            items: [],
                                            tileShape: item.posterShape?.rawValue ?? "poster",
                                            coverImage: item.artworkString(preferring: .portrait)
                                        )
                                        showFolder = true
                                    } else {
                                        selectedMedia = item
                                        showDetail = true
                                    }
                                }, onHeaderTap: {
                                    selectedFolder = row
                                    showFolder = true
                                }, metrics: metrics)
                                .onAppear {
                                    if row.id == catalogRepo.catalogRows.last?.id {
                                        Task {
                                            await catalogRepo.loadMore(
                                                rowId: row.id,
                                                addons: catalogAddonsForCurrentMode
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.top, 24)
                    } else if catalogRepo.isLoading {
                        VStack(spacing: 24) {
                            Spacer().frame(height: 20)
                            ShimmerCard(width: 375, height: 200, cornerRadius: MoonlitTheme.radiusCard)
                                .padding(.horizontal)
                            ShimmerCard(width: 120, height: 16, cornerRadius: MoonlitTheme.radiusSmall)
                                .padding(.horizontal)
                            HStack(spacing: 12) {
                                ForEach(0..<3, id: \.self) { _ in
                                    ShimmerCard(width: 180, height: 100, cornerRadius: MoonlitTheme.radiusControl)
                                }
                            }
                            .padding(.horizontal)
                            HStack(spacing: 12) {
                                ForEach(0..<4, id: \.self) { _ in
                                    ShimmerCard(width: 105, height: 158, cornerRadius: MoonlitTheme.radiusControl)
                                }
                            }
                            .padding(.horizontal)
                            Spacer()
                        }
                    } else if isFreeAccount {
                        FreeNoContentState()
                            .padding(.top, 140)
                            .padding(.horizontal, 32)
                    } else {
                        HomeEmptyState()
                            .padding(.top, featuredItems.isEmpty ? 140 : 48)
                            .padding(.horizontal, 32)
                    }

                    Spacer().frame(height: 32)
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y
            } action: { _, value in
                if heroScrollBase == nil { heroScrollBase = value }
                heroScroll = value - (heroScrollBase ?? 0)
            }
            .task(id: featuredItems.map(\.id)) {
                // Resolve textless hero posters as soon as the featured set is
                // known, so the first hero render already has the clean poster
                // (or fades it in shortly after) instead of waiting on the hero's
                // own onAppear.
                HeroArtworkProvider.shared.prefetch(items: featuredItems)
            }
#if os(tvOS)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            guard let profile = profileManager.currentProfile else {
                                await loadCatalogRowsForGuest()
                                return
                            }
                            await reloadCatalogRows()
                            await homeRepo.loadContinueWatching(profileId: profile.id)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
#else
            .refreshable {
                guard let profile = profileManager.currentProfile else {
                    await loadCatalogRowsForGuest()
                    return
                }
                await reloadCatalogRows()
                await homeRepo.loadContinueWatching(profileId: profile.id)
            }
#endif
                }
            }
            .ignoresSafeArea(edges: .top)
#if os(iOS)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    homeBrowseMenu
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let profile = profileManager.currentProfile {
                        Button {
                            profileManager.currentProfile = nil
                        } label: {
                            ProfileAvatarView(profile: profile, size: 32)
                        }
                    }
                }
            }
#endif
            .navigationDestination(isPresented: $showDetail) {
                if let media = selectedMedia {
                    DetailScreen(mediaId: media.id, type: media.type.rawValue, name: media.name)
                }
            }
            .navigationDestination(isPresented: $showCWDetail) {
                if let media = cwDetailTarget {
                    DetailScreen(mediaId: media.id, type: media.type.rawValue, name: media.name)
                }
            }
            .navigationDestination(isPresented: $showFolder) {
                if let folder = selectedFolder {
                    FolderScreen(row: folder)
                }
            }
            .navigationDestination(isPresented: $showGenre) {
                if let genre = selectedGenre {
                    GenreHubScreen(genre: genre, mediaKind: selectedGenreMediaKind)
                }
            }
            #if os(macOS)
            .navigationDestination(isPresented: $showRecFolder) {
                if let folder = selectedRecRow {
                    FolderScreen(row: folder)
                }
            }
            #endif
            .fullScreenCover(item: $playerLaunch) { launch in
#if os(tvOS)
                TVPlayerScreen(launch: launch, onDismiss: { playerLaunch = nil })
#else
                PlayerScreen(launch: launch, onDismiss: { playerLaunch = nil })
#endif
            }
            .alert("Streaming unavailable", isPresented: $showFreeUpgradeAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Streaming isn't available on this account.")
            }
            .fullScreenCover(item: $streamSelectionLaunch) { launch in
                StreamSelectionScreen(
                    mediaType: launch.contentType,
                    mediaId: launch.videoId,
                    mediaName: launch.title,
                    poster: launch.poster,
                    logo: launch.logo,
                    episodeThumbnail: launch.episodeThumbnail,
                    background: launch.background,
                    parentMetaId: launch.parentMetaId,
                    parentMetaType: launch.parentMetaType,
                    seasonNumber: launch.seasonNumber,
                    episodeNumber: launch.episodeNumber,
                    episodeTitle: launch.streamTitle,
                    initialPositionMs: launch.initialPositionMs
                )
            }
            .task {
                // Show shimmer immediately — isLoading only becomes true inside
                // loadAllCatalogs/loadFromCollections, which means the gap between
                // app launch and the first catalog fetch shows a blank screen.
                catalogRepo.isLoading = true
                guard let profile = profileManager.currentProfile else {
                    await loadCatalogRowsForGuest()
                    return
                }
                await addonRepo.loadAddons(profileId: profile.id)
                if profile.role == "free" {
                    await loadFreeUserCatalogs()
                    return
                }
                async let continueWatching: Void = homeRepo.loadContinueWatching(profileId: profile.id)
                #if os(macOS)
                Task { await recsService.load(profileId: profile.id) }
                #endif
                _ = await loadGlobalOrganizer()
                await libraryRepo.loadLibrary(profileId: profile.id)
                if catalogRepo.catalogRows.isEmpty {
                    if collectionRepo.collections.isEmpty {
                        await catalogRepo.loadAllCatalogs(addons: addonRepo.enabledAddons)
                    } else {
                        await catalogRepo.loadFromCollections(
                            collectionRepo: collectionRepo,
                            addons: addonRepo.enabledAddons
                        )
                    }
                } else {
                    // Disk cache is warm — show it immediately, refresh in background.
                    catalogRepo.isLoading = false
                    Task { await reloadCatalogRows() }
                }
                await continueWatching
                warmupContinueWatching()
                Task {
                    await AwardIndex.shared.buildIfNeeded(
                        catalogRepo: catalogRepo,
                        collectionRepo: collectionRepo,
                        addons: addonRepo.enabledAddons
                    )
                }
            }
            .onChange(of: preferenceStore.revision) { _, _ in
                Task { await reloadCatalogRows() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, let profile = profileManager.currentProfile else { return }
                Task {
                await homeRepo.loadContinueWatching(profileId: profile.id)
                #if os(macOS)
                await recsService.load(profileId: profile.id)
                #endif
                    warmupContinueWatching()
                }
            }
        }
    }

    @ViewBuilder
    private var homeBrowseMenu: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer {
                browseMenu
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
        } else {
            browseMenu
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .glassCapsule(interactive: true)
        }
    }

    private var browseMenu: some View {
        Menu {
            Button("Featured") { categoryState = HomeCategoryState(category: .featured) }
            Button("Movies") { categoryState = HomeCategoryState(category: .movies) }
            Button("Shows") { categoryState = HomeCategoryState(category: .shows) }

            Menu("Movie categories") {
                ForEach(menuMovieGenres, id: \.self) { genre in
                    Button(genre) { openGenre(genre, as: .movie) }
                }
            }
            Menu("Show categories") {
                ForEach(menuShowGenres, id: \.self) { genre in
                    Button(genre) { openGenre(genre, as: .series) }
                }
            }
        } label: {
            Label("Browse", systemImage: "rectangle.grid.2x2")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Browse content")
        .onAppear { refreshMenuGenres() }
        .onChange(of: catalogRowsFingerprint) { _, _ in refreshMenuGenres() }
    }

    /// Cheap Equatable stand-in for `catalogRepo.catalogRows`, which holds
    /// non-Equatable `CatalogRow`s. Row identity plus item count is enough to
    /// catch every change that could alter the available genres.
    private var catalogRowsFingerprint: [String] {
        catalogRepo.catalogRows.map { "\($0.id):\($0.items.count)" }
    }

    /// Recomputes the browse menu's genre lists, assigning only on a real change.
    ///
    /// HomeScreen's body re-evaluates on every catalog publish regardless, so what
    /// keeps the open menu alive is the toolbar item's *content* staying identical
    /// across those evaluations — SwiftUI then has no reason to rebuild the UIMenu.
    /// A redundant assignment here would republish @State and defeat that, so the
    /// equality guard is load-bearing, not an optimisation.
    private func refreshMenuGenres() {
        let movies = availableHomeGenres(in: catalogRepo.catalogRows, category: .movies)
        if movies != menuMovieGenres { menuMovieGenres = movies }
        let shows = availableHomeGenres(in: catalogRepo.catalogRows, category: .shows)
        if shows != menuShowGenres { menuShowGenres = shows }
    }

    private func openGenre(_ genre: String, as mediaType: MediaType) {
        selectedGenreMediaKind = mediaType
        selectedGenre = genre
        showGenre = true
    }

    private func warmupContinueWatching() {
        guard profileManager.currentProfile != nil else { return }
        let items = homeRepo.continueWatchingItems
        let addons = addonRepo.enabledAddons
        guard !items.isEmpty, !addons.isEmpty else { return }
        // Pre-warm streams for the first 5 continue-watching items in background.
        // By the time the user taps play, streams are already cached.
        for item in items.prefix(5) {
            let type = item.mediaType
            let id = item.mediaId
            Task { await StreamWarmupRepository.shared.warmup(type: type, id: id, addons: addons) }
        }
    }

    private func presentPlayback(_ launch: PlayerLaunch) {
        guard let profile = profileManager.currentProfile else {
            streamSelectionLaunch = launch
            return
        }

        if ProfileManager.shared.currentProfile?.role == "free" {
            showFreeUpgradeAlert = true
            return
        }

        if StreamAutoplayPreferenceStore.shared.mode(profileId: profile.id) == .manual {
            streamSelectionLaunch = PlayerLaunch(
                title: launch.title,
                sourceUrl: "",
                logo: launch.logo,
                poster: launch.poster,
                episodeThumbnail: launch.episodeThumbnail,
                background: launch.background,
                seasonNumber: launch.seasonNumber,
                episodeNumber: launch.episodeNumber,
                streamTitle: launch.streamTitle,
                providerName: launch.providerName,
                contentType: launch.contentType,
                videoId: launch.videoId,
                parentMetaId: launch.parentMetaId,
                parentMetaType: launch.parentMetaType,
                initialPositionMs: launch.initialPositionMs,
                subtitles: launch.subtitles
            )
        } else {
            playerLaunch = launch
        }
    }

    /// Enabled addons the free user installed themselves — never the curated
    /// `MoonlitConfig.defaultAddons`. This is the only content a free account sees.
    private var freeUserCatalogAddons: [AddonManifest] {
        addonRepo.userAddons.filter { $0.enabled }.map { $0.manifest }
    }

    /// Loads catalogs for a free account from its own addons only. Clears any
    /// warm/curated rows first so nothing leaks in from a prior premium session.
    private func loadFreeUserCatalogs() async {
        let ownAddons = freeUserCatalogAddons
        catalogRepo.catalogRows = []
        if ownAddons.isEmpty {
            catalogRepo.isLoading = false
        } else {
            await catalogRepo.loadAllCatalogs(addons: ownAddons)
        }
    }

    private func reloadCatalogRows() async {
        if isFreeAccount {
            await loadFreeUserCatalogs()
            return
        }
        _ = await loadGlobalOrganizer()
        if collectionRepo.collections.isEmpty {
            await catalogRepo.loadAllCatalogs(addons: catalogAddonsForCurrentMode)
        } else {
            await catalogRepo.loadFromCollections(
                collectionRepo: collectionRepo,
                addons: catalogAddonsForCurrentMode
            )
        }
    }

    private func loadCatalogRowsForGuest() async {
        if addonRepo.managedAddons.isEmpty {
            await addonRepo.refreshFromUrls(MoonlitConfig.defaultAddons)
        }
        _ = await loadGlobalOrganizer()
        if collectionRepo.collections.isEmpty {
            await catalogRepo.loadAllCatalogs(addons: catalogMetadataAddons)
        } else {
            await catalogRepo.loadFromCollections(
                collectionRepo: collectionRepo,
                addons: catalogMetadataAddons
            )
        }
        catalogRepo.isLoading = false
    }

    private func loadGlobalOrganizer() async -> Bool {
        // Apply bundled/disk-cached layout immediately — no network wait.
        // This is the source of truth for catalog IDs; Supabase tables can drift.
        guard let bundledURL = Bundle.main.url(forResource: "home-organizer", withExtension: "json"),
              let bundledData = try? Data(contentsOf: bundledURL),
              let organized = try? CollectionOrganizerStore.shared.cachedOrBundledLayout(bundledData: bundledData) else {
            return await collectionRepo.refreshForCatalogRows()
        }
        let before = collectionRepo.collections.count
        if collectionRepo.collections.isEmpty {
            collectionRepo.apply(organized)
        }
        // Background-refresh from Supabase — remote layout is authoritative.
        // Retries every 30s on failure so bundled data doesn't persist indefinitely.
        Task {
            let logger = Logger(subsystem: "ai.moonlit", category: "HomeScreen")
            guard let refreshed = await CollectionOrganizerStore.shared.refresh(
                remoteURL: MoonlitConfig.homeOrganizerRemoteURL.flatMap(URL.init)
            ) else {
                logger.warning("home-organizer background refresh failed")
                return
            }
            // Re-applying an identical layout republishes collectionRepo and then
            // refetches every catalog row for nothing. That churn is what tears
            // down and rebuilds the toolbar — collapsing an open browse menu.
            guard refreshed != collectionRepo.organized else {
                logger.info("home-organizer unchanged — skipping re-apply")
                return
            }
            let oldCount = collectionRepo.collections.count
            collectionRepo.apply(refreshed)
            logger.info("home-organizer applied: \(collectionRepo.collections.count) collections (was \(oldCount))")
            guard !collectionRepo.collections.isEmpty else { return }
            await catalogRepo.loadFromCollections(
                collectionRepo: collectionRepo,
                addons: catalogAddonsForCurrentMode
            )
            logger.info("home-organizer rows loaded: \(self.catalogRepo.catalogRows.count) rows")
        }
        return collectionRepo.collections.count != before || !collectionRepo.collections.isEmpty
    }

    @MainActor
    private func updateAmbientColorIfNeeded() async {
        guard cinematicModeEnabled,
              featuredItems.indices.contains(heroIndex) else {
            ambientColor = .clear
            ambientColor2 = .clear
            return
        }
        let item = featuredItems[heroIndex]
        guard let url = HeroArtworkProvider.shared.heroArtURL(for: item)
                ?? item.artworkURL(preferring: .portrait) else {
            ambientColor = .clear
            ambientColor2 = .clear
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data),
                  let (c1, c2) = image.moonlitAmbientColors() else { return }
            ambientColor  = c1.moonlitMutedForAmbient
            ambientColor2 = c2.moonlitMutedForAmbient
        } catch {
            ambientColor = .clear
            ambientColor2 = .clear
        }
    }

}

private struct HomeEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image("NoContentFound")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 240)
                .opacity(0.92)

            Text("Add catalog or metadata addons in Settings.")
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundColor(MoonlitTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Empty state shown to Free accounts in place of catalog rows.
private struct FreeNoContentState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image("NoContentFree")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 240)

            Text("No content found")
                .font(.system(size: 16, weight: .semibold, design: .default))
                .foregroundColor(MoonlitTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Folder Grid

/// Art-tinted wash shared by HomeScreen and DetailScreen. Module-internal
/// rather than private so the detail page can reuse the same treatment.
struct FusionAmbientBackground: View {
    let ambientColor: Color
    let ambientColor2: Color
    let isEnabled: Bool
    /// On-screen hero content height in points (excluding the top safe-area inset,
    /// which is added internally). The color band sits just below this line.
    let heroHeight: CGFloat
    let screenHeight: CGFloat
    /// Vertical scroll amount (points). Subtracted from the band's offset so the
    /// color hugs the hero's lower edge and scrolls up with the content.
    var scrollOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            if isEnabled {
                // Fusion-style base: a vertical charcoal gradient that never
                // resolves to pure black, so the page keeps depth even before
                // any art color loads.
                FusionAmbientBackground.baseGradient
            } else {
                MoonlitTheme.background
            }

            if isEnabled {
                // Ambient wash — an animated MeshGradient of the extracted hero
                // colors, sized to a band and offset to sit just under the hero's
                // lower edge. Because the offset subtracts the scroll amount, the
                // band hugs the hero and scrolls up with the content, so it reads
                // as the artwork bleeding down and never draws over the hero. The
                // band's own top/bottom fade blends the seams.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    MeshGradient(
                        width: 3,
                        height: 3,
                        points: meshPoints(t),
                        colors: meshColors
                    )
                }
                .frame(height: screenHeight * 0.62)
                .blur(radius: 24)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black, location: 0.18),
                            .init(color: .black, location: 0.72),
                            .init(color: .clear, location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .offset(y: (heroHeight + Self.topSafeInset) - scrollOffset)
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }

    // 3×3 mesh control points. The 4 corners and the 4 edge mid-points keep the
    // boundary pinned (so the rect always fills — no gaps), while the interior
    // and the free axis of each edge mid-point drift on slow, out-of-phase sines
    // for an organic, non-repeating motion.
    private func meshPoints(_ t: Double) -> [SIMD2<Float>] {
        func osc(_ period: Double, _ phase: Double, _ amp: Float) -> Float {
            Float(sin(t * (.pi * 2 / period) + phase)) * amp
        }
        func cl(_ v: Float) -> Float { min(max(v, 0.08), 0.92) }
        return [
            SIMD2<Float>(0.0, 0.0),
            SIMD2<Float>(0.5, 0.0),
            SIMD2<Float>(1.0, 0.0),
            SIMD2<Float>(0.0, cl(0.5 + osc(17, 0.0, 0.06))),
            SIMD2<Float>(cl(0.5 + osc(19, 1.3, 0.07)), cl(0.5 + osc(23, 0.5, 0.05))),
            SIMD2<Float>(1.0, cl(0.5 + osc(21, 2.1, 0.06))),
            SIMD2<Float>(0.0, 1.0),
            SIMD2<Float>(cl(0.5 + osc(15, 3.0, 0.06)), 1.0),
            SIMD2<Float>(1.0, 1.0),
        ]
    }

    // Mesh colors, row-major. The band's own mask fades its top and bottom edges,
    // so every row carries color: the two extracted tints (color1 left, color2
    // right) at moderate opacity, letting the charcoal base still read through.
    private var meshColors: [Color] {
        [
            ambientColor.opacity(0.55), ambientColor2.opacity(0.45), ambientColor2.opacity(0.55),
            ambientColor.opacity(0.60), ambientColor.opacity(0.50), ambientColor2.opacity(0.60),
            ambientColor.opacity(0.40), ambientColor2.opacity(0.34), ambientColor2.opacity(0.40),
        ]
    }

    // Current key window's top safe-area inset, so the color line can be placed
    // just past the hero's true on-screen bottom on any device.
    private static var topSafeInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .safeAreaInsets.top ?? 0
    }

    // Fusion-style charcoal base — top #3D3D3D, bottom #161616 (never pure black).
    private static let baseGradient = LinearGradient(
        stops: [
            .init(color: Color(hex: "3D3D3D"), location: 0.0),
            .init(color: Color(hex: "161616"), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

struct CollectionRowContainer: View {
    let row: CatalogRow
    let style: RowDisplayStyle
    let onTap: (MetaPreview) -> Void
    var onHeaderTap: (() -> Void)? = nil
    var metrics: ResponsiveMetrics? = nil

    var body: some View {
        switch style {
        case .standard:
            CatalogRowView(row: row, onTap: onTap, onHeaderTap: onHeaderTap, metrics: metrics)
        case .heroBanner:
            HeroBannerRow(row: row, onTap: onTap, onHeaderTap: onHeaderTap, metrics: metrics)
        case .cardStack:
            CardStackRow(row: row, onTap: onTap, onHeaderTap: onHeaderTap, metrics: metrics)
        case .carouselCinematic:
            CarouselCinematicRow(row: row, onTap: onTap, metrics: metrics)
        case .topTen:
            TopTenRow(row: row, onTap: onTap, onHeaderTap: onHeaderTap, metrics: metrics)
        }
    }
}

extension UIImage {
    // Extracts two ambient colors from the left/right of the artwork's top region.
    // Uses a *saturation-weighted* average over a downscaled copy rather than a flat
    // mean: weighting each pixel by saturation² × brightness pulls the result toward
    // the artwork's vivid, dominant hues instead of the muddy gray a plain average
    // collapses to. Falls back to a plain average for near-grayscale images.
    func moonlitAmbientColors() -> (Color, Color)? {
        guard let cg = cgImage else { return nil }
        let w = 48, h = 48
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &buf, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // In a CGContext row 0 is the bottom, so the artwork's top 60% is the high
        // rows. Skipping the bottom avoids dark letterbox bars muddying the color.
        let topStart = Int(Double(h) * 0.4)

        func dominant(xRange: Range<Int>) -> Color {
            var wr = 0.0, wg = 0.0, wb = 0.0, wsum = 0.0     // saturation-weighted
            var ar = 0.0, ag = 0.0, ab = 0.0, an = 0.0        // plain-average fallback
            for y in topStart..<h {
                for x in xRange {
                    let i = (y * w + x) * 4
                    let r = Double(buf[i]) / 255, g = Double(buf[i + 1]) / 255, b = Double(buf[i + 2]) / 255
                    let mx = max(r, g, b), mn = min(r, g, b)
                    let sat = mx <= 0 ? 0 : (mx - mn) / mx
                    let weight = sat * sat * mx
                    wr += r * weight; wg += g * weight; wb += b * weight; wsum += weight
                    ar += r; ag += g; ab += b; an += 1
                }
            }
            if wsum > 0.0001 {
                return Color(red: wr / wsum, green: wg / wsum, blue: wb / wsum)
            } else if an > 0 {
                return Color(red: ar / an, green: ag / an, blue: ab / an)
            }
            return .clear
        }

        let left  = dominant(xRange: 0 ..< (w * 45 / 100))
        let right = dominant(xRange: (w * 55 / 100) ..< w)
        return (left, right)
    }
}

extension Color {
    // Muted transform for Fusion-style ambient tint: keep the hue but pull the
    // color toward a soft, desaturated wash so the glow reads as a whisper of
    // color over the charcoal base rather than a vivid spotlight.
    var moonlitMutedForAmbient: Color {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }
        return Color(
            hue: Double(hue),
            saturation: Double(min(saturation * 0.85, 0.70)),
            brightness: Double(min(max(brightness, 0.40), 0.66))
        )
        #else
        return self
        #endif
    }
}

struct FolderGridSection: View {
    let rows: [CatalogRow]
    let onTap: (MetaPreview) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 80), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse")
                .font(.headline).foregroundColor(.white).padding(.horizontal)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(rows) { row in
                    FolderCell(row: row, onTap: onTap)
                }
            }
            .padding(.horizontal)
        }
    }
}

struct FolderCell: View {
    let row: CatalogRow
    let onTap: (MetaPreview) -> Void

    private var isLandscape: Bool {
        row.tileShape == "landscape"
    }

    var body: some View {
        let coverURL: URL? = {
            if let ci = row.coverImage { return URL(string: ci) }
            if let p = row.items.first?.poster { return URL(string: p) }
            return nil
        }()

        Button {
            if let first = row.items.first { onTap(first) }
        } label: {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl)
                    .fill(MoonlitTheme.surfaceElevated)
                    .aspectRatio(2/3, contentMode: .fit)

                if let url = coverURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        }
                    }
                    .aspectRatio(2/3, contentMode: .fit)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl))
                }

                LinearGradient(
                    colors: [.black.opacity(0.75), .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl))
                .aspectRatio(2/3, contentMode: .fit)

                Text(row.title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Catalog Row View

struct CatalogRowView: View {
    let row: CatalogRow
    let onTap: (MetaPreview) -> Void
    var onHeaderTap: (() -> Void)? = nil
    var metrics: ResponsiveMetrics? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { onHeaderTap?() }) {
                HStack {
                    if let titleLogo = row.titleLogo, let url = URL(string: titleLogo) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 24)
                            }
                        }
                    } else if !(row.hideTitle ?? false) {
                        Text(row.title)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MoonlitTheme.textSecondary)
                }
                .padding(.horizontal)
            }
            .buttonStyle(.plain)
            .disabled(onHeaderTap == nil)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(row.items.enumerated()), id: \.element.id) { index, item in
                        let shape = row.tileShape ?? item.posterShape?.rawValue
                        let isLandscape = shape == "landscape"
                        let isSquare = shape == "square"
                        let w = isLandscape ? (metrics?.landscapeWidth ?? 200) : isSquare ? (metrics?.posterWidth ?? 140) : (metrics?.posterWidth ?? 120)
                        let h = isLandscape ? (metrics?.landscapeHeight ?? 112) : isSquare ? (metrics?.posterWidth ?? 140) : (metrics?.posterHeight ?? 180)
                        ContentCard(item: item, row: row, index: index, width: w, height: h)
                            .onTapGesture { onTap(item) }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Continue Watching

struct ContinueWatchingRow: View {
    let items: [ContinueWatchingItem]
    let onTap: (ContinueWatchingItem) -> Void
    var onShowDetail: ((ContinueWatchingItem) -> Void)? = nil
    var metrics: ResponsiveMetrics? = nil

    @EnvironmentObject var profileManager: ProfileManager
    @StateObject private var watchProgressRepo = WatchProgressRepository.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Continue Watching")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MoonlitTheme.textSecondary)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(items) { item in
                        ContinueWatchingCard(item: item,
                                             width: metrics?.continueWatchingWidth ?? 185,
                                             height: metrics?.continueWatchingHeight ?? 104)
                            .onTapGesture { onTap(item) }
                            .contextMenu {
                                if onShowDetail != nil {
                                    Button {
                                        onShowDetail?(item)
                                    } label: {
                                        Label(
                                            item.mediaType == "movie" ? "Movie Details" : "Series Details",
                                            systemImage: item.mediaType == "movie" ? "film" : "tv"
                                        )
                                    }
                                    Divider()
                                }
                                Button {
                                    Task {
                                        guard let profile = profileManager.currentProfile else { return }
                                        await watchProgressRepo.markWatched(
                                            profileId: profile.id,
                                            mediaId: item.mediaId,
                                            mediaType: item.mediaType,
                                            name: item.name,
                                            poster: item.poster
                                        )
                                    }
                                } label: {
                                    Label("Mark as Watched", systemImage: "checkmark.circle")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    Task {
                                        guard let profile = profileManager.currentProfile else { return }
                                        await watchProgressRepo.updateProgress(
                                            profileId: profile.id,
                                            mediaId: item.mediaId,
                                            mediaType: item.mediaType,
                                            positionSeconds: item.resumePositionMs / 1000,
                                            durationSeconds: item.durationMs / 1000,
                                            completed: true,
                                            name: item.name,
                                            poster: item.poster
                                        )
                                    }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 8)
    }
}

struct ContinueWatchingCard: View {
    let item: ContinueWatchingItem
    var width: CGFloat = 240
    var height: CGFloat = 145

    private var imageURL: URL? {
        (item.thumbnail ?? item.poster).flatMap(URL.init)
    }

    /// Minutes remaining based on duration and current progress.
    private var minutesRemaining: Int? {
        guard item.durationMs > 0 else { return nil }
        let remainingMs = item.durationMs * (1.0 - item.progressFraction)
        let mins = Int((remainingMs / 60_000).rounded())
        return mins > 0 ? mins : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .bottom) {
                // Thumbnail / poster / placeholder
                Group {
                    if let url = imageURL {
                        CachedAsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fill)
                            default:
                                cwPlaceholder
                            }
                        }
                    } else {
                        cwPlaceholder
                    }
                }
                .frame(width: width, height: height)
                .clipped()

                // Frosted blur layer — fades in from bottom
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(height: 50)
                    .mask(
                        LinearGradient(
                            colors: [.clear, .black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Dark scrim for text legibility
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 55)

                // Info row
                HStack(spacing: 4) {
                    if let episodeLabel {
                        Text(episodeLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    if let mins = minutesRemaining {
                        Text("\(mins) min left")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 9)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text(item.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
    }

    private var episodeLabel: String? {
        guard let s = item.seasonNumber, let e = item.episodeNumber else { return nil }
        return "S\(s), E\(e)"
    }

    private var cwPlaceholder: some View {
        ZStack {
            Color(white: 0.12)
            VStack(spacing: 6) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.25))
                if !item.name.isEmpty {
                    Text(item.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
        }
    }
}
