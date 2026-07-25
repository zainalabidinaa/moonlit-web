import SwiftUI
import UIKit
import Combine
import AVFoundation
import MediaPlayer
import MoonlitCore

struct PlayerScreen: View {
    let onDismiss: () -> Void

    private let engine = PlayerEngine.shared
    @StateObject private var mpvEngine = MPVPlayerEngine()
    @State private var timeline = PlayerTimelineModel()
    @State private var activeLaunch: PlayerLaunch
    @StateObject private var streamRepo = StreamRepository.shared
    @StateObject private var addonRepo = AddonRepository.shared
    @StateObject private var metaRepo = MetaRepository.shared
    @State private var showControls = true
    @State private var resolvedLogo: String?
    @State private var resolvedBackground: String?
    @State private var resolvedPoster: String?
    @State private var gestureState = PlayerGestureState()
    @State private var isLocked = false
    @State private var showUnlockHint = false
    @State private var showSources = false
    @State private var showEpisodes = false
    @State private var show4KChoice = false
    @State private var hasMultiplePlayableSources = false
    @State private var hasAvailable4KSource = false
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var isAutoHidePausedByControls = false
    @State private var isScrubbing = false
    @State private var scrubPosition: Double = 0
    @State private var didWireCustomEngine = false
    @State private var engineBindings: Set<AnyCancellable> = []
    @State private var isFetchingStream = false
    @State private var isSwitchingStream = false
    @State private var isFillingVideo = false
    // Snapshots frozen while a menu is open so unrelated player state changes
    // don't rebuild the content and reset the menu's scroll position.
    @State private var subtitleMenuSnapshot: [(lang: String, items: [SubtitleItem])] = []
    @State private var subtitleMenuSelectedSnapshot: SubtitleItem? = nil
    @State private var audioMenuSnapshot: [String] = []
    @State private var audioMenuSelectedSnapshot: String? = nil
    @State private var isSubtitleMenuOpen = false
    @State private var cachedSourceFallbackTask: Task<Void, Never>?
    @State private var isResolvingStream = true
    @State private var autoPlayCandidates: [StreamItem] = []

    // Branded pre-roll loading card visibility + minimum-visible window so a
    // fast cached source doesn't flash the card out before it's perceptible.
    @State private var loadingCardVisible = true
    @State private var minLoadingElapsed = false
    private let minLoadingDuration: TimeInterval = 0.8

    // Volume
#if os(iOS)
    @State private var systemVolume: Float = AVAudioSession.sharedInstance().outputVolume
#endif

    // Skip Intro
    @StateObject private var introViewModel = IntroTimestampServiceViewModel()

    init(launch: PlayerLaunch, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        _activeLaunch = State(initialValue: launch)
    }

    private var videoReady: Bool {
        (engine.customDisplayView ?? mpvEngine.displayView) != nil && mpvEngine.hasRenderedFrame
    }

    var body: some View {
        let _ = PlayerPerformanceDiagnostics.shared.mark("PlayerScreen.body")
        ZStack {
            Color.black.ignoresSafeArea()

            // ── PRE-ROLL BRANDED LOADING CARD ─────────────────────────────
            // : full-bleed backdrop + original logo + animated
            // "Loading" dots. Held until the first video frame renders, with a
            // minimum-visible window so a fast cached source doesn't just flash.
            if loadingCardVisible, !mpvEngine.didEncounterError {
                PlaybackLoadingView(
                    backgroundURL: loadingBackdropURL,
                    logoURL: loadingLogoURL,
                    title: activeLaunch.title
                )
                .allowsHitTesting(false)
                .transition(.opacity)
                .zIndex(50)
                .overlay(alignment: .topLeading) {
                    cancelButton {
                        engine.stop()
                        onDismiss()
                    }
                }
                .overlay(alignment: .topTrailing) {
                    retryButton()
                }
            }

            if !isSwitchingStream, !mpvEngine.didEncounterError,
               let ksView = engine.customDisplayView ?? mpvEngine.displayView {
                MPVPlayerViewRepresentable(playerView: ksView)
                    .id(mpvEngine.launchToken)
                    .ignoresSafeArea()
                    .playerGestures(
                        engine: engine,
                        state: $gestureState,
                        showControls: $showControls,
                        isLocked: $isLocked
                    )
#if os(iOS)
                    .gesture(
                        MagnificationGesture()
                            .onEnded { scale in
                                let fill = scale > 1.05
                                isFillingVideo = fill
                                mpvEngine.setVideoFill(fill)
                                revealControls(scheduleAutoHide: true)
                            }
                    )
#endif
            }

            PlayerFeedbackPill(mode: gestureState.mode, value: feedbackText)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .playerGestures(
                    engine: engine,
                    state: $gestureState,
                    showControls: $showControls,
                    isLocked: $isLocked
                )
                .onTapGesture {
                    if showControls {
                        hideControlsNow()
                    } else {
                        revealControls(scheduleAutoHide: true)
                    }
                }

            // Subtitle text overlay — always visible while a subtitle is loaded
            if !mpvEngine.loadedCues.isEmpty {
                TimelineSubtitleOverlay(
                    index: SubtitleCueIndex(cues: mpvEngine.loadedCues),
                    timeline: timeline
                )
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }

            // ── STREAM-SWITCH LOADING OVERLAY ─────────────────────────────
            if isSwitchingStream {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.4)
                }
                .transition(.opacity)
                .allowsHitTesting(true)
            }

            // ── ERROR OVERLAY ──────────────────────────────────────────────
            if mpvEngine.didEncounterError {
                ZStack {
                    Color.black.opacity(0.75).ignoresSafeArea()
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.white.opacity(0.6))
                        Text("Stream Unavailable")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                        Text("The current source could not be played.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Button {
                            engine.stop()
                            mpvEngine.stop()
                            onDismiss()
                        } label: {
                            Label("Dismiss", systemImage: "xmark")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                        }
                    }
                }
                .transition(.opacity)
                .allowsHitTesting(true)
            }

            PlayerLockMode(isLocked: $isLocked, showHint: $showUnlockHint)

            if showControls && !isLocked && !mpvEngine.didEncounterError {
                playerControlsLayer
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            MainHangDiagnostics.start()
            MainHangDiagnostics.mark("player.onAppear")
#if os(iOS)
            OrientationManager.shared.currentMask = .allButUpsideDown
#endif
            // Keep the branded loading card up for a minimum window so it's
            // always perceptible, even when a cached source renders instantly.
            DispatchQueue.main.asyncAfter(deadline: .now() + minLoadingDuration) {
                minLoadingElapsed = true
                maybeHideLoadingCard()
            }
            Task { await resolveMissingArtworkIfNeeded() }
            revealControls(scheduleAutoHide: !activeLaunch.sourceUrl.isEmpty)
            if activeLaunch.sourceUrl.isEmpty {
                MainHangDiagnostics.mark("player.fetchAndAutoLaunch.start")
                Task { await fetchAndAutoLaunch() }
            } else {
                // Cached source — check TTL before using
                let cachedIsExpired: Bool = {
                    guard let profile = ProfileManager.shared.currentProfile else { return false }
                    guard let source = LastPlaybackSourceStore.shared.source(
                        profileId: profile.id, mediaId: activeLaunch.videoId
                    ) else { return false }
                    return source.isExpired
                }()
                if cachedIsExpired {
                    print("[Moonlit] cached source expired (maxAge=\(Int(LastPlaybackSource.maxAge))s), fetching fresh")
                    MainHangDiagnostics.mark("player.cachedLaunch.expired")
                    activeLaunch = PlayerLaunch(
                        title: activeLaunch.title, sourceUrl: "",
                        logo: activeLaunch.logo, poster: activeLaunch.poster,
                        episodeThumbnail: activeLaunch.episodeThumbnail,
                        background: activeLaunch.background ?? resolvedBackground,
                        seasonNumber: activeLaunch.seasonNumber,
                        episodeNumber: activeLaunch.episodeNumber,
                        streamTitle: activeLaunch.streamTitle,
                        providerName: activeLaunch.providerName,
                        contentType: activeLaunch.contentType,
                        videoId: activeLaunch.videoId,
                        parentMetaId: activeLaunch.parentMetaId,
                        parentMetaType: activeLaunch.parentMetaType,
                        initialPositionMs: activeLaunch.initialPositionMs
                    )
                    Task { await fetchAndAutoLaunch() }
                } else {
                    MainHangDiagnostics.mark("player.cachedLaunch")
                    Task {
                        let cachedUrl = activeLaunch.sourceUrl
                        let cachedHeaders = activeLaunch.sourceHeaders ?? [:]
                        if await preflightReachable(url: cachedUrl, headers: cachedHeaders) {
                            MainHangDiagnostics.mark("player.cachedLaunch.direct")
                            timeline.reset(position: max((activeLaunch.initialPositionMs ?? 0) / 1000, 0))
                            mpvEngine.launch(activeLaunch)
                            engine.launch(activeLaunch)
                            wireCustomEngine()
                            engine.play()
                            refreshSourceControlState()
                            Task {
                                await ensureStreamsLoadedForActiveLaunch()
                                if let matching = streamRepo.streams.first(where: { $0.url == cachedUrl }),
                                    StreamSourceSelector.isPendingStream(matching) {
                                    print("[Moonlit] cached source is pending, falling back to auto-launch")
                                    cachedSourceFallbackTask?.cancel()
                                    mpvEngine.stop()
                                    engine.resetState()
                                    await fetchAndAutoLaunch()
                                    return
                                }
                                await loadSubtitlesForActiveLaunchIfNeeded()
                            }
                            // 5s fallback: if the cached source hasn't rendered a frame,
                            // assume it's stale and fetch fresh streams
                            cachedSourceFallbackTask?.cancel()
                            let capturedUrl = cachedUrl
                            cachedSourceFallbackTask = Task { @MainActor in
                                try? await Task.sleep(for: .seconds(5))
                                guard !Task.isCancelled else { return }
                                if !mpvEngine.hasRenderedFrame,
                                   activeLaunch.sourceUrl == capturedUrl {
                                    print("[Moonlit] cached source stalled, falling back to auto-launch")
                                    mpvEngine.stop()
                                    engine.resetState()
                                    await fetchAndAutoLaunch()
                                }
                            }
                        } else {
                            print("[Moonlit] cached source unreachable, falling back to auto-launch")
                            MainHangDiagnostics.mark("player.cachedLaunch.fallback")
                            await fetchAndAutoLaunch()
                        }
                    }
                }
            }
#if os(iOS)
            // Request landscape after the fullScreenCover slide-up animation finishes
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
                }
            }
#endif
        }
        .onDisappear {
            hideControlsTask?.cancel()
            cachedSourceFallbackTask?.cancel()
#if os(iOS)
            OrientationManager.shared.currentMask = .portrait
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
            }
#endif
            engine.stop()
            mpvEngine.stop()
        }
        .onChange(of: showControls) { _, visible in
            guard visible else {
                hideControlsTask?.cancel()
                return
            }
            if !isAutoHidePausedByControls {
                scheduleControlsAutoHide()
            }
        }
        .onChange(of: engine.isPlaying) { _, _ in
            scheduleControlsAutoHide()
        }
        .onChange(of: mpvEngine.hasRenderedFrame) { _, hasFrame in
            if hasFrame {
                isSwitchingStream = false
                isResolvingStream = false
                maybeHideLoadingCard()
            }
        }
        .onChange(of: streamRepo.streams) { _, _ in refreshSourceControlState() }
        .onChange(of: activeLaunch.sourceUrl) { _, _ in refreshSourceControlState() }
        .onChange(of: mpvEngine.availableSubtitles) { _, subs in
            guard !isSubtitleMenuOpen else { return }
            let grouped = Dictionary(grouping: subs, by: { $0.lang })
            subtitleMenuSnapshot = grouped.keys.sorted().map { k in
                (lang: k, items: (grouped[k] ?? []).sorted { ($0.name ?? $0.lang) < ($1.name ?? $1.lang) })
            }
        }
        .task(id: activeLaunch.videoId) {
            if let imdbId = activeLaunch.parentMetaId,
               let season = activeLaunch.seasonNumber,
               let episode = activeLaunch.episodeNumber {
                await introViewModel.load(imdbId: imdbId, season: season, episode: episode)
            } else {
                introViewModel.clear()
            }
        }
        .animation(.easeInOut(duration: 0.4), value: videoReady)
        .overlay(alignment: .trailing) {
            SourcesPanel(engine: engine, isShowing: $showSources) { stream in
                showSources = false
                Task { await switchToSource(stream, persist4KPreference: false) }
            }
            .padding(.trailing, 16)
            .padding(.vertical, 20)
            .opacity(showSources ? 1 : 0)
            .offset(x: showSources ? 0 : 32)
            .allowsHitTesting(showSources)
            .animation(.easeInOut(duration: 0.22), value: showSources)
            .zIndex(10)
        }
        .onChange(of: showSources) { _, showing in
            showing ? pauseControlsAutoHide() : scheduleControlsAutoHide()
        }
        .onChange(of: showEpisodes) { _, showing in
            showing ? pauseControlsAutoHide() : scheduleControlsAutoHide()
        }
        .sheet(isPresented: $showEpisodes) { EpisodesPanel(engine: engine) }
        .confirmationDialog("4K Playback", isPresented: $show4KChoice, titleVisibility: .visible) {
            Button("Use 4K This Time") {
                if let stream = available4KStream {
                    Task { await switchToSource(stream, persist4KPreference: false) }
                }
            }
            Button("Always Prefer 4K") {
                if let profile = ProfileManager.shared.currentProfile {
                    PlaybackQualityPreferenceStore.shared.setPrefers4K(true, profileId: profile.id)
                }
                if let stream = available4KStream {
                    Task { await switchToSource(stream, persist4KPreference: true) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose whether 4K is only for this playback or should be preferred next time.")
        }
    }

    @ViewBuilder private var playerControlsLayer: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    PlayerPerformanceDiagnostics.shared.mark("controls.backgroundTap")
                    hideControlsNow()
                }

            // Transport truly centered on screen
            playerTransport

            // Top bar pinned to top
            VStack(spacing: 0) {
                playerTopBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                Spacer()
            }

            // Bottom area pinned to bottom
            VStack(spacing: 0) {
                Spacer()
                playerBottomArea
            }
        }
    }

    @ViewBuilder private var playerTransport: some View {
        HStack(spacing: 44) {
            Button {
                pauseControlsAutoHide()
                engine.skipBack15()
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
            }
            .glassCircle(clear: true)

            Button {
                pauseControlsAutoHide()
                engine.togglePlayPause()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 72, height: 72)
                    .offset(x: engine.isPlaying ? 0 : 2)
            }
            .glassCircle(clear: true)

            Button {
                pauseControlsAutoHide()
                engine.skipForward15()
            } label: {
                Image(systemName: "goforward.15")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
            }
            .glassCircle(clear: true)
        }
    }

    @ViewBuilder private var playerTopBar: some View {
#if os(iOS)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                playerTopBarContent
            }
        } else {
            playerTopBarContent
        }
#else
        playerTopBarContent
#endif
    }

    private var playerTopBarContent: some View {
        HStack(spacing: 8) {
            Button {
                engine.stop()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
            }
            .glassCircle(clear: true)

            Spacer()

#if os(iOS)
            GlassVolumeSlider(volume: $systemVolume)

            // Hidden volume view for system volume control
            VolumeViewRepresentable(volume: $systemVolume)
                .frame(width: 0, height: 0)
                .opacity(0)
#endif
        }
    }

    @ViewBuilder private var playerBottomArea: some View {
        VStack(spacing: 8) {
            // Title (left) + control buttons (right) — same row
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(activeLaunch.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    if let s = activeLaunch.seasonNumber, let e = activeLaunch.episodeNumber {
                        Text("S\(s) · E\(e)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    if hasAvailable4KSource {
                        controlPill(icon: "4k.tv", label: "4K") {
                            revealControls(scheduleAutoHide: true)
                            show4KChoice = true
                        }
                    }
                    ccMenu
                    audioMenu
                    moreMenu
                }
            }

            PlayerTimelineControls(
                engine: engine,
                timeline: timeline,
                introViewModel: introViewModel,
                isScrubbing: $isScrubbing,
                scrubPosition: $scrubPosition,
                onScrubStarted: {
                    hideControlsTask?.cancel()
                    isAutoHidePausedByControls = true
                },
                onScrubEnded: {
                    pauseControlsAutoHide()
                }
            )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    @ViewBuilder private var ccMenu: some View {
        let isActive = engine.selectedSubtitle != nil
        Menu {
            ForEach(subtitleMenuSnapshot, id: \.lang) { group in
                if group.items.count == 1, let item = group.items.first {
                    Button(action: { revealControls(scheduleAutoHide: true); engine.setSubtitle(item) }) {
                        if subtitleMenuSelectedSnapshot?.id == item.id {
                            Label(subtitleDisplayName(for: group.lang), systemImage: "checkmark")
                        } else {
                            Text(subtitleDisplayName(for: group.lang))
                        }
                    }
                } else {
                    Menu(subtitleDisplayName(for: group.lang)) {
                        ForEach(group.items) { item in
                            Button(action: { revealControls(scheduleAutoHide: true); engine.setSubtitle(item) }) {
                                if subtitleMenuSelectedSnapshot?.id == item.id {
                                    Label(item.name ?? item.lang, systemImage: "checkmark")
                                } else {
                                    Text(item.name ?? item.lang)
                                }
                            }
                        }
                    }
                }
            }
            Divider()
            Button(action: { revealControls(scheduleAutoHide: true); engine.setSubtitle(nil) }) {
                if subtitleMenuSelectedSnapshot == nil {
                    Label("Off", systemImage: "checkmark")
                } else {
                    Text("Off")
                }
            }
            Color.clear.frame(width: 0, height: 0)
                .onAppear {
                    isSubtitleMenuOpen = true
                    hideControlsTask?.cancel()
                    let grouped = Dictionary(grouping: engine.availableSubtitles, by: { $0.lang })
                    subtitleMenuSnapshot = grouped.keys.sorted().map { k in
                        (lang: k, items: (grouped[k] ?? []).sorted { ($0.name ?? $0.lang) < ($1.name ?? $1.lang) })
                    }
                    subtitleMenuSelectedSnapshot = engine.selectedSubtitle
                }
                .onDisappear {
                    isSubtitleMenuOpen = false
                    scheduleControlsAutoHide()
                }
        } label: {
            Image(systemName: "captions.bubble")
                .renderingMode(.template)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 44, height: 44)
        }
        .tint(.white)
        .glassCapsuleActive(isActive: isActive)
    }

    @ViewBuilder private var audioMenu: some View {
        let tracks = engine.availableAudioTracks.isEmpty ? mpvEngine.availableAudioTracks : engine.availableAudioTracks
        let selected = engine.selectedAudioTrack ?? mpvEngine.selectedAudioTrack
        let isActive = !tracks.isEmpty && selected != nil
        Menu {
            // Show live tracks — no snapshot needed; Menu re-renders on open.
            ForEach(tracks, id: \.self) { track in
                Button(action: { revealControls(scheduleAutoHide: true); engine.setAudioTrack(track) }) {
                    if selected == track {
                        Label(track, systemImage: "checkmark")
                    } else {
                        Text(track)
                    }
                }
            }
            // Static fallback keeps the Menu openable even before tracks arrive.
            if tracks.isEmpty {
                Button("No audio tracks") { }
                    .disabled(true)
            }
            Divider()
            Color.clear.frame(width: 0, height: 0)
                .onAppear {
                    hideControlsTask?.cancel()
                    mpvEngine.refreshAudioTracks()
                }
                .onDisappear { scheduleControlsAutoHide() }
        } label: {
            Image(systemName: "waveform")
                .renderingMode(.template)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 44, height: 44)
        }
        .tint(.white)
        .glassCapsuleActive(isActive: isActive)
    }

    @ViewBuilder private var moreMenu: some View {
        Menu {
            if hasMultiplePlayableSources {
                Button("Retry source", systemImage: "arrow.triangle.2.circlepath") {
                    revealControls(scheduleAutoHide: true)
                    switchToNextSource()
                }
                Button("All sources", systemImage: "rectangle.stack") {
                    pauseControlsAutoHide()
                    showSources = true
                }
                Divider()
            }
            Button(speedLabel, systemImage: "gauge.with.dots.needle.67percent") {
                revealControls(scheduleAutoHide: true)
                cyclePlaybackSpeed()
            }
            Color.clear.frame(width: 0, height: 0)
                .onAppear { hideControlsTask?.cancel() }
                .onDisappear { scheduleControlsAutoHide() }
        } label: {
            Image(systemName: "ellipsis")
                .renderingMode(.template)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 44, height: 44)
        }
        .tint(.white)
        .glassCapsule(interactive: true, clear: false)
    }

    private func subtitleDisplayName(for code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
    }

    @ViewBuilder
    private func controlPill(icon: String, label: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isActive ? Color(white: 0.08) : .white.opacity(0.9))
                .frame(width: 44, height: 44)
        }
        .glassCapsuleActive(isActive: isActive)
    }

    private var speedLabel: String {
        let s = engine.playbackSpeed
        if s == 1.0 { return "1×" }
        return String(format: s.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f×" : "%.2g×", s)
    }

    private func cyclePlaybackSpeed() {
        let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        let current = engine.playbackSpeed
        if let idx = speeds.firstIndex(of: current) {
            engine.setPlaybackSpeed(speeds[(idx + 1) % speeds.count])
        } else {
            engine.setPlaybackSpeed(1.0)
        }
    }

    private var currentStream: StreamItem? {
        streamRepo.streams.first { $0.url == activeLaunch.sourceUrl }
    }

    private var loadingLogoURL: URL? {
        (resolvedLogo ?? activeLaunch.logo).flatMap(URL.init)
    }

    /// Best available landscape image for the loading card, in order of
    /// preference: wide fanart → fetched fanart → episode still → poster →
    /// fetched poster. The card always renders crisp — no blur fallback.
    private var loadingBackdropURL: String? {
        activeLaunch.background ?? resolvedBackground ?? activeLaunch.episodeThumbnail ?? activeLaunch.poster ?? resolvedPoster
    }

    /// Crossfades the branded loading card out once the first frame has
    /// rendered AND the minimum-visible window has elapsed.
    private func maybeHideLoadingCard() {
        guard loadingCardVisible, videoReady, minLoadingElapsed else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            loadingCardVisible = false
        }
    }

    private var loadingTitle: some View {
        Text(activeLaunch.title)
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
    }

    private func cancelButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
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

    private func retryButton() -> some View {
        Button {
            Task { await retryStream() }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
        }
        .glassCircle(clear: true)
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func retryStream() async {
        if let profile = ProfileManager.shared.currentProfile,
           let cached = (activeLaunch.parentMetaId.flatMap { pid in
               LastPlaybackSourceStore.shared.source(profileId: profile.id, mediaId: pid)
           }) ?? LastPlaybackSourceStore.shared.source(
               profileId: profile.id, mediaId: activeLaunch.videoId
           ),
           !cached.sourceUrl.isEmpty,
           cached.sourceUrl != activeLaunch.sourceUrl,
           await preflightReachable(url: cached.sourceUrl, headers: cached.sourceHeaders ?? [:]) {
            let stream = StreamItem(
                url: cached.sourceUrl,
                sourceName: cached.providerName,
                addonName: cached.providerName,
                behaviorHints: StreamBehaviorHints(
                    proxyHeaders: StreamProxyHeaders(request: cached.sourceHeaders)
                )
            )
            await switchToSource(stream, persist4KPreference: false)
            return
        }

        if hasMultiplePlayableSources {
            let candidates = StreamSourceSelector.cachedCandidates(
                currentUrl: activeLaunch.sourceUrl,
                from: streamRepo.streams
            )
            if let stream = StreamSourceSelector.nextStream(
                after: currentStream,
                currentSourceUrl: activeLaunch.sourceUrl,
                from: candidates,
                prefer4K: prefers4K
            ) {
                await switchToSource(stream, persist4KPreference: false)
            } else {
                mpvEngine.stop()
                engine.resetState()
                await fetchAndAutoLaunch()
            }
        } else {
            if mpvEngine.displayView != nil {
                mpvEngine.launch(activeLaunch)
                engine.play()
            } else {
                mpvEngine.stop()
                engine.resetState()
                await fetchAndAutoLaunch()
            }
        }
    }

    private var available4KStream: StreamItem? {
        StreamSourceSelector.best4KStream(from: streamRepo.streams, excluding: currentStream)
    }

    private func switchToNextSource() {
        let candidates = StreamSourceSelector.cachedCandidates(
            currentUrl: activeLaunch.sourceUrl,
            from: streamRepo.streams
        )
        guard let stream = StreamSourceSelector.nextStream(
            after: currentStream,
            currentSourceUrl: activeLaunch.sourceUrl,
            from: candidates,
            prefer4K: prefers4K
        ) else { return }
        Task { await switchToSource(stream, persist4KPreference: false) }
    }

    ///  silent candidate cycling during stream resolution.
    /// Removes the current (failed) stream from the queue and tries the next
    /// auto-playable candidate. If none remain, shows the error overlay.
    private func tryNextAutoPlayCandidate() {
        autoPlayCandidates.removeAll { $0.id == currentStream?.id || $0.url == activeLaunch.sourceUrl }
        guard let next = autoPlayCandidates.first else {
            isSwitchingStream = false
            mpvEngine.didEncounterError = true
            return
        }
        Task { await switchToSource(next, persist4KPreference: false) }
    }

    private var prefers4K: Bool {
        guard let profile = ProfileManager.shared.currentProfile else { return false }
        return PlaybackQualityPreferenceStore.shared.prefers4K(profileId: profile.id)
    }

    private func refreshSourceControlState() {
        hasMultiplePlayableSources = StreamSourceSelector.hasMultiplePlaybackCandidates(in: streamRepo.streams)
        hasAvailable4KSource = StreamSourceSelector.has4KPlaybackCandidate(
            in: streamRepo.streams,
            excludingSourceUrl: activeLaunch.sourceUrl
        )
    }

    private func ensureStreamsLoadedForActiveLaunch() async {
        guard !isFetchingStream else { return }
        guard activeLaunch.sourceUrl.isEmpty == false else { return }
        guard streamRepo.streams.first(where: { $0.url == activeLaunch.sourceUrl }) == nil else {
            refreshSourceControlState()
            return
        }

        isFetchingStream = true
        defer { isFetchingStream = false }

        if addonRepo.enabledAddons.isEmpty,
           let profile = ProfileManager.shared.currentProfile {
            await addonRepo.loadAddons(profileId: profile.id)
        }

        await streamRepo.fetchStreams(
            type: activeLaunch.contentType.rawValue,
            id: activeLaunch.videoId,
            addons: addonRepo.enabledAddons
        )
        refreshSourceControlState()
    }

    private func loadSubtitlesForActiveLaunchIfNeeded() async {
        guard engine.availableSubtitles.isEmpty else { return }
        let fallbackStream = StreamItem(
            url: activeLaunch.sourceUrl,
            subtitles: activeLaunch.subtitles
        )
        let subtitles = await resolvedSubtitles(for: currentStream ?? fallbackStream)
        guard let subtitles, !subtitles.isEmpty else { return }
        mpvEngine.loadSubtitles(from: subtitles)
        engine.availableSubtitles = subtitles
    }

    private func switchToSource(_ stream: StreamItem, persist4KPreference: Bool) async {
        guard let url = stream.url else { return }
        StreamPlaybackDiagnostics.logSelectedStream(stream, reason: "source-switch")
        if persist4KPreference,
           let profile = ProfileManager.shared.currentProfile,
           StreamSourceSelector.quality(of: stream) == .ultraHD4K {
            PlaybackQualityPreferenceStore.shared.setPrefers4K(true, profileId: profile.id)
        }

        let hints = StreamPlaybackHints(stream: stream)
        let nextLaunch = PlayerLaunch(
            title: activeLaunch.title,
            sourceUrl: url,
            sourceHeaders: hints.requestHeaders,
            sourceResponseHeaders: hints.responseHeaders,
            sourceContentType: hints.contentType,
            sourceVideoSize: hints.videoSize,
            logo: activeLaunch.logo ?? resolvedLogo,
            poster: activeLaunch.poster,
            episodeThumbnail: activeLaunch.episodeThumbnail,
            background: activeLaunch.background ?? resolvedBackground,
            seasonNumber: activeLaunch.seasonNumber,
            episodeNumber: activeLaunch.episodeNumber,
            streamTitle: activeLaunch.streamTitle ?? stream.displayName,
            providerName: stream.addonName,
            contentType: activeLaunch.contentType,
            videoId: activeLaunch.videoId,
            parentMetaId: activeLaunch.parentMetaId,
            parentMetaType: activeLaunch.parentMetaType,
            initialPositionMs: max(timeline.position, 0) * 1000,
            subtitles: stream.subtitles ?? activeLaunch.subtitles
        )

        savePlaybackSource(for: stream, url: url, launch: nextLaunch)
        isSwitchingStream = true
        engine.pause()
        // Preflight: skip this candidate if the server returns an error page
        // instead of media. On failure, tryNextAutoPlayCandidate() moves to the next.
        if await preflightReachable(url: url, headers: hints.requestHeaders ?? [:]) {
            mpvEngine.launch(nextLaunch)
            engine.launch(nextLaunch)
            wireCustomEngine()
            engine.play()
        } else {
            // URL rejected by preflight — try next candidate without showing error
            tryNextAutoPlayCandidate()
            return
        }
        showControls = true
        activeLaunch = nextLaunch
        resolvedLogo = nextLaunch.logo ?? resolvedLogo
        timeline.reset(position: max((nextLaunch.initialPositionMs ?? 0) / 1000, 0))
        pauseControlsAutoHide()
    }

    private func savePlaybackSource(for stream: StreamItem, url: String, launch: PlayerLaunch) {
        guard let profile = ProfileManager.shared.currentProfile else { return }
        let source = LastPlaybackSource(
            sourceUrl: url,
            sourceHeaders: stream.behaviorHints?.proxyHeaders?.request,
            providerName: stream.addonName,
            streamTitle: launch.streamTitle ?? stream.displayName
        )
        LastPlaybackSourceStore.shared.save(source, profileId: profile.id, mediaId: launch.videoId)
        if let parentId = launch.parentMetaId {
            LastPlaybackSourceStore.shared.save(source, profileId: profile.id, mediaId: parentId)
        }
    }

    private func revealControls(scheduleAutoHide: Bool) {
        PlayerPerformanceDiagnostics.shared.mark("controls.reveal")
        isAutoHidePausedByControls = !scheduleAutoHide
        withAnimation(.easeInOut(duration: 0.18)) {
            showControls = true
        }
        if scheduleAutoHide {
            scheduleControlsAutoHide()
        } else {
            hideControlsTask?.cancel()
        }
    }

    private func pauseControlsAutoHide() {
        revealControls(scheduleAutoHide: false)
    }

    private func hideControlsNow() {
        guard !isScrubbing else { return }
        PlayerPerformanceDiagnostics.shared.mark("controls.hide")
        hideControlsTask?.cancel()
        isAutoHidePausedByControls = false
        withAnimation(.easeInOut(duration: 0.22)) {
            showControls = false
            showSources = false
            show4KChoice = false
        }
    }

    private func scheduleControlsAutoHide() {
        guard showControls, !isScrubbing, !isFetchingStream, !isAutoHidePausedByControls else { return }
        guard !showSources, !showEpisodes, !show4KChoice else { return }
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                hideControlsNow()
            }
        }
    }

    private func resolveMissingArtworkIfNeeded() async {
        // Fetch the meta only if we're missing the logo or a wide backdrop —
        // e.g. Continue Watching items carry neither.
        let needsLogo = loadingLogoURL == nil
        let needsBackdrop = (activeLaunch.background ?? resolvedBackground) == nil
        let needsPoster = activeLaunch.poster == nil
        NSLog("[Moonlit][Loading] resolveMissingArtwork needsLogo=\(needsLogo) needsBackdrop=\(needsBackdrop) needsPoster=\(needsPoster) bg=\(activeLaunch.background ?? "nil") resBg=\(resolvedBackground ?? "nil") poster=\(activeLaunch.poster ?? "nil")")
        guard needsLogo || needsBackdrop || needsPoster else { return }
        if addonRepo.enabledAddons.isEmpty,
           let profile = ProfileManager.shared.currentProfile {
            await addonRepo.loadAddons(profileId: profile.id)
        }
        let metaId = activeLaunch.parentMetaId ?? activeLaunch.videoId
        let metaType = activeLaunch.parentMetaType ?? activeLaunch.contentType.rawValue
        NSLog("[Moonlit][Loading] fetchDetail metaId=\(metaId) metaType=\(metaType) addons=\(addonRepo.enabledAddons.count)")
        guard let detail = await metaRepo.fetchDetail(
            type: metaType,
            id: metaId,
            addons: addonRepo.enabledAddons
        ) else {
            NSLog("[Moonlit][Loading] fetchDetail returned nil")
            return
        }
        NSLog("[Moonlit][Loading] fetchDetail OK background=\(detail.background ?? "nil") poster=\(detail.poster ?? "nil") logo=\(detail.logo ?? "nil")")
        if needsLogo { resolvedLogo = detail.logo }
        if needsBackdrop { resolvedBackground = detail.background }
        if needsPoster { resolvedPoster = detail.poster }
    }

    /// Called when the player launches with a cached (last-used) source URL.

    private func fetchAndAutoLaunch() async {
        guard !isFetchingStream else { return }
        isFetchingStream = true
        defer { isFetchingStream = false }
        MainHangDiagnostics.mark("player.fetchAddons")

        if addonRepo.enabledAddons.isEmpty,
           let profile = ProfileManager.shared.currentProfile {
            await addonRepo.loadAddons(profileId: profile.id)
        }

        let type = activeLaunch.contentType.rawValue
        let id   = activeLaunch.videoId

        let prefer4K: Bool = {
            guard let profile = ProfileManager.shared.currentProfile else { return false }
            return PlaybackQualityPreferenceStore.shared.prefers4K(profileId: profile.id)
        }()
        let installOrder = addonRepo.enabledAddons.map(\.name)

        // Use pre-fetched streams from DetailScreen warmup if fresh (< 5 min).
        // This makes playback start instantly — no extra network round-trip needed.
        if let cached = await StreamWarmupRepository.shared.getCached(type: type, id: id),
           !cached.isEmpty {
            streamRepo.streams = cached
        } else {
            streamRepo.clearStreams()
            MainHangDiagnostics.mark("player.fetchStreams")
            let bg = Task { await streamRepo.fetchStreams(type: type, id: id, addons: addonRepo.enabledAddons, title: activeLaunch.title) }
            // Resume on whichever comes first: a ranked stream lands, the whole
            // fetch finishes, or the 15s ceiling expires.
            final class Holder { var cancellable: AnyCancellable? }
            let holder = Holder()
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                var done = false
                let finish = {
                    guard !done else { return }
                    done = true
                    holder.cancellable?.cancel()
                    cont.resume()
                }
                // `dropFirst()` matters: @Published replays its current value to new
                // subscribers, and `streams` is still [] here. Observing `isLoading`
                // too would be worse — it reads false at subscribe time because the
                // fetch task above hasn't been scheduled yet, ending the wait
                // instantly with nothing.
                holder.cancellable = streamRepo.$streams
                    .dropFirst()
                    .sink { streams in
                        if StreamSourceSelector.initialStream(from: streams, prefer4K: prefer4K, installOrder: installOrder) != nil { finish() }
                    }
                // Healthy case: every addon answered, nothing ranked. Don't wait out the ceiling.
                Task { _ = await bg.result; finish() }
                // Ceiling for the unhealthy case: a dead addon burns 12s of timeout.
                Task { try? await Task.sleep(for: .seconds(15)); finish() }
            }
            // Whatever hasn't answered by now is unreachable, and awaiting it would
            // gate playback on the slowest dead host. Launch the best of what landed.
            bg.cancel()
            if Task.isCancelled { return }
        }

        // Populate auto-play candidate queue for silent cycling ().
        // If the first candidate fails, tryNextAutoPlayCandidate() picks the next.
        autoPlayCandidates = StreamSourceSelector.candidatesForAutoPlay(
            from: streamRepo.streams, prefer4K: prefer4K, installOrder: installOrder
        )

        let selected = autoPlayCandidates.first
        guard var stream = selected,
              StreamSourceSelector.isPlaybackCandidate(stream),
              var url = stream.url else { return }

        // Remove selected from candidate queue so it won't be retried
        autoPlayCandidates.removeFirst()

        // Preflight: verify host is reachable before mpv connects.
        // A dead proxy causes mpv_terminate_destroy to block main indefinitely.
        var hints = StreamPlaybackHints(stream: stream)
        MainHangDiagnostics.mark("player.preflight")
        if !(await preflightReachable(url: url, headers: hints.requestHeaders ?? [:])) {
            // Auto-fallback: try candidates from the auto-play queue ().
            var found = false
            while let candidate = autoPlayCandidates.first {
                autoPlayCandidates.removeFirst()
                guard let candidateUrl = candidate.url,
                      candidateUrl != url,
                      StreamSourceSelector.isAutoPlayable(candidate) else { continue }
                let candidateHints = StreamPlaybackHints(stream: candidate)
                if await preflightReachable(url: candidateUrl, headers: candidateHints.requestHeaders ?? [:]) {
                    stream = candidate
                    url = candidateUrl
                    hints = candidateHints
                    found = true
                    break
                }
            }
            guard found else {
                #if DEBUG
                print("[Moonlit] preflight all candidates unreachable")
                #endif
                return
            }
            StreamPlaybackDiagnostics.logSelectedStream(stream, reason: "player-ranked-auto-fallback")
        } else {
            StreamPlaybackDiagnostics.logSelectedStream(stream, reason: "player-ranked-auto")
        }

        // Start playback immediately — don't block on warmup or subtitle fetch
        let launch = PlayerLaunch(
            title: activeLaunch.title,
            sourceUrl: url,
            sourceHeaders: hints.requestHeaders,
            sourceResponseHeaders: hints.responseHeaders,
            sourceContentType: hints.contentType,
            sourceVideoSize: hints.videoSize,
            logo: activeLaunch.logo ?? resolvedLogo,
            poster: activeLaunch.poster,
            episodeThumbnail: activeLaunch.episodeThumbnail,
            background: activeLaunch.background ?? resolvedBackground,
            seasonNumber: activeLaunch.seasonNumber,
            episodeNumber: activeLaunch.episodeNumber,
            streamTitle: activeLaunch.streamTitle ?? stream.displayName,
            providerName: stream.addonName,
            contentType: activeLaunch.contentType,
            videoId: activeLaunch.videoId,
            parentMetaId: activeLaunch.parentMetaId,
            parentMetaType: activeLaunch.parentMetaType,
            initialPositionMs: activeLaunch.initialPositionMs,
            subtitles: nil
        )

        if let profile = ProfileManager.shared.currentProfile {
            let source = LastPlaybackSource(
                sourceUrl: url,
                sourceHeaders: stream.behaviorHints?.proxyHeaders?.request,
                providerName: stream.addonName,
                streamTitle: launch.streamTitle ?? stream.displayName
            )
            LastPlaybackSourceStore.shared.save(source, profileId: profile.id, mediaId: activeLaunch.videoId)
            if let parentId = activeLaunch.parentMetaId {
                LastPlaybackSourceStore.shared.save(source, profileId: profile.id, mediaId: parentId)
            }
        }

        activeLaunch = launch
        timeline.reset(position: max((launch.initialPositionMs ?? 0) / 1000, 0))
        MainHangDiagnostics.mark("player.mpvLaunch")
        mpvEngine.launch(launch)
        engine.launch(launch)
        wireCustomEngine()
        MainHangDiagnostics.mark("player.enginePlay")
        engine.play()
        refreshSourceControlState()

        // Load subtitles in background — don't block playback start
        let capturedStream = stream
        Task { @MainActor in
            let subtitles = await resolvedSubtitles(for: capturedStream)
            guard let subtitles, !subtitles.isEmpty else { return }
            mpvEngine.loadSubtitles(from: subtitles)
            engine.availableSubtitles = subtitles
        }
    }

    private func resolvedSubtitles(for stream: StreamItem) async -> [SubtitleItem]? {
        let embedded = (stream.subtitles ?? []).filter { !$0.url.isEmpty }
        let fetched = (try? await SubtitleService.shared.fetchSubtitlesFromAddons(
            type: activeLaunch.contentType.rawValue,
            id: activeLaunch.videoId,
            addons: addonRepo.enabledAddons
        )) ?? []
        var seen = Set<String>()
        let merged = (embedded + fetched)
            .filter { !$0.url.isEmpty }
            .filter { seen.insert($0.url).inserted }
        return merged.isEmpty ? nil : merged
    }

    private func preflightReachable(url: String, headers: [String: String]) async -> Bool {
        guard let requestUrl = URL(string: url) else { return false }
        var request = URLRequest(url: requestUrl, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
        request.httpMethod = "GET"
        request.setValue("bytes=0-4095", forHTTPHeaderField: "Range")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse else { return false }
        let statusOk = (200...208).contains(httpResponse.statusCode) || httpResponse.statusCode == 416
        guard statusOk else {
            #if DEBUG
            print("[Moonlit] preflight \(requestUrl.host ?? "nil") → \(httpResponse.statusCode)")
            #endif
            return false
        }
        // Reject auth errors: 401/403 = invalid subscription, 429 = rate limited
        let code = httpResponse.statusCode
        if code == 401 || code == 403 || code == 429 {
            #if DEBUG
            print("[Moonlit] preflight \(requestUrl.host ?? "nil") → rejected \(code)")
            #endif
            return false
        }
        let contentType = (httpResponse.allHeaderFields["Content-Type"] as? String)?.lowercased() ?? ""
        if contentType.contains("text/html") {
            #if DEBUG
            print("[Moonlit] preflight \(requestUrl.host ?? "nil") → HTML error page, source expired")
            #endif
            return false
        }
        // Read first 4KB of body — JSON errors come in HTTP 200
        if !data.isEmpty {
            let chunk = data.prefix(4096)
            let body = String(data: chunk, encoding: .utf8)
                ?? String(data: chunk, encoding: .isoLatin1)
                ?? ""
            let lower = body.lowercased()

            // Try to parse as JSON — remote services often return structured errors
            var jsonFields = ""
            if let json = try? JSONSerialization.jsonObject(with: chunk) as? [String: Any] {
                jsonFields = json.compactMap { "\($0.key): \($0.value)" }.joined(separator: " ").lowercased()
            }

            let combined = lower + " " + jsonFields
            let errorMarkers: [(String, label: String)] = [
                ("media_not_cached_yet", "not cached yet"),
                ("not downloaded", "not downloaded"),
                ("not cached", "not cached"),
                ("not yet cached", "not yet cached"),
                ("downloading", "downloading"),
                ("caching", "caching"),
                ("queued", "queued"),
                ("try again shortly", "try again shortly"),
                ("being prepared", "being prepared"),
                ("wait a short while", "wait a short while"),
                ("something went wrong", "addon error"),
                ("unexpected error resolving", "addon error"),
                ("access denied", "access denied"),
                ("not downloaded yet", "not downloaded"),
                ("torrent not downloaded", "not downloaded"),
                ("invalid token", "invalid token"),
                ("subscription", "subscription"),
                ("internal provider issue", "internal provider"),
                ("please retry later", "retry later"),
            ]
            for (term, label) in errorMarkers {
                if combined.contains(term) {
                    let preview = lower.prefix(150).replacingOccurrences(of: "\n", with: " ")
                    #if DEBUG
                    print("[Moonlit] preflight \(requestUrl.host ?? "nil") → \(label): \(preview)")
                    #endif
                    return false
                }
            }

            // Generic JSON error: non-empty error field + empty/absent stream data
            if let json = try? JSONSerialization.jsonObject(with: chunk) as? [String: Any],
               let errorValue = json["error"] as? String, !errorValue.isEmpty,
               json["streams"] == nil, json["url"] == nil, json["data"] == nil {
                #if DEBUG
                print("[Moonlit] preflight \(requestUrl.host ?? "nil") → json error: \(errorValue.prefix(100))")
                #endif
                return false
            }
        }
        return true
    }

    private var feedbackText: String {
        switch gestureState.mode {
        case .brightness: return "\(Int(gestureState.value * 100))%"
        case .none: return ""
        }
    }

    private func wireCustomEngine() {
        engine.customDisplayView = mpvEngine.displayView
        engine.onCustomPlay = { [weak mpvEngine] in mpvEngine?.play() }
        engine.onCustomPause = { [weak mpvEngine] in mpvEngine?.pause() }
        engine.onCustomSeek = { [weak mpvEngine] in mpvEngine?.seek(to: $0) }
        engine.onCustomSetSpeed = { [weak mpvEngine] in mpvEngine?.setPlaybackSpeed($0) }
        engine.onCustomSkipForward = { [weak mpvEngine] in mpvEngine?.skipForward() }
        engine.onCustomSkipBack = { [weak mpvEngine] in mpvEngine?.skipBack() }
        engine.onCustomSkipForward15 = { [weak mpvEngine] in mpvEngine?.skipForward15() }
        engine.onCustomSkipBack15 = { [weak mpvEngine] in mpvEngine?.skipBack15() }
        engine.onCustomToggleMute = { [weak mpvEngine] in mpvEngine?.toggleMute() }
        engine.onCustomCycleSubtitle = { [weak mpvEngine] in mpvEngine?.cycleSubtitle() }
        engine.onCustomSetSubtitle = { [weak mpvEngine] in mpvEngine?.setSubtitle($0) }
        engine.onCustomSetAudioTrack = { [weak mpvEngine] in mpvEngine?.selectAudioTrack(named: $0) }
        engine.onCustomStop = { [weak mpvEngine] in mpvEngine?.stop() }

        guard !didWireCustomEngine else { return }
        didWireCustomEngine = true

        mpvEngine.$isPlaying
            .removeDuplicates()
            .sink { engine.isPlaying = $0 }
            .store(in: &engineBindings)
        mpvEngine.$isLoading
            .removeDuplicates()
            .sink { engine.isLoading = $0 }
            .store(in: &engineBindings)
        mpvEngine.$isEnded
            .removeDuplicates()
            .sink { engine.isEnded = $0 }
            .store(in: &engineBindings)
        mpvEngine.positionPublisher
            .throttle(for: .milliseconds(250), scheduler: RunLoop.main, latest: true)
            .sink { position in
                PlayerPerformanceDiagnostics.shared.mark("timeline.bridge")
                engine.currentPosition = position
                timeline.update(position: position)
                guard VideoPlayerPreferenceStore.shared.autoSkipIntros,
                      let ts = introViewModel.timestamps,
                      position >= ts.introStart && position < ts.introEnd else { return }
                engine.seek(to: ts.introEnd)
            }
            .store(in: &engineBindings)
        mpvEngine.bufferedPositionPublisher
            .throttle(for: .milliseconds(250), scheduler: RunLoop.main, latest: true)
            .sink { bufferedPosition in
                PlayerPerformanceDiagnostics.shared.mark("buffer.bridge")
                timeline.update(bufferedPosition: bufferedPosition)
            }
            .store(in: &engineBindings)
        mpvEngine.$duration
            .removeDuplicates()
            .sink {
                engine.duration = $0
                timeline.update(duration: $0)
            }
            .store(in: &engineBindings)
        mpvEngine.$playbackSpeed
            .removeDuplicates()
            .sink { engine.playbackSpeed = $0 }
            .store(in: &engineBindings)
        mpvEngine.$availableSubtitles
            .removeDuplicates()
            .sink { engine.availableSubtitles = $0 }
            .store(in: &engineBindings)
        mpvEngine.$selectedSubtitle
            .removeDuplicates()
            .sink { engine.selectedSubtitle = $0 }
            .store(in: &engineBindings)
        mpvEngine.$availableAudioTracks
            .removeDuplicates()
            .sink { engine.availableAudioTracks = $0 }
            .store(in: &engineBindings)
        mpvEngine.$selectedAudioTrack
            .removeDuplicates()
            .sink { engine.selectedAudioTrack = $0 }
            .store(in: &engineBindings)
        mpvEngine.$isMuted
            .removeDuplicates()
            .sink { engine.isMuted = $0 }
            .store(in: &engineBindings)
        mpvEngine.$didEncounterError
            .filter { $0 }
            .sink { _ in
                // During stream resolution: silently try next candidate ().
                // Only show error when all auto-playable candidates are exhausted.
                if self.isResolvingStream {
                    self.tryNextAutoPlayCandidate()
                } else {
                    // Mid-playback error: auto-switch if multiple sources available
                    guard self.hasMultiplePlayableSources else { return }
                    self.switchToNextSource()
                }
            }
            .store(in: &engineBindings)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        }
        return "\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
    }
}

// MARK: - Intro Timestamp ViewModel

@MainActor
private class IntroTimestampServiceViewModel: ObservableObject {
    @Published var timestamps: IntroTimestamp?

    func load(imdbId: String, season: Int, episode: Int) async {
        timestamps = await IntroTimestampService.shared.timestamps(imdbId: imdbId, season: season, episode: episode)
    }

    func clear() { timestamps = nil }
}

// MARK: - Glass Volume Slider

@MainActor
private final class PlayerTimelineModel: ObservableObject {
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var bufferedPosition: Double = 0

    func reset(position: Double = 0, duration: Double = 0, bufferedPosition: Double = 0) {
        self.position = position
        self.duration = duration
        self.bufferedPosition = bufferedPosition
    }

    func update(position: Double) {
        self.position = position
    }

    func update(duration: Double) {
        self.duration = duration
    }

    func update(bufferedPosition: Double) {
        self.bufferedPosition = bufferedPosition
    }
}

private struct PlayerTimelineControls: View {
    let engine: PlayerEngine
    @ObservedObject var timeline: PlayerTimelineModel
    @ObservedObject var introViewModel: IntroTimestampServiceViewModel
    @Binding var isScrubbing: Bool
    @Binding var scrubPosition: Double
    let onScrubStarted: () -> Void
    let onScrubEnded: () -> Void

    private var displayPosition: Double {
        isScrubbing ? scrubPosition : timeline.position
    }

    private var scrubberBinding: Binding<Double> {
        Binding(
            get: { displayPosition },
            set: { newValue in
                scrubPosition = min(max(newValue, 0), max(timeline.duration, 0))
            }
        )
    }

    var body: some View {
        let _ = PlayerPerformanceDiagnostics.shared.mark("PlayerTimelineControls.body")
        VStack(spacing: 8) {
            skipIntroButton

            PlayerScrubber(
                value: scrubberBinding,
                duration: max(timeline.duration, 0),
                isScrubbing: isScrubbing,
                onEditingChanged: handleScrubbingChanged,
                highlights: introViewModel.timestamps?.highlights ?? []
            )

            HStack {
                Text(formatTime(displayPosition))
                Spacer()
                Text(formatTime(max(timeline.duration - displayPosition, 0)))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.5))
        }
    }

    @ViewBuilder private var skipIntroButton: some View {
        let prefs = VideoPlayerPreferenceStore.shared
        if prefs.showSkipIntroButton,
           let ts = introViewModel.timestamps,
           timeline.position >= ts.introStart && timeline.position < ts.introEnd {
            HStack {
                Spacer()
                SkipIntroButton(label: "Skip Intro") { engine.seek(to: ts.introEnd) }
                Spacer()
            }
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity
            ))
            .animation(.spring(duration: 0.3), value: introViewModel.timestamps != nil)
        } else if prefs.showSkipIntroButton, prefs.fallbackSkipEnabled,
                  introViewModel.timestamps == nil,
                  timeline.position > 15, timeline.position < 300 {
            HStack {
                Spacer()
                SkipIntroButton(label: "Skip +\(prefs.fallbackSkipSeconds)s") {
                    engine.seek(to: timeline.position + Double(prefs.fallbackSkipSeconds))
                }
                Spacer()
            }
            .transition(.opacity)
        }
    }

    private func handleScrubbingChanged(_ editing: Bool) {
        if editing {
            if !isScrubbing {
                scrubPosition = timeline.position
                onScrubStarted()
            }
            isScrubbing = true
        } else {
            isScrubbing = false
            engine.seek(to: scrubPosition)
            onScrubEnded()
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        }
        return "\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
    }
}

#if os(iOS)
private struct GlassVolumeSlider: View {
    @Binding var volume: Float

    private let fallbackThumbSize: CGFloat = 16
    private let trackHeight: CGFloat = 5

    var body: some View {
        if #available(iOS 26.0, *) {
            nativeGlassSlider
        } else {
            fallbackSlider
        }
    }

    @available(iOS 26.0, *)
    private var nativeGlassSlider: some View {
        HStack(spacing: 10) {
            speakerIcon

            Slider(
                value: Binding(
                    get: { Double(volume) },
                    set: { volume = Float(max(0, min(1, $0))) }
                ),
                in: 0...1
            )
            .labelsHidden()
            .tint(.white)
            .controlSize(.regular)
            .frame(width: 198, height: 28)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.clear.interactive(), in: .capsule)
    }

    private var fallbackSlider: some View {
        HStack(spacing: 10) {
            speakerIcon

            GeometryReader { geo in
                let trackW = geo.size.width
                let clampedVolume = max(0, min(1, CGFloat(volume)))
                let fillW = trackW * clampedVolume
                let thumbX = max(0, min(fillW - fallbackThumbSize / 2, trackW - fallbackThumbSize))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: trackHeight)

                    Capsule()
                        .fill(Color.white.opacity(0.78))
                        .frame(width: max(0, fillW), height: trackHeight)

                    Circle()
                        .fill(Color.white)
                        .frame(width: fallbackThumbSize, height: fallbackThumbSize)
                        .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
                        .offset(x: thumbX)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            guard trackW > 0 else { return }
                            volume = Float(max(0, min(1, val.location.x / trackW)))
                        }
                )
            }
            .frame(width: 198, height: 28)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.03)))
                .environment(\.colorScheme, .dark)
        }
    }

    private var speakerIcon: some View {
        Image(systemName: volume <= 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 20)
    }
}
#endif

// MARK: - System Volume Bridge

#if os(iOS)
private struct VolumeViewRepresentable: UIViewRepresentable {
    @Binding var volume: Float

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView()
        view.isHidden = false
        view.alpha = 0.0001
        view.clipsToBounds = true
        DispatchQueue.main.async {
            context.coordinator.attach(to: view)
        }
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        context.coordinator.attach(to: uiView)
        guard let slider = context.coordinator.slider else { return }
        // Push UI changes to the system volume; skip tiny deltas to avoid loops.
        if abs(slider.value - volume) > 0.01 {
            DispatchQueue.main.async { slider.value = volume }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(volume: $volume) }

    final class Coordinator: NSObject {
        let volume: Binding<Float>
        weak var slider: UISlider?

        init(volume: Binding<Float>) { self.volume = volume }

        func attach(to view: MPVolumeView) {
            guard slider == nil,
                  let s = view.subviews.compactMap({ $0 as? UISlider }).first else { return }
            slider = s
            s.addTarget(self, action: #selector(valueChanged(_:)), for: .valueChanged)
        }

        @objc private func valueChanged(_ sender: UISlider) {
            // Hardware buttons / system changes flow back into the glass slider.
            if abs(volume.wrappedValue - sender.value) > 0.01 {
                volume.wrappedValue = sender.value
            }
        }
    }
}
#endif

// MARK: - Skip Intro Button

private struct SkipIntroButton: View {
    var label: String = "Skip Intro"
    let onSkip: () -> Void

    var body: some View {
        Button(action: onSkip) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background {
#if os(iOS)
                if #available(iOS 26.0, *) {
                    Capsule().glassEffect()
                } else {
                    Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                }
#else
                Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
#endif
            }
        }
    }
}

private struct PlayerScrubber: View {
    @Binding var value: Double
    let duration: Double
    let isScrubbing: Bool
    let onEditingChanged: (Bool) -> Void
    var highlights: [Double] = []

    var body: some View {
#if os(iOS)
        if #available(iOS 26, *) {
            Slider(
                value: $value,
                in: 0...max(duration, 1),
                onEditingChanged: onEditingChanged
            )
            .labelsHidden()
            .tint(.white)
            .controlSize(.large)
            .frame(height: 32)
        } else {
            GeometryReader { geo in
                let progress = duration > 0 ? min(max(value / duration, 0), 1) : 0
                let fillWidth = geo.size.width * progress
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                        .frame(height: isScrubbing ? 6 : 4)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: fillWidth, height: isScrubbing ? 6 : 4)
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .scaleEffect(isScrubbing ? 1.35 : 1.0)
                        .offset(x: min(max(fillWidth - 7, -7), geo.size.width - 7))

                    // Timeline highlight dots (amber, e.g. intro markers)
                    if VideoPlayerPreferenceStore.shared.showHighlightsOnTimeline && duration > 0 {
                        ForEach(highlights, id: \.self) { time in
                            Circle()
                                .fill(Color(red: 1.0, green: 0.75, blue: 0.0))
                                .frame(width: 5, height: 5)
                                .offset(x: geo.size.width * CGFloat(min(time / duration, 1)) - 2.5,
                                        y: -(isScrubbing ? 3 : 2))
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            onEditingChanged(true)
                            let fraction = min(max(gesture.location.x / max(geo.size.width, 1), 0), 1)
                            value = duration * fraction
                        }
                        .onEnded { _ in
                            onEditingChanged(false)
                        }
                )
            }
            .frame(height: 32)
        }
#else
        // tvOS: always use non-gesture approach (d-pad based seeking)
        // On tvOS the AVPlayerViewController handles transport, so this won't render
        // But it must compile. Use a simple non-gesture scrubber:
        GeometryReader { geo in
            let progress = duration > 0 ? min(max(value / duration, 0), 1) : 0
            let fillWidth = geo.size.width * progress
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                    .frame(height: 4)
                Capsule()
                    .fill(Color.white)
                    .frame(width: fillWidth, height: 4)
            }
        }
        .frame(height: 32)
#endif
    }
}

// MARK: - Subtitle Text Overlay

private struct TimelineSubtitleOverlay: View {
    let index: SubtitleCueIndex
    @ObservedObject var timeline: PlayerTimelineModel

    var body: some View {
        let _ = PlayerPerformanceDiagnostics.shared.mark("SubtitleTextOverlay.body")
        SubtitleTextOverlay(index: index, position: timeline.position)
    }
}

private struct SubtitleTextOverlay: View {
    let index: SubtitleCueIndex
    let position: TimeInterval

    var body: some View {
        let active = PlayerPerformanceDiagnostics.shared.measure("subtitle.lookup") {
            index.activeCues(at: position)
        }
        VStack(spacing: 0) {
            Spacer()
            ForEach(active.indices, id: \.self) { i in
                let text = active[i].text
                if !text.isEmpty {
                    Text(text)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .shadow(color: .black.opacity(0.9), radius: 2, x: 1, y: 1)
                        .shadow(color: .black.opacity(0.9), radius: 2, x: -1, y: -1)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.45).cornerRadius(MoonlitTheme.radiusSmall))
                        .padding(.bottom, 4)
                }
            }
        }
        .padding(.bottom, 88)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension View {
    func glassCapsuleActive(isActive: Bool) -> some View {
        // Non-interactive glass: the interactive press effect fights the Menu's
        // own open/highlight animation and flashes matte for a frame.
        self.glassCapsule(interactive: false, clear: false)
    }
}
