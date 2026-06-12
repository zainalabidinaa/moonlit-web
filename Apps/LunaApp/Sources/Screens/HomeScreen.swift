import SwiftUI
import UIKit
import CoreImage
import LunaCore

struct HomeScreen: View {
    @EnvironmentObject var profileManager: ProfileManager
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
    @State private var selectedFolder: CatalogRow? = nil
    @State private var showFolder = false
    @State private var playerLaunch: PlayerLaunch?
    @State private var streamSelectionLaunch: PlayerLaunch?
    @State private var ambientColor: Color = .clear
    @AppStorage("luna.cinematicModeEnabled") private var cinematicModeEnabled = false

    private let mainRowNames: Set<String> = [
        "Popular Movies", "Popular TV Shows",
        "Trending Movies", "Trending TV Shows"
    ]

    private var featuredItems: [MetaPreview] {
        let allRows = catalogRepo.catalogRows
        let heroRows: [CatalogRow]
        if heroStore.rowOrder.isEmpty {
            // Default: main rows in natural order
            heroRows = allRows.filter { mainRowNames.contains($0.title) }
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
            // Fall back to default rows when all hero-configured rows are disabled
            heroRows = computed.isEmpty ? allRows.filter { mainRowNames.contains($0.title) } : computed
        }
        // Respect hero management row priority: earlier rows contribute first.
        // Cap per row so a single row can't fill the whole carousel.
        let perRowCap = 3
        let totalCap = 10
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

    private var currentHeroBackdropURL: URL? {
        guard featuredItems.indices.contains(heroIndex) else { return nil }
        let item = featuredItems[heroIndex]
        return (item.banner ?? item.poster).flatMap(URL.init)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let metrics = ResponsiveMetrics(for: geo.size.width)
                ZStack {
                    FusionAmbientBackground(
                        ambientColor: ambientColor,
                        heroBackdropURL: currentHeroBackdropURL,
                        isEnabled: cinematicModeEnabled,
                        screenWidth: geo.size.width,
                        screenHeight: geo.size.height
                    )
                    .animation(.easeInOut(duration: 0.9), value: ambientColor)
                    .animation(.easeInOut(duration: 0.6), value: currentHeroBackdropURL)
                    .animation(.easeInOut(duration: 0.35), value: cinematicModeEnabled)

                    ScrollView {
                        VStack(spacing: 0) {
                            if !featuredItems.isEmpty {
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
                        metrics: metrics
                        )
                        .padding(.top, 16)
                    }

                    if !catalogRepo.catalogRows.isEmpty {
                        LazyVStack(spacing: 28) {
                            ForEach(catalogRepo.catalogRows) { row in
                                CollectionRowContainer(row: row, style: rowStyleStore.style(forRowTitle: row.title), onTap: { item in
                                    if item.id.hasPrefix("folder_") {
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
                                                addons: addonRepo.enabledAddons
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
                    }

                    Spacer().frame(height: 32)
                }
            }
            .refreshable {
                guard let profile = profileManager.currentProfile else { return }
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
            .navigationDestination(isPresented: $showFolder) {
                if let folder = selectedFolder {
                    FolderScreen(row: folder)
                }
            }
            .fullScreenCover(item: $playerLaunch) { launch in
                PlayerScreen(launch: launch, onDismiss: { playerLaunch = nil })
            }
            .fullScreenCover(item: $streamSelectionLaunch) { launch in
                StreamSelectionScreen(
                    mediaType: launch.contentType,
                    mediaId: launch.videoId,
                    mediaName: launch.title,
                    poster: launch.poster,
                    logo: launch.logo,
                    episodeThumbnail: launch.episodeThumbnail,
                    parentMetaId: launch.parentMetaId,
                    parentMetaType: launch.parentMetaType,
                    seasonNumber: launch.seasonNumber,
                    episodeNumber: launch.episodeNumber,
                    episodeTitle: launch.streamTitle,
                    initialPositionMs: launch.initialPositionMs
                )
            }
            .task {
                guard let profile = profileManager.currentProfile else { return }
                // Show shimmer immediately — isLoading only becomes true inside
                // loadAllCatalogs/loadFromCollections, which means the gap between
                // app launch and the first catalog fetch shows a blank screen.
                catalogRepo.isLoading = true
                await addonRepo.loadAddons(profileId: profile.id)
                async let continueWatching: Void = homeRepo.loadContinueWatching(profileId: profile.id)
                await loadGlobalOrganizer()
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
                    catalogRepo.isLoading = false
                }
                await continueWatching
                warmupContinueWatching()
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

        if StreamAutoplayPreferenceStore.shared.mode(profileId: profile.id) == .manual {
            streamSelectionLaunch = PlayerLaunch(
                title: launch.title,
                sourceUrl: "",
                logo: launch.logo,
                poster: launch.poster,
                episodeThumbnail: launch.episodeThumbnail,
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

    private func reloadCatalogRows() async {
        await loadGlobalOrganizer()
        if collectionRepo.collections.isEmpty {
            await catalogRepo.loadAllCatalogs(addons: addonRepo.enabledAddons)
        } else {
            await catalogRepo.loadFromCollections(
                collectionRepo: collectionRepo,
                addons: addonRepo.enabledAddons
            )
        }
    }

    private func loadGlobalOrganizer() async {
        guard let url = Bundle.main.url(forResource: "home-organizer", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            await collectionRepo.load()
            return
        }
        await collectionRepo.loadOrganizer(
            bundledData: data,
            remoteURL: LunaConfig.homeOrganizerRemoteURL.flatMap(URL.init(string:))
        )
    }

    @MainActor
    private func updateAmbientColorIfNeeded() async {
        guard cinematicModeEnabled,
              featuredItems.indices.contains(heroIndex),
              let item = Optional(featuredItems[heroIndex]),
              let url = (item.banner ?? item.poster).flatMap(URL.init) else {
            ambientColor = .clear
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data),
                  let color = image.lunaDominantColor else { return }
            ambientColor = color.lunaClampedForAmbient
        } catch {
            ambientColor = .clear
        }
    }

}

// MARK: - Folder Grid

private struct FusionAmbientBackground: View {
    let ambientColor: Color
    let heroBackdropURL: URL?
    let isEnabled: Bool
    let screenWidth: CGFloat
    let screenHeight: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            LunaTheme.background

            if isEnabled, let url = heroBackdropURL {
                // Width must be pinned: an unbounded scaledToFill image reports its
                // natural width and inflates the whole screen's layout proposal.
                CachedAsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.clear
                    }
                }
                .frame(width: screenWidth, height: screenHeight * 0.58)
                .clipped()
                .scaleEffect(1.08)
                .blur(radius: 32)
                .saturation(0.85)
                .brightness(-0.12)
                .opacity(0.72)
                .frame(width: screenWidth, height: screenHeight * 0.58, alignment: .top)
                .clipped()
                .id(url)
                .transition(.opacity)
            }

            if isEnabled {
                RadialGradient(
                    colors: [
                        ambientColor.opacity(0.38),
                        ambientColor.opacity(0.18),
                        .clear
                    ],
                    center: .top,
                    startRadius: 0,
                    endRadius: screenHeight * 0.72
                )

                RadialGradient(
                    colors: [
                        ambientColor.opacity(0.16),
                        .clear
                    ],
                    center: UnitPoint(x: 0.82, y: 0.04),
                    startRadius: 0,
                    endRadius: screenHeight * 0.48
                )

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.04), location: 0.00),
                        .init(color: .black.opacity(0.18), location: 0.34),
                        .init(color: LunaTheme.background.opacity(0.68), location: 0.68),
                        .init(color: LunaTheme.background, location: 1.00)
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
    var lunaDominantColor: Color? {
        guard let inputImage = CIImage(image: self) else { return nil }
        let extent = inputImage.extent
        guard let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [
                kCIInputImageKey: inputImage,
                kCIInputExtentKey: CIVector(cgRect: extent)
            ]
        ),
        let outputImage = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        return Color(
            red: Double(bitmap[0]) / 255,
            green: Double(bitmap[1]) / 255,
            blue: Double(bitmap[2]) / 255
        )
    }
}

private extension Color {
    var lunaClampedForAmbient: Color {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }
        return Color(
            hue: Double(hue),
            saturation: Double(min(max(saturation * 0.48, 0.10), 0.28)),
            brightness: Double(min(max(brightness * 0.42, 0.12), 0.24))
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
                    .fill(LunaTheme.surfaceElevated)
                    .aspectRatio(isLandscape ? 16/9 : 2/3, contentMode: .fit)

                if let url = coverURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable()
                                .aspectRatio(contentMode: isLandscape ? .fit : .fill)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .aspectRatio(isLandscape ? 16/9 : 2/3, contentMode: .fit)
                }

                LinearGradient(
                    colors: [.black.opacity(0.75), .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .aspectRatio(isLandscape ? 16/9 : 2/3, contentMode: .fit)

                Text(row.title)
                    .font(.system(size: isLandscape ? 11 : 9, weight: .bold))
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
                        .foregroundColor(LunaTheme.textSecondary)
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
                    .foregroundColor(LunaTheme.textSecondary)
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
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Bottom gradient
                LinearGradient(colors: [.black.opacity(0.55), .clear],
                               startPoint: .bottom, endPoint: .top)
                    .frame(height: height * 0.55)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                // Play button row (above the glass strip)
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(5)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Circle())
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 38)

                // Frosted glass strip at bottom
                VStack(spacing: 0) {
                    Spacer()
                    ZStack {
                        // Glass background
                        if #available(iOS 26, *) {
                            Color.clear
                                .glassEffect(
                                    .regular,
                                    in: UnevenRoundedRectangle(
                                        topLeadingRadius: 0,
                                        bottomLeadingRadius: 12,
                                        bottomTrailingRadius: 12,
                                        topTrailingRadius: 0
                                    )
                                )
                        } else {
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .clipShape(
                                    UnevenRoundedRectangle(
                                        topLeadingRadius: 0,
                                        bottomLeadingRadius: 12,
                                        bottomTrailingRadius: 12,
                                        topTrailingRadius: 0
                                    )
                                )
                        }

                        // Content row
                        HStack(spacing: 4) {
                            if let episodeLabel {
                                Text(episodeLabel)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            Spacer()
                            if let mins = minutesRemaining {
                                Text("\(mins) min left")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    .frame(height: 30)
                }
            }
            .frame(width: width, height: height)

            Text(item.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)

            if let subtitle = cardSubtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)
            }
        }
    }

    private var cardSubtitle: String? {
        if let s = item.seasonNumber, let e = item.episodeNumber {
            let epLabel = formattedEpisodeLabel(season: s, episode: e).replacingOccurrences(of: " · ", with: " ")
            if let title = item.episodeTitle, !title.isEmpty {
                return "\(epLabel) · \(title)"
            }
            return epLabel
        }
        // Movie: show timestamp
        if item.resumePositionMs > 0 {
            let secs = Int(item.resumePositionMs / 1000)
            let h = secs / 3600
            let m = (secs % 3600) / 60
            let s = secs % 60
            let ts = h > 0
                ? String(format: "%d:%02d:%02d", h, m, s)
                : String(format: "%d:%02d", m, s)
            return ts
        }
        return nil
    }

    private var episodeLabel: String? {
        guard let s = item.seasonNumber, let e = item.episodeNumber else { return nil }
        return formattedEpisodeLabel(season: s, episode: e)
    }

    private func formattedEpisodeLabel(season: Int, episode: Int) -> String {
        "S\(String(format: "%02d", season)) · E\(String(format: "%02d", episode))"
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
