import SwiftUI
import UIKit
import Combine
import AVFoundation
import MediaPlayer
import LunaCore

struct PlayerScreen: View {
    let onDismiss: () -> Void

    @StateObject private var engine = PlayerEngine.shared
    @StateObject private var ksEngine = KSPlayerEngine()
    @State private var activeLaunch: PlayerLaunch
    @StateObject private var streamRepo = StreamRepository.shared
    @StateObject private var addonRepo = AddonRepository.shared
    @StateObject private var metaRepo = MetaRepository.shared
    @State private var showControls = true
    @State private var logoPulse = false
    @State private var resolvedLogo: String?
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
    @State private var isFillingVideo = false
    // Snapshots frozen when a menu opens so 250ms currentPosition re-renders
    // don't rebuild the content and reset the menu's scroll position.
    @State private var subtitleMenuSnapshot: [(lang: String, items: [SubtitleItem])] = []
    @State private var subtitleMenuSelectedSnapshot: SubtitleItem? = nil
    @State private var audioMenuSnapshot: [String] = []
    @State private var audioMenuSelectedSnapshot: String? = nil

    // Volume
    @State private var systemVolume: Float = AVAudioSession.sharedInstance().outputVolume

    // Skip Intro
    @StateObject private var introViewModel = IntroTimestampServiceViewModel()

    init(launch: PlayerLaunch, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        _activeLaunch = State(initialValue: launch)
    }

    private var videoReady: Bool {
        (engine.customDisplayView ?? ksEngine.displayView) != nil && ksEngine.hasRenderedFrame
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // ── PRE-ROLL BACKDROP ─────────────────────────────────────────
            if !videoReady {
                let backdropURL = (activeLaunch.episodeThumbnail ?? activeLaunch.poster).flatMap(URL.init)
                let logoURL = loadingLogoURL
                ZStack {
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
                    Color.black.opacity(backdropURL == nil ? 1 : 0.55).ignoresSafeArea()

                    Group {
                        if let logoURL {
                            CachedAsyncImage(url: logoURL) { phase in
                                if case .success(let img) = phase {
                                    img.resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: 220)
                                        .shadow(color: .black.opacity(0.6), radius: 12, x: 0, y: 4)
                                }
                                // .loading / .failure → show nothing, no title text flash
                            }
                        }
                        // logoURL nil → show nothing while logo resolves
                    }
                    .opacity(logoPulse ? 1.0 : 0.35)
                    .animation(
                        .easeInOut(duration: 1.15)
                        .repeatForever(autoreverses: true),
                        value: logoPulse
                    )
                }
                .transition(.opacity)
            }

            if let ksView = engine.customDisplayView ?? ksEngine.displayView {
                KSPlayerViewRepresentable(playerView: ksView)
                    .ignoresSafeArea()
                    .playerGestures(
                        engine: engine,
                        state: $gestureState,
                        showControls: $showControls,
                        isLocked: $isLocked
                    )
                    .gesture(
                        MagnificationGesture()
                            .onEnded { scale in
                                let fill = scale > 1.05
                                isFillingVideo = fill
                                ksEngine.setVideoFill(fill)
                                revealControls(scheduleAutoHide: true)
                            }
                    )
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
            if !ksEngine.loadedCues.isEmpty {
                SubtitleTextOverlay(cues: ksEngine.loadedCues, position: engine.currentPosition)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }

            PlayerLockMode(isLocked: $isLocked, showHint: $showUnlockHint)

            if showControls && !isLocked {
                playerControlsLayer
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            OrientationManager.shared.currentMask = .allButUpsideDown
            logoPulse = false
            Task { @MainActor in logoPulse = true }
            Task { await resolveMissingLogoIfNeeded() }
            revealControls(scheduleAutoHide: true)
            if activeLaunch.sourceUrl.isEmpty {
                Task { await fetchAndAutoLaunch() }
            } else {
                ksEngine.launch(activeLaunch)
                engine.launch(activeLaunch)
                wireCustomEngine()
                engine.play()
                refreshSourceControlState()
                Task {
                    await ensureStreamsLoadedForActiveLaunch()
                    await loadSubtitlesForActiveLaunchIfNeeded()
                }
            }
            // Request landscape after the fullScreenCover slide-up animation finishes
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
                }
            }
        }
        .onDisappear {
            hideControlsTask?.cancel()
            logoPulse = false
            OrientationManager.shared.currentMask = .portrait
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
            }
            engine.stop()
            ksEngine.stop()
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
        .onChange(of: streamRepo.streams) { _, _ in refreshSourceControlState() }
        .onChange(of: activeLaunch.sourceUrl) { _, _ in refreshSourceControlState() }
        .task(id: activeLaunch.videoId) {
            if let imdbId = activeLaunch.parentMetaId,
               let season = activeLaunch.seasonNumber,
               let episode = activeLaunch.episodeNumber {
                await introViewModel.load(imdbId: imdbId, season: season, episode: episode)
            } else {
                introViewModel.clear()
            }
        }
        .onChange(of: engine.currentPosition) { _, newPos in
            guard VideoPlayerPreferenceStore.shared.autoSkipIntros,
                  let ts = introViewModel.timestamps,
                  newPos >= ts.introStart && newPos < ts.introEnd else { return }
            engine.seek(to: ts.introEnd)
        }
        .animation(.easeInOut(duration: 0.4), value: videoReady)
        .overlay(alignment: .trailing) {
            if showSources {
                SourcesPanel(engine: engine, isShowing: $showSources) { stream in
                    showSources = false
                    switchToSource(stream, persist4KPreference: false)
                }
                .padding(.trailing, 16)
                .padding(.vertical, 20)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .onChange(of: showSources) { _, showing in
            showing ? pauseControlsAutoHide() : scheduleControlsAutoHide()
        }
        .animation(.easeInOut(duration: 0.22), value: showSources)
        .onChange(of: showEpisodes) { _, showing in
            showing ? pauseControlsAutoHide() : scheduleControlsAutoHide()
        }
        .sheet(isPresented: $showEpisodes) { EpisodesPanel(engine: engine) }
        .confirmationDialog("4K Playback", isPresented: $show4KChoice, titleVisibility: .visible) {
            Button("Use 4K This Time") {
                if let stream = available4KStream {
                    switchToSource(stream, persist4KPreference: false)
                }
            }
            Button("Always Prefer 4K") {
                if let profile = ProfileManager.shared.currentProfile {
                    PlaybackQualityPreferenceStore.shared.setPrefers4K(true, profileId: profile.id)
                }
                if let stream = available4KStream {
                    switchToSource(stream, persist4KPreference: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose whether 4K is only for this playback or should be preferred next time.")
        }
    }

    @ViewBuilder private var playerControlsLayer: some View {
        ZStack {
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

            GlassVolumeSlider(volume: $systemVolume)

            // Hidden volume view for system volume control
            VolumeViewRepresentable(volume: $systemVolume)
                .frame(width: 0, height: 0)
                .opacity(0)
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

            // Skip Intro button — shown when in intro window
            let prefs = VideoPlayerPreferenceStore.shared
            if prefs.showSkipIntroButton,
               let ts = introViewModel.timestamps,
               engine.currentPosition >= ts.introStart && engine.currentPosition < ts.introEnd {
                HStack {
                    Spacer()
                    SkipIntroButton { engine.seek(to: ts.introEnd) }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
                .animation(.spring(duration: 0.3), value: introViewModel.timestamps != nil)
            }

            PlayerScrubber(
                value: scrubberBinding,
                duration: max(engine.duration, 0),
                isScrubbing: isScrubbing,
                onEditingChanged: handleScrubbingChanged,
                highlights: introViewModel.timestamps?.highlights ?? []
            )

            HStack {
                Text(formatTime(displayPosition))
                Spacer()
                Text(formatTime(max(engine.duration - displayPosition, 0)))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.5))
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
                    hideControlsTask?.cancel()
                    let grouped = Dictionary(grouping: engine.availableSubtitles, by: { $0.lang })
                    subtitleMenuSnapshot = grouped.keys.sorted().map { k in
                        (lang: k, items: (grouped[k] ?? []).sorted { ($0.name ?? $0.lang) < ($1.name ?? $1.lang) })
                    }
                    subtitleMenuSelectedSnapshot = engine.selectedSubtitle
                }
                .onDisappear {
                    subtitleMenuSnapshot = []
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
        let isActive = !engine.availableAudioTracks.isEmpty && engine.selectedAudioTrack != nil
        Menu {
            ForEach(audioMenuSnapshot, id: \.self) { track in
                Button(action: { revealControls(scheduleAutoHide: true); engine.setAudioTrack(track) }) {
                    if audioMenuSelectedSnapshot == track {
                        Label(track, systemImage: "checkmark")
                    } else {
                        Text(track)
                    }
                }
            }
            Color.clear.frame(width: 0, height: 0)
                .onAppear {
                    hideControlsTask?.cancel()
                    audioMenuSnapshot = engine.availableAudioTracks
                    audioMenuSelectedSnapshot = engine.selectedAudioTrack
                }
                .onDisappear {
                    audioMenuSnapshot = []
                    scheduleControlsAutoHide()
                }
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

    private var displayPosition: Double {
        isScrubbing ? scrubPosition : engine.currentPosition
    }

    private var scrubberBinding: Binding<Double> {
        Binding(
            get: { displayPosition },
            set: { newValue in
                scrubPosition = min(max(newValue, 0), max(engine.duration, 0))
            }
        )
    }

    private func handleScrubbingChanged(_ editing: Bool) {
        isScrubbing = editing
        if editing {
            hideControlsTask?.cancel()
            isAutoHidePausedByControls = true
            scrubPosition = engine.currentPosition
        } else {
            engine.seek(to: scrubPosition)
            pauseControlsAutoHide()
        }
    }

    private var currentStream: StreamItem? {
        streamRepo.streams.first { $0.url == activeLaunch.sourceUrl }
    }

    private var loadingLogoURL: URL? {
        (resolvedLogo ?? activeLaunch.logo).flatMap(URL.init)
    }

    private var loadingTitle: some View {
        Text(activeLaunch.title)
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
    }

    private var available4KStream: StreamItem? {
        StreamSourceSelector.best4KStream(from: streamRepo.streams, excluding: currentStream)
    }

    private func switchToNextSource() {
        guard let stream = StreamSourceSelector.nextStream(
            after: currentStream,
            currentSourceUrl: activeLaunch.sourceUrl,
            from: streamRepo.streams,
            prefer4K: prefers4K
        ) else { return }
        switchToSource(stream, persist4KPreference: false)
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
        ksEngine.loadSubtitles(from: subtitles)
        engine.availableSubtitles = subtitles
    }

    private func switchToSource(_ stream: StreamItem, persist4KPreference: Bool) {
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
            background: activeLaunch.background,
            seasonNumber: activeLaunch.seasonNumber,
            episodeNumber: activeLaunch.episodeNumber,
            streamTitle: activeLaunch.streamTitle ?? stream.displayName,
            providerName: stream.addonName,
            contentType: activeLaunch.contentType,
            videoId: activeLaunch.videoId,
            parentMetaId: activeLaunch.parentMetaId,
            parentMetaType: activeLaunch.parentMetaType,
            initialPositionMs: max(engine.currentPosition, 0) * 1000,
            subtitles: stream.subtitles ?? activeLaunch.subtitles
        )

        savePlaybackSource(for: stream, url: url, launch: nextLaunch)
        engine.pause()
        ksEngine.stop()
        engine.resetState()
        activeLaunch = nextLaunch
        resolvedLogo = nextLaunch.logo ?? resolvedLogo
        ksEngine.launch(nextLaunch)
        engine.launch(nextLaunch)
        wireCustomEngine()
        engine.play()
        logoPulse = false
        Task { @MainActor in logoPulse = true }
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
        hideControlsTask?.cancel()
        isAutoHidePausedByControls = false
        withAnimation(.easeInOut(duration: 0.22)) {
            showControls = false
            showSources = false
            show4KChoice = false
        }
    }

    private func scheduleControlsAutoHide() {
        guard showControls, !isScrubbing, !isAutoHidePausedByControls else { return }
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

    private func resolveMissingLogoIfNeeded() async {
        guard loadingLogoURL == nil else { return }
        if addonRepo.enabledAddons.isEmpty,
           let profile = ProfileManager.shared.currentProfile {
            await addonRepo.loadAddons(profileId: profile.id)
        }
        let metaId = activeLaunch.parentMetaId ?? activeLaunch.videoId
        let metaType = activeLaunch.parentMetaType ?? activeLaunch.contentType.rawValue
        guard let detail = await metaRepo.fetchDetail(
            type: metaType,
            id: metaId,
            addons: addonRepo.enabledAddons
        ) else { return }
        resolvedLogo = detail.logo
    }

    private func fetchAndAutoLaunch() async {
        guard !isFetchingStream else { return }
        isFetchingStream = true
        defer { isFetchingStream = false }

        if addonRepo.enabledAddons.isEmpty,
           let profile = ProfileManager.shared.currentProfile {
            await addonRepo.loadAddons(profileId: profile.id)
        }

        let type = activeLaunch.contentType.rawValue
        let id   = activeLaunch.videoId

        // Use pre-fetched streams from DetailScreen warmup if fresh (< 5 min).
        // This makes playback start instantly — no extra network round-trip needed.
        if let cached = await StreamWarmupRepository.shared.getCached(type: type, id: id),
           !cached.isEmpty {
            streamRepo.streams = cached
        } else {
            streamRepo.clearStreams()
            await streamRepo.fetchStreams(type: type, id: id, addons: addonRepo.enabledAddons)
        }

        let prefer4K: Bool = {
            guard let profile = ProfileManager.shared.currentProfile else { return false }
            return PlaybackQualityPreferenceStore.shared.prefers4K(profileId: profile.id)
        }()

        guard let stream = StreamSourceSelector.initialStream(from: streamRepo.streams, prefer4K: prefer4K),
              StreamSourceSelector.isPlaybackCandidate(stream),
              let url = stream.url else { return }
        StreamPlaybackDiagnostics.logSelectedStream(stream, reason: "player-ranked-auto")

        // Start playback immediately — don't block on warmup or subtitle fetch
        let hints = StreamPlaybackHints(stream: stream)
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
            background: activeLaunch.background,
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
        ksEngine.launch(launch)
        engine.launch(launch)
        wireCustomEngine()
        engine.play()
        refreshSourceControlState()

        // Load subtitles in background — don't block playback start
        let capturedStream = stream
        Task { @MainActor in
            let subtitles = await resolvedSubtitles(for: capturedStream)
            guard let subtitles, !subtitles.isEmpty else { return }
            ksEngine.loadSubtitles(from: subtitles)
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

    private var feedbackText: String {
        switch gestureState.mode {
        case .brightness: return "\(Int(gestureState.value * 100))%"
        case .none: return ""
        }
    }

    private func wireCustomEngine() {
        engine.customDisplayView = ksEngine.displayView
        engine.onCustomPlay = { [weak ksEngine] in ksEngine?.play() }
        engine.onCustomPause = { [weak ksEngine] in ksEngine?.pause() }
        engine.onCustomSeek = { [weak ksEngine] in ksEngine?.seek(to: $0) }
        engine.onCustomSetSpeed = { [weak ksEngine] in ksEngine?.setPlaybackSpeed($0) }
        engine.onCustomSkipForward = { [weak ksEngine] in ksEngine?.skipForward() }
        engine.onCustomSkipBack = { [weak ksEngine] in ksEngine?.skipBack() }
        engine.onCustomSkipForward15 = { [weak ksEngine] in ksEngine?.skipForward15() }
        engine.onCustomSkipBack15 = { [weak ksEngine] in ksEngine?.skipBack15() }
        engine.onCustomToggleMute = { [weak ksEngine] in ksEngine?.toggleMute() }
        engine.onCustomCycleSubtitle = { [weak ksEngine] in ksEngine?.cycleSubtitle() }
        engine.onCustomSetSubtitle = { [weak ksEngine] in ksEngine?.setSubtitle($0) }
        engine.onCustomSetAudioTrack = { [weak ksEngine] in ksEngine?.selectAudioTrack(named: $0) }
        engine.onCustomStop = { [weak ksEngine] in ksEngine?.stop() }

        guard !didWireCustomEngine else { return }
        didWireCustomEngine = true

        ksEngine.$isPlaying
            .removeDuplicates()
            .sink { engine.isPlaying = $0 }
            .store(in: &engineBindings)
        ksEngine.$isLoading
            .removeDuplicates()
            .sink { engine.isLoading = $0 }
            .store(in: &engineBindings)
        ksEngine.$isEnded
            .removeDuplicates()
            .sink { engine.isEnded = $0 }
            .store(in: &engineBindings)
        ksEngine.$currentPosition
            .throttle(for: .milliseconds(250), scheduler: RunLoop.main, latest: true)
            .sink { engine.currentPosition = $0 }
            .store(in: &engineBindings)
        ksEngine.$duration
            .removeDuplicates()
            .sink { engine.duration = $0 }
            .store(in: &engineBindings)
        ksEngine.$playbackSpeed
            .removeDuplicates()
            .sink { engine.playbackSpeed = $0 }
            .store(in: &engineBindings)
        ksEngine.$availableSubtitles
            .removeDuplicates()
            .sink { engine.availableSubtitles = $0 }
            .store(in: &engineBindings)
        ksEngine.$selectedSubtitle
            .removeDuplicates()
            .sink { engine.selectedSubtitle = $0 }
            .store(in: &engineBindings)
        ksEngine.$availableAudioTracks
            .removeDuplicates()
            .sink { engine.availableAudioTracks = $0 }
            .store(in: &engineBindings)
        ksEngine.$selectedAudioTrack
            .removeDuplicates()
            .sink { engine.selectedAudioTrack = $0 }
            .store(in: &engineBindings)
        ksEngine.$isMuted
            .removeDuplicates()
            .sink { engine.isMuted = $0 }
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

private struct GlassVolumeSlider: View {
    @Binding var volume: Float

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: volume <= 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 14)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2)).frame(height: 4)
                    Capsule()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: geo.size.width * CGFloat(volume), height: 4)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                        .offset(x: max(0, geo.size.width * CGFloat(volume) - 9))
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            volume = Float(max(0, min(1, val.location.x / geo.size.width)))
                        }
                )
            }
            .frame(width: 180, height: 22)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            if #available(iOS 26.0, *) {
                Capsule().glassEffect()
            } else {
                Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
            }
        }
    }
}

// MARK: - System Volume Bridge

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

// MARK: - Skip Intro Button

private struct SkipIntroButton: View {
    let onSkip: () -> Void

    var body: some View {
        Button(action: onSkip) {
            HStack(spacing: 5) {
                Text("Skip Intro")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background {
                if #available(iOS 26.0, *) {
                    Capsule().glassEffect()
                } else {
                    Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                }
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
    }
}

// MARK: - Subtitle Text Overlay

private struct SubtitleTextOverlay: View {
    let cues: [SubtitleCue]
    let position: TimeInterval

    private var active: [SubtitleCue] {
        cues.filter { position >= $0.start && position < $0.end }
    }

    var body: some View {
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
                        .background(Color.black.opacity(0.45).cornerRadius(6))
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
        self.glassCapsule(interactive: true, clear: false)
    }
}
