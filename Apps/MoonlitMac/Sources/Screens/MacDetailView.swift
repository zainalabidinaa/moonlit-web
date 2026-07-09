import SwiftUI
import AppKit
import MoonlitCore

struct MacDetailView: View {
    let mediaId: String
    let type: String
    let name: String
    let onBack: () -> Void
    var onSelectActor: (Person) -> Void = { _ in }

    @StateObject private var metaRepo = MetaRepository.shared
    @StateObject private var libraryRepo = LibraryRepository.shared
    @StateObject private var watchedRepo = WatchProgressRepository.shared
    @EnvironmentObject var profileManager: ProfileManager
    @StateObject private var addonRepo = AddonRepository.shared
    @StateObject private var likedRepo = LikedRepository.shared
    @StateObject private var awardsMeta = AwardsMetadataService.shared
    @State private var showSourcePicker = false
    @State private var isResolvingPlayback = false
    @State private var selectedSeasonId: String?
    @State private var showSeasonPicker = false
    @State private var selectedVideoId: String?
    @State private var selectedSeasonNum: Int?
    @State private var selectedEpisodeNum: Int?
    @State private var selectedInitialPositionMs: Double?
    @State private var isLiked = false
    @State private var isResolvingDownload = false
    @State private var downloadMessage: String?
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var showFullOverview = false
    @State private var trailers: [MacMediaTrailer] = []
    @State private var trailerLink: URL?
    @State private var ambientColor: Color = .clear
    @State private var ambientColor2: Color = .clear
    @AppStorage("moonlit.cinematicModeEnabled") private var cinematicModeEnabled = true
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    private let contentMaxWidth: CGFloat = 1500
    private let contentHorizontalPadding: CGFloat = 28
    private let heroHeight: CGFloat = 780

    private var staleDetailLabel: String {
        guard let updatedAt = metaRepo.cachedDetailUpdatedAt else {
            return "Showing saved details"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Last updated \(formatter.localizedString(for: updatedAt, relativeTo: Date()))"
    }

    var body: some View {
        detailScroll
    }

    private var detailScroll: some View {
        ZStack(alignment: .top) {
            MacFusionAmbientBackground(
                ambientColor: ambientColor,
                ambientColor2: ambientColor2,
                isEnabled: cinematicModeEnabled,
                intensity: 0.55,
                glowHeight: heroHeight
            )
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.9), value: ambientColor)
            .animation(.easeInOut(duration: 0.9), value: ambientColor2)

            ScrollView {
                if let detail = metaRepo.detail {
                    VStack(alignment: .leading, spacing: 0) {
                        hero(for: detail)

                        if metaRepo.isShowingStaleDetail {
                            staleIndicator
                        }

                        if let directors = detail.director, !directors.isEmpty {
                            directorsView(directors)
                                .padding(.top, 12)
                        }

                        if let links = detail.links, !links.isEmpty {
                            linksView(links)
                                .padding(.top, 16)
                        }

                        if let seasons = detail.seasons, !seasons.isEmpty {
                            episodesView(seasons)
                                .padding(.top, 48)
                        }

                        contentRail { MacCrewInfoGrid(detail: detail) }
                            .padding(.top, 48)

                        if let cast = detail.cast, !cast.isEmpty {
                            castView(cast)
                                .padding(.top, 48)
                        }

                        contentRail { MacMediaGallerySection(detail: detail, trailers: trailers) }
                            .padding(.top, 48)

                        if let summary = awardsMeta.summary(forId: detail.id) {
                            contentRail { MacAwardsRecognitionSection(summary: summary) }
                                .padding(.top, 48)
                        }

                        contentRail { MacInformationGrid(detail: detail) }
                            .padding(.top, 48)

                        if let recommendations = detail.recommendations, !recommendations.isEmpty {
                            moreLikeThisView(title: "More Like This", recommendations)
                                .padding(.top, 48)
                        }

                        if let related = detail.moreLikeThis, !related.isEmpty {
                            moreLikeThisView(title: "You Might Also Like", related)
                                .padding(.top, 48)
                        }

                        Spacer().frame(height: 32)
                    }
                } else if metaRepo.isLoading {
                    VStack {
                        Spacer().frame(height: 200)
                        MacLoadingView(size: 44)
                        Spacer()
                    }
                } else if let error = metaRepo.errorMessage {
                    VStack(spacing: 12) {
                        Spacer().frame(height: 200)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundColor(MoonlitTheme.textSecondary)
                        Text(error)
                            .foregroundColor(MoonlitTheme.textSecondary)
                            .padding()
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                }
            }
            // Let the hero backdrop bleed up to the true window top so there's
            // no strip of bare ambient wash above it. The hero's own top
            // content compensates with extra top padding to clear the
            // traffic-light controls.
            .ignoresSafeArea(.container, edges: .top)

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
        .sheet(isPresented: $showSourcePicker) {
            MacSourcePickerView(
                mediaType: MediaType(rawValue: type) ?? .movie,
                mediaId: mediaId,
                mediaName: metaRepo.detail?.name ?? name,
                poster: metaRepo.detail?.poster,
                logo: metaRepo.detail?.logo,
                background: metaRepo.detail?.background,
                videoId: selectedVideoId,
                seasonNumber: selectedSeasonNum,
                episodeNumber: selectedEpisodeNum,
                onLaunch: { launch in
                    showSourcePicker = false
                    openWindow(id: "player", value: launch)
                }
            )
            .frame(minWidth: 500, minHeight: 400)
        }
        .task {
            await metaRepo.loadDetail(type: type, id: mediaId, addons: addonRepo.findAddonWithMetaResource(type: type))
            if let profile = profileManager.currentProfile {
                await libraryRepo.loadLibrary(profileId: profile.id)
                await watchedRepo.loadAll(profileId: profile.id)
                isLiked = likedRepo.isLiked(mediaId)
            }
            Task.detached { await StreamWarmupRepository.shared.warmup(type: type, id: mediaId, addons: addonRepo.managedAddons.map(\.manifest)) }
        }
        .task(id: metaRepo.detail?.id) {
            guard let detail = metaRepo.detail else { return }
            await fetchTrailers(detail: detail)
            if detail.id.hasPrefix("tt") {
                await awardsMeta.fetch(id: detail.id)
            }
        }
        .task(id: metaRepo.detail?.logo) {
            guard let logoURL = metaRepo.detail?.logo.flatMap(URL.init) else { return }
            _ = await MoonlitImageCache.image(for: logoURL)
        }
        .task(id: "\(metaRepo.detail?.id ?? "")-\(cinematicModeEnabled)") {
            await updateAmbientColorIfNeeded()
        }
    }

    private func updateAmbientColorIfNeeded() async {
        guard cinematicModeEnabled, let urlString = metaRepo.detail?.background, let url = URL(string: urlString) else {
            ambientColor = .clear
            ambientColor2 = .clear
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = NSImage(data: data), let (c1, c2) = image.moonlitAmbientColors() else { return }
            ambientColor = c1.moonlitBoostedForAmbient
            ambientColor2 = c2.moonlitBoostedForAmbient
        } catch {
            ambientColor = .clear
            ambientColor2 = .clear
        }
    }

    // MARK: - Hero

    private func hero(for detail: MetaDetail) -> some View {
        ZStack(alignment: .bottomLeading) {
            backdrop(for: detail.background)

            contentRail {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 22) {
                        if let tagline = detail.tagline, !tagline.isEmpty {
                            Text(tagline)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white.opacity(0.48))
                                .tracking(4.2)
                                .textCase(.uppercase)
                                .lineLimit(1)
                        }

                        heroLogoOrTitle(for: detail)
                    }
                    .frame(maxWidth: 760, alignment: .leading)

                    heroMetadata(for: detail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 22) {
                        heroActions(for: detail)
                            .padding(.top, 10)

                        if let description = detail.description, !description.isEmpty {
                            heroOverview(description)
                                .padding(.top, 8)
                        }
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                }
            }
            .padding(.bottom, 90)
        }
        .frame(height: heroHeight)
    }

    private func heroOverview(_ description: String) -> some View {
        Button {
            showFullOverview.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Overview")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Text(description)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(showFullOverview ? nil : 3)
                    .multilineTextAlignment(.leading)
                if !showFullOverview && description.count > 220 {
                    Text("Show more")
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func backdrop(for background: String?) -> some View {
        if let background, let url = URL(string: background) {
            Color.clear
                .frame(height: heroHeight)
                .overlay(alignment: .top) {
                    ZStack(alignment: .top) {
                        CachedAsyncImage(url: url, maxDimension: 3000) { image in
                            image.resizable()
                                .scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }

                        LinearGradient(
                            stops: [
                                .init(color: MoonlitTheme.background.opacity(0.85), location: 0.0),
                                .init(color: MoonlitTheme.background.opacity(0.45), location: 0.28),
                                .init(color: .clear, location: 0.62)
                            ],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .allowsHitTesting(false)
                    }
                    .mask(
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
                    )
                }
        } else {
            MoonlitTheme.surfaceElevated.frame(height: heroHeight)
        }
    }

    @ViewBuilder
    private func heroLogoOrTitle(for detail: MetaDetail) -> some View {
        if let logoURL = detail.logo.flatMap(URL.init) {
            CachedAsyncImage(url: logoURL) { image in
                image.resizable()
                    .scaledToFit()
                    .frame(maxWidth: 390, maxHeight: 176, alignment: .leading)
                    .shadow(color: .black.opacity(0.65), radius: 12, x: 0, y: 5)
            } placeholder: {
                heroTextTitle(detail.name)
            }
            .id(detail.logo)
        } else {
            heroTextTitle(detail.name)
        }
    }

    private func heroTextTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 66, weight: .medium, design: .serif))
            .foregroundStyle(
                LinearGradient(
                    colors: [.white, MoonlitTheme.harborGold.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .lineLimit(2)
            .shadow(color: .black.opacity(0.52), radius: 10, x: 0, y: 4)
    }

    private func heroMetadata(for detail: MetaDetail) -> some View {
        HStack(spacing: 10) {
            if let year = releaseYear(from: detail.releaseInfo) {
                metadataChip(year)
            }
            if let rating = detail.imdbRating {
                metadataChip {
                    Text("IMDb")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(MoonlitTheme.harborGold)
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(MoonlitTheme.harborGold)
                    Text(rating)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            if let seasons = seasonSummary(for: detail) {
                metadataChip(seasons)
            } else if let runtime = detail.runtime {
                metadataChip(runtime)
            }
            ForEach((detail.genres ?? []).prefix(3), id: \.self) { genre in
                metadataChip(genre)
            }

            if let summary = awardsMeta.summary(forId: detail.id) {
                Spacer(minLength: 20)
                inlineAwardBadge(summary)
            }
        }
    }

    @ViewBuilder
    private func inlineAwardBadge(_ summary: AwardSummary) -> some View {
        if let body = summary.primaryBodyWithAsset {
            HStack(spacing: 12) {
                HStack(spacing: -4) {
                    Image(systemName: "laurel.leading")
                        .font(.system(size: 30))
                        .foregroundColor(body.tintColor)
                    if let asset = body.assetName {
                        Image(asset)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                    }
                    Image(systemName: "laurel.trailing")
                        .font(.system(size: 30))
                        .foregroundColor(body.tintColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(body.displayName) \(summary.isWinner ? "Winner" : "Nominee")")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundColor(.white.opacity(0.85))
                    Text(awardCountLine(summary))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
    }

    private func awardCountLine(_ summary: AwardSummary) -> String {
        guard let body = summary.primaryBody else { return "" }
        var parts: [String] = []
        if summary.totalWins > 0 {
            parts.append("\(summary.totalWins) \(body.displayName)\(summary.totalWins == 1 ? "" : "s")")
        }
        if summary.totalNominations > 0 {
            parts.append("\(summary.totalNominations) nomination\(summary.totalNominations == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    private func metadataChip(_ text: String) -> some View {
        metadataChip {
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.76))
        }
    }

    private func metadataChip<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            content()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.045), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    private func releaseYear(from releaseInfo: String?) -> String? {
        guard let releaseInfo else { return nil }
        let digits = releaseInfo.prefix(4)
        return digits.count == 4 && digits.allSatisfy(\.isNumber) ? String(digits) : releaseInfo
    }

    private func seasonSummary(for detail: MetaDetail) -> String? {
        guard let seasons = detail.seasons?.filter({ $0.number != 0 }), !seasons.isEmpty else { return nil }
        return seasons.count == 1 ? "1 season" : "\(seasons.count) seasons"
    }

    private var staleIndicator: some View {
        contentRail {
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
        }
        .padding(.top, 10)
    }

    // MARK: - Actions

    private func heroActions(for detail: MetaDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 12) {
                let progress = watchedRepo.getProgress(mediaId: detail.id)
                let watched = watchedRepo.isWatched(mediaId: detail.id)

                Button {
                    let initMs = progress.map { $0.positionSeconds * 1000 }
                    playNow(
                        detail: detail,
                        videoId: nil,
                        seasonNum: nil,
                        episodeNum: nil,
                        initialPositionMs: initMs
                    )
                } label: {
                    HStack(spacing: 8) {
                        if isResolvingPlayback {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.black)
                        } else {
                            Image(systemName: progress == nil ? "play.fill" : "play.circle.fill")
                        }
                        Text(playButtonTitle(hasProgress: progress != nil, isWatched: watched, progress: progress))
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: 240)
                    .padding(.vertical, 13)
                    .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isResolvingPlayback)

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
                    HStack(spacing: 8) {
                        Image(systemName: inLibrary ? "checkmark" : "plus")
                            .font(.system(size: 14, weight: .semibold))
                        Text(inLibrary ? "In Watchlist" : "Add to Watchlist")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .background(Color.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)

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
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(isLiked ? .red : .white)
                        .frame(width: 50, height: 50)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)

                let existingDownload = downloadManager.downloads.first { $0.mediaId == detail.id }
                Button {
                    startDownload()
                } label: {
                    Group {
                        if isResolvingDownload {
                            ProgressView().controlSize(.small).tint(.white)
                        } else if existingDownload?.state == .completed {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(MoonlitTheme.accent)
                        } else if existingDownload?.state == .downloading || existingDownload?.state == .queued {
                            Image(systemName: "stop.circle")
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: "arrow.down.to.line")
                                .foregroundColor(.white)
                        }
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 50, height: 50)
                    .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isResolvingDownload)
                .help(downloadButtonHelp(existingDownload))
                .onAppear { isLiked = likedRepo.isLiked(detail.id) }

                if let firstTrailerURL = trailers.first?.url.flatMap(URL.init) {
                    Button {
                        openURL(firstTrailerURL)
                    } label: {
                        Image(systemName: "play.rectangle")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.white.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Menu {
                    Button {
                        Task {
                            guard let profile = profileManager.currentProfile else { return }
                            if watchedRepo.isWatched(mediaId: detail.id) {
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
                        Label(
                            watchedRepo.isWatched(mediaId: detail.id) ? "Mark as Unwatched" : "Mark as Watched",
                            systemImage: "checkmark.circle"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            if let downloadMessage {
                Text(downloadMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MoonlitTheme.textSecondary)
                    .padding(.top, 6)
            }
        }
    }

    private func downloadButtonHelp(_ existing: DownloadItem?) -> String {
        switch existing?.state {
        case .completed: return "Downloaded — available offline"
        case .downloading, .queued: return "Downloading…"
        case .failed: return "Download failed — tap to retry"
        default: return "Download for offline playback"
        }
    }

    private func startDownload() {
        guard let detail = metaRepo.detail, !isResolvingDownload else { return }

        if let existing = downloadManager.downloads.first(where: { $0.mediaId == detail.id }) {
            if existing.state == .completed {
                downloadMessage = "Already downloaded"
                return
            }
            if existing.state == .downloading || existing.state == .queued {
                downloadManager.delete(existing)
                downloadMessage = "Download cancelled"
                return
            }
        }

        isResolvingDownload = true
        downloadMessage = "Finding a downloadable source…"
        Task {
            await StreamRepository.shared.fetchStreams(
                type: type,
                id: detail.id,
                addons: addonRepo.enabledAddons
            )
            let candidates = StreamSourceSelector.cachedCandidates(
                currentUrl: nil,
                from: StreamRepository.shared.streams
            )
            isResolvingDownload = false

            guard let candidate = candidates.first(where: {
                $0.url.map { DownloadSupport.isDownloadable($0) } ?? false
            }), let url = candidate.url else {
                downloadMessage = "Not available offline"
                return
            }

            let ok = downloadManager.startDownload(
                mediaId: detail.id,
                type: type,
                name: detail.name,
                poster: detail.rawPosterUrl ?? detail.poster,
                quality: candidate.displayName,
                url: url,
                headers: candidate.behaviorHints?.proxyHeaders?.request
            )
            downloadMessage = ok ? "Download started" : "Not available offline"
        }
    }

    private func playButtonTitle(hasProgress: Bool, isWatched: Bool, progress: WatchProgressEntry?) -> String {
        if isWatched { return "Rewatch" }
        if let progress, progress.progressFraction > 0.01 {
            if let season = progress.season, let episode = progress.episode {
                return "Continue · S\(season)E\(episode)"
            }
            let minutes = Int(progress.positionSeconds / 60)
            let seconds = Int(progress.positionSeconds) % 60
            return "Continue · \(minutes):\(String(format: "%02d", seconds))"
        }
        return "Play"
    }

    // MARK: - Overview

    // MARK: - Directors

    private func directorsView(_ directors: [Person]) -> some View {
        contentRail {
            VStack(alignment: .leading, spacing: 4) {
                Text("Director")
                    .font(.caption)
                    .foregroundColor(MoonlitTheme.textTertiary)
                Text(directors.map(\.name).joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - Links

    private func linksView(_ links: [MetaLink]) -> some View {
        let networks = links.filter { $0.category?.lowercased() == "network" }
        let studios = links.filter { $0.category?.lowercased() == "production" }
        return Group {
            if !networks.isEmpty || !studios.isEmpty {
                contentRail {
                    VStack(alignment: .leading, spacing: 8) {
                        if !networks.isEmpty {
                            linkRow(label: "NETWORK", links: networks)
                        }
                        if !studios.isEmpty {
                            linkRow(label: "PRODUCTION", links: studios)
                        }
                    }
                }
            }
        }
    }

    private func linkRow(label: String, links: [MetaLink]) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(MoonlitTheme.textTertiary)
                .frame(width: 80, alignment: .leading)
            ForEach(links) { link in
                Button {
                    if let url = URL(string: link.url) {
                        openURL(url)
                    }
                } label: {
                    Text(link.name)
                        .font(.subheadline)
                        .foregroundColor(MoonlitTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - More Like This

    private func moreLikeThisView(title: String, _ items: [MetaPreview]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            contentRail {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items.prefix(20)) { item in
                        MediaCard(item: item, width: 154, height: 231)
                            .onTapGesture {
                                onBack()
                            }
                    }
                }
                .padding(.horizontal, contentHorizontalPadding)
            }
        }
    }

    // MARK: - Cast

    private func castView(_ cast: [Person]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            contentRail {
                Text("Cast · \(cast.count)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(cast.prefix(15)) { person in
                        Button {
                            onSelectActor(person)
                        } label: {
                            VStack(spacing: 4) {
                                // Request a larger TMDB profile size than the shared
                                // w185 default (used on iOS) for crisper Retina cards.
                                let photoURL = person.photo
                                    .map { $0.replacingOccurrences(of: "/w185", with: "/w342") }
                                    .flatMap(URL.init)
                                if let url = photoURL {
                                    CachedAsyncImage(url: url) { img in
                                        img.resizable().scaledToFill()
                                    } placeholder: {
                                        castPlaceholder(for: person.name)
                                    }
                                    .frame(width: 148, height: 207)
                                    .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard, style: .continuous))
                                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                                } else {
                                    castPlaceholder(for: person.name)
                                        .frame(width: 148, height: 207)
                                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                                }
                                Text(person.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .frame(width: 148)
                                if let character = person.character {
                                    Text(character)
                                        .font(.caption)
                                        .foregroundColor(MoonlitTheme.textTertiary)
                                        .lineLimit(1)
                                        .frame(width: 148)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, contentHorizontalPadding)
            }
        }
    }

    @ViewBuilder
    private func castPlaceholder(for name: String) -> some View {
        RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard, style: .continuous)
            .fill(MoonlitTheme.surfaceElevated)
            .overlay(
                Text(String(name.prefix(1)))
                    .font(.title2)
                    .foregroundColor(MoonlitTheme.textSecondary)
            )
    }

    // MARK: - Episodes

    private func episodesView(_ seasons: [Season]) -> some View {
        let sorted = seasons.filter { $0.number != 0 }.sorted { $0.number < $1.number }
        let activeId = selectedSeasonId ?? sorted.first?.id

        return contentRail {
            let activeSeason = sorted.first { $0.id == activeId }
            let episodes = activeSeason?.episodes ?? []

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Episodes")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)

                        Text(episodeSubtitle(for: activeSeason))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(MoonlitTheme.textTertiary)
                    }

                    Spacer()

                    Button {
                        Task { await markSeasonWatched(activeSeason) }
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white.opacity(0.75))
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Mark Season \(activeSeason?.number ?? 1) as Watched")

                    Button {
                        showSeasonPicker.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Text(activeSeason?.name ?? "Season \(activeSeason?.number ?? 1)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                            if hasUnwatchedEpisodes(activeSeason) {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showSeasonPicker, arrowEdge: .top) {
                        seasonPickerList(sorted, activeId: activeId)
                    }
                }

                if let activeSeason {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 300), spacing: 20)], alignment: .leading, spacing: 28) {
                            ForEach(episodes) { ep in
                                let seasonNumber = ep.season ?? activeSeason.number
                                let progress = watchedRepo.getEpisodeProgress(
                                    parentMediaId: detailId(for: activeSeason),
                                    season: seasonNumber,
                                    episode: ep.episode
                                )
                                let watched = watchedRepo.isEpisodeWatched(
                                    parentMediaId: detailId(for: activeSeason),
                                    season: seasonNumber,
                                    episode: ep.episode
                                )
                                MacEpisodeListRow(
                                    episode: ep,
                                    seasonNumber: seasonNumber,
                                    progressFraction: progress?.progressFraction,
                                    isWatched: watched,
                                    onToggleWatched: {
                                        Task {
                                            if watched {
                                                await watchedRepo.markUnwatched(mediaId: ep.id)
                                            } else if let profile = profileManager.currentProfile,
                                                      let detail = metaRepo.detail {
                                                await watchedRepo.markWatched(
                                                    profileId: profile.id,
                                                    mediaId: ep.id,
                                                    mediaType: type,
                                                    name: detail.name,
                                                    poster: detail.poster,
                                                    season: seasonNumber,
                                                    episode: ep.episode
                                                )
                                            }
                                        }
                                    },
                                    onPlay: {
                                        playNow(
                                            detail: metaRepo.detail,
                                            videoId: ep.id,
                                            seasonNum: seasonNumber,
                                            episodeNum: ep.episode,
                                            initialPositionMs: progress.map { $0.positionSeconds * 1000 }
                                        )
                                    }
                                )
                            }
                    }
                }
            }
        }
    }

    private func detailId(for season: Season) -> String {
        metaRepo.detail?.id ?? mediaId
    }

    private func markSeasonWatched(_ season: Season?) async {
        guard let season, let episodes = season.episodes,
              let profile = profileManager.currentProfile,
              let detail = metaRepo.detail else { return }
        await watchedRepo.markSeasonWatched(
            profileId: profile.id,
            seriesId: detail.id,
            mediaType: type,
            season: season.number,
            episodes: episodes.map { (mediaId: $0.id, episode: $0.episode) },
            name: detail.name,
            poster: detail.poster
        )
    }

    @ViewBuilder
    private func seasonPickerList(_ seasons: [Season], activeId: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(seasons) { season in
                Button {
                    selectedSeasonId = season.id
                    showSeasonPicker = false
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(season.name ?? "Season \(season.number)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            Text(episodeSubtitle(for: season))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(MoonlitTheme.textTertiary)
                        }
                        Spacer()
                        if season.id == seasons.last?.id {
                            Text("NEW")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(MoonlitTheme.harborGold, in: Capsule())
                        }
                        if season.id == (activeId ?? seasons.first?.id) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(MoonlitTheme.harborGold)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    season.id == (activeId ?? seasons.first?.id)
                        ? Color.white.opacity(0.06) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }
        }
        .padding(8)
        .frame(minWidth: 240)
        .background(MoonlitTheme.background)
    }

    private func hasUnwatchedEpisodes(_ season: Season?) -> Bool {
        guard let season, let episodes = season.episodes, let seriesId = metaRepo.detail?.id else { return false }
        return episodes.contains { ep in
            !watchedRepo.isEpisodeWatched(parentMediaId: seriesId, season: season.number, episode: ep.episode)
        }
    }

    private func episodeSubtitle(for season: Season?) -> String {
        let count = season?.episodes?.count ?? 0
        let year = season?.episodes?
            .compactMap { MoonlitDateFormatting.year(from: $0.released) }
            .first
        if let year {
            return "\(count) episode\(count == 1 ? "" : "s") · \(year)"
        }
        return "\(count) episode\(count == 1 ? "" : "s")"
    }

    // MARK: - Playback

    /// Resolves a stream and opens the player directly when autoplay is on,
    /// so playback starts immediately and the player's own startup overlay
    /// handles the wait — no separate "finding streams" screen beforehand.
    /// Falls back to the manual source-picker sheet otherwise.
    private func playNow(
        detail: MetaDetail?,
        videoId: String?,
        seasonNum: Int?,
        episodeNum: Int?,
        initialPositionMs: Double?
    ) {
        guard let detail else { return }
        let isAutomatic = ProfileManager.shared.currentProfile
            .map { StreamAutoplayPreferenceStore.shared.mode(profileId: $0.id) == .automatic }
            ?? false

        guard isAutomatic, !isResolvingPlayback else {
            selectedVideoId = videoId
            selectedSeasonNum = seasonNum
            selectedEpisodeNum = episodeNum
            selectedInitialPositionMs = initialPositionMs
            showSourcePicker = true
            return
        }

        isResolvingPlayback = true
        Task {
            let lookupId = videoId ?? mediaId
            await StreamRepository.shared.fetchStreams(
                type: type,
                id: lookupId,
                addons: addonRepo.enabledAddons
            )
            let candidates = StreamSourceSelector.cachedCandidates(
                currentUrl: nil,
                from: StreamRepository.shared.streams
            )
            isResolvingPlayback = false

            guard let candidate = candidates.first(where: { $0.url != nil }),
                  let url = candidate.url else {
                selectedVideoId = videoId
                selectedSeasonNum = seasonNum
                selectedEpisodeNum = episodeNum
                selectedInitialPositionMs = initialPositionMs
                showSourcePicker = true
                return
            }

            let launch = PlayerLaunch(
                title: detail.name,
                sourceUrl: url,
                sourceHeaders: candidate.behaviorHints?.proxyHeaders?.request,
                logo: detail.logo, poster: detail.poster,
                background: detail.background,
                seasonNumber: seasonNum,
                episodeNumber: episodeNum,
                streamTitle: candidate.displayName,
                providerName: candidate.addonName,
                contentType: MediaType(rawValue: type) ?? .movie,
                videoId: lookupId,
                parentMetaId: detail.id,
                parentMetaType: type,
                initialPositionMs: initialPositionMs
            )
            openWindow(id: "player", value: launch)
        }
    }

    // MARK: - Data Fetching

    private func fetchTrailers(detail: MetaDetail) async {
        var allTrailers: [MacMediaTrailer] = []

        if type == "series", let seasons = detail.seasons?.filter({ $0.number != 0 }), !seasons.isEmpty {
            let seasonTrailers = await TMDBDiscoverService.shared.seasonTrailers(
                imdbId: detail.id,
                seasonNumbers: seasons.map(\.number)
            )
            allTrailers.append(contentsOf: seasonTrailers.map {
                MacMediaTrailer(
                    name: detail.name,
                    url: $0.youtubeWatchURL?.absoluteString,
                    seasonLabel: $0.name,
                    ytId: $0.youtubeKey
                )
            })
        } else if type == "movie" {
            let movieTrailers = await TMDBDiscoverService.shared.movieTrailers(imdbId: detail.id)
            allTrailers.append(contentsOf: movieTrailers.map {
                MacMediaTrailer(
                    name: detail.name,
                    url: $0.youtubeWatchURL?.absoluteString,
                    seasonLabel: $0.name,
                    ytId: $0.youtubeKey
                )
            })
        }

        // The generic addon trailer often has no YouTube id (so no thumbnail) —
        // only worth showing when TMDB found nothing at all.
        if allTrailers.isEmpty {
            let streailerBase = "https://streailer.elfhosted.com"
            if let streams = try? await StreamService.shared.fetchStreams(
                type: type,
                id: mediaId,
                baseURL: streailerBase
            ) {
                let trailers = streams.compactMap { stream -> MacMediaTrailer? in
                    guard let name = stream.name, !name.isEmpty, stream.ytId != nil else { return nil }
                    let watchURL = stream.url ?? stream.ytId.map { "https://www.youtube.com/watch?v=\($0)" }
                    return MacMediaTrailer(
                        name: name.trimmingCharacters(in: .whitespaces),
                        url: watchURL,
                        ytId: stream.ytId
                    )
                }
                allTrailers.append(contentsOf: trailers)
            }
        }

        await MainActor.run { self.trailers = allTrailers }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func contentRail<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack {
            content()
                .frame(maxWidth: contentMaxWidth, alignment: .leading)
            Spacer(minLength: 0)
        }
                .padding(.horizontal, contentHorizontalPadding)
                .padding(.vertical, 10)
            }

    @ViewBuilder
    private func posterView(for poster: String?) -> some View {
        if let poster, let url = URL(string: poster) {
            CachedAsyncImage(url: url) { image in
                image.resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                MoonlitTheme.surfaceElevated
            }
            .frame(width: 118, height: 177)
            .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
        }
    }
}

// MARK: - Episode Row

private struct MacEpisodeListRow: View {
    let episode: MetaVideo
    let seasonNumber: Int
    let progressFraction: Double?
    let isWatched: Bool
    let onToggleWatched: () -> Void
    let onPlay: () -> Void

    @State private var isHovering = false

    private let thumbWidth: CGFloat = 260
    private let thumbHeight: CGFloat = 146

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            still
                .frame(width: thumbWidth, height: thumbHeight)

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(episode.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(metaLine)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MoonlitTheme.textTertiary)

                    if let overview = episode.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MoonlitTheme.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 6)

                Button(action: onToggleWatched) {
                    Image(systemName: isWatched ? "eye.fill" : "eye")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isWatched ? .white : .white.opacity(0.64))
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(isWatched ? 0.14 : 0.06), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .frame(width: thumbWidth, alignment: .leading)
        }
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isHovering)
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
        .onHover { isHovering = $0 }
    }

    private var still: some View {
        ZStack {
            RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl, style: .continuous)
                .fill(MoonlitTheme.surfaceElevated)

            if let thumb = episode.thumbnail, let url = URL(string: thumb) {
                CachedAsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
                .frame(width: thumbWidth, height: thumbHeight)
                .clipped()
            }

            VStack {
                HStack {
                    Text(episodeNumberText)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.78), in: Capsule())
                    Spacer()
                    if isWatched {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundColor(Color(red: 0.25, green: 0.86, blue: 0.52))
                            .shadow(color: .black.opacity(0.55), radius: 5)
                    }
                }
                Spacer()
                HStack {
                    if let rating = episode.voteAverage, rating > 0 {
                        RatingBadge(rating: String(format: "%.1f", rating), compact: true)
                    }
                    Spacer()
                }
            }
            .padding(8)

            if let fraction = progressFraction, fraction > 0, !isWatched {
                VStack {
                    Spacer()
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.28))
                            Capsule()
                                .fill(MoonlitTheme.accent)
                                .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
                        }
                    }
                    .frame(height: 3)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl, style: .continuous))
    }

    private var episodeNumberText: String {
        if let episode = episode.episode { return "\(episode)" }
        return "-"
    }

    private var metaLine: String {
        var parts: [String] = []
        if let episode = episode.episode {
            parts.append("S\(seasonNumber) E\(episode)")
        } else {
            parts.append("S\(seasonNumber)")
        }
        if let runtime = episode.runtime, !runtime.isEmpty {
            parts.append(runtime)
        }
        if let released = MoonlitDateFormatting.mediumDate(from: episode.released) {
            parts.append(released)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - DetailItem (for window-based navigation)

struct DetailItem: Codable, Hashable {
    let mediaId: String
    let type: String
    let name: String
}
