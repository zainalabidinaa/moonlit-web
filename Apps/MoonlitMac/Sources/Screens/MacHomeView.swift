import SwiftUI
import MoonlitCore
import AppKit
import OSLog

struct MacHomeView: View {
    let onSelectMedia: (MetaPreview) -> Void
    var onSelectFolder: ((CatalogRow) -> Void)?
    var onSelectGenre: ((String, MediaType) -> Void)? = nil
    var onSelectLanguage: ((String, String) -> Void)? = nil
    var initialCategory: HomeCategoryFilter = .featured

    @EnvironmentObject var profileManager: ProfileManager
    @Environment(\.openWindow) private var openWindow
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

    @State private var heroIndex = 0
    @State private var isResumingItemId: String?
    @State private var categoryState: HomeCategoryState

    /// Temporarily hides the "For You" personalized row on Home. Flip to `true`
    /// to bring it back — the RecommendationsService pipeline stays intact.
    private let showForYouSection = false

    init(
        onSelectMedia: @escaping (MetaPreview) -> Void,
        onSelectFolder: ((CatalogRow) -> Void)? = nil,
        onSelectGenre: ((String, MediaType) -> Void)? = nil,
        onSelectLanguage: ((String, String) -> Void)? = nil,
        initialCategory: HomeCategoryFilter = .featured
    ) {
        self.onSelectMedia = onSelectMedia
        self.onSelectFolder = onSelectFolder
        self.onSelectGenre = onSelectGenre
        self.onSelectLanguage = onSelectLanguage
        self.initialCategory = initialCategory
        _categoryState = State(initialValue: HomeCategoryState(category: initialCategory))
    }

    private var categoryGenres: [String] {
        availableHomeGenres(in: catalogRepo.catalogRows, category: categoryState.category)
    }

    /// True on the dedicated Movies / Series nav tabs, where the primary
    /// Featured/Movies/Shows selector would just duplicate the top nav.
    private var isDedicatedMediaTab: Bool {
        initialCategory != .featured
    }

    private var browseTitle: String? {
        switch initialCategory {
        case .movies: return "Browse Movies"
        case .shows: return "Browse Series"
        case .featured: return nil
        }
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

    private let homeGenres: [String] = [
        "Action", "Adventure", "Thriller", "Crime", "Drama",
        "Romance", "Mystery", "Sci-Fi", "Fantasy", "Horror",
        "Comedy", "Family", "Animation", "Western", "War",
        "History", "Documentary", "Music",
    ]

    private let homeLanguages: [MacLanguageData] = [
        .init(iso: "ko", name: "Korean", endonym: "한국어", hue: 25),
        .init(iso: "ja", name: "Japanese", endonym: "日本語", hue: 350),
        .init(iso: "es", name: "Spanish", endonym: "Español", hue: 60),
        .init(iso: "fr", name: "French", endonym: "Français", hue: 260),
        .init(iso: "zh", name: "Chinese", endonym: "中文", hue: 10),
        .init(iso: "hi", name: "Indian", endonym: "हिन्दी", hue: 300),
        .init(iso: "de", name: "German", endonym: "Deutsch", hue: 40),
        .init(iso: "it", name: "Italian", endonym: "Italiano", hue: 145),
        .init(iso: "pt", name: "Portuguese", endonym: "Português", hue: 130),
        .init(iso: "tr", name: "Turkish", endonym: "Türkçe", hue: 200),
        .init(iso: "sv", name: "Swedish", endonym: "Svenska", hue: 230),
        .init(iso: "da", name: "Danish", endonym: "Dansk", hue: 0),
        .init(iso: "no", name: "Norwegian", endonym: "Norsk", hue: 250),
        .init(iso: "ru", name: "Russian", endonym: "Русский", hue: 340),
        .init(iso: "pl", name: "Polish", endonym: "Polski", hue: 170),
        .init(iso: "th", name: "Thai", endonym: "ไทย", hue: 320),
        .init(iso: "nl", name: "Dutch", endonym: "Nederlands", hue: 80),
        .init(iso: "ar", name: "Arabic", endonym: "العربية", hue: 165),
    ]
    @AppStorage("moonlit.cinematicModeEnabled") private var cinematicModeEnabled = true

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
            for item in row.items.sorted(by: { ($0.popularity ?? 0) > ($1.popularity ?? 0) })
                where !seen.contains(item.id) && matchesHomeCategory(item, filter: categoryState) {
                guard taken < 8, candidates.count < 20 else { break }
                seen.insert(item.id)
                candidates.append(item)
                taken += 1
            }
        }
        return candidates
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
            let merged = becauseRows[0]
            result.append(RecommendationRow(
                rowType: "because_you_watched",
                rowTitle: "Because You Watched...",
                coverImage: merged.coverImage,
                sortOrder: merged.sortOrder,
                items: becauseRows.flatMap { $0.items }
            ))
        }
        return result
    }

    @State private var ambientColor: Color = .clear
    @State private var ambientColor2: Color = .clear

    /// The blurred backdrop shown behind the home page — the current hero item's
    /// landscape art. Drives the restored `.heroBackdrop` fusion background.
    /// Backdrop for the current hero. Takes the already-computed `featured` list so `body`
    /// evaluates the expensive `featuredItems` sort/dedup only once per pass.
    private func backdropURL(for featured: [MetaPreview]) -> URL? {
        guard featured.indices.contains(heroIndex) else { return nil }
        let item = featured[heroIndex]
        return MacHeroArtworkProvider.shared.heroArtURL(for: item)
            ?? item.artworkURL(preferring: .landscape)
    }

    var body: some View {
        // Evaluate the expensive featured sort/dedup once per pass, not ~5× — every
        // reference below reuses these locals.
        let featured = featuredItems
        let heroBackdropURL = backdropURL(for: featured)
        return ZStack(alignment: .top) {
            MacFusionAmbientBackground(
                ambientColor: ambientColor,
                ambientColor2: ambientColor2,
                isEnabled: cinematicModeEnabled,
                heroBackdropURL: heroBackdropURL,
                intensity: 1.20,
                style: .heroBackdrop,
                radiusScale: 1.80
            )
            .animation(.easeInOut(duration: 0.9), value: ambientColor)
            .animation(.easeInOut(duration: 0.9), value: ambientColor2)
            .animation(.easeInOut(duration: 0.6), value: heroBackdropURL)
            .animation(.easeInOut(duration: 0.35), value: cinematicModeEnabled)

            ScrollView {
            VStack(spacing: 0) {
                if !featured.isEmpty {
                    HomeHero(
                        items: featured,
                        currentIndex: $heroIndex,
                        onWatchNow: { item in route(item: item) },
                        onMoreInfo: { item in route(item: item) },
                        ambientColor: ambientColor,
                        ambientColor2: ambientColor2
                    )
                        // `.task(id:)` already re-runs whenever heroIndex or cinematic mode
                        // changes, so a separate .onChange(of: heroIndex) would double-fetch.
                        .task(id: "\(heroIndex)-\(cinematicModeEnabled)") {
                            await updateAmbientColorIfNeeded()
                        }

                        if isDedicatedMediaTab {
                            MacCategoryPillsRow(
                                genres: categoryGenres,
                                state: $categoryState,
                                hidePrimaryCategories: isDedicatedMediaTab,
                                browseTitle: browseTitle
                            ) { genre in
                                let kind: MediaType = categoryState.category == .movies ? .movie : .series
                                onSelectGenre?(genre, kind)
                            }
                            .padding(.top, 14)
                            .onChange(of: categoryState) { _, _ in heroIndex = 0 }
                        }
                    }

                    if !homeRepo.continueWatchingItems.isEmpty {
                        continueWatchingRow
                            .padding(.top, featured.isEmpty ? 96 : 26)
                            .padding(.bottom, 38)
                    }

                    // For You — Personalized Recommendations
                    if showForYouSection && !recsService.rows.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("For You")
                                .font(.system(size: 21, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 32)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
                                    ForEach(recsDisplayRows) { displayRow in
                                        Button {
                                            if displayRow.rowType == "because_you_watched" {
                                                let subRows = recsService.rows.filter { $0.rowType == "because_you_watched" }
                                                let catalogRow = CatalogRow(
                                                    id: "because_you_watched_all",
                                                    title: "Because You Watched...",
                                                    items: subRows.flatMap { $0.items },
                                                    tileShape: nil,
                                                    coverImage: displayRow.coverImage
                                                )
                                                onSelectFolder?(catalogRow)
                                            } else {
                                                let catalogRow = CatalogRow(
                                                    id: displayRow.id,
                                                    title: displayRow.rowTitle,
                                                    items: displayRow.items,
                                                    tileShape: nil,
                                                    coverImage: displayRow.coverImage
                                                )
                                                onSelectFolder?(catalogRow)
                                            }
                                        } label: {
                                            VStack(alignment: .center, spacing: 8) {
                                                ZStack {
                                                    RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard)
                                                        .fill(MoonlitTheme.surfaceElevated)
                                                        .frame(width: 220, height: 124)

                                                    if let url = displayRow.coverImage.flatMap(URL.init) {
                                                        CachedAsyncImage(url: url) { image in
                                                            image.resizable().scaledToFill()
                                                        } placeholder: {
                                                            Color.clear
                                                        }
                                                        .frame(width: 220, height: 124)
                                                        .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard))
                                                    }
                                                }

                                                Text(displayRow.rowTitle)
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(.white.opacity(0.85))
                                                    .lineLimit(2)
                                                    .multilineTextAlignment(.center)
                                                    .frame(width: 220)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 32)
                                .padding(.vertical, 8)
                            }
                        }
                        .padding(.bottom, 32)
                    }

                    genreBrowseRow
                        .padding(.top, 20)
                        .padding(.bottom, 24)

                    languageBrowseRow
                        .padding(.bottom, 36)

                    if !catalogRepo.catalogRows.isEmpty {
                        LazyVStack(spacing: 44) {
                            ForEach(visibleCatalogRows) { row in
                                MacCollectionRowContainer(
                                    row: row,
                                    style: rowStyleStore.style(forRowTitle: row.title),
                                    onTap: route(item:),
                                    onHeaderTap: { onSelectFolder?(row) }
                                )
                                .onAppear {
                                    if row.id == catalogRepo.catalogRows.last?.id {
                                        Task {
                                            await catalogRepo.loadMore(rowId: row.id, addons: addonRepo.enabledAddons)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.top, featured.isEmpty ? 96 : 24)
                    } else if catalogRepo.isLoading || addonRepo.isLoading {
                        loadingState.padding(.top, 180)
                    }

                    Spacer().frame(height: 64)
                }
            }
            .ignoresSafeArea(edges: .top)
        }  // ZStack
        .background(MoonlitTheme.background)
        .task {
            guard let profile = profileManager.currentProfile else { return }
            let homeTaskStart = Date()
            NSLog("[Moonlit][Perf] MacHomeView.task started")
            catalogRepo.isLoading = true

            if !(await StartupCoordinator.shared.isPhaseComplete(.phase1)) {
                await StartupCoordinator.shared.startPhase1(
                    profileId: profile.id,
                    collectionRepo: collectionRepo,
                    addonRepo: addonRepo,
                    catalogRepo: catalogRepo,
                    homeRepo: homeRepo,
                    recsService: recsService,
                    libraryRepo: libraryRepo
                )
            }

            await StartupCoordinator.shared.waitForPhase(.phase2)
            NSLog("[Moonlit][Perf] MacHomeView Phase2 awaited in %.2fs", Date().timeIntervalSince(homeTaskStart))

            prefetchHeroLogos(from: await StartupCoordinator.shared.catalogRows)

            catalogRepo.catalogRows = await StartupCoordinator.shared.catalogRows
            catalogRepo.collectionRows = await StartupCoordinator.shared.collectionRows
            let coordRows = await StartupCoordinator.shared.allFolderRows
            var merged = catalogRepo.allFolderRows
            for (key, row) in coordRows {
                if merged[key]?.items.isEmpty ?? true {
                    merged[key] = row
                }
            }
            catalogRepo.allFolderRows = merged
            catalogRepo.isLoading = false
            NSLog("[Moonlit][Perf] MacHomeView rows assigned in %.2fs", Date().timeIntervalSince(homeTaskStart))

            warmupContinueWatching()
            await updateAmbientColorIfNeeded()
            NSLog("[Moonlit][Perf] MacHomeView.task complete in %.2fs", Date().timeIntervalSince(homeTaskStart))

            Task {
                await StartupCoordinator.shared.startPhase3(
                    catalogRepo: catalogRepo,
                    collectionRepo: collectionRepo,
                    addonRepo: addonRepo
                )
            }

            Task {
                await AwardIndex.shared.buildIfNeeded(
                    catalogRepo: catalogRepo,
                    collectionRepo: CollectionRepository.shared,
                    addons: addonRepo.enabledAddons
                )
            }
        }
        .onChange(of: preferenceStore.revision) { _, _ in
            Task { await reloadCatalogRows(mode: .replaceCache) }
        }
        .onChange(of: rowStyleStore.revision) { _, _ in
            Task { await reloadCatalogRows(mode: .replaceCache) }
        }
        .onChange(of: heroStore.revision) { _, _ in
            heroIndex = 0
        }
        .onChange(of: watchProgressRepo.watchedItems.count) { _, _ in
            // Watched state changed somewhere (detail page eye toggle, context
            // menu, finished playback) — re-evaluate the Continue Watching row
            // so finished cards flip to Up Next / Upcoming immediately.
            guard let profile = profileManager.currentProfile else { return }
            Task { await homeRepo.advanceContinueWatching(profileId: profile.id) }
        }
    }

    private var continueWatchingRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue Watching")
                .font(.system(size: 21, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 32)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(homeRepo.continueWatchingItems) { item in
                        ContinueWatchingCard(
                            item: item,
                            isLoading: isResumingItemId == item.mediaId,
                            width: 250,
                            height: 142,
                            onMarkWatched: { markContinueWatchingItemWatched(item) },
                            onShowDetail: { showDetail(for: item) },
                            onRemove: { Task { await homeRepo.removeFromContinueWatching(item) } }
                        )
                        .onTapGesture { resumeItem(item) }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 6)
            }
            // Don't shear the hover halo off at the row bounds.
            .scrollClipDisabled()
        }
    }

    private var loadingState: some View {
        MacLoadingView(size: 44)
            .frame(maxWidth: .infinity)
    }

    private var genreBrowseRow: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Browse by Genre")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 32)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 20) {
                    ForEach(homeGenres, id: \.self) { genre in
                        MacGenreTile(
                            name: genre,
                            onTap: {
                                onSelectGenre?(genre, .movie)
                            }
                        )
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 6)
            }
        }
    }

    private var languageBrowseRow: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Browse by Language")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 32)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 20) {
                    ForEach(homeLanguages, id: \.iso) { lang in
                        MacLanguageTile(
                            iso: lang.iso,
                            name: lang.name,
                            endonym: lang.endonym,
                            hue: lang.hue,
                            onTap: {
                                onSelectLanguage?(lang.iso, lang.name)
                            }
                        )
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 6)
            }
        }
    }

    private func route(item: MetaPreview) {
        if item.id.hasPrefix("folder_") {
            let fallback = CatalogRow(
                id: item.id, title: item.name, items: [],
                tileShape: item.posterShape?.rawValue ?? "poster",
                coverImage: item.artworkString(preferring: .portrait),
                heroBackdrop: item.backdrop
            )
            onSelectFolder?(catalogRepo.allFolderRows[item.id] ?? fallback)
        } else {
            onSelectMedia(item)
        }
    }

    private func showDetail(for item: ContinueWatchingItem) {
        let type: MediaType = item.mediaType == "movie" ? .movie : .series
        onSelectMedia(MetaPreview(
            id: item.parentMediaId ?? item.mediaId,
            type: type,
            name: item.name,
            poster: item.poster,
            logo: item.logo
        ))
    }

    private func markContinueWatchingItemWatched(_ item: ContinueWatchingItem) {
        guard let profile = profileManager.currentProfile else { return }
        Task {
            await watchProgressRepo.markWatched(
                profileId: profile.id,
                mediaId: item.mediaId,
                mediaType: item.mediaType,
                name: item.name,
                poster: item.poster,
                season: item.seasonNumber,
                episode: item.episodeNumber
            )
            // Marking watched advances the card in place (Up Next / Upcoming),
            // . Removing the card is its own separate action.
            await homeRepo.advanceContinueWatching(profileId: profile.id)
        }
    }

    private func resumeItem(_ item: ContinueWatchingItem) {
        guard isResumingItemId == nil else { return }
        isResumingItemId = item.mediaId
        Task {
            defer { isResumingItemId = nil }
            guard let profile = profileManager.currentProfile else { return }
            let decodedId = item.mediaId.removingPercentEncoding ?? item.mediaId
            let cachedSource = [decodedId, item.parentMediaId]
                .compactMap { $0 }
                .lazy
                .compactMap { LastPlaybackSourceStore.shared.source(profileId: profile.id, mediaId: $0) }
                .first

            if let cachedSource {
                openWindow(id: "player", value: PlayerLaunch(
                    title: item.name,
                    sourceUrl: cachedSource.sourceUrl,
                    sourceHeaders: cachedSource.sourceHeaders,
                    logo: item.logo, poster: item.poster,
                    episodeThumbnail: item.thumbnail,
                    background: item.background,
                    seasonNumber: item.seasonNumber,
                    episodeNumber: item.episodeNumber,
                    streamTitle: cachedSource.streamTitle ?? item.episodeTitle,
                    providerName: cachedSource.providerName,
                    contentType: item.mediaType == "movie" ? .movie : .series,
                    videoId: decodedId,
                    parentMetaId: item.parentMediaId,
                    parentMetaType: item.parentMediaId == nil ? nil : item.mediaType,
                    initialPositionMs: item.resumePositionMs,
                    subtitles: nil
                ))
                return
            }

            let prefer4K = PlaybackQualityPreferenceStore.shared.prefers4K(profileId: profile.id)
            guard let stream = await StreamRepository.shared.bestStream(
                for: item.mediaType, id: item.mediaId,
                from: addonRepo.enabledAddons,
                prefer4K: prefer4K,
                preferredAudioLanguage: VideoPlayerPreferenceStore.shared.preferredAudioLanguage
            ), let url = stream.url else { return }

            openWindow(id: "player", value: PlayerLaunch(
                title: item.name, sourceUrl: url,
                sourceHeaders: stream.behaviorHints?.proxyHeaders?.request,
                logo: item.logo, poster: item.poster,
                episodeThumbnail: item.thumbnail,
                background: item.background,
                seasonNumber: item.seasonNumber,
                episodeNumber: item.episodeNumber,
                streamTitle: stream.displayName,
                providerName: stream.addonName,
                contentType: item.mediaType == "movie" ? .movie : .series,
                videoId: decodedId,
                parentMetaId: item.parentMediaId,
                parentMetaType: item.parentMediaId == nil ? nil : item.mediaType,
                initialPositionMs: item.resumePositionMs,
                subtitles: stream.subtitles
            ))
        }
    }

    private func warmupContinueWatching() {
        let addons = addonRepo.enabledAddons
        guard !homeRepo.continueWatchingItems.isEmpty, !addons.isEmpty else { return }
        for item in homeRepo.continueWatchingItems.prefix(5) {
            Task {
                await StreamWarmupRepository.shared.warmup(type: item.mediaType, id: item.mediaId, addons: addons)
            }
        }
    }

    private func prefetchHeroLogos(from rows: [CatalogRow]? = nil) {
        let source = rows ?? catalogRepo.catalogRows
        let topItems = source.prefix(3).flatMap(\.items)
        let logoURLs = topItems.compactMap { $0.logo.flatMap(URL.init) }
        for url in logoURLs {
            Task.detached(priority: .background) {
                _ = await MoonlitImageCache.image(for: url)
            }
        }
    }

    private func reloadCatalogRows(mode: CatalogReloadMode = .preserveCacheOnEmpty) async {
        let collectionsChanged = await loadGlobalOrganizer()
        guard collectionsChanged || catalogRepo.catalogRows.isEmpty else { return }
        if collectionRepo.collections.isEmpty {
            await catalogRepo.loadAllCatalogs(addons: addonRepo.enabledAddons)
        } else {
            await catalogRepo.loadFromCollections(
                collectionRepo: collectionRepo,
                addons: addonRepo.enabledAddons,
                mode: mode
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
        Task {
            let logger = Logger(subsystem: "ai.moonlit", category: "MacHomeView")
            guard let refreshed = await CollectionOrganizerStore.shared.refresh(
                remoteURL: MoonlitConfig.homeOrganizerRemoteURL.flatMap(URL.init)
            ) else {
                logger.warning("home-organizer background refresh failed")
                return
            }
            let oldCount = collectionRepo.collections.count
            // Merge onto the bundled/cached layout — applying the raw remote
            // response drops bundle-only collections and their tab flags.
            collectionRepo.apply(CollectionRepository.mergeByName(base: organized, overlay: refreshed))
            logger.info("home-organizer applied: \(collectionRepo.collections.count) collections (was \(oldCount))")
            guard !collectionRepo.collections.isEmpty else { return }
            await catalogRepo.loadFromCollections(
                collectionRepo: collectionRepo,
                addons: addonRepo.enabledAddons
            )
            logger.info("home-organizer rows loaded: \(self.catalogRepo.catalogRows.count) rows")
        }
        return collectionRepo.collections.count != before || !collectionRepo.collections.isEmpty
    }

    // MARK: - Color Extraction

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
            // Image decode + vImage box-blur/peak detection are CPU-heavy; run them off
            // the main actor and hop back only to assign the @State colors.
            let colors: (Color, Color)? = await Task.detached(priority: .userInitiated) {
                guard let image = NSImage(data: data),
                      let (c1, c2) = image.moonlitAmbientColors() else { return nil }
                return (c1.moonlitBoostedForAmbient, c2.moonlitBoostedForAmbient)
            }.value
            guard let colors else { return }
            ambientColor = colors.0
            ambientColor2 = colors.1
        } catch {
            ambientColor = .clear
            ambientColor2 = .clear
        }
    }
}

private struct MacLanguageData {
    let iso: String
    let name: String
    let endonym: String
    let hue: Double
}

