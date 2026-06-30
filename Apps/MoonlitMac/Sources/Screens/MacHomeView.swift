import SwiftUI
import MoonlitCore
import AppKit
import OSLog

struct MacHomeView: View {
    let onSelectMedia: (MetaPreview) -> Void
    var onSelectFolder: ((CatalogRow) -> Void)?

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

    @State private var heroIndex = 0
    @State private var isResumingItemId: String?
    @State private var ambientColor: Color = .clear
    @State private var ambientColor2: Color = .clear
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
            for item in row.items.sorted(by: { ($0.popularity ?? 0) > ($1.popularity ?? 0) }) where !seen.contains(item.id) {
                guard taken < 8, candidates.count < 20 else { break }
                seen.insert(item.id)
                candidates.append(item)
                taken += 1
            }
        }
        return candidates
    }

    private var currentHeroBackdropURL: URL? {
        guard featuredItems.indices.contains(heroIndex) else { return nil }
        let item = featuredItems[heroIndex]
        return MacHeroArtworkProvider.shared.heroArtURL(for: item)
            ?? (item.banner ?? item.poster).flatMap(URL.init)
    }

    var body: some View {
        ZStack(alignment: .top) {
            FusionAmbientBackground(
                ambientColor: ambientColor,
                ambientColor2: ambientColor2,
                heroBackdropURL: currentHeroBackdropURL,
                isEnabled: cinematicModeEnabled
            )
            .animation(.easeInOut(duration: 0.9), value: ambientColor)
            .animation(.easeInOut(duration: 0.9), value: ambientColor2)
            .animation(.easeInOut(duration: 0.6), value: currentHeroBackdropURL)
            .animation(.easeInOut(duration: 0.35), value: cinematicModeEnabled)

            ScrollView {
                VStack(spacing: 0) {
                    if !featuredItems.isEmpty {
                        HomeHero(
                            items: featuredItems,
                            currentIndex: $heroIndex,
                            onWatchNow: { item in route(item: item) },
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

                    if !homeRepo.continueWatchingItems.isEmpty {
                        continueWatchingRow
                            .padding(.top, featuredItems.isEmpty ? 96 : 18)
                            .padding(.bottom, 28)
                    }

                    // For You — Personalized Recommendations
                    if !recsService.rows.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("For You")
                                .font(.system(size: 21, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 28)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
                                    ForEach(recsService.rows) { row in
                                        Button {
                                            let catalogRow = CatalogRow(
                                                id: row.id,
                                                title: row.rowTitle,
                                                items: row.items,
                                                tileShape: "landscape",
                                                coverImage: row.coverImage
                                            )
                                            onSelectFolder?(catalogRow)
                                        } label: {
                                            VStack(alignment: .center, spacing: 8) {
                                                ZStack {
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .fill(MoonlitTheme.surfaceElevated)
                                                        .frame(width: 220, height: 124)

                                                    if let url = row.coverImage.flatMap(URL.init) {
                                                        CachedAsyncImage(url: url) { image in
                                                            image.resizable().scaledToFill()
                                                        } placeholder: {
                                                            Color.clear
                                                        }
                                                        .frame(width: 220, height: 124)
                                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                                    }
                                                }

                                                Text(row.rowTitle)
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
                                .padding(.horizontal, 28)
                            }
                        }
                        .padding(.bottom, 20)
                    }

                    if !catalogRepo.catalogRows.isEmpty {
                        LazyVStack(spacing: 30) {
                            ForEach(catalogRepo.catalogRows) { row in
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
                        .padding(.top, featuredItems.isEmpty ? 96 : 24)
                    } else if catalogRepo.isLoading || addonRepo.isLoading {
                        loadingState.padding(.top, 180)
                    }

                    Spacer().frame(height: 48)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .background(MoonlitTheme.background)
        .task {
            guard let profile = profileManager.currentProfile else { return }
            catalogRepo.isLoading = true
            await addonRepo.loadAddons(profileId: profile.id)
            async let continueWatching: Void = homeRepo.loadContinueWatching(profileId: profile.id)
            Task { await recsService.load(profileId: profile.id) }
            await libraryRepo.loadLibrary(profileId: profile.id)
            await reloadCatalogRows(mode: .replaceCache)
            await continueWatching
            warmupContinueWatching()
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
    }

    private var continueWatchingRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue Watching")
                .font(.system(size: 21, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 28)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(homeRepo.continueWatchingItems) { item in
                        ContinueWatchingCard(
                            item: item,
                            isLoading: isResumingItemId == item.mediaId,
                            width: 250,
                            height: 142
                        )
                        .onTapGesture { resumeItem(item) }
                    }
                }
                .padding(.horizontal, 28)
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 18) {
            MacLottieLoadingView(size: 70)
            Text("Loading your collections")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity)
    }

    private func route(item: MetaPreview) {
        if item.id.hasPrefix("folder_") {
            let fallback = CatalogRow(
                id: item.id, title: item.name, items: [],
                tileShape: item.posterShape?.rawValue ?? "poster",
                coverImage: item.poster ?? item.banner
            )
            onSelectFolder?(catalogRepo.allFolderRows[item.id] ?? fallback)
        } else {
            onSelectMedia(item)
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

            guard let stream = await StreamRepository.shared.bestStream(
                for: item.mediaType, id: item.mediaId,
                from: addonRepo.enabledAddons
            ), let url = stream.url else { return }

            openWindow(id: "player", value: PlayerLaunch(
                title: item.name, sourceUrl: url,
                sourceHeaders: stream.behaviorHints?.proxyHeaders?.request,
                logo: item.logo, poster: item.poster,
                episodeThumbnail: item.thumbnail,
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
            collectionRepo.apply(refreshed)
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
                ?? (item.banner ?? item.poster).flatMap(URL.init) else {
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

// MARK: - FusionAmbientBackground

private struct FusionAmbientBackground: View {
    let ambientColor: Color
    let ambientColor2: Color
    let heroBackdropURL: URL?
    let isEnabled: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                MoonlitTheme.background

                if isEnabled, let url = heroBackdropURL {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.clear
                    }
                    .frame(width: geo.size.width, height: geo.size.height * 0.72)
                    .clipped()
                    .scaleEffect(1.1)
                    .blur(radius: 30)
                    .saturation(0.28)
                    .brightness(0.14)
                    .opacity(0.90)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0.0),
                                .init(color: .black, location: 0.50),
                                .init(color: .black.opacity(0.5), location: 0.72),
                                .init(color: .clear, location: 1.0),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .id(url)
                    .transition(.opacity)
                }

                if isEnabled {
                    RadialGradient(
                        stops: [
                            .init(color: ambientColor.opacity(0.75), location: 0.0),
                            .init(color: ambientColor.opacity(0.45), location: 0.30),
                            .init(color: ambientColor.opacity(0.18), location: 0.60),
                            .init(color: .clear, location: 1.0),
                        ],
                        center: .top,
                        startRadius: 0,
                        endRadius: geo.size.height * 0.80
                    )
                    .blur(radius: 28)

                    RadialGradient(
                        colors: [ambientColor2.opacity(0.45), .clear],
                        center: UnitPoint(x: 0.80, y: 0.05),
                        startRadius: 0,
                        endRadius: geo.size.height * 0.50
                    )

                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.0), location: 0.00),
                            .init(color: .black.opacity(0.10), location: 0.30),
                            .init(color: MoonlitTheme.background.opacity(0.60), location: 0.65),
                            .init(color: MoonlitTheme.background, location: 1.00)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Color Extraction Extensions

private extension NSImage {
    func moonlitAmbientColors() -> (Color, Color)? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let ci = CIImage(bitmapImageRep: bitmap) else { return nil }
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
        guard let rgb = NSColor(self).usingColorSpace(.deviceRGB) else { return self }
        let r = rgb.redComponent
        let g = rgb.greenComponent
        let b = rgb.blueComponent

        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        let brightness = maxC

        if delta > 0.001 {
            saturation = delta / maxC
            if r == maxC {
                hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if g == maxC {
                hue = (b - r) / delta + 2
            } else {
                hue = (r - g) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }

        return Color(
            hue: Double(hue),
            saturation: Double(min(max(saturation * 2.2, 0.60), 1.0)),
            brightness: Double(min(max(brightness * 1.3, 0.40), 0.75))
        )
    }
}
