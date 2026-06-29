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
    @State private var selectedMedia: MetaPreview?
    @State private var showDetail = false
    @State private var cwDetailTarget: MetaPreview? = nil
    @State private var showCWDetail = false
    @State private var selectedFolder: CatalogRow? = nil
    @State private var showFolder = false
    @State private var selectedGenre: String? = nil
    @State private var showGenre = false
    @State private var showAwards = false
    @State private var playerLaunch: PlayerLaunch?
    @State private var streamSelectionLaunch: PlayerLaunch?
    @State private var showFreeUpgradeAlert = false
    @State private var ambientColor: Color = .clear
    @State private var ambientColor2: Color = .clear
    @AppStorage("moonlit.cinematicModeEnabled") private var cinematicModeEnabled = true
    @AppStorage("moonlit.guestMode") private var guestMode = false

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
            // Default: prefer named rows, fall back to all rows with items
            let named = allRows.filter { mainRowNames.contains($0.title) }
            heroRows = named.isEmpty ? allRows.filter { !$0.items.isEmpty } : named
        } else {
            // Respect saved order and enabled/disabled state
            let enabledOrdered = heroStore.rowOrder
                .filter { heroStore.isEnabled(rowTitle: $0) }
                .compactMap { title in allRows.first { $0.title == title } }
            // Also include any mainRow titles not yet in saved order (new defaults)
            let missing = allRows.filter {
                mainRowNames.contains($0.title) &&
                !heroStore.rowOrder.contains($0.title) &&
                heroStore.isEnabled(rowTitle: $0.title)
            }
            let computed = enabledOrdered + missing
            // Fall back: named rows → any rows with items
            if computed.isEmpty {
                let named = allRows.filter { mainRowNames.contains($0.title) }
                heroRows = named.isEmpty ? allRows.filter { !$0.items.isEmpty } : named
            } else {
                heroRows = computed
            }
        }
        // Cap per row so a single row can't fill the whole carousel.
        let perRowCap = 8
        let totalCap = 20
        var seen = Set<String>()
        var candidates: [MetaPreview] = []
        for row in heroRows {
            let rowItems = row.items
                .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
            var taken = 0
            for item in rowItems where !seen.contains(item.id) {
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

    private var currentHeroBackdropURL: URL? {
        guard featuredItems.indices.contains(heroIndex) else { return nil }
        let item = featuredItems[heroIndex]
        return HeroArtworkProvider.shared.heroArtURL(for: item)
            ?? (item.banner ?? item.poster).flatMap(URL.init)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let metrics = ResponsiveMetrics(for: geo.size.width)
                ZStack {
                    FusionAmbientBackground(
                        ambientColor: ambientColor,
                        ambientColor2: ambientColor2,
                        heroBackdropURL: currentHeroBackdropURL,
                        isEnabled: cinematicModeEnabled,
                        screenWidth: geo.size.width,
                        screenHeight: geo.size.height
                    )
                    .animation(.easeInOut(duration: 0.9), value: ambientColor)
                    .animation(.easeInOut(duration: 0.9), value: ambientColor2)
                    .animation(.easeInOut(duration: 0.6), value: currentHeroBackdropURL)
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

                    if !catalogRepo.catalogRows.isEmpty {
                        LazyVStack(spacing: 28) {
                            ForEach(catalogRepo.catalogRows) { row in
                                CollectionRowContainer(row: row, style: rowStyleStore.style(forRowTitle: row.title), onTap: { item in
                                    if item.id.hasPrefix("folder_"),
                                       let genre = collectionRepo.genreName(forFolderRowId: item.id) {
                                        selectedGenre = genre
                                        showGenre = true
                                    } else if item.id.hasPrefix("folder_"),
                                              collectionRepo.isAwardsFolder(forFolderRowId: item.id) {
                                        showAwards = true
                                    } else if item.id.hasPrefix("folder_") {
                                        selectedFolder = catalogRepo.allFolderRows[item.id] ?? CatalogRow(
                                            id: item.id,
                                            title: item.name,
                                            items: [],
                                            tileShape: item.posterShape?.rawValue ?? "poster",
                                            coverImage: item.poster ?? item.banner
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
                            ShimmerCard(width: 375, height: 200, cornerRadius: 12)
                                .padding(.horizontal)
                            ShimmerCard(width: 120, height: 16, cornerRadius: 4)
                                .padding(.horizontal)
                            HStack(spacing: 12) {
                                ForEach(0..<3, id: \.self) { _ in
                                    ShimmerCard(width: 180, height: 100, cornerRadius: 8)
                                }
                            }
                            .padding(.horizontal)
                            HStack(spacing: 12) {
                                ForEach(0..<4, id: \.self) { _ in
                                    ShimmerCard(width: 105, height: 158, cornerRadius: 8)
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
            .refreshable {
                guard let profile = profileManager.currentProfile else {
                    await loadCatalogRowsForGuest()
                    return
                }
                await reloadCatalogRows()
                await homeRepo.loadContinueWatching(profileId: profile.id)
            }
                }
            }
            .ignoresSafeArea(edges: .top)
            .toolbar {
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
                    GenreHubScreen(genre: genre)
                }
            }
            .navigationDestination(isPresented: $showAwards) {
                AwardsHubScreen()
            }
            .fullScreenCover(item: $playerLaunch) { launch in
                PlayerScreen(launch: launch, onDismiss: { playerLaunch = nil })
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
                    warmupContinueWatching()
                }
            }
        }
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
        collectionRepo.apply(organized)
        // Background-refresh from Supabase — remote layout is authoritative.
        Task {
            guard let refreshed = await CollectionOrganizerStore.shared.refresh(
                remoteURL: MoonlitConfig.homeOrganizerRemoteURL.flatMap(URL.init)
            ) else {
                Logger(subsystem: "ai.moonlit", category: "HomeScreen")
                    .warning("home-organizer background refresh failed")
                return
            }
            collectionRepo.apply(refreshed)
            guard !collectionRepo.collections.isEmpty else { return }
            await catalogRepo.loadFromCollections(
                collectionRepo: collectionRepo,
                addons: catalogAddonsForCurrentMode
            )
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
                ?? (item.banner ?? item.poster).flatMap(URL.init) else {
            ambientColor = .clear
            ambientColor2 = .clear
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data),
                  let (c1, c2) = image.moonlitAmbientColors() else { return }
            ambientColor  = c1.moonlitBoostedForAmbient
            ambientColor2 = c2.moonlitBoostedForAmbient
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

private struct FusionAmbientBackground: View {
    let ambientColor: Color
    let ambientColor2: Color
    let heroBackdropURL: URL?
    let isEnabled: Bool
    let screenWidth: CGFloat
    let screenHeight: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            MoonlitTheme.background

            if isEnabled, let url = heroBackdropURL {
                CachedAsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Color.clear
                    }
                }
                .frame(width: screenWidth, height: screenHeight * 0.72)
                .clipped()
                .scaleEffect(1.1)
                .blur(radius: 30)
                .saturation(0.28)
                .brightness(0.14)
                .opacity(0.90)
                .frame(width: screenWidth, height: screenHeight * 0.72, alignment: .top)
                .clipped()
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black, location: 0.50),
                            .init(color: .black.opacity(0.5), location: 0.72),
                            .init(color: .clear, location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .id(url)
                .transition(.opacity)
            }

            if isEnabled {
                // Primary glow — left-region color, centered at top.
                RadialGradient(
                    stops: [
                        .init(color: ambientColor.opacity(0.75), location: 0.0),
                        .init(color: ambientColor.opacity(0.45), location: 0.30),
                        .init(color: ambientColor.opacity(0.18), location: 0.60),
                        .init(color: .clear, location: 1.0),
                    ],
                    center: .top,
                    startRadius: 0,
                    endRadius: screenHeight * 0.80
                )
                .blur(radius: 28)

                // Accent glow — right-region color, off-center right.
                RadialGradient(
                    colors: [ambientColor2.opacity(0.45), .clear],
                    center: UnitPoint(x: 0.80, y: 0.05),
                    startRadius: 0,
                    endRadius: screenHeight * 0.50
                )

                // Dark overlay: transparent at top, opaque at bottom.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.0),  location: 0.00),
                        .init(color: .black.opacity(0.10), location: 0.30),
                        .init(color: MoonlitTheme.background.opacity(0.60), location: 0.65),
                        .init(color: MoonlitTheme.background, location: 1.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
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
        }
    }
}

private extension UIImage {
    // Samples left and right regions of the top 60% of the image to extract two
    // distinct ambient colors. Avoids dark letterbox bars at the bottom.
    func moonlitAmbientColors() -> (Color, Color)? {
        guard let ci = CIImage(image: self) else { return nil }
        let e = ci.extent
        let topH = e.height * 0.6

        func avgColor(in rect: CGRect) -> Color? {
            guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
                kCIInputImageKey: ci,
                kCIInputExtentKey: CIVector(cgRect: rect)
            ]), let out = filter.outputImage else { return nil }
            var px = [UInt8](repeating: 0, count: 4)
            let ctx = CIContext(options: [.workingColorSpace: kCFNull as Any])
            ctx.render(out, toBitmap: &px, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
            return Color(red: Double(px[0]) / 255, green: Double(px[1]) / 255, blue: Double(px[2]) / 255)
        }

        let leftRect  = CGRect(x: e.minX,                    y: e.minY, width: e.width * 0.45, height: topH)
        let rightRect = CGRect(x: e.minX + e.width * 0.55,   y: e.minY, width: e.width * 0.45, height: topH)

        guard let c1 = avgColor(in: leftRect), let c2 = avgColor(in: rightRect) else { return nil }
        return (c1, c2)
    }
}

private extension Color {
    var moonlitBoostedForAmbient: Color {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }
        return Color(
            hue: Double(hue),
            saturation: Double(min(max(saturation * 2.2, 0.60), 1.0)),
            brightness: Double(min(max(brightness * 1.3, 0.40), 0.75))
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
                RoundedRectangle(cornerRadius: 8)
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
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                LinearGradient(
                    colors: [.black.opacity(0.75), .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
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
