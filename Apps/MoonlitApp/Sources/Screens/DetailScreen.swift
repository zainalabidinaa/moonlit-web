import SwiftUI
import MoonlitCore

struct DetailScreen: View {
    let mediaId: String
    let type: String
    let name: String

    @StateObject private var metaRepo = MetaRepository.shared
    @StateObject private var libraryRepo = LibraryRepository.shared
    @StateObject private var watchedRepo = WatchProgressRepository.shared
    @EnvironmentObject var profileManager: ProfileManager
    @StateObject private var addonRepo = AddonRepository.shared

    @State private var selectedMedia: MetaPreview?
    @State private var selectedSeasonId: String? = nil
    @State private var selectedEpisode: MetaVideo? = nil
    @State private var selectedSeasonNumber: Int? = nil
    @State private var selectedEpisodeNumber: Int? = nil
    @State private var selectedPlaybackMediaId: String? = nil
    @State private var selectedInitialPositionMs: Double? = nil
    @State private var playerLaunch: PlayerLaunch?
    @State private var streamSelectionLaunch: PlayerLaunch?
    @State private var trailerLink: URL?
    @State private var moreLikeThisItems: [MetaPreview] = []
    @State private var streailerTrailers: [Trailer] = []
    @State private var isLiked = false
    @State private var descriptionSheet: DescriptionSheetData?
    @State private var showGuestStreamingAlert = false
    @State private var autoScrollEpisodeID: String?
    @State private var ambientColor: Color = .clear
    @State private var ambientColor2: Color = .clear
    @State private var detailScroll: CGFloat = 0
    @State private var detailScrollBase: CGFloat? = nil
    /// Season awaiting a mark/unmark confirmation. Non-nil drives the dialog.
    @State private var seasonWatchPrompt: SeasonWatchPrompt?
    @StateObject private var likedRepo = LikedRepository.shared
    @StateObject private var awardsMeta = AwardsMetadataService.shared
    @ObservedObject private var heroArtwork = HeroArtworkProvider.shared
    @State private var resolvedBackdrop: String?
    /// Source for the ambient page colors — the textless poster the hero
    /// actually renders, falling back to the addon backdrop until it resolves.
    private var effectiveBackdrop: String? { resolvedBackdrop ?? metaRepo.detail?.background }
    @AppStorage("moonlit.guestMode") private var guestMode = false
    @AppStorage("moonlit.cinematicModeEnabled") private var cinematicModeEnabled = true

    private static let streailerBaseURL = "https://streailer.elfhosted.com/%7B%22language%22%3A%22en-US%22%2C%22externalLink%22%3Afalse%2C%22showRecap%22%3Afalse%2C%22onlyRecaps%22%3Afalse%7D"
    private static let mltBaseURL = "https://bbab4a35b833-more-like-this.baby-beamup.club/%7B%22iv%22%3A%226eccbcc6a9db21bd4cb1fef5f30b4892%22%2C%22salt%22%3Anull%2C%22authTag%22%3A%22017bc87cc819a77554085544340d58ee%22%2C%22data%22%3A%22d270093abcf6a558d135729ff8b3b1f799809a1b7bcf8e42b77a79357857b567587078990ef4e3668c550ee8b53b3219b6b9d39a201b768bf39dd3516762994348df48afdf938ad363cdf3bf2c620fb2014ee02826dac096aaa4e23da726f2b5de5467874ff0a51a87567354a45e23daf41cddbac084ed0f72000bf89b4d66acbf6908349fa70d0106a0e803001766e4a8635343e348c523061beabaa612a054ca63730898aa357d37af353db6ebf07dc415bb4de0064ef88f13c308a8bf8a64c620b9433575b7dd6a3b135d2aa0db02a82e434a0a713dd00e2c23efe2938ffcb5bcefe24fb2b7b70e2d0749029c88e2f9c4eb72af2cdd7162a706fccd56cc4f81d470fd9d3518f8d6d0d79943de3bafb4bc83de616f236f4e111bfad494bdb50426351aaaeb7df0573f4dc195c87f18094466b490bb9c8d9547ed3a82f2a0930cd55d177b03df493591470b75f4c7fe179b4725e40aafc21cfe7593e0d72dc825598b2c083854a60c284c0582f75736904a8b35842cc44872c8c294b9bec96421288ab2d80f6cb5c824eec1aff65e485193083a66da91022dffa55f9059b986ad65e2f09902648fc197a076773f29136b2c1df1b2af9e7334b3c0285d397602abc0ffd6bcdecf5d5318093dce2b8b2922d8ac1215e8ec4385e3eef554f21f6e49fa1fd6d37544530f3dd41a3bcd2f3febe53dd3a3390a6ce5a4748fa600a9466b425901e5e05500c941882ecce958e40f30256c02eedfccc5f7b630b214c9e61795bdba0481abd9160b901a014ac4d4cddf57a83ca8529ce5c30bf368ff8740ce7b757313cce9f0b73567897250ab333bfa%22%7D"
    @Environment(\.openURL) private var openURL
    #if os(tvOS)
    @Environment(\.isFocused) var isFocused
    #endif

    private let heroHeight: CGFloat = 520
    private let contentRailInset: CGFloat = 16

    private var isSyntheticFolderId: Bool {
        mediaId.hasPrefix("folder_")
    }

    private var staleDetailLabel: String {
        guard let updatedAt = metaRepo.cachedDetailUpdatedAt else {
            return "Showing saved details"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Last updated \(formatter.localizedString(for: updatedAt, relativeTo: Date()))"
    }

    var body: some View {
        ScrollView {
            if let detail = metaRepo.detail {
                VStack(alignment: .leading, spacing: 0) {

                    // ── BACKDROP ──────────────────────────────────────────
                    // Mirrors macOS: the artwork fades to transparent so the ambient
                    // page layer carries through the bottom of the hero.
                    GeometryReader { geo in
                        let topInset = geo.safeAreaInsets.top

                        ZStack(alignment: .bottom) {
                            heroPoster(for: detail, width: geo.size.width, height: heroHeight + topInset)
                                .mask(heroArtworkMask)

                            // Tagline, centered logo, then a single metadata line.
                            VStack(spacing: 10) {
                                if let tagline = detail.tagline, !tagline.isEmpty {
                                    Text(tagline)
                                        .font(.system(size: 10, weight: .medium))
                                        .tracking(2.6)
                                        .textCase(.uppercase)
                                        .foregroundColor(.white.opacity(0.48))
                                        .lineLimit(1)
                                        .multilineTextAlignment(.center)
                                }

                                heroLogo(for: detail)

                                heroMetaLine(for: detail)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: heroHeight + topInset)
                    }
                    .frame(height: heroHeight)

                    if metaRepo.isShowingStaleDetail {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                            Text(staleDetailLabel)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white.opacity(0.72))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }

                    // ── ACTION BUTTONS ────────────────────────────────────
                    HStack(spacing: 12) {
                        let activeProgress = watchedRepo.getProgress(mediaId: detail.id)
                        let watched = watchedRepo.isWatched(mediaId: detail.id)

                         Button { preparePlayback(detail: detail, progress: activeProgress) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: activeProgress == nil ? "play.fill" : "play.circle.fill")
                                    .font(.subheadline)
                                Text(playButtonTitle(hasProgress: activeProgress != nil, isWatched: watched, progress: activeProgress))
                                    .font(.subheadline.bold())
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
                            #if os(tvOS)
                            .scaleEffect(isFocused ? 1.05 : 1.0)
                            .animation(.easeOut(duration: 0.15), value: isFocused)
                            .shadow(color: isFocused ? Color.white.opacity(0.3) : .clear, radius: isFocused ? 10 : 0)
                            #endif
                        }

                        let inLibrary = libraryRepo.isInLibrary(mediaId: detail.id)
                        Button {
                            Task {
                                guard let profile = profileManager.currentProfile else { return }
                                await libraryRepo.toggleLibrary(
                                    profileId: profile.id,
                                    mediaId: detail.id,
                                    mediaType: type,
                                    name: detail.name,
                                    poster: detail.rawPosterUrl ?? detail.poster
                                )
                            }
                        } label: {
                            Image(systemName: inLibrary ? "bookmark.fill" : "bookmark")
                                .font(.title3)
                                .foregroundColor(inLibrary ? MoonlitTheme.accent : .white)
                                .frame(width: 50, height: 50)
                        }
                        .glassCard(cornerRadius: 14)
                        #if os(tvOS)
                        .scaleEffect(isFocused ? 1.05 : 1.0)
                        .animation(.easeOut(duration: 0.15), value: isFocused)
                        .shadow(color: isFocused ? Color.white.opacity(0.3) : .clear, radius: isFocused ? 10 : 0)
                        #endif
                        .sensoryFeedback(.impact(weight: .light), trigger: inLibrary)

                        Button {
                            Task {
                                guard let profile = profileManager.currentProfile else { return }
                                if isLiked {
                                    await likedRepo.removeLiked(mediaId: detail.id, profileId: profile.id)
                                } else {
                                    await likedRepo.addLiked(LikedItem(
                                        mediaId: detail.id,
                                        mediaType: type,
                                        name: detail.name,
                                        poster: detail.rawPosterUrl ?? detail.poster,
                                        tmdbId: nil
                                    ), profileId: profile.id)
                                }
                                isLiked = likedRepo.isLiked(detail.id)
                            }
                        } label: {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .font(.title3)
                                .foregroundColor(isLiked ? .red : .white)
                                .frame(width: 50, height: 50)
                        }
                        .glassCard(cornerRadius: 14)
                        #if os(tvOS)
                        .scaleEffect(isFocused ? 1.05 : 1.0)
                        .animation(.easeOut(duration: 0.15), value: isFocused)
                        .shadow(color: isFocused ? Color.white.opacity(0.3) : .clear, radius: isFocused ? 10 : 0)
                        #endif
                        .onAppear { isLiked = likedRepo.isLiked(detail.id) }
                        .sensoryFeedback(.impact(weight: .light), trigger: isLiked)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    // ── OVERVIEW ──────────────────────────────────────────
                    // Clamped to two centered lines; the full text opens in a
                    // sheet rather than expanding in place, so tapping it never
                    // pushes the episode list down the page.
                    if let description = detail.description, !description.isEmpty {
                        Button {
                            descriptionSheet = DescriptionSheetData(
                                title: detail.name,
                                text: description
                            )
                        } label: {
                            Text(description)
                                .font(.subheadline)
                                .foregroundColor(MoonlitTheme.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                    }

                    // ── DETAILS CHIPS ─────────────────────────────────────
                    detailChips(detail: detail)

                    // ── EPISODES ──────────────────────────────────────────
                    if let seasons = detail.seasons, !seasons.isEmpty {
                        let sorted = seasons.filter { $0.number != 0 }.sorted { $0.number < $1.number }
                        let activeId = selectedSeasonId ?? sorted.first?.id

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Episodes")
                                .font(.headline).foregroundColor(.white)
                                .padding(.horizontal, 16)

                            seasonControls(detail: detail, sorted: sorted, activeId: activeId)
                                .padding(.horizontal, 16)

                            if let activeSeason = sorted.first(where: { $0.id == activeId }),
                               let episodes = activeSeason.episodes {
                                ScrollViewReader { proxy in
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 12) {
                                        ForEach(episodes) { ep in
                                            let seasonNumber = ep.season ?? activeSeason.number
                                            let progress = watchedRepo.getEpisodeProgress(
                                                parentMediaId: detail.id,
                                                season: seasonNumber,
                                                episode: ep.episode
                                            )
                                            let watched = watchedRepo.isEpisodeWatched(
                                                parentMediaId: detail.id,
                                                season: seasonNumber,
                                                episode: ep.episode
                                            )
                                            EpisodeCard(
                                                episode: ep,
                                                progressFraction: progress?.progressFraction,
                                                isWatched: watched,
                                                onToggleWatched: {
                                                    toggleEpisodeWatched(
                                                        detail: detail,
                                                        episode: ep,
                                                        season: seasonNumber,
                                                        isWatched: watched
                                                    )
                                                },
                                                onShowDescription: {
                                                    if let overview = ep.overview, !overview.isEmpty {
                                                        let epLabel = ep.episode.map { "Episode \($0) · " } ?? ""
                                                        descriptionSheet = DescriptionSheetData(
                                                            title: epLabel + ep.title,
                                                            text: overview
                                                        )
                                                    }
                                                }
                                            ) {
                                                selectedEpisode = ep
                                                selectedSeasonNumber = seasonNumber
                                                selectedEpisodeNumber = ep.episode
                                                let epId = resolvedEpisodeId(for: ep, season: seasonNumber)
                                                selectedPlaybackMediaId = epId
                                                let initMs = progress.map { $0.positionSeconds * 1000 }
                                                selectedInitialPositionMs = initMs
                                                if let detail = metaRepo.detail {
                                                    presentPlayback(
                                                        detail: detail,
                                                        playbackId: epId,
                                                        episode: ep,
                                                        season: seasonNumber,
                                                        episodeNumber: ep.episode,
                                                        initialPositionMs: initMs
                                                    )
                                                }
                                            }
                                            #if os(tvOS)
                                            .focusable(true)
                                            #endif
                                            .id(ep.id)
                                        }
                                    }
                                }
                                .contentMargins(.horizontal, contentRailInset, for: .scrollContent)
                                // Land on the episode the viewer would actually
                                // press play on, not E1. Deferred a beat so the
                                // LazyHStack has built the row before we scroll.
                                .task(id: "\(activeSeason.id)-\(autoScrollEpisodeID ?? "")") {
                                    guard let target = autoScrollEpisodeID,
                                          episodes.contains(where: { $0.id == target }) else { return }
                                    try? await Task.sleep(for: .milliseconds(350))
                                    guard !Task.isCancelled else { return }
                                    withAnimation(.easeInOut(duration: 0.35)) {
                                        proxy.scrollTo(target, anchor: .leading)
                                    }
                                    autoScrollEpisodeID = nil
                                }
                                }
                            }
                        }
                        .padding(.top, 20)
                    }

                    // ── TRAILERS ──────────────────────────────────────────
                    let displayTrailers = resolvedTrailers(detail: detail)
                    if !displayTrailers.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Trailers")
                                .font(.headline).foregroundColor(.white)
                                .padding(.horizontal, 16)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(displayTrailers) { trailer in
                                        TrailerCard(trailer: trailer)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.top, 20)
                    }

                    // ── RELATED ───────────────────────────────────────────
                    let related = moreLikeThisItems.isEmpty
                        ? (detail.moreLikeThis ?? [])
                        : moreLikeThisItems
                    if !related.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("More Like This")
                                .font(.headline).foregroundColor(.white)
                                .padding(.horizontal, 16)
                            GeometryReader { geo in
                                let m = ResponsiveMetrics(for: geo.size.width)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 12) {
                                        ForEach(related.prefix(20)) { item in
                                            ContentCard(item: item, width: m.posterWidth, height: m.posterHeight)
                                                .onTapGesture { selectedMedia = item }
                                                #if os(tvOS)
                                                .scaleEffect(isFocused ? 1.05 : 1.0)
                                                .animation(.easeOut(duration: 0.15), value: isFocused)
                                                .shadow(color: isFocused ? Color.white.opacity(0.3) : .clear, radius: isFocused ? 10 : 0)
                                                #endif
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                            .frame(height: ResponsiveMetrics(for: UIScreen.main.bounds.width).posterHeight + 40)
                        }
                        .padding(.top, 20)
                    }

                    // ── CAST ──────────────────────────────────────────────
                    if let cast = detail.cast, !cast.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Cast")
                                .font(.headline).foregroundColor(.white)
                                .padding(.horizontal, 16)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(cast.prefix(20)) { person in
                                        NavigationLink {
                                            ActorBioScreen(
                                                name: person.name,
                                                tmdbPersonId: nil,
                                                characterName: person.character,
                                                showName: detail.name
                                            )
                                        } label: {
                                            VStack(spacing: 7) {
                                                if let photo = person.photo, let url = URL(string: photo) {
                                                    CachedAsyncImage(url: url) { phase in
                                                        if case .success(let img) = phase {
                                                            img.resizable().scaledToFill()
                                                                .frame(width: 104, height: 148)
                                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                                                .overlay(
                                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                                                )
                                                        } else {
                                                            castPortraitPlaceholder(person.name)
                                                        }
                                                    }
                                                } else {
                                                    castPortraitPlaceholder(person.name)
                                                }
                                                Text(person.name)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundColor(.white)
                                                    .lineLimit(1)
                                                    .frame(width: 104)
                                                if let role = person.character {
                                                    Text(role)
                                                        .font(.caption)
                                                        .foregroundColor(MoonlitTheme.textTertiary)
                                                        .lineLimit(1)
                                                        .frame(width: 104)
                                                }
                                            }
                                            .frame(width: 104)
                                        }
                                        .buttonStyle(.plain)
                                        #if os(tvOS)
                                        .scaleEffect(isFocused ? 1.05 : 1.0)
                                        .animation(.easeOut(duration: 0.15), value: isFocused)
                                        .shadow(color: isFocused ? Color.white.opacity(0.3) : .clear, radius: isFocused ? 10 : 0)
                                        #endif
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.top, 20)
                    }

                    if let summary = awardsMeta.summary(forId: detail.id),
                       !summary.bodiesRepresented.isEmpty {
                        AwardsRecognitionSection(summary: summary)
                            .padding(.top, 28)
                    }

                    InformationGrid(detail: detail)
                        .padding(.top, 28)

                    // ── NETWORK / PRODUCTION ──────────────────────────────
                    if let links = detail.links, !links.isEmpty {
                        let networks = links.filter { $0.category?.lowercased() == "network" }
                        let studios  = links.filter { $0.category?.lowercased() == "production" }
                        if !networks.isEmpty || !studios.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                if !networks.isEmpty {
                                    linkRow(label: "NETWORK", links: networks)
                                }
                                if !studios.isEmpty {
                                    linkRow(label: "PRODUCTION", links: studios)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                        }
                    }

                    Spacer().frame(height: 48)
                }
            } else if metaRepo.isLoading {
                VStack {
                    Spacer()
                    LottieLoadingView(size: 72)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: UIScreen.main.bounds.height * 0.8)
            } else if let error = metaRepo.errorMessage {
                VStack {
                    Spacer().frame(height: 200)
                    Text(error).foregroundColor(MoonlitTheme.textSecondary).padding().multilineTextAlignment(.center)
                    Spacer()
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y
        } action: { _, value in
            if detailScrollBase == nil { detailScrollBase = value }
            detailScroll = value - (detailScrollBase ?? 0)
        }
        .background {
            FusionAmbientBackground(
                ambientColor: ambientColor,
                ambientColor2: ambientColor2,
                isEnabled: cinematicModeEnabled,
                heroHeight: heroHeight,
                screenHeight: UIScreen.main.bounds.height,
                scrollOffset: detailScroll
            )
            .animation(.easeInOut(duration: 0.9), value: ambientColor)
            .animation(.easeInOut(duration: 0.9), value: ambientColor2)
        }
        .refreshable {
            await metaRepo.loadDetail(
                type: type,
                id: mediaId,
                addons: addonRepo.findAddonWithMetaResource(type: type, id: mediaId)
            )
        }
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .navigationDestination(item: $selectedMedia) { media in
            DetailScreen(mediaId: media.id, type: media.type.rawValue, name: media.name)
        }
        .sheet(item: $descriptionSheet) { data in
            DescriptionSheet(title: data.title, text: data.text)
        }
        .alert("Streaming unavailable", isPresented: $showGuestStreamingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Streaming isn't available on this account.")
        }
        .fullScreenCover(item: $playerLaunch) { launch in
#if os(tvOS)
            TVPlayerScreen(launch: launch) {
                playerLaunch = nil
            }
#else
            PlayerScreen(launch: launch) {
                playerLaunch = nil
            }
#endif
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
        .confirmationDialog(
            seasonWatchPrompt.map {
                $0.markingWatched
                    ? "Mark Season \($0.season.number) as watched?"
                    : "Unmark Season \($0.season.number)?"
            } ?? "",
            isPresented: Binding(
                get: { seasonWatchPrompt != nil },
                set: { if !$0 { seasonWatchPrompt = nil } }
            ),
            titleVisibility: .visible,
            presenting: seasonWatchPrompt
        ) { prompt in
            Button(prompt.markingWatched ? "Mark Watched" : "Unmark", role: prompt.markingWatched ? nil : .destructive) {
                applySeasonWatchPrompt(prompt)
                seasonWatchPrompt = nil
            }
            Button("Cancel", role: .cancel) { seasonWatchPrompt = nil }
        } message: { prompt in
            let count = prompt.season.episodes?.count ?? 0
            Text(prompt.markingWatched
                 ? "This marks all \(count) episodes as watched."
                 : "This clears the watched mark from all \(count) episodes.")
        }
        .task(id: effectiveBackdrop) {
            await updateAmbientColors(from: effectiveBackdrop)
        }
        .task(id: metaRepo.detail?.id) {
            guard let detail = metaRepo.detail, detail.id.hasPrefix("tt") else { return }
            await awardsMeta.fetch(id: detail.id)
        }
        .task(id: metaRepo.detail?.id) {
            resolvedBackdrop = nil
            // The hero always shows the textless portrait poster (like the home
            // hero), so resolve it for every title — not just ones the addon
            // left without a backdrop.
            guard let detail = metaRepo.detail else { return }
            let preview = MetaPreview(id: detail.id, type: detail.type, name: detail.name)
            HeroArtworkProvider.shared.prefetch(items: [preview])
        }
        .onChange(of: heroArtwork.posterPaths) { _, _ in
            guard let detail = metaRepo.detail else { return }
            let preview = MetaPreview(id: detail.id, type: detail.type, name: detail.name)
            guard let url = heroArtwork.heroArtURL(for: preview), resolvedBackdrop != url.absoluteString else { return }
            resolvedBackdrop = url.absoluteString
        }
        .task {
            selectedSeasonId = nil
            autoScrollEpisodeID = nil
            guard !isSyntheticFolderId else {
                metaRepo.detail = nil
                metaRepo.isLoading = false
                metaRepo.isShowingStaleDetail = false
                metaRepo.cachedDetailUpdatedAt = nil
                metaRepo.errorMessage = "Open this collection folder from Home to see its titles."
                return
            }

            if addonRepo.enabledAddons.isEmpty {
                if let profile = profileManager.currentProfile {
                    await addonRepo.loadAddons(profileId: profile.id)
                } else if guestMode {
                    await addonRepo.refreshFromUrls(MoonlitConfig.defaultAddons)
                }
            }

            // Fire stream pre-fetch concurrently with meta load so streams are ready
            // by the time the user taps play — mirrors Stremio's guessStream strategy.
            if profileManager.currentProfile != nil {
                let warmupAddons = addonRepo.enabledAddons
                let warmupType = type
                let warmupId = mediaId
                Task.detached(priority: .background) {
                    await StreamWarmupRepository.shared.warmup(
                        type: warmupType, id: warmupId, addons: warmupAddons
                    )
                }
            }

            await metaRepo.loadDetail(
                type: type,
                id: mediaId,
                addons: addonRepo.findAddonWithMetaResource(type: type, id: mediaId)
            )
            await loadCompanionLinks()
            await fetchMoreLikeThis()
            await fetchStreailerTrailers()
            if let profile = profileManager.currentProfile {
                await libraryRepo.loadLibrary(profileId: profile.id)
                await watchedRepo.loadAll(profileId: profile.id)
            }
            configureInitialEpisodePosition(for: metaRepo.detail)
        }
    }

    /// Fixed-size, center-cropped hero art — the same treatment as the home
    /// hero (`ParallaxHero.heroImage`): the textless TMDB *portrait* poster, so
    /// the overlaid title logo isn't duplicated by text baked into the art. The
    /// placeholder is the base layer and the poster fades in on top once
    /// resolved, so the addon's landscape backdrop never shows.
    private func heroPoster(for detail: MetaDetail, width: CGFloat, height: CGFloat) -> some View {
        let preview = MetaPreview(id: detail.id, type: detail.type, name: detail.name)
        let candidates = heroArtwork.heroArtCandidates(for: preview)
        return ZStack {
            MoonlitTheme.surfaceContainer
            if !candidates.isEmpty {
                LadderedCachedImage(urls: candidates) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    } else {
                        Color.clear
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private var heroArtworkMask: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0.0),
                .init(color: .black, location: 0.48),
                .init(color: .black.opacity(0.5), location: 0.72),
                .init(color: .black.opacity(0.15), location: 0.88),
                .init(color: .clear, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func updateAmbientColors(from backdrop: String?) async {
        guard cinematicModeEnabled,
              let backdrop,
              let url = URL(string: backdrop) else {
            ambientColor = .clear
            ambientColor2 = .clear
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data),
                  let (primary, secondary) = image.moonlitAmbientColors() else {
                ambientColor = .clear
                ambientColor2 = .clear
                return
            }
            ambientColor = primary.moonlitMutedForAmbient
            ambientColor2 = secondary.moonlitMutedForAmbient
        } catch {
            ambientColor = .clear
            ambientColor2 = .clear
        }
    }

    private func fetchMoreLikeThis() async {
        guard let detail = metaRepo.detail else { return }
        // Build a title-relevant list, most-relevant sources first, deduped and never
        // including the title itself.
        var seen: Set<String> = [mediaId]
        var combined: [MetaPreview] = []
        func add(_ items: [MetaPreview]?) {
            for item in items ?? [] where !seen.contains(item.id) {
                seen.insert(item.id)
                combined.append(item)
            }
        }

        // 1. TMDB recommendations — algorithmic "recommended for fans of this title"
        //    (resolved with real IMDb ids/posters during detail load).
        add(detail.recommendations)

        // 2. Fusion-style: TMDB Discover seeded by THIS title's own genres.
        if combined.count < 20, let genres = detail.genres, !genres.isEmpty {
            add(await TMDBDiscoverService.shared.discoverSimilar(
                genres: genres, mediaKind: detail.type, excludingImdbId: mediaId))
        }

        // 3. TMDB similar (weaker genre/keyword match) as fill.
        add(detail.moreLikeThis)

        // 4. Dedicated MLT addon (Trakt semantic) — best-effort extra fill when the
        //    TMDB sources came up short (e.g. addon-only titles with no TMDB id).
        if combined.count < 12,
           let mltURL = URL(string: "\(Self.mltBaseURL)/catalog/\(type)/mlt/\(mediaId).json"),
           let data = try? await URLSession.shared.data(from: mltURL).0,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let metas = json["metas"] as? [[String: Any]] {
            add(metas.compactMap { m -> MetaPreview? in
                guard let id = m["id"] as? String, let name = m["name"] as? String else { return nil }
                return MetaPreview(
                    id: id,
                    type: MediaType(rawValue: m["type"] as? String ?? type) ?? .movie,
                    name: name,
                    poster: m["poster"] as? String,
                    imdbRating: m["imdbRating"] as? String
                )
            })
        }

        moreLikeThisItems = combined
    }

    private func fetchStreailerTrailers() async {
        guard let detail = metaRepo.detail else { return }

        if detail.type == .series {
            // Derive season numbers from videos (detail.seasons may be empty from some addons)
            let seasonNums: [Int]
            if let seasons = detail.seasons, !seasons.isEmpty {
                seasonNums = seasons.map { $0.number }.sorted()
            } else {
                seasonNums = Array(Set(detail.videos?.compactMap { $0.season } ?? [])).sorted()
            }
            guard !seasonNums.isEmpty else { return }

            var results: [Trailer] = []
            let baseURL = Self.streailerBaseURL
            let mediaId = self.mediaId
            await withTaskGroup(of: Trailer?.self) { group in
                for seasonNum in seasonNums {
                    group.addTask {
                        let videoId = "\(mediaId):\(seasonNum):1"
                        let url = "\(baseURL)/stream/series/\(videoId).json"
                        guard let reqURL = URL(string: url),
                              let data = try? await URLSession.shared.data(from: reqURL).0,
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let streams = json["streams"] as? [[String: Any]],
                              let first = streams.first,
                              let ytId = first["ytId"] as? String else { return nil }
                        let title = first["title"] as? String ?? "Season \(seasonNum) Trailer"
                        return Trailer(id: "\(ytId)-s\(seasonNum)", title: title, youtubeId: ytId)
                    }
                }
                for await t in group { if let t { results.append(t) } }
            }
            streailerTrailers = results.sorted {
                seasonNumberFromTitle($0.title) < seasonNumberFromTitle($1.title)
            }
        } else {
            // Movies: try aiometadata addon for rich trailer names first
            let aioTrailers = await fetchAIOMetaTrailers()
            if !aioTrailers.isEmpty {
                streailerTrailers = aioTrailers
                return
            }
            // Fallback: streailer single trailer
            let url = "\(Self.streailerBaseURL)/stream/movie/\(mediaId).json"
            guard let reqURL = URL(string: url),
                  let data = try? await URLSession.shared.data(from: reqURL).0,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let streams = json["streams"] as? [[String: Any]] else { return }
            streailerTrailers = streams.compactMap { s -> Trailer? in
                guard let ytId = s["ytId"] as? String else { return nil }
                return Trailer(id: ytId, title: "Trailer", youtubeId: ytId)
            }
        }
    }

    private func fetchAIOMetaTrailers() async -> [Trailer] {
        guard let aioAddon = addonRepo.enabledAddons.first(where: {
            $0.transportUrl?.contains("aiometadata") == true
        }), let baseURL = aioAddon.transportUrl else { return [] }
        let url = "\(baseURL)/meta/\(type)/\(mediaId).json"
        guard let reqURL = URL(string: url),
              let data = try? await URLSession.shared.data(from: reqURL).0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let meta = json["meta"] as? [String: Any],
              let trailers = meta["trailers"] as? [[String: Any]],
              !trailers.isEmpty else { return [] }
        return trailers.compactMap { t -> Trailer? in
            guard let ytId = t["ytId"] as? String ?? t["source"] as? String else { return nil }
            let title = t["name"] as? String ?? t["title"] as? String
            return Trailer(id: ytId, title: title, youtubeId: ytId)
        }
    }

    private func seasonNumberFromTitle(_ title: String?) -> Int {
        guard let title else { return 99 }
        let words = title.lowercased().components(separatedBy: .whitespaces)
        if let idx = words.firstIndex(of: "season"), idx + 1 < words.count,
           let n = Int(words[idx + 1]) { return n }
        return 99
    }

    private func resolvedTrailers(detail: MetaDetail) -> [Trailer] {
        if !streailerTrailers.isEmpty { return streailerTrailers }
        if let t = detail.trailers, !t.isEmpty { return t }
        guard let streams = detail.trailerStreams else { return [] }
        var count = 0
        return streams.compactMap { stream -> Trailer? in
            guard let ytId = stream.ytId else { return nil }
            count += 1
            let title = (stream.title == nil || stream.title == detail.name)
                ? "Trailer \(count)" : stream.title
            return Trailer(id: ytId, title: title, youtubeId: ytId)
        }
    }

    // MARK: - Season controls

    /// Season menu + mark-watched button. The menu replaces the old horizontal
    /// pill rail: it stays one row tall no matter how many seasons a series has,
    /// and iOS renders the popup itself so it matches the system exactly.
    @ViewBuilder
    private func seasonControls(detail: MetaDetail, sorted: [Season], activeId: String?) -> some View {
        let activeSeason = sorted.first { $0.id == activeId }
        let allWatched = activeSeason.map { isSeasonFullyWatched($0, detail: detail) } ?? false

        HStack(spacing: 8) {
            Menu {
                Picker("Season", selection: Binding(
                    get: { activeId ?? sorted.first?.id ?? "" },
                    set: { newId in
                        selectedSeasonId = newId
                        // A manual season change means the viewer is browsing;
                        // don't yank the rail back to next-up underneath them.
                        autoScrollEpisodeID = nil
                    }
                )) {
                    ForEach(sorted) { season in
                        Text(season.name ?? "Season \(season.number)").tag(season.id)
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Text(activeSeason?.name ?? "Season \(activeSeason?.number ?? 1)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.10), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                #if os(tvOS)
                .scaleEffect(isFocused ? 1.05 : 1.0)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                .shadow(color: isFocused ? Color.white.opacity(0.3) : .clear, radius: isFocused ? 10 : 0)
                #endif
            }

            if let activeSeason {
                Button {
                    seasonWatchPrompt = SeasonWatchPrompt(season: activeSeason, markingWatched: !allWatched)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: allWatched ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 12, weight: .semibold))
                        Text(allWatched ? "Watched" : "Mark Watched")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(allWatched ? .green : .white.opacity(0.9))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(
                        (allWatched ? Color.green.opacity(0.14) : Color.white.opacity(0.06)),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().stroke(
                            allWatched ? Color.green.opacity(0.4) : Color.white.opacity(0.14),
                            lineWidth: 0.5
                        )
                    )
                }
                .buttonStyle(.plain)
                #if os(tvOS)
                .scaleEffect(isFocused ? 1.05 : 1.0)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                .shadow(color: isFocused ? Color.white.opacity(0.3) : .clear, radius: isFocused ? 10 : 0)
                #endif
                .sensoryFeedback(.impact(weight: .light), trigger: allWatched)
            }

            Spacer(minLength: 0)
        }
    }

    private func isSeasonFullyWatched(_ season: Season, detail: MetaDetail) -> Bool {
        guard let episodes = season.episodes, !episodes.isEmpty else { return false }
        return episodes.allSatisfy {
            watchedRepo.isEpisodeWatched(
                parentMediaId: detail.id,
                season: $0.season ?? season.number,
                episode: $0.episode
            )
        }
    }

    private func applySeasonWatchPrompt(_ prompt: SeasonWatchPrompt) {
        Task {
            guard let profile = profileManager.currentProfile,
                  let detail = metaRepo.detail,
                  let episodes = prompt.season.episodes else { return }

            if prompt.markingWatched {
                await watchedRepo.markSeasonWatched(
                    profileId: profile.id,
                    seriesId: detail.id,
                    mediaType: type,
                    season: prompt.season.number,
                    episodes: episodes.map { (mediaId: $0.id, episode: $0.episode) },
                    name: detail.name,
                    poster: detail.rawPosterUrl ?? detail.poster
                )
            } else {
                // No bulk unmark exists on the repository — markUnwatched deletes
                // one row at a time, so walk the season.
                for ep in episodes {
                    await watchedRepo.markUnwatched(mediaId: ep.id)
                }
            }
        }
    }

    private func toggleEpisodeWatched(detail: MetaDetail, episode: MetaVideo, season: Int, isWatched: Bool) {
        Task {
            guard let profile = profileManager.currentProfile else { return }
            if isWatched {
                await watchedRepo.markUnwatched(mediaId: episode.id)
            } else {
                await watchedRepo.markWatched(
                    profileId: profile.id,
                    mediaId: episode.id,
                    mediaType: type,
                    name: detail.name,
                    poster: detail.rawPosterUrl ?? detail.poster,
                    season: season,
                    episode: episode.episode
                )
            }
        }
    }

    // MARK: - Next up

    /// The episode the viewer is most likely to want: the one they're partway
    /// through, else the first unwatched one after the last watched. Returns nil
    /// for a season that's already fully watched.
    private func nextUpEpisodeId(in season: Season, detail: MetaDetail) -> String? {
        guard let episodes = season.episodes, !episodes.isEmpty else { return nil }

        if let inProgress = episodes.first(where: { ep in
            guard let p = watchedRepo.getEpisodeProgress(
                parentMediaId: detail.id,
                season: ep.season ?? season.number,
                episode: ep.episode
            ) else { return false }
            let f = p.progressFraction
            return f > 0.01 && f < 0.95
        }) {
            return inProgress.id
        }

        let lastWatchedIndex = episodes.lastIndex { ep in
            watchedRepo.isEpisodeWatched(
                parentMediaId: detail.id,
                season: ep.season ?? season.number,
                episode: ep.episode
            )
        }
        guard let lastWatchedIndex else { return nil }
        let next = episodes.index(after: lastWatchedIndex)
        return episodes.indices.contains(next) ? episodes[next].id : nil
    }

    /// The season the viewer should land on — next-up often isn't in Season 1.
    /// Picks the first season with something in progress or partially watched,
    /// falling back to the first season.
    private func initialSeasonId(for detail: MetaDetail, sorted: [Season]) -> String? {
        for season in sorted where nextUpEpisodeId(in: season, detail: detail) != nil {
            return season.id
        }
        return sorted.first?.id
    }

    private func configureInitialEpisodePosition(for detail: MetaDetail?) {
        guard let detail,
              let seasons = detail.seasons, !seasons.isEmpty else { return }

        let sorted = seasons.filter { $0.number != 0 }.sorted { $0.number < $1.number }
        guard let seasonID = initialSeasonId(for: detail, sorted: sorted),
              let season = sorted.first(where: { $0.id == seasonID }) else { return }

        selectedSeasonId = seasonID
        autoScrollEpisodeID = nextUpEpisodeId(in: season, detail: detail)
    }

    /// The title's stylized clearlogo, centered in the hero. Deliberately has NO
    /// text fallback: when the addon supplies no logo the hero shows the meta
    /// line only. Mac keeps a serif fallback here; iOS does not, by request.
    @ViewBuilder
    private func heroLogo(for detail: MetaDetail) -> some View {
        if let logoURL = detail.logo.flatMap(URL.init) {
            CachedAsyncImage(url: logoURL) { phase in
                // Must return a real view in every phase — CachedAsyncImage hangs
                // its fetch off `.task` applied to this closure's result, and an
                // empty ViewBuilder result has no lifecycle to attach it to.
                ZStack {
                    Color.clear
                    if case .success(let img) = phase {
                        img.resizable()
                            .scaledToFit()
                            .frame(maxWidth: 260, maxHeight: 104)
                            .shadow(color: .black.opacity(0.65), radius: 10, x: 0, y: 4)
                    }
                }
                .frame(height: 104)
            }
            .id(detail.logo)
        }
    }

    /// A single centered metadata line under the logo: IMDb rating, then year,
    /// genre, age rating and runtime separated by dots. Replaces the old pill
    /// row — six bordered chips wrapped to two lines and fought the poster for
    /// attention. The IMDb wordmark and star stay so the score is still
    /// attributable; only the pill around it is gone.
    @ViewBuilder
    private func heroMetaLine(for detail: MetaDetail) -> some View {
        let parts: [String] = [
            releaseYear(from: detail.releaseInfo),
            (detail.genres ?? []).first,
            detail.ageRating,
            seasonSummary(for: detail) ?? detail.runtime
        ].compactMap { $0 }.filter { !$0.isEmpty }

        HStack(spacing: 6) {
            if let rating = detail.imdbRating {
                Text("IMDb")
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(MoonlitTheme.ratingGold)
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 1, height: 9)
                Image(systemName: "star.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(MoonlitTheme.ratingGold)
                Text(rating.replacingOccurrences(of: "/10", with: ""))
                    .fontWeight(.bold)
                if !parts.isEmpty {
                    metaDot
                }
            }

            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                Text(part)
                if index < parts.count - 1 {
                    metaDot
                }
            }
        }
        .font(.system(size: 12.5, weight: .medium))
        .foregroundColor(.white.opacity(0.85))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var metaDot: some View {
        Text("•")
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.38))
    }

    private func releaseYear(from releaseInfo: String?) -> String? {
        guard let releaseInfo else { return nil }
        let year = releaseInfo.prefix(4)
        return year.count == 4 && Int(year) != nil ? String(year) : releaseInfo
    }

    private func seasonSummary(for detail: MetaDetail) -> String? {
        let real = (detail.seasons ?? []).filter { $0.number != 0 }
        guard !real.isEmpty else { return nil }
        return real.count == 1 ? "1 Season" : "\(real.count) Seasons"
    }

    @ViewBuilder
    private func personInitialsCircle(_ name: String) -> some View {
        Circle()
            .fill(MoonlitTheme.surfaceElevated)
            .frame(width: 64, height: 64)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.title3.weight(.semibold))
                    .foregroundColor(MoonlitTheme.textSecondary)
            )
    }

    @ViewBuilder
    private func castPortraitPlaceholder(_ name: String) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(MoonlitTheme.surfaceElevated)
            .frame(width: 104, height: 148)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.largeTitle.weight(.semibold))
                    .foregroundColor(MoonlitTheme.textSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
    }

    private func loadCompanionLinks() async {
        trailerLink = nil

        let streamAddons = addonRepo.enabledAddons.filter {
            $0.hasResource("stream")
            && ($0.types?.contains(type) ?? false)
            && $0.transportUrl != nil
        }

        async let trailer = companionLink(
            from: streamAddons,
            matching: { addon in
                addon.id == "org.streailer.trailer"
                || addon.name.localizedCaseInsensitiveContains("Streailer")
                || addon.transportUrl?.contains("streailer") == true
            },
            streamMatching: { stream in
                let text = [stream.name, stream.title, stream.description]
                    .compactMap { $0 }
                    .joined(separator: " ")
                    .lowercased()
                return text.contains("trailer") || stream.behaviorHints?.bingeGroup == "trailer"
            }
        )

        trailerLink = await trailer
    }

    private func companionLink(
        from addons: [AddonManifest],
        matching addonMatches: (AddonManifest) -> Bool,
        streamMatching streamMatches: (StreamItem) -> Bool
    ) async -> URL? {
        for addon in addons where addonMatches(addon) {
            guard let streams = try? await StreamRepository.shared.fetchStreamsFromSingleAddon(
                type: type,
                id: mediaId,
                addon: addon
            ) else { continue }

            if let stream = streams.first(where: streamMatches),
               let url = companionURL(for: stream) {
                return url
            }
        }
        return nil
    }

    private func companionURL(for stream: StreamItem) -> URL? {
        if let external = stream.externalUrl.flatMap(URL.init) { return external }
        if let ytId = stream.ytId { return URL(string: "https://www.youtube.com/watch?v=\(ytId)") }
        return stream.url.flatMap(URL.init)
    }

    private func companionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .glassCard(cornerRadius: 18)
    }

    private func playButtonTitle(hasProgress: Bool, isWatched: Bool, progress: WatchProgressEntry? = nil) -> String {
        if hasProgress, let progress {
            if type == "series" {
                if let s = progress.inferredSeason, let e = progress.inferredEpisode {
                    return "Continue · S\(s)E\(e)"
                }
            } else {
                let secs = Int(progress.positionSeconds)
                let h = secs / 3600
                let m = (secs % 3600) / 60
                let s = secs % 60
                let timestamp = h > 0
                    ? String(format: "%d:%02d:%02d", h, m, s)
                    : String(format: "%d:%02d", m, s)
                return "Continue · \(timestamp)"
            }
            return "Continue"
        }
        if isWatched { return "Rewatch" }
        return type == "series" ? "Play First Episode" : "Play"
    }

    private func preparePlayback(detail: MetaDetail, progress: WatchProgressEntry?) {
        guard profileManager.currentProfile != nil else {
            showGuestStreamingAlert = true
            return
        }

        selectedEpisode = nil
        selectedSeasonNumber = nil
        selectedEpisodeNumber = nil
        selectedPlaybackMediaId = nil
        selectedInitialPositionMs = nil

        if let progress {
            selectedPlaybackMediaId = progress.decodedMediaId
            selectedSeasonNumber = progress.inferredSeason
            selectedEpisodeNumber = progress.inferredEpisode
            selectedInitialPositionMs = progress.positionSeconds * 1000
            selectedEpisode = episode(
                in: detail,
                season: progress.inferredSeason,
                episode: progress.inferredEpisode
            )
        } else if type == "series", let first = firstPlayableEpisode(in: detail) {
            selectedEpisode = first.video
            selectedSeasonNumber = first.seasonNumber
            selectedEpisodeNumber = first.video.episode
            selectedPlaybackMediaId = resolvedEpisodeId(for: first.video, season: first.seasonNumber)
        }

        let playbackId = selectedPlaybackMediaId ?? mediaId
        presentPlayback(
            detail: detail,
            playbackId: playbackId,
            episode: selectedEpisode,
            season: selectedSeasonNumber,
            episodeNumber: selectedEpisodeNumber,
            initialPositionMs: selectedInitialPositionMs
        )
    }

    private func presentPlayback(
        detail: MetaDetail,
        playbackId: String,
        episode: MetaVideo?,
        season: Int?,
        episodeNumber: Int?,
        initialPositionMs: Double?
    ) {
        guard profileManager.currentProfile != nil else {
            showGuestStreamingAlert = true
            return
        }

        if ProfileManager.shared.currentProfile?.role == "free" {
            showGuestStreamingAlert = true
            return
        }

        let pendingLaunch = buildPendingLaunch(
            detail: detail,
            playbackId: playbackId,
            episode: episode,
            season: season,
            episodeNumber: episodeNumber,
            initialPositionMs: initialPositionMs
        )

        if shouldUseManualStreamSelection {
            streamSelectionLaunch = pendingLaunch
            return
        }

        playerLaunch = cachedLaunch(
            detail: detail,
            playbackId: playbackId,
            episode: episode,
            season: season,
            episodeNumber: episodeNumber,
            initialPositionMs: initialPositionMs
        ) ?? pendingLaunch
    }

    private var shouldUseManualStreamSelection: Bool {
        guard let profile = profileManager.currentProfile else { return true }
        return StreamAutoplayPreferenceStore.shared.mode(profileId: profile.id) == .manual
    }

    private func cachedLaunch(
        detail: MetaDetail,
        playbackId: String,
        episode: MetaVideo?,
        season: Int?,
        episodeNumber: Int?,
        initialPositionMs: Double?
    ) -> PlayerLaunch? {
        guard let profile = profileManager.currentProfile,
              let source = LastPlaybackSourceStore.shared.source(profileId: profile.id, mediaId: playbackId) else {
            return nil
        }
        return PlayerLaunch(
            title: detail.name,
            sourceUrl: source.sourceUrl,
            sourceHeaders: source.sourceHeaders,
            logo: detail.logo,
            poster: detail.poster,
            episodeThumbnail: episode?.thumbnail,
            background: detail.background,
            seasonNumber: season,
            episodeNumber: episodeNumber,
            streamTitle: episode?.title ?? source.streamTitle,
            providerName: source.providerName,
            contentType: MediaType(rawValue: type) ?? .movie,
            videoId: playbackId,
            parentMetaId: playbackId == mediaId ? nil : mediaId,
            parentMetaType: playbackId == mediaId ? nil : type,
            initialPositionMs: initialPositionMs
        )
    }

    private func buildPendingLaunch(
        detail: MetaDetail,
        playbackId: String,
        episode: MetaVideo?,
        season: Int?,
        episodeNumber: Int?,
        initialPositionMs: Double?
    ) -> PlayerLaunch {
        PlayerLaunch(
            title: detail.name,
            sourceUrl: "",
            logo: detail.logo,
            poster: detail.poster,
            episodeThumbnail: episode?.thumbnail,
            background: detail.background,
            seasonNumber: season,
            episodeNumber: episodeNumber,
            streamTitle: episode?.title,
            contentType: MediaType(rawValue: type) ?? .movie,
            videoId: playbackId,
            parentMetaId: playbackId == mediaId ? nil : mediaId,
            parentMetaType: playbackId == mediaId ? nil : type,
            initialPositionMs: initialPositionMs
        )
    }

    private func firstPlayableEpisode(in detail: MetaDetail) -> (video: MetaVideo, seasonNumber: Int)? {
        if let seasons = detail.seasons?.sorted(by: { $0.number < $1.number }) {
            for season in seasons {
                if let episode = season.episodes?.sorted(by: { ($0.episode ?? 0) < ($1.episode ?? 0) }).first {
                    return (episode, episode.season ?? season.number)
                }
            }
        }
        if let video = detail.videos?.sorted(by: {
            if ($0.season ?? 0) == ($1.season ?? 0) {
                return ($0.episode ?? 0) < ($1.episode ?? 0)
            }
            return ($0.season ?? 0) < ($1.season ?? 0)
        }).first, let season = video.season {
            return (video, season)
        }
        return nil
    }

    private func episode(in detail: MetaDetail, season: Int?, episode: Int?) -> MetaVideo? {
        guard let season, let episode else { return nil }
        if let video = detail.videos?.first(where: { $0.season == season && $0.episode == episode }) {
            return video
        }
        return detail.seasons?
            .first(where: { $0.number == season })?
            .episodes?
            .first(where: { $0.episode == episode })
    }

    /// Returns the correct stream-request ID for an episode.
    /// Prefers the addon-provided `ep.id` (already in `imdbId:s:e` format for
    /// most addons). When it's empty or encodes the wrong season/episode —
    /// which happens with some metadata addons that mis-map episodes — we
    /// construct the canonical Stremio format `{seriesImdbId}:{season}:{episode}`.
    private func resolvedEpisodeId(for ep: MetaVideo, season: Int) -> String {
        if !ep.id.isEmpty && ep.id.hasPrefix(mediaId) {
            let parts = ep.id.components(separatedBy: ":")
            // Series episodes MUST have the imdbId:season:episode format.
            // A plain series ID (count == 1, e.g. "tt9813792") is not a valid
            // episode stream ID — fall through to construct the canonical one.
            // Also validate the embedded season:episode numbers match what we
            // expect; some addons return IDs like "tt9813792:2:1" for S4E9.
            if parts.count >= 3,
               let idSeason = Int(parts[1]),
               let idEpisode = Int(parts[2]),
               let expectedEpisode = ep.episode,
               idSeason == season && idEpisode == expectedEpisode {
                return ep.id
            }
        }
        // Construct the canonical Stremio episode ID: imdbId:season:episode
        if let epNum = ep.episode { return "\(mediaId):\(season):\(epNum)" }
        return mediaId
    }

    @ViewBuilder
    private func detailChips(detail: MetaDetail) -> some View {
        // Genre pills removed — the primary genre already appears in the hero
        // meta line, and a second listing here was pure duplication.
        if let director = detail.director, !director.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("DIRECTOR")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(MoonlitTheme.textTertiary)
                    .tracking(1.5)
                Text(director.map(\.name).joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
        }
    }

    @ViewBuilder
    private func linkRow(label: String, links: [MetaLink]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(MoonlitTheme.textTertiary)
                .tracking(1.5)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(links) { link in
                        Text(link.name)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(MoonlitTheme.textSecondary)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(MoonlitTheme.surfaceElevated)
                            .cornerRadius(16)
                    }
                }
            }
        }
    }
}

// MARK: - Trailer Card

private struct TrailerCard: View {
    let trailer: Trailer
    @Environment(\.openURL) private var openURL
    #if os(tvOS)
    @Environment(\.isFocused) var isFocused
    #endif

    private var thumbnailURL: URL? {
        if let t = trailer.thumbnail { return URL(string: t) }
        if let ytId = trailer.youtubeId { return URL(string: "https://img.youtube.com/vi/\(ytId)/hqdefault.jpg") }
        return nil
    }

    var body: some View {
        Button {
            if let ytId = trailer.youtubeId,
               let url = URL(string: "https://www.youtube.com/watch?v=\(ytId)") {
                openURL(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(MoonlitTheme.surfaceElevated)
                        .frame(width: 220, height: 124)

                    if let url = thumbnailURL {
                        CachedAsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable().aspectRatio(contentMode: .fill)
                                    .frame(width: 220, height: 124)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            } else {
                                trailerPlaceholder
                            }
                        }
                    } else {
                        trailerPlaceholder
                    }

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .center, endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .frame(width: 220, height: 124)

                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(10)
                }
                .frame(width: 220, height: 124)

                if let title = trailer.title {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(width: 220, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
        #if os(tvOS)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .shadow(color: isFocused ? Color.white.opacity(0.3) : .clear, radius: isFocused ? 10 : 0)
        #endif
    }

    private var trailerPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(MoonlitTheme.surfaceElevated)
            .frame(width: 220, height: 124)
            .overlay(
                Image(systemName: "play.rectangle.fill")
                    .font(.title2)
                    .foregroundColor(MoonlitTheme.textTertiary)
            )
    }
}

// MARK: - Description bottom sheet (liquid glass)

struct DescriptionSheetData: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}

struct DescriptionSheet: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // No close button — the drag indicator is the affordance, and a
            // glass panel reads cleaner without a control fighting the title.
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 14)

            ScrollView {
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.88))
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground { DescriptionSheetGlassBackground() }
    }
}

/// Real Liquid Glass (`.glassEffect`, iOS 26+) rather than a material-plus-
/// gradient approximation — the system renders the specular highlight and
/// refraction itself. Falls back to `.ultraThinMaterial` pre-iOS 26.
private struct DescriptionSheetGlassBackground: View {
    /// Only the top corners round — the sheet's bottom edge sits flush with
    /// the screen edge, so rounding it too would cut a visible notch there.
    private var shape: UnevenRoundedRectangle {
        .rect(topLeadingRadius: 26, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 26)
    }

    var body: some View {
#if os(iOS)
        if #available(iOS 26, *) {
            Color.clear
                .glassEffect(.regular, in: shape)
                .ignoresSafeArea()
        } else {
            shape.fill(.ultraThinMaterial)
                .ignoresSafeArea()
        }
#else
        shape.fill(.ultraThinMaterial)
            .ignoresSafeArea()
#endif
    }
}

// MARK: - Episode Card

/// A pending "mark/unmark this whole season" confirmation.
struct SeasonWatchPrompt: Identifiable {
    let season: Season
    /// true = about to mark watched, false = about to unmark.
    let markingWatched: Bool
    var id: String { "\(season.id)-\(markingWatched)" }
}

/// Left-aligned wrapping flow: each subview keeps its natural size and rows wrap
/// when they run out of width. Used for the hero's metadata pills, which don't
/// fit a phone width on one line.
///
/// Mirrors MoonlitMac's `FlowLayout` — the two apps are separate targets and
/// only share code through MoonlitCore, which can't vend SwiftUI layouts here
/// without pulling the whole component set across.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + rowSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty && needed > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

struct EpisodeCard: View {
    let episode: MetaVideo
    let progressFraction: Double?
    let isWatched: Bool
    var onToggleWatched: (() -> Void)? = nil
    var onShowDescription: (() -> Void)? = nil
    let onPlay: () -> Void
    #if os(tvOS)
    @Environment(\.isFocused) var isFocused
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(MoonlitTheme.surfaceElevated)
                    .frame(width: 220, height: 124)

                if let thumb = episode.thumbnail, let url = URL(string: thumb) {
                    CachedAsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().aspectRatio(contentMode: .fill)
                                .frame(width: 220, height: 124)
                                .clipped()
                                .cornerRadius(10)
                        } else {
                            episodePlaceholder
                        }
                    }
                    .frame(width: 220, height: 124)
                } else {
                    episodePlaceholder
                }

                if isWatched {
                    Label("Seen", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.62), in: Capsule())
                        .padding(8)
                } else if let progressFraction, progressFraction > 0 {
                    GeometryReader { geo in
                        VStack {
                            Spacer()
                            Rectangle()
                                .fill(Color.white.opacity(0.25))
                                .frame(height: 3)
                                .overlay(alignment: .leading) {
                                    Rectangle()
                                        .fill(MoonlitTheme.accent)
                                        .frame(width: geo.size.width * min(max(progressFraction, 0), 1), height: 3)
                                }
                        }
                    }
                    .frame(width: 220, height: 124)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .frame(width: 220, height: 124)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture(perform: onPlay)
            // Long-press rather than a visible control: the card is already
            // carrying a thumbnail, episode number, title, overview and a
            // progress bar in 220pt.
            .contextMenu {
                if let onToggleWatched {
                    Button {
                        onToggleWatched()
                    } label: {
                        Label(
                            isWatched ? "Mark as Unwatched" : "Mark as Watched",
                            systemImage: isWatched ? "checkmark.circle.badge.xmark" : "checkmark.circle"
                        )
                    }
                }
                Button {
                    onPlay()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
            }

            if let epNum = episode.episode {
                Text("Episode \(epNum)")
                    .font(.caption2)
                    .foregroundColor(MoonlitTheme.textTertiary)
            }
            Text(episode.title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: 220, alignment: .leading)
            if let overview = episode.overview {
                Text(overview)
                    .font(.caption2)
                    .foregroundColor(MoonlitTheme.textSecondary)
                    .lineLimit(2)
                    .frame(width: 220, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onShowDescription?() }
            }
        }
        #if os(tvOS)
        .focusable(true)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .shadow(color: isFocused ? Color.white.opacity(0.3) : .clear, radius: isFocused ? 10 : 0)
        #endif
    }

    private var episodePlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(MoonlitTheme.surfaceElevated)
            .frame(width: 220, height: 124)
            .overlay(
                Image(systemName: "play.rectangle.fill")
                    .font(.title2)
                    .foregroundColor(MoonlitTheme.textTertiary)
            )
    }
}

struct SeasonDetailScreen: View {
    let season: Season
    let seriesName: String

    var body: some View {
        List {
            if let episodes = season.episodes {
                ForEach(episodes) { episode in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("E\(episode.episode ?? 0): \(episode.title)")
                                .foregroundColor(.white)
                            if let overview = episode.overview {
                                Text(overview)
                                    .font(.caption)
                                    .foregroundColor(MoonlitTheme.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        if let runtime = episode.runtime {
                            Text(runtime)
                                .font(.caption2)
                                .foregroundColor(MoonlitTheme.textTertiary)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(MoonlitTheme.surface)
                }
            }
        }
#if os(iOS)
        .scrollContentBackground(.hidden)
#endif
        .background(MoonlitTheme.background)
        .navigationTitle(season.name ?? "Season \(season.number)")
    }
}
