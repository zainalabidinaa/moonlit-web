import SwiftUI
import LunaCore

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
    @State private var deepDiveLink: URL?
    @State private var moreLikeThisItems: [MetaPreview] = []
    @State private var streailerTrailers: [Trailer] = []
    @State private var isLiked = false
    @StateObject private var likedRepo = LikedRepository.shared

    private static let streailerBaseURL = "https://streailer.elfhosted.com/%7B%22language%22%3A%22en-US%22%2C%22externalLink%22%3Afalse%2C%22showRecap%22%3Afalse%2C%22onlyRecaps%22%3Afalse%7D"
    private static let mltBaseURL = "https://bbab4a35b833-more-like-this.baby-beamup.club/%7B%22iv%22%3A%226eccbcc6a9db21bd4cb1fef5f30b4892%22%2C%22salt%22%3Anull%2C%22authTag%22%3A%22017bc87cc819a77554085544340d58ee%22%2C%22data%22%3A%22d270093abcf6a558d135729ff8b3b1f799809a1b7bcf8e42b77a79357857b567587078990ef4e3668c550ee8b53b3219b6b9d39a201b768bf39dd3516762994348df48afdf938ad363cdf3bf2c620fb2014ee02826dac096aaa4e23da726f2b5de5467874ff0a51a87567354a45e23daf41cddbac084ed0f72000bf89b4d66acbf6908349fa70d0106a0e803001766e4a8635343e348c523061beabaa612a054ca63730898aa357d37af353db6ebf07dc415bb4de0064ef88f13c308a8bf8a64c620b9433575b7dd6a3b135d2aa0db02a82e434a0a713dd00e2c23efe2938ffcb5bcefe24fb2b7b70e2d0749029c88e2f9c4eb72af2cdd7162a706fccd56cc4f81d470fd9d3518f8d6d0d79943de3bafb4bc83de616f236f4e111bfad494bdb50426351aaaeb7df0573f4dc195c87f18094466b490bb9c8d9547ed3a82f2a0930cd55d177b03df493591470b75f4c7fe179b4725e40aafc21cfe7593e0d72dc825598b2c083854a60c284c0582f75736904a8b35842cc44872c8c294b9bec96421288ab2d80f6cb5c824eec1aff65e485193083a66da91022dffa55f9059b986ad65e2f09902648fc197a076773f29136b2c1df1b2af9e7334b3c0285d397602abc0ffd6bcdecf5d5318093dce2b8b2922d8ac1215e8ec4385e3eef554f21f6e49fa1fd6d37544530f3dd41a3bcd2f3febe53dd3a3390a6ce5a4748fa600a9466b425901e5e05500c941882ecce958e40f30256c02eedfccc5f7b630b214c9e61795bdba0481abd9160b901a014ac4d4cddf57a83ca8529ce5c30bf368ff8740ce7b757313cce9f0b73567897250ab333bfa%22%7D"
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            if let detail = metaRepo.detail {
                VStack(alignment: .leading, spacing: 0) {

                    // ── BACKDROP ──────────────────────────────────────────
                    // Use GeometryReader to extend the image under the status bar
                    // WITHOUT putting ignoresSafeArea on an inner view (which breaks
                    // sibling layout frames and strips horizontal padding below).
                    GeometryReader { geo in
                        let topInset = geo.safeAreaInsets.top
                        let backdropURL = detail.background.flatMap(URL.init)
                            ?? detail.poster.flatMap(URL.init)

                        ZStack(alignment: .bottom) {
                            if let url = backdropURL {
                                AsyncImage(url: url) { phase in
                                    if case .success(let img) = phase {
                                        img.resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: geo.size.width, height: 380 + topInset)
                                            .clipped()
                                    } else {
                                        Color(LunaTheme.surfaceElevated)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 380 + topInset)
                                    }
                                }
                            } else {
                                Color(LunaTheme.surfaceElevated)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 380 + topInset)
                            }

                            LinearGradient(
                                stops: [
                                    .init(color: .clear,                            location: 0.0),
                                    .init(color: .clear,                            location: 0.30),
                                    .init(color: LunaTheme.background.opacity(0.6), location: 0.60),
                                    .init(color: LunaTheme.background,              location: 1.0),
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 380 + topInset)

                            // Title + meta overlaid at backdrop bottom
                            VStack(alignment: .leading, spacing: 6) {
                                if let genres = detail.genres, !genres.isEmpty {
                                    Text(genres.prefix(3).joined(separator: " · "))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.65))
                                        .lineLimit(1)
                                }

                                Text(detail.name)
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)

                                HStack(spacing: 8) {
                                    if let rating = detail.imdbRating {
                                        HStack(spacing: 3) {
                                            Image(systemName: "star.fill")
                                                .font(.caption2)
                                                .foregroundColor(.yellow)
                                            Text(rating)
                                                .font(.caption.bold())
                                                .foregroundColor(.yellow)
                                        }
                                    }
                                    if let release = detail.releaseInfo {
                                        Text(release)
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                    if let runtime = detail.runtime {
                                        Text(runtime)
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 380 + topInset)
                    }
                    .frame(height: 380)

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
                            .background(Capsule().fill(.white))
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
                                .foregroundColor(inLibrary ? LunaTheme.accent : .white)
                                .frame(width: 50, height: 50)
                        }
                        .glassCard(cornerRadius: 25)
                        .sensoryFeedback(.impact(weight: .light), trigger: inLibrary)

                        Button {
                            Task {
                                if isLiked {
                                    await likedRepo.removeLiked(mediaId: detail.id)
                                } else {
                                    await likedRepo.addLiked(LikedItem(
                                        mediaId: detail.id,
                                        mediaType: type,
                                        name: detail.name,
                                        poster: detail.rawPosterUrl ?? detail.poster,
                                        tmdbId: nil
                                    ))
                                }
                                isLiked = likedRepo.isLiked(detail.id)
                            }
                        } label: {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .font(.title3)
                                .foregroundColor(isLiked ? .red : .white)
                                .frame(width: 50, height: 50)
                        }
                        .glassCard(cornerRadius: 25)
                        .onAppear { isLiked = likedRepo.isLiked(detail.id) }
                        .sensoryFeedback(.impact(weight: .light), trigger: isLiked)

                        Button {
                            Task {
                                guard let profile = profileManager.currentProfile else { return }
                                if watched {
                                    await watchedRepo.markUnwatched(mediaId: detail.id)
                                } else {
                                    await watchedRepo.markWatched(
                                        profileId: profile.id,
                                        mediaId: detail.id,
                                        mediaType: type,
                                        name: detail.name,
                                        poster: detail.poster
                                    )
                                }
                            }
                        } label: {
                            Image(systemName: watched ? "checkmark.circle.fill" : "checkmark.circle")
                                .font(.title3)
                                .foregroundColor(watched ? .green : .white)
                                .frame(width: 50, height: 50)
                        }
                        .glassCard(cornerRadius: 25)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    if let deepDiveLink {
                        HStack(spacing: 10) {
                            companionButton(title: "Deep Dive", systemImage: "text.magnifyingglass") {
                                openURL(deepDiveLink)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }

                    // ── OVERVIEW ──────────────────────────────────────────
                    if let description = detail.description, !description.isEmpty {
                        ExpandableText(text: description)
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                    }

                    // ── DETAILS CHIPS ─────────────────────────────────────
                    detailChips(detail: detail)

                    // ── EPISODES ──────────────────────────────────────────
                    if let seasons = detail.seasons, !seasons.isEmpty {
                        let sorted = seasons.sorted { $0.number < $1.number }
                        let activeId = selectedSeasonId ?? sorted.first?.id

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Episodes")
                                .font(.headline).foregroundColor(.white)
                                .padding(.horizontal, 16)

                            // Season picker
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(sorted) { season in
                                        Button { selectedSeasonId = season.id } label: {
                                            Text("Season \(season.number)")
                                                .font(.subheadline.weight(.medium))
                                                .foregroundColor(season.id == activeId ? .black : .white.opacity(0.7))
                                                .padding(.horizontal, 14).padding(.vertical, 7)
                                                .background(
                                                    Capsule().fill(
                                                        season.id == activeId
                                                            ? LunaTheme.accent
                                                            : Color.white.opacity(0.12)
                                                    )
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }

                            if let activeSeason = sorted.first(where: { $0.id == activeId }),
                               let episodes = activeSeason.episodes {
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
                                                isWatched: watched
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
                                        }
                                    }
                                    .padding(.horizontal, 16)
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
                                            VStack(spacing: 4) {
                                                if let photo = person.photo, let url = URL(string: photo) {
                                                    CachedAsyncImage(url: url) { phase in
                                                        if case .success(let img) = phase {
                                                            img.resizable().scaledToFill()
                                                                .frame(width: 72, height: 90)
                                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                        } else {
                                                            castPortraitPlaceholder(person.name)
                                                        }
                                                    }
                                                } else {
                                                    castPortraitPlaceholder(person.name)
                                                }
                                                Text(person.name)
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundColor(.white)
                                                    .lineLimit(1)
                                                    .frame(width: 72)
                                                if let role = person.character {
                                                    Text(role)
                                                        .font(.system(size: 10))
                                                        .foregroundColor(LunaTheme.textTertiary)
                                                        .lineLimit(1)
                                                        .frame(width: 72)
                                                }
                                            }
                                            .frame(width: 72)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.top, 20)
                    }

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
                    Spacer().frame(height: 280)
                    ProgressView().tint(LunaTheme.accent)
                    Spacer()
                }
            } else if let error = metaRepo.errorMessage {
                VStack {
                    Spacer().frame(height: 200)
                    Text(error).foregroundColor(LunaTheme.textSecondary).padding().multilineTextAlignment(.center)
                    Spacer()
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(LunaTheme.background)
        .refreshable {
            await metaRepo.loadDetail(
                type: type,
                id: mediaId,
                addons: addonRepo.findAddonWithMetaResource(type: type)
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedMedia) { media in
            DetailScreen(mediaId: media.id, type: media.type.rawValue, name: media.name)
        }
        .fullScreenCover(item: $playerLaunch) { launch in
            PlayerScreen(launch: launch) {
                playerLaunch = nil
            }
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
            if addonRepo.enabledAddons.isEmpty, let profile = profileManager.currentProfile {
                await addonRepo.loadAddons(profileId: profile.id)
            }

            // Fire stream pre-fetch concurrently with meta load so streams are ready
            // by the time the user taps play — mirrors Stremio's guessStream strategy.
            let warmupAddons = addonRepo.enabledAddons
            let warmupType = type
            let warmupId = mediaId
            Task.detached(priority: .background) {
                await StreamWarmupRepository.shared.warmup(
                    type: warmupType, id: warmupId, addons: warmupAddons
                )
            }

            await metaRepo.loadDetail(
                type: type,
                id: mediaId,
                addons: addonRepo.findAddonWithMetaResource(type: type)
            )
            await loadCompanionLinks()
            await fetchMoreLikeThis()
            await fetchStreailerTrailers()
            if let profile = profileManager.currentProfile {
                await libraryRepo.loadLibrary(profileId: profile.id)
                await watchedRepo.loadAll(profileId: profile.id)
            }
        }
    }

    private func fetchMoreLikeThis() async {
        // 1. Try the dedicated MLT addon first (Trakt-powered, best semantic results)
        if let mltURL = URL(string: "\(Self.mltBaseURL)/catalog/\(type)/mlt/\(mediaId).json"),
           let data = try? await URLSession.shared.data(from: mltURL).0,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let metas = json["metas"] as? [[String: Any]], !metas.isEmpty {
            moreLikeThisItems = metas.compactMap { m -> MetaPreview? in
                guard let id = m["id"] as? String, let name = m["name"] as? String else { return nil }
                let typeStr = m["type"] as? String ?? type
                return MetaPreview(
                    id: id,
                    type: MediaType(rawValue: typeStr) ?? .movie,
                    name: name,
                    poster: m["poster"] as? String,
                    imdbRating: m["imdbRating"] as? String
                )
            }
            return
        }

        // 2. TMDB similar — already resolved with real IMDb IDs and posters during detail load
        if let tmdbSimilar = metaRepo.detail?.moreLikeThis, !tmdbSimilar.isEmpty {
            moreLikeThisItems = tmdbSimilar
            return
        }

        // 3. Last resort: genre-filtered catalog from installed addons
        guard let genre = metaRepo.detail?.genres?.first else { return }
        let results = await CatalogRepository.shared.fetchRelated(
            type: type,
            genre: genre,
            excludingId: mediaId,
            addons: addonRepo.enabledAddons
        )
        if !results.isEmpty {
            moreLikeThisItems = results
        }
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

    @ViewBuilder
    private func personInitialsCircle(_ name: String) -> some View {
        Circle()
            .fill(LunaTheme.surfaceElevated)
            .frame(width: 64, height: 64)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.title3.weight(.semibold))
                    .foregroundColor(LunaTheme.textSecondary)
            )
    }

    @ViewBuilder
    private func castPortraitPlaceholder(_ name: String) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(LunaTheme.surfaceElevated)
            .frame(width: 72, height: 90)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.title2.weight(.semibold))
                    .foregroundColor(LunaTheme.textSecondary)
            )
    }

    private func loadCompanionLinks() async {
        trailerLink = nil
        deepDiveLink = nil

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

        async let deepDive = companionLink(
            from: streamAddons,
            matching: { addon in
                addon.id == "org.stremio.deepdivecompanion"
                || addon.name.localizedCaseInsensitiveContains("Deep Dive")
                || addon.transportUrl?.contains("deepdive") == true
            },
            streamMatching: { stream in
                let text = [stream.name, stream.title, stream.description]
                    .compactMap { $0 }
                    .joined(separator: " ")
                    .lowercased()
                return text.contains("deep dive") || text.contains("analysis")
            }
        )

        trailerLink = await trailer
        deepDiveLink = await deepDive
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
        let hasGenres  = !(detail.genres ?? []).isEmpty
        let hasDirector = !(detail.director ?? []).isEmpty
        if hasGenres || hasDirector {
            VStack(alignment: .leading, spacing: 14) {
                if hasGenres {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GENRES")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(LunaTheme.textTertiary)
                            .tracking(1.5)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(detail.genres!, id: \.self) { genre in
                                    Text(genre)
                                        .font(.caption)
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(LunaTheme.surfaceElevated)
                                        .foregroundColor(LunaTheme.textSecondary)
                                        .cornerRadius(16)
                                }
                            }
                        }
                    }
                }
                if hasDirector {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DIRECTOR")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(LunaTheme.textTertiary)
                            .tracking(1.5)
                        Text(detail.director!.map(\.name).joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                }
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
                .foregroundColor(LunaTheme.textTertiary)
                .tracking(1.5)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(links) { link in
                        Text(link.name)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(LunaTheme.textSecondary)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(LunaTheme.surfaceElevated)
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
                        .fill(LunaTheme.surfaceElevated)
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
    }

    private var trailerPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(LunaTheme.surfaceElevated)
            .frame(width: 220, height: 124)
            .overlay(
                Image(systemName: "play.rectangle.fill")
                    .font(.title2)
                    .foregroundColor(LunaTheme.textTertiary)
            )
    }
}

// MARK: - Expandable overview text

private struct ExpandableText: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.subheadline)
                .foregroundColor(LunaTheme.textSecondary)
                .lineLimit(expanded ? nil : 3)
                .animation(.easeInOut(duration: 0.2), value: expanded)

            Button { expanded.toggle() } label: {
                Text(expanded ? "Less" : "More")
                    .font(.caption.bold())
                    .foregroundColor(LunaTheme.accent)
            }
        }
    }
}

// MARK: - Episode Card

struct EpisodeCard: View {
    let episode: MetaVideo
    let progressFraction: Double?
    let isWatched: Bool
    let onPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LunaTheme.surfaceElevated)
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
                                        .fill(LunaTheme.accent)
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

            if let epNum = episode.episode {
                Text("Episode \(epNum)")
                    .font(.caption2)
                    .foregroundColor(LunaTheme.textTertiary)
            }
            Text(episode.title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: 220, alignment: .leading)
            if let overview = episode.overview {
                Text(overview)
                    .font(.caption2)
                    .foregroundColor(LunaTheme.textSecondary)
                    .lineLimit(2)
                    .frame(width: 220, alignment: .leading)
            }
        }
    }

    private var episodePlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(LunaTheme.surfaceElevated)
            .frame(width: 220, height: 124)
            .overlay(
                Image(systemName: "play.rectangle.fill")
                    .font(.title2)
                    .foregroundColor(LunaTheme.textTertiary)
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
                                    .foregroundColor(LunaTheme.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        if let runtime = episode.runtime {
                            Text(runtime)
                                .font(.caption2)
                                .foregroundColor(LunaTheme.textTertiary)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(LunaTheme.surface)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LunaTheme.background)
        .navigationTitle(season.name ?? "Season \(season.number)")
    }
}
