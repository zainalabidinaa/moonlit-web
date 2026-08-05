import SwiftUI
import UIKit
import Combine
import AVFoundation
import MediaPlayer
import MoonlitCore

struct PlayerScreen: View {
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let engine = PlayerEngine.shared
    @StateObject private var mpvEngine = MPVPlayerEngine()
    @State private var timeline = PlayerTimelineModel()
    @State private var activeLaunch: PlayerLaunch
    @StateObject private var streamRepo = StreamRepository.shared
    @StateObject private var addonRepo = AddonRepository.shared
    @StateObject private var metaRepo = MetaRepository.shared
    @StateObject private var subtitleAppearanceStore = SubtitleAppearanceStore.shared
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
    @State private var skipBackAngle: Double = 0
    @State private var skipBackScale: CGFloat = 1
    @State private var skipForwardAngle: Double = 0
    @State private var skipForwardScale: CGFloat = 1
    @State private var showSubtitleAppearanceEditor = false
    @State private var cachedSourceFallbackTask: Task<Void, Never>?
    @State private var isResolvingStream = true
    @State private var autoPlayCandidates: [StreamItem] = []
    @StateObject private var recoveryCoordinator = PlaybackRecoveryCoordinator()
    @StateObject private var soundtrackService = SoundtrackService.shared

    // Branded pre-roll loading card visibility + minimum-visible window so a
    // fast cached source doesn't flash the card out before it's perceptible.
    @State private var loadingCardVisible = true
    @State private var minLoadingElapsed = false
    private let minLoadingDuration: TimeInterval = 0.8

    // Volume
#if os(iOS)
    @State private var systemVolume: Float = AVAudioSession.sharedInstance().outputVolume
#endif

    // Community-verified recap/intro/outro windows for the active episode.
    @StateObject private var segmentViewModel = PlaybackSegmentsViewModel()
    @State private var skipActionsHiddenForSource = false
    @State private var playerDetailTab: PlayerDetailTab? = nil
    @State private var isDismissing = false
    // Measured height of the bottom chrome block, so the skip-intro pill (which
    // lives outside playerControlsLayer so it survives auto-hide) can float just
    // above it instead of overlapping the tab row / speed / track menus.
    @State private var chromeHeight: CGFloat = 0

    init(launch: PlayerLaunch, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        _activeLaunch = State(initialValue: launch)
    }

    private var videoReady: Bool {
        (engine.customDisplayView ?? mpvEngine.displayView) != nil && mpvEngine.hasRenderedFrame
    }

    /// First 4-digit run in the loaded detail's release info — disambiguates a
    /// MusicBrainz soundtrack search for titles that share a name with a much
    /// more famous album (e.g. a low-profile film named after a hit song).
    private var releaseYear: Int? {
        guard let raw = metaRepo.detail?.releaseInfo else { return nil }
        var digits = ""
        for ch in raw {
            if ch.isNumber {
                digits.append(ch)
                if digits.count == 4 { return Int(digits) }
            } else {
                digits = ""
            }
        }
        return nil
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
                .overlay(alignment: .topTrailing) {
                    retryButton()
                }
            }

            if !mpvEngine.didEncounterError,
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
                .onTapGesture { handleBackgroundTap() }

            // Subtitle text overlay. Kept mounted at all times and faded via opacity
            // rather than conditionally inserted — mounting/unmounting this on every
            // `loadedCues` change (e.g. when switching tracks) was contributing to the
            // flicker reported around subtitle/audio selection, the same reason
            // playerControlsLayer above uses opacity instead of removal.
            TimelineSubtitleOverlay(
                index: SubtitleCueIndex(cues: mpvEngine.loadedCues),
                timeline: timeline,
                delay: mpvEngine.subtitleDelaySeconds,
                trailingInset: showSubtitleAppearanceEditor ? subtitleCustomizationPanelWidth : 0,
                // Rests at its normal configured position when controls are
                // hidden, and lifts clear of the bottom chrome (title, scrubber,
                // tabs, an open detail panel) when they're shown — previously a
                // fixed offset, which is why controls used to land on top of it.
                extraBottomInset: showControls ? chromeHeight + 12 : 12
            )
                .opacity(mpvEngine.loadedCues.isEmpty ? 0 : 1)
                .allowsHitTesting(false)
                .ignoresSafeArea()
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: showControls)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: chromeHeight)

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
                            dismissPlayer()
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

            // Keep native Menu presenters mounted while controls fade. Removing
            // this subtree while a system menu is open dismisses it and produces
            // the visible flicker reported during playback progress updates.
            playerControlsLayer
                .opacity(showControls && !isLocked && !mpvEngine.didEncounterError ? 1 : 0)
                .allowsHitTesting(showControls && !isLocked && !mpvEngine.didEncounterError)
                .accessibilityHidden(!showControls || isLocked || mpvEngine.didEncounterError)

            // Rendered outside playerControlsLayer (and its opacity gate) so the
            // skip pill survives auto-hide instead of disappearing with the rest
            // of the chrome. Floats above the bottom chrome block when controls
            // are visible, drops to the safe-area inset when they aren't.
            if !isLocked && !mpvEngine.didEncounterError {
                skipSegmentOverlay
            }

            if !isLocked && (loadingCardVisible || showControls || mpvEngine.didEncounterError) {
                playerCloseButton
                    .zIndex(200)
            }

        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .trailing) {
            if showSubtitleAppearanceEditor {
                PlayerSubtitleCustomizationPanel(
                    delay: Binding(
                        get: { mpvEngine.subtitleDelaySeconds },
                        set: { mpvEngine.setSubtitleDelay($0) }
                    ),
                    onClose: closeAdvancedSubtitleAppearance
                )
                .frame(width: subtitleCustomizationPanelWidth)
                .safeAreaPadding(.vertical, 12)
                .safeAreaPadding(.trailing, 12)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .trailing).combined(with: .opacity)
                )
                .zIndex(150)
            }
        }
        .onAppear {
            MainHangDiagnostics.start()
            MainHangDiagnostics.mark("player.onAppear")
            recoveryCoordinator.reset()
#if os(iOS)
            // Restrict UIKit before asking the scene to rotate; otherwise the
            // player can briefly lay out in portrait during presentation.
            OrientationManager.shared.prepare(.landscape)
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
            // Request landscape from the active app scene after the cover attaches.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                OrientationManager.shared.request(.landscape)
            }
#endif
        }
        .onDisappear {
            hideControlsTask?.cancel()
            cachedSourceFallbackTask?.cancel()
#if os(iOS)
            // Fallback for every dismissal path, including errors and interrupted covers.
            OrientationManager.shared.request(.portrait)
            PlaybackWakeLock.set(false)
#endif
            engine.stop()
            mpvEngine.stop()
        }
        .onChange(of: showSubtitleAppearanceEditor) { _, showing in
            showing ? pauseControlsAutoHide() : resumeControlsAutoHide()
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
        .onReceive(subtitleAppearanceStore.objectWillChange) { _ in
            // Store setters announce immediately before persisting their new value.
            // Defer one main-queue turn so both custom cue rendering and embedded
            // libass subtitles read the updated appearance.
            DispatchQueue.main.async {
                mpvEngine.applySubtitleAppearance()
            }
        }
        .onChange(of: streamRepo.streams) { _, _ in refreshSourceControlState() }
        .onChange(of: activeLaunch.sourceUrl) { _, _ in
            skipActionsHiddenForSource = false
            segmentViewModel.clear()
            refreshSourceControlState()
        }
        .task(id: segmentLookupKey) {
            guard mpvEngine.duration > 0,
                  let rawId = activeLaunch.parentMetaId,
                  let imdbId = rawId.split(separator: ":").first.map(String.init),
                  imdbId.hasPrefix("tt"),
                  let season = activeLaunch.seasonNumber,
                  let episode = activeLaunch.episodeNumber else {
                segmentViewModel.clear()
                return
            }
            let request = PlaybackSegmentRequest(
                imdbId: imdbId,
                season: season,
                episode: episode,
                duration: mpvEngine.duration,
                streamIdentity: activeStreamIdentity
            )
            await segmentViewModel.load(
                request: request,
                exactSegments: mpvEngine.embeddedPlaybackSegments
            )
        }
        .task(id: activeLaunch.parentMetaId) {
            guard let id = activeLaunch.parentMetaId else { return }
            await metaRepo.loadDetail(
                type: activeLaunch.parentMetaType ?? activeLaunch.contentType.rawValue,
                id: id,
                addons: addonRepo.activeAddons
            )
        }
        .task(id: activeLaunch.parentMetaId ?? activeLaunch.videoId) {
            let id = activeLaunch.parentMetaId ?? activeLaunch.videoId
            // For an episode, `activeLaunch.title` is the *episode's* title —
            // querying a soundtrack source with that almost never matches.
            // The parent show's own name is what actually resolves, so this
            // awaits the parent detail itself (idempotent/cached if the
            // sibling `.task` above already loaded it) rather than racing it.
            var queryTitle = activeLaunch.title
            if let parentId = activeLaunch.parentMetaId {
                await metaRepo.loadDetail(
                    type: activeLaunch.parentMetaType ?? activeLaunch.contentType.rawValue,
                    id: parentId,
                    addons: addonRepo.activeAddons
                )
                queryTitle = metaRepo.detail?.name ?? activeLaunch.title
            }
            await soundtrackService.fetch(id: id, title: queryTitle, year: releaseYear)
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
            showing ? pauseControlsAutoHide() : resumeControlsAutoHide()
        }
        .onChange(of: showEpisodes) { _, showing in
            showing ? pauseControlsAutoHide() : resumeControlsAutoHide()
        }
        .onChange(of: show4KChoice) { _, showing in
            showing ? pauseControlsAutoHide() : resumeControlsAutoHide()
        }
        .onChange(of: playerDetailTab) { _, tab in
            PlayerLayoutLog.write("detailTab=\(tab.map(String.init(describing:)) ?? "nil") chromeHeight=\(chromeHeight)")
            tab == nil ? resumeControlsAutoHide() : pauseControlsAutoHide()
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

    private func selectAudioTrackFromPanel(_ id: Int64) {
        mpvEngine.selectAudioTrack(id: id)
        // Deferred a tick so this doesn't invalidate the view while the system
        // Menu is still animating its dismissal — a contributor to the flicker
        // reported around track selection.
        DispatchQueue.main.async {
            revealControls(scheduleAutoHide: true)
        }
    }

    private func selectSubtitleFromPanel(_ subtitle: SubtitleItem?) {
        engine.setSubtitle(subtitle)
        DispatchQueue.main.async {
            revealControls(scheduleAutoHide: true)
        }
    }

    private func openAdvancedSubtitleAppearance() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
            showSubtitleAppearanceEditor = true
        }
    }

    private func closeAdvancedSubtitleAppearance() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
            showSubtitleAppearanceEditor = false
        }
    }

    @ViewBuilder private var playerControlsLayer: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    PlayerPerformanceDiagnostics.shared.mark("controls.backgroundTap")
                    handleBackgroundTap()
                }

            // True screen center — matches the transport position on tvOS/iOS
            // native players. Faded out (not offset) while a detail panel is
            // open so it doesn't compete with the panel for attention.
            playerTransport
                // Centre on the full frame, not on the space left once the bottom safe
                // area is subtracted. The home indicator inset (~21pt in landscape) was
                // pulling the centre to (402-21)/2 = 190.5pt; measured 191pt against
                // Apple's exact 201pt.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .opacity(playerDetailTab == nil ? 1 : 0)
                .allowsHitTesting(playerDetailTab == nil)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: playerDetailTab)

            // Top bar pinned to top. Deliberately NOT gated on `playerDetailTab` —
            // the Apple TV player keeps close/PiP/AirPlay/share and the volume slider
            // visible while a detail panel is open, so the user always has an exit.
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
        HStack(spacing: 40) {
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.prepare()
                generator.impactOccurred()
                skipBackAngle = -30
                skipBackScale = 0.85
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) {
                        skipBackAngle = 0
                        skipBackScale = 1
                    }
                }
                pauseControlsAutoHide()
                engine.seek(to: max(timeline.position - 10, 0))
            } label: {
                ZStack {
                    Image(systemName: "gobackward")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(skipBackAngle))
                    Text("10")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                .scaleEffect(skipBackScale)
                .frame(width: 60, height: 60)
                .glassCircle(clear: false)
                .frame(width: 88, height: 88)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Go back 10 seconds")

            Button {
                pauseControlsAutoHide()
                engine.togglePlayPause()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 96, height: 96)
                    .offset(x: engine.isPlaying ? 0 : 2)
                    .glassCircle(clear: true)
                    .frame(width: 120, height: 120)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")

            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.prepare()
                generator.impactOccurred()
                skipForwardAngle = 30
                skipForwardScale = 0.85
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) {
                        skipForwardAngle = 0
                        skipForwardScale = 1
                    }
                }
                pauseControlsAutoHide()
                let destination = timeline.duration > 0
                    ? min(timeline.position + 10, timeline.duration)
                    : timeline.position + 10
                engine.seek(to: destination)
            } label: {
                ZStack {
                    Image(systemName: "goforward")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(skipForwardAngle))
                    Text("10")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                .scaleEffect(skipForwardScale)
                .frame(width: 60, height: 60)
                .glassCircle(clear: false)
                .frame(width: 88, height: 88)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Go forward 10 seconds")
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

    private var playerCloseButton: some View {
        Button(action: dismissPlayer) {
            Image(systemName: "xmark")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassCircle(clear: false)
        .accessibilityLabel("Close player")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Sits at the safe-area edge rather than 16pt inside it. Apple places its close
        // button at 38pt, i.e. *within* the landscape safe area — not matched here, since
        // that region is where the Dynamic Island lands depending on which way the phone
        // is rotated. This closes most of the 58pt gap without risking a collision.
        .padding(.top, 12)
    }

    /// Background taps close an open detail panel before they do anything else. With the
    /// chrome hidden behind a panel, the usual "toggle controls" response would be
    /// invisible, leaving the tap feeling dead.
    @MainActor
    private func handleBackgroundTap() {
        if playerDetailTab != nil {
            withAnimation(.snappy(duration: 0.2)) { playerDetailTab = nil }
            return
        }
        if showControls {
            hideControlsNow()
        } else {
            revealControls(scheduleAutoHide: true)
        }
    }

    @MainActor
    private func dismissPlayer() {
        guard !isDismissing else { return }
        isDismissing = true
        hideControlsTask?.cancel()
        cachedSourceFallbackTask?.cancel()
        engine.stop()
        mpvEngine.stop()
#if os(iOS)
        // Restore the orientation while this explicit close action is still on screen;
        // waiting for onDisappear leaves UIKit with no reason to re-query the mask.
        OrientationManager.shared.request(.portrait)
        PlaybackWakeLock.set(false)
#endif
        onDismiss()
    }

    // Prefer the actual episode title (already resolved by DetailScreen into
    // `streamTitle` when known) over a bare "S1 · E2" so the caption row reads
    // like the reference design instead of leaving it blank most of the time.
    private var episodeCaption: String? {
        guard let s = activeLaunch.seasonNumber, let e = activeLaunch.episodeNumber else { return nil }
        if let title = activeLaunch.streamTitle, !title.isEmpty { return title }
        return "S\(s) · E\(e)"
    }

    /// Title, episode caption and the right-hand icon row. Hidden while a detail panel
    /// is open — the panel takes this space, matching the Apple TV player.
    @ViewBuilder private var playerTitleRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if let episodeCaption {
                    Text(episodeCaption)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Text(activeLaunch.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                if hasAvailable4KSource {
                    controlPill(icon: "4k.tv", label: "4K") {
                        revealControls(scheduleAutoHide: true)
                        show4KChoice = true
                    }
                }
                nativeTrackMenus
                moreMenu
            }
        }
    }

    @ViewBuilder private var playerBottomArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Closed state: title + scrubber above the chips. Open state: neither —
            // the chips rise and the panel takes the space below them. The chip row is
            // the SAME view in both states, so SwiftUI animates its position rather
            // than cross-fading it; no matchedGeometryEffect is needed.
            if playerDetailTab == nil {
                playerTitleRow

                PlayerTimelineControls(
                    engine: engine,
                    timeline: timeline,
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

            playerDetailTabButtons

            if let tab = playerDetailTab {
                PlayerDetailsPanel(
                    tab: tab,
                    launch: activeLaunch,
                    detail: metaRepo.detail,
                    soundtrack: soundtrackService.soundtrack(forId: activeLaunch.parentMetaId ?? activeLaunch.videoId),
                    restart: { engine.seek(to: 0) }
                )
            }
        }
        // No horizontal padding. In landscape the safe area already insets this by
        // ~62pt, which is exactly where the Apple TV player puts its content edge.
        // Adding a nominal 20pt gutter on top double-inset the whole block and gave
        // away 40pt of width — measured at 82.7pt against Apple's 62.0pt.
        .padding(.bottom, 14)
        // A VStack(alignment: .leading) sizes itself to its CONTENT, not the screen.
        // Without this the backdrop below inherited that narrower width and stopped
        // partway across. Width only — height is untouched, so this cannot reintroduce
        // the vertical overflow that resized the video.
        .frame(maxWidth: .infinity, alignment: .leading)
        // Only while a panel is open. Applied unconditionally it read as a permanent
        // black bar across the bottom of the picture.
        //
        // Blurred material rather than a flat gradient, masked so it dissolves upward
        // instead of ending on a hard edge. `.background` is sized by its host and
        // cannot affect that host's layout, so this cannot inflate the container.
        .background {
            if playerDetailTab != nil {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black.opacity(0.6), location: 0.25),
                                .init(color: .black, location: 0.55),
                                .init(color: .black, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { chromeHeight = $0 }
    }

    @ViewBuilder
    private var playerDetailTabButtons: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    playerDetailTabButton(.info, title: "Info")
                    playerDetailTabButton(.spotlight, title: "Spotlight")
                    playerDetailTabButton(.soundtrack, title: "Soundtrack")
                }
            }
        } else {
            HStack(spacing: 8) {
                playerDetailTabButton(.info, title: "Info")
                playerDetailTabButton(.spotlight, title: "Spotlight")
                playerDetailTabButton(.soundtrack, title: "Soundtrack")
            }
        }
    }

    @ViewBuilder
    private var skipSegmentButton: some View {
        if VideoPlayerPreferenceStore.shared.showSkipIntroButton,
           !skipActionsHiddenForSource,
           let segment = segmentViewModel.segments?.action(at: timeline.position) {
            SkipSegmentAction(
                label: segment.kind == .recap ? "Skip Recap" : "Skip Intro"
            ) {
                engine.seek(to: segment.end)
                revealControls(scheduleAutoHide: true)
            }
            .contextMenu {
                Button("Hide Skip Actions", systemImage: "eye.slash") {
                    skipActionsHiddenForSource = true
                }
            }
        }
    }

    @ViewBuilder
    private var skipSegmentOverlay: some View {
        skipSegmentButton
            .padding(.trailing, 20)
            // Same reason as SubtitleTextOverlay: a rigid bottom padding built from
            // `chromeHeight` can exceed the screen and inflate the
            // enclosing ZStack, which resizes the video. Offset instead — it positions
            // without contributing to layout.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .offset(y: -(showControls ? chromeHeight + 12 : 28))
            .transition(.move(edge: .trailing).combined(with: .opacity))
            .animation(
                reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86),
                value: showControls
            )
            .zIndex(120)
    }

    private func playerDetailTabButton(_ tab: PlayerDetailTab, title: String) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                playerDetailTab = playerDetailTab == tab ? nil : tab
            }
        } label: {
            playerDetailTabLabel(tab, title: title)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(playerDetailTab == tab ? .isSelected : [])
    }

    @ViewBuilder
    private func playerDetailTabLabel(_ tab: PlayerDetailTab, title: String) -> some View {
        let selected = playerDetailTab == tab
        // `Text` hit-tests its glyph bounds, not the frame padded around it — without
        // an explicit contentShape the capsule looks tappable but only the word is.
        // Horizontal padding comes before the frame (not a minWidth) so every
        // label gets proportional breathing room — `minWidth: 76` alone left
        // "Soundtrack" (wider than that floor) with zero padding, its text
        // touching the capsule edge.
        let content = Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(minHeight: 48)
            .contentShape(.capsule)

        if #available(iOS 26.0, *) {
            // `.regular` is what actually reads as glass — `.clear` was
            // visually indistinguishable from a flat dark fill over video.
            content
                .glassEffect(
                    selected
                        ? .regular.tint(.white.opacity(0.28)).interactive()
                        : .regular.interactive(),
                    in: .capsule
                )
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(selected ? 0.28 : 0.12), lineWidth: 0.75)
                }
        }
    }

    private var nativeTrackMenus: some View {
        PlayerNativeTrackMenus(
            audioTracks: mpvEngine.availableAudioTrackItems,
            subtitles: engine.availableSubtitles,
            selectedAudioID: mpvEngine.availableAudioTrackItems.first(where: \.isSelected)?.id,
            selectedSubtitleID: engine.selectedSubtitle?.id,
            onSelectAudio: selectAudioTrackFromPanel,
            onSelectSubtitle: selectSubtitleFromPanel,
            onCustomizeSubtitles: openAdvancedSubtitleAppearance,
            onMenuPresented: pauseControlsAutoHide,
            onMenuDismissed: resumeControlsAutoHide
        )
        .equatable()
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
                .onAppear(perform: pauseControlsAutoHide)
                .onDisappear(perform: resumeControlsAutoHide)
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

    private var activeStreamIdentity: String {
        PlaybackStreamIdentity.make(
            providerName: activeLaunch.providerName,
            sourceURL: activeLaunch.sourceUrl,
            sourceSize: activeLaunch.sourceVideoSize,
            streamTitle: activeLaunch.streamTitle
        )
    }

    private var segmentLookupKey: String {
        let durationBucket = Int(mpvEngine.duration.rounded())
        let exactMarker = mpvEngine.embeddedPlaybackSegments == nil ? "remote" : "embedded"
        return "\(activeLaunch.videoId):\(activeStreamIdentity):\(durationBucket):\(exactMarker)"
    }

    private var loadingLogoURL: URL? {
        (resolvedLogo ?? activeLaunch.logo).flatMap(URL.init)
    }

    /// Best available landscape image for the loading card, in order of
    /// preference: wide fanart → fetched fanart → episode still → poster →
    /// fetched poster. The card always renders crisp — no blur fallback.
    private var loadingBackdropURL: String? {
        activeLaunch.background ?? resolvedBackground ?? metaRepo.detail?.background ?? activeLaunch.episodeThumbnail
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
        .glassCircle(clear: false)
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
        .glassCircle(clear: false)
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

    /// Single entry point for both the automatic failure sink and the manual
    /// "Retry source" menu action. Routed through `PlaybackRecoveryCoordinator`,
    /// which classifies what just failed and — only for the two shapes an
    /// expired or IP-rejected link actually takes — re-fetches the stream list
    /// from the user's own enabled addons before giving up. Shows the error
    /// overlay only once every avenue, including a fresh fetch, is exhausted.
    private func switchToNextSource() {
        Task {
            await recoverFromPlaybackFailure(
                failedUrl: activeLaunch.sourceUrl,
                failedHeaders: activeLaunch.sourceHeaders ?? [:]
            )
        }
    }

    /// `failedUrl`/`failedHeaders` describe whatever candidate just failed —
    /// this is NOT always `activeLaunch`. When `switchToSource` rejects a
    /// candidate at its own preflight, `activeLaunch` still reflects the
    /// previously-playing source, since the new one is only committed after a
    /// clean preflight.
    private func recoverFromPlaybackFailure(failedUrl: String, failedHeaders: [String: String]) async {
        if !failedUrl.isEmpty { recoveryCoordinator.markTried(failedUrl) }
        let reason: PlaybackFailureReason? = failedUrl.isEmpty
            ? nil
            : await StreamPreflight.classify(url: failedUrl, headers: failedHeaders)

        let candidates = isResolvingStream
            ? autoPlayCandidates
            : StreamSourceSelector.cachedCandidates(currentUrl: failedUrl, from: streamRepo.streams, prefer4K: prefers4K)

        let outcome = await recoveryCoordinator.recover(
            candidates: candidates,
            reason: reason,
            type: activeLaunch.contentType.rawValue,
            id: activeLaunch.videoId,
            title: activeLaunch.title,
            addons: addonRepo.activeAddons,
            prefer4K: prefers4K
        )

        guard let stream = outcome.stream else {
            isSwitchingStream = false
            mpvEngine.didEncounterError = true
            return
        }
        if isResolvingStream {
            autoPlayCandidates.removeAll { $0.id == stream.id }
        }
        StreamPlaybackDiagnostics.logSelectedStream(
            stream,
            reason: outcome.refetched ? "recovery-expired" : "recovery-cascade"
        )
        await switchToSource(stream, persist4KPreference: false)
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
            addons: addonRepo.activeAddons
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
        // instead of media. On failure, recoverFromPlaybackFailure() moves to the next.
        if await preflightReachable(url: url, headers: hints.requestHeaders ?? [:]) {
            mpvEngine.launch(nextLaunch)
            engine.launch(nextLaunch)
            wireCustomEngine()
            engine.play()
        } else {
            // URL rejected by preflight — try next candidate without showing error
            await recoverFromPlaybackFailure(failedUrl: url, failedHeaders: hints.requestHeaders ?? [:])
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

    private var subtitleCustomizationPanelWidth: CGFloat {
        let bounds = UIScreen.main.bounds
        return min(max(bounds.width, bounds.height) * 0.34, 380)
    }

    private func resumeControlsAutoHide() {
        guard !showSources,
              !showEpisodes,
              !show4KChoice,
              !showSubtitleAppearanceEditor,
              playerDetailTab == nil else {
            return
        }
        isAutoHidePausedByControls = false
        scheduleControlsAutoHide()
    }

    private func hideControlsNow() {
        guard !isScrubbing,
              !showSources,
              !showEpisodes,
              !show4KChoice,
              !showSubtitleAppearanceEditor,
              playerDetailTab == nil else {
            return
        }
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
        NSLog("[Moonlit][Loading] fetchDetail metaId=\(metaId) metaType=\(metaType) addons=\(addonRepo.activeAddons.count)")
        guard let detail = await metaRepo.fetchDetail(
            type: metaType,
            id: metaId,
            addons: addonRepo.activeAddons
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
        let installOrder = addonRepo.activeAddons.map(\.name)

        // Use pre-fetched streams from DetailScreen warmup if fresh (< 5 min).
        // This makes playback start instantly — no extra network round-trip needed.
        if let cached = await StreamWarmupRepository.shared.getCached(type: type, id: id),
           !cached.isEmpty {
            streamRepo.streams = cached
        } else {
            streamRepo.clearStreams()
            MainHangDiagnostics.mark("player.fetchStreams")
            let bg = Task { await streamRepo.fetchStreams(type: type, id: id, addons: addonRepo.activeAddons, title: activeLaunch.title) }
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

        // Resolve the best candidate via PlaybackRecoveryCoordinator: the first
        // pass (`reason: nil`) just preflights the already-fetched pool in rank
        // order; if every one of those fails, a second pass forces a fresh fetch
        // from the user's own enabled addons — the recoverable shape an expired
        // or IP-rejected link actually takes — before finally giving up.
        autoPlayCandidates = StreamSourceSelector.candidatesForAutoPlay(
            from: streamRepo.streams, prefer4K: prefer4K, installOrder: installOrder
        )
        MainHangDiagnostics.mark("player.preflight")
        var outcome = await recoveryCoordinator.recover(
            candidates: autoPlayCandidates,
            reason: nil,
            type: type, id: id, title: activeLaunch.title,
            addons: addonRepo.activeAddons, prefer4K: prefer4K
        )
        if outcome.stream == nil {
            outcome = await recoveryCoordinator.recover(
                candidates: [],
                reason: .providerError,
                type: type, id: id, title: activeLaunch.title,
                addons: addonRepo.activeAddons, prefer4K: prefer4K
            )
        }
        guard let stream = outcome.stream, let url = stream.url else {
            #if DEBUG
            print("[Moonlit] preflight all candidates unreachable, including a fresh fetch")
            #endif
            mpvEngine.didEncounterError = true
            return
        }
        autoPlayCandidates.removeAll { $0.id == stream.id }
        let hints = StreamPlaybackHints(stream: stream)
        StreamPlaybackDiagnostics.logSelectedStream(
            stream,
            reason: outcome.refetched ? "recovery-expired" : "player-ranked-auto"
        )

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
            addons: addonRepo.activeAddons
        )) ?? []
        var seen = Set<String>()
        let merged = (embedded + fetched)
            .filter { !$0.url.isEmpty }
            .filter { seen.insert($0.url).inserted }
        return merged.isEmpty ? nil : merged
    }

    /// Was a from-scratch reimplementation of `StreamPreflight.isReachable` with
    /// slightly drifting error markers — now a thin wrapper over the canonical
    /// MoonlitCore copy that `PlaybackRecoveryCoordinator` also uses.
    private func preflightReachable(url: String, headers: [String: String]) async -> Bool {
        await StreamPreflight.isReachable(url: url, headers: headers)
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
        mpvEngine.$isPlaying
            .removeDuplicates()
            .sink { isPlaying in
#if os(iOS)
                PlaybackWakeLock.set(isPlaying)
#endif
            }
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
                // Always attempt recovery, even mid-playback with only one known
                // source — PlaybackRecoveryCoordinator may still find a fresh URL
                // for it via a re-fetch. It shows the error overlay itself once
                // every avenue is exhausted.
                self.switchToNextSource()
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

// MARK: - Playback segments

@MainActor
private class PlaybackSegmentsViewModel: ObservableObject {
    @Published var segments: PlaybackSegments?
    private var activeLoadToken: UUID?

    func load(
        request: PlaybackSegmentRequest,
        exactSegments: PlaybackSegments?
    ) async {
        let loadToken = UUID()
        activeLoadToken = loadToken
        segments = nil
        let result = await IntroTimestampService.shared.segments(
            request: request,
            exactSegments: exactSegments
        )
        guard !Task.isCancelled, activeLoadToken == loadToken else { return }
        segments = result
    }

    func clear() {
        activeLoadToken = nil
        segments = nil
    }
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

private enum PlayerDetailTab { case info, spotlight, soundtrack }

private struct PlayerDetailsPanel: View {
    let tab: PlayerDetailTab
    let launch: PlayerLaunch
    let detail: MetaDetail?
    let soundtrack: TitleSoundtrack?
    let restart: () -> Void

    @State private var albumArtworkURL: URL?

    var body: some View {
        Group {
            switch tab {
            case .info:
                HStack(spacing: 14) {
                    if let image = launch.episodeThumbnail ?? launch.poster, let url = URL(string: image) {
                        CachedAsyncImage(url: url) { phase in
                            if case .success(let image) = phase { image.resizable().scaledToFill() }
                            else { Color.white.opacity(0.1) }
                        }
                        .frame(width: 108, height: 64).clipShape(.rect(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(launch.title).font(.system(size: 16, weight: .bold))
                        Text(detail?.description ?? launch.streamTitle ?? "Now playing")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.72)).lineLimit(3)
                    }
                    Spacer()
                    Button(action: restart) { Label("From Beginning", systemImage: "play.fill") }
                        .buttonStyle(.bordered).tint(.white).foregroundStyle(.black)
                }
            case .spotlight:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach((detail?.cast ?? []).prefix(8)) { person in
                            VStack(alignment: .leading, spacing: 8) {
                                Group {
                                    if let photo = person.photo, let url = URL(string: photo) {
                                        CachedAsyncImage(url: url) { phase in
                                            if case .success(let image) = phase {
                                                image.resizable().scaledToFill()
                                            } else {
                                                actorPlaceholder
                                            }
                                        }
                                    } else {
                                        actorPlaceholder
                                    }
                                }
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .padding(4)
                                .modifier(SpotlightCastGlass())
                                .overlay {
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.75)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(person.name).font(.system(size: 11.5, weight: .bold)).lineLimit(1)
                                    if let character = person.character, !character.isEmpty {
                                        Text(character)
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(.white.opacity(0.55))
                                            .lineLimit(1)
                                    }
                                }
                            }.frame(width: 84, alignment: .leading)
                        }
                        if (detail?.cast ?? []).isEmpty { Text("Cast information is unavailable for this title.").foregroundStyle(.white.opacity(0.65)) }
                    }
                }
            case .soundtrack:
                let cues = soundtrack?.cues ?? []
                if cues.isEmpty {
                    Text("No soundtrack information is available for this title.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                } else {
                    // The height cap is load-bearing, not cosmetic. A vertical
                    // ScrollView has no intrinsic height — it expands to fill whatever
                    // it is offered. This panel sits inside the measured bottom block
                    // (`chromeHeight`), which sibling overlays offset themselves by; an
                    // uncapped list would take every point offered, and the measurement
                    // would chase it. That runaway pegs the main thread — the controls
                    // stop responding while mpv, which renders off the main thread,
                    // carries on playing. Info and Spotlight never hit it because both
                    // have an intrinsic height and cannot expand.
                    //
                    // LazyVStack because a soundtrack can carry 100+ cues and every row
                    // builds a CachedAsyncImage; the eager VStack constructed all of
                    // them, and kicked off all their fetches, in one main-thread pass.
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            albumHeader
                            ForEach(cues) { cue in
                                soundtrackRow(cue)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }
        }
        // No card. The Apple TV player renders panel content flush over the video,
        // legibility coming from the bottom scrim on `playerBottomArea` rather than
        // from a container. Vertical padding only — horizontal comes from the block.
        .padding(.vertical, 8)
        .task {
            guard tab == .soundtrack, let groupId = soundtrack?.releaseGroupId else { return }
            albumArtworkURL = await SoundtrackService.fetchAlbumArtwork(releaseGroupId: groupId)
        }
    }

    @ViewBuilder
    private var albumHeader: some View {
        if let sourceAlbum = soundtrack?.sourceAlbum {
            HStack(spacing: 12) {
                Group {
                    if let url = albumArtworkURL {
                        CachedAsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFill()
                            } else {
                                albumArtPlaceholder
                            }
                        }
                    } else {
                        albumArtPlaceholder
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("SOUNDTRACK")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(.white.opacity(0.4))
                    Text(sourceAlbum)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let count = soundtrack?.cues.count {
                        Text("\(count) tracks")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                Spacer()
            }
            .padding(.bottom, 4)

            Divider()
                .background(Color.white.opacity(0.12))
        }
    }

    private func soundtrackRow(_ cue: SoundtrackCue) -> some View {
        HStack(spacing: 10) {
            Group {
                if let artworkURL = cue.artworkURL, let url = URL(string: artworkURL) {
                    CachedAsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            soundtrackArtPlaceholder
                        }
                    }
                } else {
                    soundtrackArtPlaceholder
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(cue.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let artist = cue.artist {
                    Text(artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                if let scene = cue.sceneDescription {
                    Text(scene)
                        .font(.system(size: 11))
                        .foregroundStyle(MoonlitTheme.accent.opacity(0.85))
                        .lineLimit(2)
                }
            }
            Spacer()
        }
    }

    private var soundtrackArtPlaceholder: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .overlay(Image(systemName: "music.note").font(.system(size: 15)).foregroundStyle(.white.opacity(0.5)))
    }

    private var albumArtPlaceholder: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .overlay(Image(systemName: "music.note.list").font(.system(size: 22)).foregroundStyle(.white.opacity(0.4)))
    }

    private var actorPlaceholder: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .overlay(Image(systemName: "person.fill").foregroundStyle(.white.opacity(0.7)))
    }
}

/// Real liquid glass over the cast photo — matches the reference Apple TV
/// InSight cards and the rounded-square treatment `DetailScreen`/
/// `ActorBioScreen` already use for cast, instead of Spotlight's old bare
/// circle with no chrome.
private struct SpotlightCastGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 20, style: .continuous))
        } else {
            content.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

private struct PlayerTimelineControls: View {
    let engine: PlayerEngine
    @ObservedObject var timeline: PlayerTimelineModel
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
        HStack(spacing: 10) {
            // Leading, not trailing. Right-aligning a short time like "00:29" inside a
            // 44pt box pushed it ~12pt inward, so it no longer shared the left edge with
            // the title and chips. Apple puts elapsed time, title and chips on one
            // unbroken vertical line; one stray edge is enough to lose that.
            Text(formatTime(displayPosition))
                .frame(minWidth: 44, alignment: .leading)

            PlayerScrubber(
                value: scrubberBinding,
                duration: max(timeline.duration, 0),
                isScrubbing: isScrubbing,
                onEditingChanged: handleScrubbingChanged,
                highlights: []
            )
            .frame(maxWidth: .infinity)

            // Trailing, for the mirror reason: the remaining time should pin to the
            // right content edge rather than floating just after the track.
            Text("−\(formatTime(max(timeline.duration - displayPosition, 0)))")
                .frame(minWidth: 52, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .medium).monospacedDigit())
        .foregroundStyle(.white.opacity(0.55))
    }


    private func handleScrubbingChanged(_ editing: Bool) {
        if editing {
            if !isScrubbing {
                scrubPosition = timeline.position
                onScrubStarted()
            }
            isScrubbing = true
        } else {
            let destination = scrubPosition
            timeline.update(position: destination)
            engine.seek(to: destination)
            isScrubbing = false
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

private struct SkipSegmentAction: View {
    let label: String
    let onSkip: () -> Void

    var body: some View {
        Button(action: onSkip) {
            let content = HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .contentShape(.capsule)

#if os(iOS)
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular.interactive(), in: .capsule)
            } else {
                content
                    .background(.ultraThinMaterial, in: Capsule())
                    .environment(\.colorScheme, .dark)
            }
#else
            content
                .background(.ultraThinMaterial, in: Capsule())
                .environment(\.colorScheme, .dark)
#endif
        }
        .buttonStyle(.plain)
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
    let delay: TimeInterval
    let trailingInset: CGFloat
    let extraBottomInset: CGFloat

    var body: some View {
        let _ = PlayerPerformanceDiagnostics.shared.mark("SubtitleTextOverlay.body")
        SubtitleTextOverlay(index: index, position: timeline.position - delay, extraBottomInset: extraBottomInset)
            .padding(.trailing, trailingInset)
    }
}

private struct SubtitleTextOverlay: View {
    let index: SubtitleCueIndex
    let position: TimeInterval
    let extraBottomInset: CGFloat
    @ObservedObject private var appearance = SubtitleAppearanceStore.shared

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
                        .font(.system(
                            size: min(max(appearance.fontSize * appearance.scale, 12), 72),
                            weight: appearance.isBold ? .bold : .regular
                        ))
                        .italic(appearance.isItalic)
                        .foregroundStyle(subtitleColor(appearance.textColorHex, fallback: .white))
                        .multilineTextAlignment(textAlignment)
                        .lineSpacing(2)
                        .shadow(
                            color: subtitleColor(appearance.outlineColorHex, fallback: .black).opacity(0.95),
                            radius: 2,
                            x: 1,
                            y: 1
                        )
                        .shadow(
                            color: subtitleColor(appearance.outlineColorHex, fallback: .black).opacity(0.95),
                            radius: 2,
                            x: -1,
                            y: -1
                        )
                        .blur(radius: appearance.textBlur)
                        .padding(.horizontal, appearance.horizontalMargin)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: frameAlignment)
                        .background(
                            subtitleColor(appearance.backgroundColorHex, fallback: .black)
                                .opacity(appearance.backgroundOpacity),
                            in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusSmall)
                        )
                        .padding(.bottom, 4)
                }
            }
        }
        // `.offset`, not `.padding`. Padding is rigid: it raises this view's MINIMUM
        // height, and the `.frame(maxHeight: .infinity)` that follows cannot shrink below
        // it. With a detail panel open the inset reaches ~503pt on a 402pt screen, so this
        // overlay demanded 503pt, the enclosing ZStack grew to match, and the mpv video
        // view — a sibling with `.ignoresSafeArea()` — filled the inflated space and
        // rendered ~101pt taller than the screen. That was the "zoom".
        //
        // `.offset` is a render-time transform and contributes nothing to layout, so the
        // subtitles still lift above the chrome without any of it reaching the container.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .offset(y: -(SubtitleRenderingMetrics.bottomMargin(appearance.verticalPosition) + extraBottomInset))
    }

    private var textAlignment: TextAlignment {
        switch appearance.horizontalAlignment {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }

    private var frameAlignment: Alignment {
        switch appearance.horizontalAlignment {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }

    private func subtitleColor(_ hex: String, fallback: Color) -> Color {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return fallback }
        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

extension View {
    @ViewBuilder
    func glassCapsuleActive(isActive: Bool) -> some View {
        // Non-interactive glass: the interactive press effect fights the Menu's
        // own open/highlight animation and flashes matte for a frame. `glassCapsule`
        // has no tint parameter, so the active state is a plate behind the content,
        // visible through the glass blur — `isActive` previously had no effect at all.
        self
            .background {
                if isActive {
                    Capsule(style: .continuous).fill(Color.white.opacity(0.24))
                }
            }
            .glassCapsule(interactive: false, clear: false)
    }
}
