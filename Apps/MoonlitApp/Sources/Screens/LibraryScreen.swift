import SwiftUI
import MoonlitCore

#Preview("Library") {
    LibraryScreen()
        .environmentObject(ProfileManager.shared)
        .preferredColorScheme(.dark)
}

struct LibraryScreen: View {
    @StateObject private var libraryRepo = LibraryRepository.shared
    @StateObject private var addonRepo = AddonRepository.shared
    @StateObject private var likedRepo = LikedRepository.shared
    @StateObject private var upcomingService = UpcomingItemsService.shared
    @StateObject private var traktAuth = TraktAuthService.shared
    @StateObject private var watchProgressRepo = WatchProgressRepository.shared
    @EnvironmentObject var profileManager: ProfileManager

    @State private var watchlistFilter: MediaFilter = .all
    @State private var likedFilter: MediaFilter = .all
    @State private var upcomingFilter: MediaFilter = .all
    @State private var resolvedArtwork: [String: String] = [:]
    @State private var upcomingBackdrops: [String: String] = [:]

    enum MediaFilter: String, CaseIterable {
        case all = "All"
        case movies = "Movies"
        case series = "Series"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    upcomingSection
                    watchlistSection
                    likedSection
                    Spacer().frame(height: 40)
                }
            }
            .background(MoonlitTheme.background)
            .navigationTitle("Library")
#if os(iOS)
            .navigationBarTitleDisplayMode(.large)
#endif
        }
        .task {
            guard let profile = profileManager.currentProfile else { return }
            if addonRepo.enabledAddons.isEmpty {
                await addonRepo.loadAddons(profileId: profile.id)
            }
            await libraryRepo.loadLibrary(profileId: profile.id)
            await watchProgressRepo.loadAll(profileId: profile.id)
            await likedRepo.loadLiked(profileId: profile.id)
            await TraktAuthService.shared.loadToken(profileId: profile.id)
            await upcomingService.refresh(likedItems: likedRepo.likedItems)
            await resolveLibraryArtwork()
            await resolveUpcomingBackdrops()
        }
    }

    // MARK: - Computed

    private var filteredWatchlist: [MoonlitCore.LibraryItem] {
        switch watchlistFilter {
        case .all:    return libraryRepo.libraryItems
        case .movies: return libraryRepo.libraryItems.filter { $0.mediaType == "movie" }
        case .series: return libraryRepo.libraryItems.filter { $0.mediaType != "movie" }
        }
    }

    private var availableLikedItems: [LikedItem] {
        switch likedFilter {
        case .all:    return likedRepo.likedItems
        case .movies: return likedRepo.likedItems.filter { $0.mediaType == "movie" }
        case .series: return likedRepo.likedItems.filter { $0.mediaType != "movie" }
        }
    }

    private var upcomingItems: [LikedItem] {
        let liked = likedRepo.likedItems.filter { upcomingService.isUpcoming($0.mediaId) }
        let traktOnly = upcomingService.traktUpcomingItems.filter { upcomingService.isUpcoming($0.mediaId) }
        let likedTmdbIds = Set(liked.compactMap(\.tmdbId))
        let uniqueTrakt = traktOnly.filter { item in
            guard let tmdbId = item.tmdbId else { return true }
            return !likedTmdbIds.contains(tmdbId)
        }
        let all = liked + uniqueTrakt
        // Filter by type
        let filtered: [LikedItem]
        switch upcomingFilter {
        case .all:    filtered = all
        case .movies: filtered = all.filter { $0.mediaType == "movie" }
        case .series: filtered = all.filter { $0.mediaType != "movie" }
        }
        // Sort earliest to farthest
        return filtered.sorted { a, b in
            let da = upcomingService.upcomingInfo[a.mediaId]?.releaseDate
            let db = upcomingService.upcomingInfo[b.mediaId]?.releaseDate
            switch (da, db) {
            case (let a?, let b?): return a < b
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    }

    // MARK: - Watchlist Section

    private var watchlistSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            librarySectionHeader(title: "Watchlist", count: libraryRepo.libraryItems.count)
            filterChips(selection: $watchlistFilter)

            if filteredWatchlist.isEmpty {
                emptyState(icon: "bookmark", message: "Nothing bookmarked yet.\nTap 🔖 on any title to add it.")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 10)], spacing: 10) {
                    ForEach(filteredWatchlist, id: \.id) { item in
                        watchlistPosterCard(item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private func watchlistPosterCard(_ item: MoonlitCore.LibraryItem) -> some View {
        NavigationLink(destination: DetailScreen(
            mediaId: item.mediaId,
            type: item.mediaType,
            name: item.name ?? item.mediaId
        )) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let url = artworkURL(for: item) {
                        CachedAsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFill()
                            } else {
                                watchlistPlaceholder(item)
                            }
                        }
                    } else {
                        watchlistPlaceholder(item)
                    }
                }
                .frame(width: 100, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl))

                // Watch progress bar
                if let entry = watchProgressRepo.getProgress(mediaId: item.mediaId),
                   entry.progressFraction > 0.02 {
                    VStack(spacing: 0) {
                        Spacer()
                        GeometryReader { geo in
                            Capsule()
                                .fill(MoonlitTheme.accent.opacity(0.9))
                                .frame(width: geo.size.width * entry.progressFraction, height: 3)
                        }
                        .frame(height: 3)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl))
                }
            }
            .frame(width: 100, height: 150)
        }
        .buttonStyle(.plain)
        #if os(tvOS)
        .tvosFocusScale()
        #endif
        .contextMenu {
            Button(role: .destructive) {
                Task {
                    guard let profile = profileManager.currentProfile else { return }
                    await libraryRepo.removeFromLibrary(profileId: profile.id, mediaId: item.mediaId)
                }
            } label: {
                Label("Remove from Watchlist", systemImage: "bookmark.slash")
            }
        }
    }

    @ViewBuilder
    private func watchlistPlaceholder(_ item: MoonlitCore.LibraryItem) -> some View {
        Color.white.opacity(0.05)
            .overlay(
                Image(systemName: item.mediaType == "movie" ? "film" : "tv")
                    .foregroundColor(MoonlitTheme.textTertiary)
            )
    }

    // MARK: - Liked Section

    private var likedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            librarySectionHeader(systemImage: "heart.fill", imageTint: Color(red: 1, green: 0.25, blue: 0.35), title: "Liked", count: availableLikedItems.count)
            filterChips(selection: $likedFilter)

            if availableLikedItems.isEmpty {
                emptyState(icon: "heart", message: "Nothing liked yet.\nTap the heart button on any title to add it.")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 10)], spacing: 10) {
                    ForEach(availableLikedItems, id: \.id) { item in
                        likedPosterCard(item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private func likedPosterCard(_ item: LikedItem) -> some View {
        NavigationLink(destination: DetailScreen(
            mediaId: item.mediaId,
            type: item.mediaType,
            name: item.name
        )) {
            Group {
                let posterURLStr = PosterService.posterURL(forImdbId: item.mediaId) ?? item.poster
                if let urlStr = posterURLStr, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        } else {
                            Color.white.opacity(0.05)
                        }
                    }
                } else {
                    Color.white.opacity(0.05)
                }
            }
            .frame(width: 100, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl))
        }
        .buttonStyle(.plain)
        #if os(tvOS)
        .tvosFocusScale()
        #endif
        .contextMenu {
            Button(role: .destructive) {
                Task { await likedRepo.removeLiked(mediaId: item.mediaId, profileId: profileManager.currentProfile?.id ?? "") }
            } label: {
                Label("Remove from Liked", systemImage: "heart.slash")
            }
        }
    }

    // MARK: - Upcoming Section

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            librarySectionHeader(systemImage: "calendar", imageTint: MoonlitTheme.accent, title: "Upcoming", count: upcomingItems.count)
            filterChips(selection: $upcomingFilter)

            if upcomingItems.isEmpty {
                emptyState(icon: "calendar", message: "No upcoming releases.\nLike a movie or series to track it.")
            } else { upcomingList }
        }
    }

    private var upcomingList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(upcomingItems, id: \.id) { item in
                    NavigationLink(destination: DetailScreen(
                        mediaId: item.mediaId,
                        type: item.mediaType,
                        name: item.name
                    )) {
                        upcomingLandscapeCard(item)
                    }
                    .buttonStyle(.plain)
                    #if os(tvOS)
                    .tvosFocusScale()
                    #endif
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private func upcomingLandscapeCard(_ item: LikedItem) -> some View {
        let cardW: CGFloat = 248
        let cardH: CGFloat = 140
        let backdropURL: URL? = upcomingBackdrops[item.mediaId].flatMap(URL.init)
            ?? (PosterService.posterURL(forImdbId: item.mediaId)).flatMap(URL.init)
            ?? item.poster.flatMap(URL.init)
        let isMovie = item.mediaType == "movie"
        let daysLabel = upcomingService.daysLabel(for: item.mediaId)
        let episodeLabel = upcomingService.episodeLabel(for: item.mediaId)

        return ZStack(alignment: .bottomLeading) {
            // Backdrop image — fill the frame and clip the overflow so portrait posters
            // don't bleed past the card.
            Group {
                if let url = backdropURL {
                    CachedAsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        } else {
                            upcomingCardPlaceholder(item)
                        }
                    }
                } else {
                    upcomingCardPlaceholder(item)
                }
            }
            .frame(width: cardW, height: cardH)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.35), .black.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: cardW, height: cardH)

            // Title + type / episode pills
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    upcomingPill(isMovie ? "Movie" : "Series",
                                 systemImage: isMovie ? "film.fill" : "tv.fill")
                    if !isMovie, let episodeLabel {
                        upcomingPill(episodeLabel)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 11)
        }
        .frame(width: cardW, height: cardH)
        .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        // Prominent "how soon" badge, top-right.
        .overlay(alignment: .topTrailing) {
            if let daysLabel {
                HStack(spacing: 3) {
                    Image(systemName: "calendar")
                        .font(.system(size: 9, weight: .bold))
                    Text(daysLabel)
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(MoonlitTheme.accent, in: Capsule())
                .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                .padding(8)
            }
        }
    }

    private func upcomingPill(_ text: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 8, weight: .bold))
            }
            Text(text).font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(.white.opacity(0.92))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
    }

    private func upcomingCardPlaceholder(_ item: LikedItem) -> some View {
        ZStack {
            Color.white.opacity(0.05)
            Image(systemName: item.mediaType == "movie" ? "film" : "tv")
                .font(.title2)
                .foregroundColor(MoonlitTheme.textTertiary)
        }
    }

    // MARK: - Shared helpers

    private func librarySectionHeader(
        systemImage: String? = nil,
        imageTint: Color = .white,
        title: String,
        count: Int
    ) -> some View {
        HStack(spacing: 6) {
            if let icon = systemImage {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(imageTint)
            }
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundColor(.white)
            Text("(\(count))")
                .font(.subheadline)
                .foregroundColor(MoonlitTheme.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private func filterChips(selection: Binding<MediaFilter>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MediaFilter.allCases, id: \.self) { filter in
                    Button { selection.wrappedValue = filter } label: {
                        Text(filter.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(selection.wrappedValue == filter ? .white : MoonlitTheme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(selection.wrappedValue == filter ? Color.white.opacity(0.22) : Color.white.opacity(0.08))
                            .cornerRadius(20)
                            #if os(tvOS)
                            .tvosFocusScale()
                            #endif
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundColor(Color.white.opacity(0.2))
            Text(message)
                .font(.subheadline)
                .foregroundColor(MoonlitTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding()
    }

    // MARK: - Artwork resolution (preserved from original)

    private func artworkURL(for item: MoonlitCore.LibraryItem) -> URL? {
        // Prefer btttr poster for any IMDb-id item — always up to date.
        if let bttr = PosterService.posterURL(forImdbId: item.mediaId) { return URL(string: bttr) }
        if let resolved = resolvedArtwork[item.mediaId] { return URL(string: resolved) }
        guard let poster = item.poster, !isStaleSavedArtwork(poster) else { return nil }
        return URL(string: poster)
    }

    private func isStaleSavedArtwork(_ url: String) -> Bool {
        let l = url.lowercased()
        // btttr.cc is now our primary poster source — never stale.
        return l.contains("betterposters")
            || l.contains("ratingposterdb") || l.contains("api.top-posters.com")
    }

    private func resolveLibraryArtwork() async {
        let items = libraryRepo.libraryItems
        let movieAddons = addonRepo.findAddonWithMetaResource(type: "movie")
        let seriesAddons = addonRepo.findAddonWithMetaResource(type: "series")
        await withTaskGroup(of: (String, String?).self) { group in
            for item in items {
                let addons = item.mediaType == "movie" ? movieAddons : seriesAddons
                group.addTask {
                    let detail = await MetaRepository.shared.fetchDetail(
                        type: item.mediaType,
                        id: item.mediaId,
                        addons: addons
                    )
                    return (item.mediaId, detail?.rawPosterUrl ?? detail?.poster)
                }
            }
            var artwork = resolvedArtwork
            for await (mediaId, poster) in group {
                if let poster, !poster.isEmpty { artwork[mediaId] = poster }
            }
            resolvedArtwork = artwork
        }
    }

    private func resolveUpcomingBackdrops() async {
        guard let apiKey = MetadataIntegrationStore.shared.effectiveTMDBAPIKey else { return }
        let items = upcomingItems
        guard !items.isEmpty else { return }
        var backdrops: [String: String] = upcomingBackdrops
        await withTaskGroup(of: (String, String?).self) { group in
            for item in items {
                guard let tmdbId = item.tmdbId else { continue }
                let type = item.mediaType == "movie" ? "movie" : "tv"
                let mediaId = item.mediaId
                group.addTask {
                    guard let url = URL(string: "https://api.themoviedb.org/3/\(type)/\(tmdbId)?api_key=\(apiKey)"),
                          let (data, _) = try? await URLSession.shared.data(from: url),
                          let json = try? JSONDecoder().decode(TMDBBackdropResponse.self, from: data),
                          let path = json.backdropPath, !path.isEmpty else { return (mediaId, nil) }
                    return (mediaId, "https://image.tmdb.org/t/p/w780\(path)")
                }
            }
            for await (mediaId, url) in group {
                if let url { backdrops[mediaId] = url }
            }
        }
        upcomingBackdrops = backdrops
    }
}

#if os(tvOS)
private struct TVFocusModifier: ViewModifier {
    @Environment(\.isFocused) var isFocused
    func body(content: Content) -> some View {
        content
            .scaleEffect(isFocused ? 1.03 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isFocused)
    }
}

private extension View {
    func tvosFocusScale() -> some View {
        modifier(TVFocusModifier())
    }
}
#endif

private struct TMDBBackdropResponse: Decodable {
    let backdropPath: String?
    enum CodingKeys: String, CodingKey { case backdropPath = "backdrop_path" }
}
