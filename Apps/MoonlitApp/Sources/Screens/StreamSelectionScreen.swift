import SwiftUI
import MoonlitCore

struct StreamSelectionScreen: View {
    let mediaType: MediaType
    let mediaId: String
    let mediaName: String
    let poster: String?
    let logo: String?
    var episodeThumbnail: String? = nil
    var background: String? = nil
    var parentMetaId: String? = nil
    var parentMetaType: String? = nil
    var seasonNumber: Int? = nil
    var episodeNumber: Int? = nil
    var episodeTitle: String? = nil
    var initialPositionMs: Double? = nil

    @StateObject private var streamRepo = StreamRepository.shared
    @StateObject private var addonRepo = AddonRepository.shared
    @StateObject private var metaRepo = MetaRepository.shared
    @State private var selectedStream: StreamItem?
    @State private var showPlayer = false
    @State private var playerLaunch: PlayerLaunch?
    @State private var noUrlAlert = false
    @State private var upgradeAlert = false
    @State private var didAutoLaunch = false
    @State private var resolvedLogo: String?
    @State private var resolvedBackground: String?
    @State private var resolvedPoster: String?
    @State private var autoLaunchTask: Task<Void, Never>?
    @State private var selectedAddonFilter: String? = nil
    @State private var cachedPlayableStreams: [StreamItem] = []
    @AppStorage("moonlit.guestMode") private var guestMode = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if autoplayMode == .manual {
                let backdropURL = (episodeThumbnail ?? poster).flatMap(URL.init)
                if let url = backdropURL {
                    CachedAsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable()
                                .aspectRatio(contentMode: .fill)
                                .ignoresSafeArea()
                        }
                    }
                    .blur(radius: 24, opaque: true)
                    .ignoresSafeArea()
                }
                Color.black.opacity(backdropURL == nil ? 1 : 0.58).ignoresSafeArea()

                manualPickerContent
            } else {
                // Auto-play: same branded card as the player, so tapping Play →
                // video is one continuous loading screen.
                PlaybackLoadingView(
                    backgroundURL: background ?? resolvedBackground ?? episodeThumbnail ?? poster ?? resolvedPoster,
                    logoURL: loadingLogoURL,
                    title: mediaName,
                    statusOverride: playbackUnavailable ? " " : nil
                )
                .overlay {
                    if playbackUnavailable {
                        PlaybackUnavailableAlert(contextTitle: playbackContextTitle)
                    }
                }
                .overlay(alignment: .topLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                    }
                    .glassCircle(clear: true)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: selectedStream?.id)
        .fullScreenCover(isPresented: $showPlayer) {
            if let launch = playerLaunch {
                PlayerScreen(
                    launch: launch,
                    onDismiss: {
                        showPlayer = false
                        dismiss()
                    }
                )
            }
        }
        .alert("No direct URL", isPresented: $noUrlAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This stream doesn't have a direct playback URL.")
        }
        .alert("Streaming unavailable", isPresented: $upgradeAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Streaming isn't available on this account.")
        }
        .onChange(of: streamRepo.streams) { _, streams in
            cachedPlayableStreams = StreamSourceSelector.playbackCandidates(from: streams)
            if let filter = selectedAddonFilter, !streams.contains(where: { $0.addonName == filter }) {
                selectedAddonFilter = nil
            }
            scheduleAutoLaunchIfNeeded(streams: streams)
        }
        .onChange(of: streamRepo.isLoading) { _, isLoading in
            guard !isLoading else { return }
            scheduleAutoLaunchIfNeeded(streams: streamRepo.streams)
        }
        .task {
            streamRepo.clearStreams()
            cachedPlayableStreams = []
            didAutoLaunch = false
            autoLaunchTask?.cancel()
            guard !isGuestWithoutAccount else {
                didAutoLaunch = true
                await resolveMissingArtworkIfNeeded()
                return
            }
            if addonRepo.enabledAddons.isEmpty,
               let profile = ProfileManager.shared.currentProfile {
                await addonRepo.loadAddons(profileId: profile.id)
            }
            await resolveMissingArtworkIfNeeded()
            await streamRepo.fetchStreams(
                type: mediaType.rawValue,
                id: mediaId,
                addons: streamRequestAddons
            )
            cachedPlayableStreams = StreamSourceSelector.playbackCandidates(from: streamRepo.streams)
            if streamRepo.streams.isEmpty {
                didAutoLaunch = true
            }
        }
        .onDisappear {
            autoLaunchTask?.cancel()
        }
    }

    private var loadingLogoURL: URL? {
        (logo ?? resolvedLogo).flatMap(URL.init)
    }

    private var playbackUnavailable: Bool {
        !streamRepo.isLoading && didAutoLaunch && cachedPlayableStreams.isEmpty
    }

    private var playbackContextTitle: String {
        if let episodeTitle, !episodeTitle.isEmpty {
            if let seasonNumber, let episodeNumber {
                return "S\(seasonNumber)E\(episodeNumber) · \(episodeTitle)"
            }
            return episodeTitle
        }
        return mediaName
    }

    private var manualPickerContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .glassCard(cornerRadius: 22)
                }
                .buttonStyle(.plain)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Choose Source")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Text(mediaName)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.62))
                    .lineLimit(2)
            }

            if !addonNames.isEmpty {
                addonFilterBar
            }

            if filteredStreams.isEmpty {
                VStack(spacing: 12) {
                    LottieLoadingView(size: 44)
                        .opacity(streamRepo.isLoading ? 1 : 0)
                    Text(streamRepo.isLoading ? "Finding sources..." : "No playable sources found")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.68))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredStreams) { stream in
                            Button {
                                launchStream(stream)
                            } label: {
                                manualStreamRow(stream)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private func manualStreamRow(_ stream: StreamItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(stream.addonName ?? stream.sourceName ?? "Source")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(MoonlitTheme.accent)
                    Text(sourceQualityLabel(for: stream))
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white.opacity(0.72))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }

                Text(stream.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                if let description = stream.description, description != stream.displayName {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "play.fill")
                .font(.caption.weight(.bold))
                .foregroundColor(.black)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.white))
        }
        .padding(14)
        .glassCard(cornerRadius: MoonlitTheme.radiusCard, interactive: true)
    }

    private func launchStream(_ stream: StreamItem) {
        selectedStream = stream

        // Block free accounts from playing
        if ProfileManager.shared.currentProfile?.role == "free" {
            upgradeAlert = true
            return
        }

        guard StreamSourceSelector.isPlaybackCandidate(stream), let url = stream.url else {
            noUrlAlert = true
            return
        }
        StreamPlaybackDiagnostics.logSelectedStream(stream, reason: autoplayMode == .automatic ? "automatic" : "manual")
        let hints = StreamPlaybackHints(stream: stream)
        let launch = PlayerLaunch(
            title: mediaName,
            sourceUrl: url,
            sourceHeaders: hints.requestHeaders,
            sourceResponseHeaders: hints.responseHeaders,
            sourceContentType: hints.contentType,
            sourceVideoSize: hints.videoSize,
            logo: logo ?? resolvedLogo,
            poster: poster,
            episodeThumbnail: episodeThumbnail,
            background: background ?? resolvedBackground,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            streamTitle: episodeTitle ?? stream.displayName,
            providerName: stream.addonName,
            contentType: mediaType,
            videoId: mediaId,
            parentMetaId: parentMetaId,
            parentMetaType: parentMetaType,
            initialPositionMs: initialPositionMs,
            subtitles: stream.subtitles
        )
        if let profile = ProfileManager.shared.currentProfile {
            let source = LastPlaybackSource(
                sourceUrl: url,
                sourceHeaders: stream.behaviorHints?.proxyHeaders?.request,
                providerName: stream.addonName,
                streamTitle: episodeTitle ?? stream.displayName
            )
            // Save per-episode key so the exact stream can resume directly
            LastPlaybackSourceStore.shared.save(source, profileId: profile.id, mediaId: mediaId)
            // Also save at series level so future episodes of the same series
            // auto-select the same provider without the user having to pick again
            if let parentId = parentMetaId {
                LastPlaybackSourceStore.shared.save(source, profileId: profile.id, mediaId: parentId)
            }
        }
        playerLaunch = launch
        showPlayer = true
    }

    private var autoplayMode: StreamAutoplayMode {
        guard let profile = ProfileManager.shared.currentProfile else { return .manual }
        return StreamAutoplayPreferenceStore.shared.mode(profileId: profile.id)
    }

    private var streamRequestAddons: [AddonManifest] {
        guard !isGuestWithoutAccount else { return [] }
        guard autoplayMode == .automatic,
              let profile = ProfileManager.shared.currentProfile else {
            return addonRepo.enabledAddons
        }
        return StreamAutoplayPreferenceStore.automaticAddons(
            from: addonRepo.managedAddons,
            selectedUrls: StreamAutoplayPreferenceStore.shared.automaticAddonUrls(profileId: profile.id)
        )
    }

    private var isGuestWithoutAccount: Bool {
        guestMode && !ProfileManager.shared.isAuthenticated
    }

    private var addonNames: [String] {
        var seen = Set<String>()
        return cachedPlayableStreams.compactMap { $0.addonName }.filter { seen.insert($0).inserted }
    }

    private var filteredStreams: [StreamItem] {
        guard let filter = selectedAddonFilter else { return cachedPlayableStreams }
        return cachedPlayableStreams.filter { $0.addonName == filter }
    }

    private var addonFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "All", isSelected: selectedAddonFilter == nil) {
                    selectedAddonFilter = nil
                }
                ForEach(addonNames, id: \.self) { name in
                    let count = cachedPlayableStreams.filter { $0.addonName == name }.count
                    filterChip(label: "\(name) (\(count))", isSelected: selectedAddonFilter == name) {
                        selectedAddonFilter = selectedAddonFilter == name ? nil : name
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(isSelected ? .black : .white.opacity(0.75))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? Color.white : Color.white.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func scheduleAutoLaunchIfNeeded(streams: [StreamItem]) {
        guard autoplayMode == .automatic, !didAutoLaunch else { return }
        guard !cachedPlayableStreams.isEmpty else { return }

        if !streamRepo.isLoading {
            autoLaunchTask?.cancel()
            performAutoLaunch(from: streams)
            return
        }

        let timeout = ProfileManager.shared.currentProfile
            .flatMap { StreamAutoplayPreferenceStore.shared.timeoutSeconds(profileId: $0.id) }

        guard let timeout else { return }
        guard autoLaunchTask == nil else { return }

        if timeout == 0 {
            performAutoLaunch(from: streams)
            return
        }

        autoLaunchTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            performAutoLaunch(from: streamRepo.streams)
        }
    }

    private func performAutoLaunch(from streams: [StreamItem]) {
        guard !didAutoLaunch else { return }
        let prefer4K: Bool = {
            guard let profile = ProfileManager.shared.currentProfile else { return false }
            return PlaybackQualityPreferenceStore.shared.prefers4K(profileId: profile.id)
        }()

        guard let autoStream = StreamSourceSelector.initialStream(
            from: streams, prefer4K: prefer4K,
            installOrder: addonRepo.enabledAddons.map(\.name)
        ) else { return }
        didAutoLaunch = true
        StreamPlaybackDiagnostics.logSelectedStream(autoStream, reason: "ranked-auto")
        launchStream(autoStream)
    }

    private func sourceQualityLabel(for stream: StreamItem) -> String {
        switch StreamSourceSelector.quality(of: stream) {
        case .ultraHD4K: return "4K"
        case .hd1080: return "1080p"
        case .unknown: return "Auto"
        }
    }

    private func resolveMissingArtworkIfNeeded() async {
        let needsLogo = logo == nil && resolvedLogo == nil
        let needsBackdrop = background == nil && resolvedBackground == nil
        let needsPoster = poster == nil
        guard needsLogo || needsBackdrop || needsPoster else { return }
        let detailId = parentMetaId ?? mediaId
        let detailType = parentMetaType ?? mediaType.rawValue
        guard let detail = await metaRepo.fetchDetail(
            type: detailType,
            id: detailId,
            addons: addonRepo.enabledAddons.filter { !$0.hasResource("stream") }
        ) else { return }
        if needsLogo { resolvedLogo = detail.logo }
        if needsBackdrop { resolvedBackground = detail.background }
        if needsPoster { resolvedPoster = detail.poster }
    }

}

private struct PlaybackUnavailableAlert: View {
    let contextTitle: String

    var body: some View {
        VStack(spacing: 14) {
            Text(contextTitle)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)
            Text("No results found.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.64))
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .glassCard(cornerRadius: 24)
        .padding(.horizontal, 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(contextTitle). No results found.")
    }
}
