import SwiftUI
import MoonlitCore

#if os(macOS)
import AppKit
#endif

struct MacPlayerView: View {
    let launch: PlayerLaunch

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var profileManager: ProfileManager
    @StateObject private var engine = MPVPlayerEngine()
    @StateObject private var addonRepo = AddonRepository.shared
    @StateObject private var videoPrefs = VideoPlayerPreferenceStore.shared
    @State private var visibility = PlayerControlVisibilityState()
    @State private var hideTask: Task<Void, Never>?
    @State private var isSeeking = false
    @State private var pendingSeekTime: Double = 0
    @State private var subtitleChoices: [SubtitleItem] = []
    @State private var selectedExternalSubtitle: SubtitleItem?
    @State private var externalSubtitleCues: [SubtitleCue] = []
    @State private var isLoadingSubtitles = false
    @State private var subtitleError: String?
    @State private var showStartupLoading = true
    @State private var autoPlayCandidates: [StreamItem] = []
    @State private var triedUrls = Set<String>()
    @State private var isTryingNextSource = false
    @State private var errorUIVisible = false
    @State private var introStart: Double?
    @State private var introEnd: Double?
    @State private var hasAutoSkippedIntro = false
    @State private var skipPillDismissed = false
    @State private var adjacentEpisodes: (prev: MetaVideo?, next: MetaVideo?) = (nil, nil)
    @State private var isChangingEpisode = false
    @State private var pipController = MacPipWindowController()
    @State private var isPipActive = false
    @State private var startupLoadingTask: Task<Void, Never>?
    @State private var playerWindow: NSWindow?
    @State private var showUpNextPanel = false
    @State private var upNextDetail: MetaDetail?
    @State private var upNextSeasonNumber: Int = 1
    @State private var didAutoPromptUpNext = false
    @State private var showEpisodeInfoPanel = false
    @State private var episodeGuestStars: [Person] = []
    @State private var isLoadingGuestStars = false
    @State private var episodePosterURL: URL?
    @State private var episodeGuestStarIDs: Set<String> = []
    @State private var episodeDirectors: [String] = []
    @State private var episodeWriters: [String] = []
    // #6 player additions
    @State private var streamCheckVariant: MacStreamCheckPill.Variant?
    @State private var streamCheckDismissed = false
    @State private var streamCheckTask: Task<Void, Never>?
    @State private var cachedFallbackToast: String?
    @State private var cachedToastTask: Task<Void, Never>?
    @State private var showSourcePicker = false
    @State private var showResumePrompt = false
    @State private var didOfferResume = false
    @State private var screenshotToast: String?

    var body: some View {
        ZStack {
            Color.black

            if let displayView = engine.displayView, !isPipActive {
                MPVPlayerViewRepresentable(playerView: displayView)
                    .ignoresSafeArea()
            } else if engine.didEncounterError {
                Color.black.ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "play.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.4))
                    Text("Playback failed")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text(isTryingNextSource
                         ? "Trying next source… (\(triedUrls.count) of \(autoPlayCandidates.count + 1))"
                         : (triedUrls.isEmpty
                              ? "This stream could not be played."
                              : "Tried \(triedUrls.count + 1) source(s) — none worked."))
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.55))
                    HStack(spacing: 12) {
                Button {
                    isTryingNextSource = false
                    triedUrls = []
                    showStartupLoading = true
                    engine.launch(launch)
                    waitForFirstFrameThenHideOverlay()
                    Task { await fetchAutoPlayCandidates() }
                } label: {
                            Label("Retry Stream", systemImage: "arrow.clockwise")
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                        }
                        .buttonStyle(.plain)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                        .foregroundColor(.white)
                        Button(action: { tryNextCandidate() }) {
                            Label("Next Source", systemImage: "forward.fill")
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                        }
                        .buttonStyle(.plain)
                        .background(Capsule().fill(MoonlitTheme.accent.opacity(0.18)))
                        .foregroundColor(MoonlitTheme.accent)
                        .opacity(!autoPlayCandidates.isEmpty ? 1 : 0.4)
                        Button(action: { dismiss() }) {
                            Label("Close", systemImage: "xmark")
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                        }
                        .buttonStyle(.plain)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .foregroundColor(.white.opacity(0.7))
                    }
                }
                .scaleEffect(errorUIVisible ? 1 : 0.98)
                .opacity(errorUIVisible ? 1 : 0)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: errorUIVisible)
                .onAppear { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { errorUIVisible = true } }
                .onDisappear { errorUIVisible = false }
            }

            if let selectedExternalSubtitle {
                ExternalSubtitleOverlay(
                    cues: externalSubtitleCues,
                    time: engine.currentPosition,
                    isLoading: isLoadingSubtitles,
                    title: selectedExternalSubtitle.displayTitle
                )
                .padding(.horizontal, 56)
                .padding(.bottom, 150)
                .allowsHitTesting(false)
            }

            PlayerMouseTrackingView {
                showControls()
            }
            .ignoresSafeArea()

            if showStartupLoading {
                PlayerStartupLoadingOverlay(launch: launch, onClose: { playerWindow?.close() })
                    .transition(.opacity)
            }

            if let start = introStart, let end = introEnd, start > 0, !hasAutoSkippedIntro, !skipPillDismissed {
                SkipIntroPill(onSkip: skipIntro, onDismiss: { skipPillDismissed = true })
                    .padding(.trailing, 28)
                    .padding(.bottom, 176)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(5)
            }

            VStack {
                topBar
                Spacer()
                NativeLikePlayerControls(
                    title: launch.title,
                    engine: engine,
                    isSeeking: $isSeeking,
                    pendingSeekTime: $pendingSeekTime,
                    subtitleChoices: subtitleChoices,
                    selectedExternalSubtitle: $selectedExternalSubtitle,
                    isLoadingSubtitles: isLoadingSubtitles,
                    subtitleError: subtitleError,
                    introStart: introStart,
                    onSkipIntro: skipIntro,
                    onInteraction: showControls,
                    onSelectExternalSubtitle: { subtitle in
                        Task { await selectExternalSubtitle(subtitle) }
                    },
                    onDisableExternalSubtitles: {
                        selectedExternalSubtitle = nil
                        externalSubtitleCues = []
                        subtitleError = nil
                    },
                    hasPrevEp: adjacentEpisodes.prev != nil,
                    hasNextEp: adjacentEpisodes.next != nil,
                    onPrevEp: { if let ep = adjacentEpisodes.prev { Task { await goToEpisode(ep) } } },
                    onNextEp: { if let ep = adjacentEpisodes.next { Task { await goToEpisode(ep) } } },
                    isPipActive: isPipActive,
                    onTogglePip: togglePip,
                    onDismiss: { dismiss() }
                )
            }
            .opacity(visibility.controlsVisible ? 1 : 0)
            .allowsHitTesting(visibility.controlsVisible)
            .animation(.easeInOut(duration: 0.18), value: visibility.controlsVisible)

            if adjacentEpisodes.next != nil {
                HStack {
                    Spacer()
                    if !showUpNextPanel {
                        UpNextTab {
                            showControls()
                            Task {
                                await loadUpNextIfNeeded()
                                showUpNextPanel = true
                            }
                        }
                        .padding(.trailing, 4)
                    }
                }
                .opacity(visibility.controlsVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.18), value: visibility.controlsVisible)
            }

            if showUpNextPanel, let detail = upNextDetail {
                HStack {
                    Spacer()
                    UpNextPanel(
                        seriesTitle: detail.name,
                        seasons: detail.seasons ?? [],
                        selectedSeasonNumber: $upNextSeasonNumber,
                        currentSeasonNumber: launch.seasonNumber ?? 1,
                        currentEpisodeNumber: launch.episodeNumber ?? 1,
                        currentEpisodeTitle: launch.title,
                        onRestart: {
                            engine.seek(to: 0)
                            showUpNextPanel = false
                        },
                        onPlay: { episode in
                            showUpNextPanel = false
                            Task { await goToEpisode(episode) }
                        },
                        onClose: { showUpNextPanel = false }
                    )
                    .ignoresSafeArea()
                }
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }

            if showEpisodeInfoPanel, let episode = currentEpisodeForInfoPanel {
                EpisodeInfoPanel(
                    seriesTitle: launch.title,
                    episode: episode,
                    episodePosterURL: episodePosterURL,
                    backgroundURL: launch.background.flatMap(URL.init),
                    directors: episodeDirectors,
                    writers: episodeWriters,
                    guestStarIDs: episodeGuestStarIDs,
                    isLoadingGuestStars: isLoadingGuestStars,
                    onClose: { showEpisodeInfoPanel = false }
                )
                .transition(.opacity)
                .zIndex(2)
            }

            // #6 — top-center feedback microinteraction + resume prompt
            VStack(spacing: 10) {
                if let variant = streamCheckVariant, !streamCheckDismissed {
                    MacStreamCheckPill(
                        variant: variant,
                        onLooksGood: { dismissStreamCheck() },
                        onPickAnother: {
                            dismissStreamCheck()
                            showSourcePicker = true
                        }
                    )
                }
                if showResumePrompt {
                    resumePrompt
                }
            }
            .padding(.top, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: streamCheckVariant)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: streamCheckDismissed)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showResumePrompt)
            .zIndex(6)

            // #6 — bottom-center transient toasts (cached fallback / screenshot)
            VStack(spacing: 8) {
                if let toast = cachedFallbackToast { playerToast(toast, icon: "exclamationmark.triangle.fill", tint: .orange) }
                if let toast = screenshotToast { playerToast(toast, icon: "camera.fill", tint: MoonlitTheme.accent) }
            }
            .padding(.bottom, 150)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: cachedFallbackToast)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: screenshotToast)
            .zIndex(6)
        }
        .ignoresSafeArea(edges: .all)
        .sheet(isPresented: $showSourcePicker) {
            sourcePickerSheet
                .frame(minWidth: 560, minHeight: 520)
        }
        .animation(.easeInOut(duration: 0.25), value: showUpNextPanel)
        .animation(.easeInOut(duration: 0.2), value: showEpisodeInfoPanel)
        .background(
            PlayerWindowAccessor { window in
                guard playerWindow == nil else { return }
                playerWindow = window
                // Give the player window the same transparent, full-size-content
                // titlebar treatment the main window gets in the AppDelegate.
                // Without this, hiding just the traffic-light buttons leaves the
                // titlebar container showing through as a black notch at the top.
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = true
                window.backgroundColor = .black
                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
            }
        )
        .background(Color.black)
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .automatic)
        .onAppear {
            showControls()
            upNextSeasonNumber = launch.seasonNumber ?? 1
            engine.launch(launch)
            applyAnime4KIfNeeded()
            waitForFirstFrameThenHideOverlay()
            Task { await loadAvailableSubtitles() }
            Task { await fetchAutoPlayCandidates() }
            Task { await fetchIntroTimestamps() }
            Task { await fetchAdjacentEpisodes() }
        }
        .onChange(of: engine.didEncounterError) { _, didError in
            guard didError else { return }
            guard !engine.isLoading else { return }
            isTryingNextSource = false
            if !launch.sourceUrl.isEmpty {
                triedUrls.insert(launch.sourceUrl)
            }
            // No auto-cascade — show error UI with manual Retry / Next Source buttons.
            // mpv handles its own buffering and will report genuine failures only.
        }
        .onChange(of: engine.currentPosition) { _, pos in
            checkAutoSkipIntro(at: pos)
            checkAutoShowUpNext(at: pos)
        }
        .onChange(of: engine.hasRenderedFrame) { _, rendered in
            if rendered { handleFirstFrame() }
        }
        .onChange(of: videoPrefs.anime4KEnabled) { _, _ in
            applyAnime4KIfNeeded()
        }
        .onDisappear {
            hideTask?.cancel()
            engine.stop()
        }
        .onTapGesture {
            if visibility.controlsVisible {
                hideControlsIfAllowed()
            } else {
                showControls()
            }
        }
        .onKeyPress(.space) {
            togglePlayback()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            seekBy(-5)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            seekBy(5)
            return .handled
        }
        .onKeyPress(.upArrow) {
            adjustVolume(by: 0.05)
            return .handled
        }
        .onKeyPress(.downArrow) {
            adjustVolume(by: -0.05)
            return .handled
        }
        .onKeyPress(KeyEquivalent("f")) {
            NSApp.keyWindow?.toggleFullScreen(nil)
            return .handled
        }
        .onKeyPress(KeyEquivalent("m")) {
            engine.toggleMute()
            return .handled
        }
        .onKeyPress(KeyEquivalent("s")) {
            let rates: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]
            if let idx = rates.firstIndex(of: engine.playbackSpeed), idx + 1 < rates.count {
                engine.setPlaybackSpeed(rates[idx + 1])
            } else {
                engine.setPlaybackSpeed(rates[0])
            }
            return .handled
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(FlatPlayerButtonStyle())
            .foregroundStyle(.white)
            .accessibilityLabel("Close player")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(launch.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    if launch.contentType == .series {
                        Button {
                            openEpisodeInfoPanel()
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Episode info")
                    }
                }
                if let subtitle = episodeSubtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer()

            HStack(spacing: 18) {
                Button {
                    showControls()
                    captureScreenshot()
                } label: {
                    Image(systemName: "camera")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(FlatPlayerButtonStyle())
                .foregroundStyle(.white)
                .accessibilityLabel("Screenshot")

                Button {
                    showControls()
                    showSourcePicker = true
                } label: {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(FlatPlayerButtonStyle())
                .foregroundStyle(.white)
                .accessibilityLabel("Pick another source")

                windowChromeButton("minus") { playerWindow?.miniaturize(nil) }
                windowChromeButton("square") { playerWindow?.zoom(nil) }
                windowChromeButton("xmark") { playerWindow?.close() }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .frame(height: 88)
        .background(
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.35), location: 0),
                    .init(color: .black.opacity(0.15), location: 0.6),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        )
    }

    private func windowChromeButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(FlatPlayerButtonStyle())
        .foregroundStyle(.white.opacity(0.85))
    }

    private var episodeSubtitle: String? {
        guard let season = launch.seasonNumber, let episode = launch.episodeNumber else { return nil }
        return "S\(season) · E\(episode)"
    }

    // MARK: - #6 Player extras (resume, feedback pill, screenshot, cached toast)

    private var resumePrompt: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white.opacity(0.85))
            Text("Resuming from \(Self.timeLabel(ms: launch.initialPositionMs ?? 0))")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Button {
                engine.seek(to: 0)
                showResumePrompt = false
            } label: {
                Text("Start over")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Color.white.opacity(0.14), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 9)
        .padding(.leading, 14)
        .padding(.trailing, 9)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func playerToast(_ text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(tint)
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 14)
        .background(.black.opacity(0.85), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private static func timeLabel(ms: Double) -> String {
        let total = max(0, Int(ms / 1000))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Runs once the engine renders its first frame for a load. Offers a resume
    /// prompt (initial launch only) and schedules the "does this look right?" pill.
    private func handleFirstFrame() {
        if !didOfferResume {
            didOfferResume = true
            if (launch.initialPositionMs ?? 0) > 10_000 {
                showResumePrompt = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(8))
                    showResumePrompt = false
                }
            }
        }
        scheduleStreamCheckPill()
    }

    private func scheduleStreamCheckPill() {
        streamCheckTask?.cancel()
        streamCheckDismissed = false
        streamCheckVariant = nil
        streamCheckTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, !streamCheckDismissed else { return }
            streamCheckVariant = .check
            try? await Task.sleep(for: .seconds(9))
            guard !Task.isCancelled, !streamCheckDismissed else { return }
            dismissStreamCheck()
        }
    }

    private func dismissStreamCheck() {
        streamCheckDismissed = true
        streamCheckVariant = nil
        streamCheckTask?.cancel()
    }

    private func flashCachedFallbackToast() {
        cachedToastTask?.cancel()
        cachedFallbackToast = "Last source wasn't cached on your debrid yet. Trying another…"
        cachedToastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            cachedFallbackToast = nil
        }
    }

    private func captureScreenshot() {
        let dir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = dir.appendingPathComponent("Moonlit Screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let safeTitle = launch.title.replacingOccurrences(of: "/", with: "-")
        let fileURL = folder.appendingPathComponent("\(safeTitle) \(stamp).png")
        engine.takeScreenshot(to: fileURL)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            #if os(macOS)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            }
            #endif
            screenshotToast = "Screenshot saved"
            try? await Task.sleep(for: .seconds(2.5))
            screenshotToast = nil
        }
    }

    private var sourcePickerSheet: some View {
        MacSourcePickerView(
            mediaType: launch.contentType == .movie ? .movie : .series,
            mediaId: launch.parentMetaId ?? launch.videoId,
            mediaName: launch.title,
            poster: launch.poster,
            logo: launch.logo,
            background: launch.background,
            videoId: launch.videoId,
            seasonNumber: launch.seasonNumber,
            episodeNumber: launch.episodeNumber,
            onLaunch: { newLaunch in
                showSourcePicker = false
                switchToSource(newLaunch)
            },
            forceManual: true,
            currentSourceUrl: launch.sourceUrl
        )
    }

    /// Switches the currently-playing stream to a new source picked from the
    /// in-player source picker, keeping the same window and playback position.
    private func switchToSource(_ newLaunch: PlayerLaunch) {
        guard !newLaunch.sourceUrl.isEmpty else { return }
        let resumeAt = engine.currentPosition
        triedUrls = []
        autoPlayCandidates = []
        isTryingNextSource = false
        showStartupLoading = true
        engine.loadURL(newLaunch.sourceUrl, headers: newLaunch.sourceHeaders ?? [:])
        waitForFirstFrameThenHideOverlay {
            if resumeAt > 5 { engine.seek(to: resumeAt) }
        }
        Task { await fetchAutoPlayCandidates() }
    }

    private func showControls() {
        visibility.registerInteraction()
        scheduleAutoHideIfNeeded()
    }

    private func scheduleAutoHideIfNeeded() {
        hideTask?.cancel()
        guard visibility.shouldScheduleAutoHide else { return }

        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            hideControlsIfAllowed()
        }
    }

    private func hideControlsIfAllowed() {
        guard !isSeeking else { return }
        visibility.hideAfterInactivityIfAllowed()
    }

    private func togglePlayback() {
        showControls()
        engine.togglePlayPause()
    }

    private func seekBy(_ interval: Int) {
        showControls()
        engine.seekBy(Double(interval))
    }

    private func adjustVolume(by delta: Float) {
        showControls()
        if engine.isMuted {
            engine.toggleMute()
        }
    }

    private func applyAnime4KIfNeeded() {
        guard videoPrefs.anime4KEnabled,
              let base = Bundle.main.resourcePath else {
            engine.setShader(nil)
            return
        }
        let paths = [
            "Anime4K_Clamp_Highlights.glsl",
            "Anime4K_Restore_CNN_M.glsl",
            "Anime4K_Upscale_Denoise_CNN_x2_M.glsl",
        ].map { base + "/" + $0 }
        engine.setShader(paths.joined(separator: ":"))
    }

    private func loadAvailableSubtitles() async {
        let embedded = launch.subtitles ?? []
        let addonSubtitles: [SubtitleItem]
        do {
            addonSubtitles = try await SubtitleService.shared.fetchSubtitlesFromAddons(
                type: launch.parentMetaType ?? launch.contentType.rawValue,
                id: launch.videoId,
                addons: addonRepo.managedAddons.map(\.manifest)
            )
        } catch {
            addonSubtitles = []
        }

        var seen = Set<String>()
        subtitleChoices = (embedded + addonSubtitles).filter { subtitle in
            seen.insert(subtitle.url).inserted
        }
    }

    private func fetchAutoPlayCandidates() async {
        await StreamRepository.shared.fetchStreams(
            type: launch.parentMetaType ?? launch.contentType.rawValue,
            id: launch.videoId,
            addons: addonRepo.managedAddons.map(\.manifest),
            title: launch.title
        )
        let prefer4K = PlaybackQualityPreferenceStore.shared.prefers4K(profileId: profileManager.currentProfile?.id ?? "")
        let installOrder = addonRepo.managedAddons.map(\.displayName)
        let allSources = StreamRepository.shared.streams
        let currentUrl = launch.sourceUrl
        autoPlayCandidates = StreamSourceSelector.candidatesForAutoPlay(
            from: allSources, prefer4K: prefer4K, installOrder: installOrder
        ).filter { $0.url != currentUrl }
        if !currentUrl.isEmpty { triedUrls.insert(currentUrl) }
    }

    private func tryNextCandidate() {
        guard !isTryingNextSource else { return }
        isTryingNextSource = true
        Task { @MainActor in
            defer { isTryingNextSource = false }
            while let next = autoPlayCandidates.first {
                autoPlayCandidates.removeFirst()
                guard let url = next.url, !url.isEmpty, !triedUrls.contains(url) else { continue }
                let headers = next.behaviorHints?.proxyHeaders?.request ?? [:]
                guard await StreamPreflight.isReachable(url: url, headers: headers) else {
                    triedUrls.insert(url)
                    // The previous source resolved but wasn't actually playable
                    // (uncached debrid / stub file) — tell the viewer we're moving on.
                    flashCachedFallbackToast()
                    continue
                }
                triedUrls.insert(url)
                engine.loadURL(url, headers: headers)
                showStartupLoading = true
                waitForFirstFrameThenHideOverlay()
                return
            }
        }
    }

    /// Keeps `showStartupLoading` up (hiding any stale frame from the previous
    /// source/episode) until the engine actually renders a frame for the new
    /// load, instead of a blind fixed delay. Falls through to the existing
    /// error UI via an 8s safety timeout if the stream never renders.
    private func waitForFirstFrameThenHideOverlay(onSettled: @escaping () -> Void = {}) {
        startupLoadingTask?.cancel()
        startupLoadingTask = Task { @MainActor in
            let deadline = Date().addingTimeInterval(8)
            while !Task.isCancelled, !engine.hasRenderedFrame, !engine.didEncounterError, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            showStartupLoading = false
            onSettled()
        }
    }

    private func fetchAdjacentEpisodes() async {
        adjacentEpisodes = await EpisodeNavigator.adjacentEpisodes(
            for: launch,
            addons: addonRepo.managedAddons.map(\.manifest)
        )
    }

    private func goToEpisode(_ episode: MetaVideo) async {
        guard !isChangingEpisode else { return }
        isChangingEpisode = true
        showStartupLoading = true
        engine.pause()
        defer { isChangingEpisode = false }

        guard let newLaunch = await EpisodeNavigator.buildLaunch(
            for: episode,
            base: launch,
            addons: addonRepo.managedAddons.map(\.manifest)
        ) else {
            showStartupLoading = false
            return
        }

        engine.launch(newLaunch)
        selectedExternalSubtitle = nil
        externalSubtitleCues = []
        subtitleError = nil
        hasAutoSkippedIntro = false
        skipPillDismissed = false
        introStart = nil
        introEnd = nil
        triedUrls = []
        autoPlayCandidates = []
        isTryingNextSource = false
        didAutoPromptUpNext = false
        upNextSeasonNumber = newLaunch.seasonNumber ?? upNextSeasonNumber
        showEpisodeInfoPanel = false
        episodeGuestStars = []
        episodeGuestStarIDs = []
        episodeDirectors = []
        episodeWriters = []

        waitForFirstFrameThenHideOverlay()
        Task { await loadAvailableSubtitles() }
        Task { await fetchAutoPlayCandidates() }
        Task { await fetchIntroTimestamps() }
        Task { await fetchAdjacentEpisodes() }
    }

    /// Lazily fetches the full season/episode list the first time the Up Next
    /// panel is opened (either manually via the tab, or the auto-prompt near
    /// an episode's end) — avoids a second `fetchDetail` call up front when
    /// `EpisodeNavigator.adjacentEpisodes` already made one just to find prev/next.
    private func loadUpNextIfNeeded() async {
        guard upNextDetail == nil, let metaId = launch.parentMetaId else { return }
        upNextDetail = await MetaRepository.shared.fetchDetail(
            type: launch.parentMetaType ?? launch.contentType.rawValue,
            id: metaId,
            addons: addonRepo.managedAddons.map(\.manifest)
        )
    }

    private func checkAutoShowUpNext(at position: Double) {
        guard !didAutoPromptUpNext, !showUpNextPanel,
              adjacentEpisodes.next != nil, engine.duration > 0 else { return }
        let remaining = engine.duration - position
        let threshold = Double(VideoPlayerPreferenceStore.shared.showNextEpisodeSecondsRemaining)
        guard remaining > 0, remaining <= threshold else { return }
        didAutoPromptUpNext = true
        Task {
            await loadUpNextIfNeeded()
            showUpNextPanel = true
        }
    }

    /// Finds the current episode inside the (lazily fetched) season/episode
    /// list and merges in the guest-star cast fetched separately, so the
    /// info panel doesn't need its own copy of `MetaRepository.fetchDetail`.
    private var currentEpisodeForInfoPanel: MetaVideo? {
        guard let season = launch.seasonNumber, let episodeNumber = launch.episodeNumber,
              let seasons = upNextDetail?.seasons,
              let seasonEntry = seasons.first(where: { $0.number == season }),
              let episode = seasonEntry.episodes?.first(where: { $0.episode == episodeNumber }) else {
            return nil
        }
        return MetaVideo(
            id: episode.id,
            title: episode.title,
            released: episode.released,
            thumbnail: episode.thumbnail,
            season: episode.season,
            episode: episode.episode,
            overview: episode.overview,
            runtime: episode.runtime,
            streams: episode.streams,
            trailerStreams: episode.trailerStreams,
            voteAverage: episode.voteAverage,
            guestStars: episodeGuestStars.isEmpty ? nil : episodeGuestStars
        )
    }

    private func openEpisodeInfoPanel() {
        Task {
            await loadUpNextIfNeeded()
            showEpisodeInfoPanel = true
            guard let metaId = launch.parentMetaId,
                  let season = launch.seasonNumber, let episodeNumber = launch.episodeNumber else { return }
            if episodePosterURL == nil, let poster = await MetaRepository.shared.fetchEpisodePoster(
                seriesId: metaId, season: season, episode: episodeNumber
            ) {
                episodePosterURL = URL(string: poster)
            }
            if episodeGuestStars.isEmpty {
                isLoadingGuestStars = true
                let credits = await MetaRepository.shared.fetchEpisodeCredits(
                    seriesId: metaId, season: season, episode: episodeNumber
                )
                episodeGuestStars = credits.cast
                episodeGuestStarIDs = credits.guestStarIDs
                episodeDirectors = credits.directors
                episodeWriters = credits.writers
                isLoadingGuestStars = false
            }
        }
    }

    /// Order matters here: the main window hosts `videoView` inside a SwiftUI
    /// `NSViewRepresentable` (`MPVPlayerViewRepresentable`). Entering PiP first
    /// flips `isPipActive` so SwiftUI drops that representable from the tree
    /// *before* we reparent the raw NSView into the floating panel — otherwise
    /// SwiftUI's dismantle could yank the view back out of the panel. Exiting
    /// does the reverse: reparent back to the main window first, then flip the
    /// flag so SwiftUI's `makeNSView` simply re-adopts the (already correctly
    /// placed) existing view instance.
    private func togglePip() {
        guard let videoView = engine.displayView else { return }
        if isPipActive {
            pipController.exit()
            isPipActive = false
        } else {
            isPipActive = true
            let chrome = NSHostingView(rootView: PipChrome(
                engine: engine,
                hasPrevEp: adjacentEpisodes.prev != nil,
                hasNextEp: adjacentEpisodes.next != nil,
                onPrevEp: { if let ep = adjacentEpisodes.prev { Task { await goToEpisode(ep) } } },
                onNextEp: { if let ep = adjacentEpisodes.next { Task { await goToEpisode(ep) } } },
                onExitPip: togglePip
            ))
            DispatchQueue.main.async {
                pipController.enter(videoView: videoView, chrome: chrome)
            }
        }
    }

    private func fetchIntroTimestamps() async {
        guard let imdbId = launch.videoId.components(separatedBy: ":").first,
              let season = launch.seasonNumber,
              let episode = launch.episodeNumber else { return }

        guard let timestamp = await IntroTimestampService.shared.timestamps(imdbId: imdbId, season: season, episode: episode) else { return }
        introStart = timestamp.introStart
        introEnd = timestamp.introEnd
        skipPillDismissed = false
    }

    private func skipIntro() {
        guard let end = introEnd else { return }
        engine.seek(to: end)
        introStart = nil
        introEnd = nil
    }

    private func checkAutoSkipIntro(at position: Double) {
        guard !hasAutoSkippedIntro,
              let start = introStart,
              let end = introEnd,
              position > 0 else { return }

        if position >= start && position <= end {
            hasAutoSkippedIntro = true
            skipIntro()
        }
    }

    private func selectExternalSubtitle(_ subtitle: SubtitleItem) async {
        selectedExternalSubtitle = subtitle
        isLoadingSubtitles = true
        subtitleError = nil
        externalSubtitleCues = []

        guard let url = URL(string: subtitle.url) else {
            subtitleError = "Invalid subtitle URL"
            isLoadingSubtitles = false
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                subtitleError = "Unable to decode subtitles"
                isLoadingSubtitles = false
                return
            }
            externalSubtitleCues = SubtitleCue.parse(content)
        } catch {
            subtitleError = "Unable to load subtitles"
        }
        isLoadingSubtitles = false
    }
}

/// Resolves the hosting NSWindow once so the player can hide the native
/// traffic lights and draw Harbor-style custom minimize/maximize/close
/// buttons in `topBar` instead.
private struct PlayerWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct NativeLikePlayerControls: View {
    let title: String
    @ObservedObject var engine: MPVPlayerEngine
    @Binding var isSeeking: Bool
    @Binding var pendingSeekTime: Double
    let subtitleChoices: [SubtitleItem]
    @Binding var selectedExternalSubtitle: SubtitleItem?
    let isLoadingSubtitles: Bool
    let subtitleError: String?
    let introStart: Double?
    let onSkipIntro: () -> Void
    let onInteraction: () -> Void
    let onSelectExternalSubtitle: (SubtitleItem) -> Void
    let onDisableExternalSubtitles: () -> Void
    let hasPrevEp: Bool
    let hasNextEp: Bool
    let onPrevEp: () -> Void
    let onNextEp: () -> Void
    let isPipActive: Bool
    let onTogglePip: () -> Void
    let onDismiss: () -> Void

    @State private var showSubtitlePanel = false
    @State private var showAudioPanel = false

    private var currentTime: Double {
        isSeeking ? pendingSeekTime : engine.currentPosition
    }

    private var totalTime: Double {
        max(engine.duration, 1)
    }

    var body: some View {
        VStack(spacing: 4) {

            HStack(spacing: 10) {
                Text(formatTime(currentTime))
                    .foregroundStyle(.white.opacity(0.9))

                PlayerScrubber(
                    value: Binding(get: { currentTime }, set: { pendingSeekTime = $0 }),
                    range: 0 ... totalTime,
                    isEditing: $isSeeking,
                    onInteraction: onInteraction,
                    onCommit: { engine.seek(to: pendingSeekTime) }
                )

                Text(formatTime(totalTime))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .font(.system(size: 14, weight: .medium, design: .monospaced))

            ZStack {
                // Leading/trailing groups anchor to the edges independently of
                // the transport cluster's width, so the cluster below can be
                // centered in the full row regardless of how wide these are.
                HStack(spacing: 2) {
                    HStack(spacing: 8) {
                        PlayerControlButton(
                            systemName: engine.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                            size: 17,
                            frameSize: 52,
                            tooltip: engine.isMuted ? "Unmute" : "Mute"
                        ) {
                            onInteraction()
                            engine.toggleMute()
                        }

                        PlayerVolumeSlider(
                            volume: Binding(
                                get: { engine.volume },
                                set: { newValue in
                                    onInteraction()
                                    if engine.isMuted, newValue > 0 { engine.toggleMute() }
                                    engine.setVolume(newValue)
                                }
                            ),
                            isMuted: engine.isMuted
                        )
                    }

                    Spacer()

                    HStack(spacing: 2) {
                        PlayerControlButton(
                            systemName: "captions.bubble\(engine.selectedSubtitle != nil || selectedExternalSubtitle != nil ? ".fill" : "")",
                            size: 17,
                            frameSize: 52,
                            tooltip: "Subtitles"
                        ) {
                            onInteraction()
                            showSubtitlePanel.toggle()
                        }
                        .popover(isPresented: $showSubtitlePanel, arrowEdge: .bottom) {
                            SubtitleTrackPanel(
                                engine: engine,
                                externalSubtitles: subtitleChoices,
                                selectedExternalSubtitle: $selectedExternalSubtitle,
                                isLoadingExternal: isLoadingSubtitles,
                                error: subtitleError,
                                onSelectExternalSubtitle: onSelectExternalSubtitle,
                                onDisableExternalSubtitles: onDisableExternalSubtitles,
                                onClose: { showSubtitlePanel = false }
                            )
                        }

                        PlayerControlButton(systemName: "waveform", size: 17, frameSize: 52, tooltip: "Audio Tracks") {
                            onInteraction()
                            showAudioPanel.toggle()
                        }
                        .popover(isPresented: $showAudioPanel, arrowEdge: .bottom) {
                            AudioTrackPanel(engine: engine, onClose: { showAudioPanel = false })
                        }

                        SpeedMenu(engine: engine, onInteraction: onInteraction)

                        AirPlayButton()
                            .frame(width: 26, height: 26)
                            .padding(.horizontal, 13)
                            .help("AirPlay")

                        PlayerControlButton(
                            systemName: isPipActive ? "pip.exit" : "pip.enter",
                            size: 17,
                            frameSize: 52,
                            tooltip: "Picture in Picture"
                        ) {
                            onInteraction()
                            onTogglePip()
                        }

                        PlayerControlButton(
                            systemName: "arrow.up.backward.and.arrow.down.forward",
                            size: 17,
                            frameSize: 52,
                            tooltip: "Fullscreen"
                        ) {
                            onInteraction()
                            NSApp.keyWindow?.toggleFullScreen(nil)
                    }
                }
            }

            HStack(spacing: 6) {
                    if hasPrevEp || hasNextEp {
                        Button {
                            onInteraction()
                            onPrevEp()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left.2")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Previous Episode")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 40)
                        }
                        .buttonStyle(FlatPlayerButtonStyle())
                        .foregroundStyle(.white.opacity(hasPrevEp ? 0.85 : 0.3))
                        .disabled(!hasPrevEp)
                    }

                    PlayerControlButton(systemName: "gobackward.10", size: 19, frameSize: 48, tooltip: "Back 10s") {
                        onInteraction()
                        engine.seekBy(-10)
                    }

                    PlayerControlButton(
                        systemName: engine.isPlaying ? "pause.fill" : "play.fill",
                        size: 21,
                        frameSize: 52,
                        tooltip: engine.isPlaying ? "Pause" : "Play"
                    ) {
                        onInteraction()
                        engine.togglePlayPause()
                    }

                    PlayerControlButton(systemName: "goforward.10", size: 19, frameSize: 48, tooltip: "Forward 10s") {
                        onInteraction()
                        engine.seekBy(10)
                    }

                    if hasPrevEp || hasNextEp {
                        Button {
                            onInteraction()
                            onNextEp()
                        } label: {
                            HStack(spacing: 6) {
                                Text("Next Episode")
                                    .font(.system(size: 13, weight: .medium))
                                Image(systemName: "chevron.right.2")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 40)
                        }
                        .buttonStyle(FlatPlayerButtonStyle())
                        .foregroundStyle(.white.opacity(hasNextEp ? 0.85 : 0.3))
                        .disabled(!hasNextEp)
                    }
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 48)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        )
        .onHover { hovering in
            if hovering { onInteraction() }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let clamped = max(Int(seconds), 0)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

private struct PlayerScrubber: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    @Binding var isEditing: Bool
    let onInteraction: () -> Void
    let onCommit: () -> Void

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.2))
                    .frame(height: 6)

                if range.upperBound > 0 {
                    Capsule()
                        .fill(.white)
                        .frame(width: max(0, min(width, width * CGFloat(value / range.upperBound))), height: 6)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        isEditing = true
                        onInteraction()
                        let ratio = g.location.x / max(width, 1)
                        value = max(range.lowerBound, min(range.upperBound, Double(ratio) * range.upperBound))
                    }
                    .onEnded { _ in
                        isEditing = false
                        onCommit()
                    }
            )
        }
        .frame(height: 18)
        .contentShape(Rectangle())
    }
}

private struct PlayerControlButton: View {
    let systemName: String
    let size: CGFloat
    var frameSize: CGFloat = 46
    var tooltip: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .frame(width: frameSize, height: frameSize)
        }
        .buttonStyle(FlatPlayerButtonStyle())
        .foregroundStyle(.white.opacity(0.85))
        .help(tooltip ?? "")
    }
}

/// Harbor-style transport button: transparent at rest, a soft white wash on
/// hover/press — no persistent glass background like the rest of the app.
private struct FlatPlayerButtonStyle: ButtonStyle {
    var baseOpacity: Double = 0.10

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Circle())
            .background(
                Circle().fill(Color.white.opacity(configuration.isPressed ? baseOpacity * 2 : 0))
            )
    }
}

private struct SpeedMenu: View {
    @ObservedObject var engine: MPVPlayerEngine
    let onInteraction: () -> Void
    private let rates: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        Menu {
            ForEach(rates, id: \.self) { rate in
                Button {
                    onInteraction()
                    engine.setPlaybackSpeed(rate)
                } label: {
                    Label(String(format: "%.2g×", rate), systemImage: abs(engine.playbackSpeed - rate) < 0.01 ? "checkmark" : "")
                }
            }
        } label: {
            Text(String(format: "%.1f×", engine.playbackSpeed))
                .font(.system(size: 13, weight: .bold))
                .frame(width: 50, height: 38)
                .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .menuStyle(.borderlessButton)
        .foregroundStyle(.white.opacity(0.85))
    }
}

private struct ExternalSubtitleOverlay: View {
    let cues: [SubtitleCue]
    let time: TimeInterval
    let isLoading: Bool
    let title: String

    private var activeText: String? {
        cues.first { time >= $0.start && time <= $0.end }?.text
    }

    var body: some View {
        VStack {
            Spacer()
            if isLoading {
                Text("Loading \(title)...")
                    .subtitleBubble(fontSize: 18)
            } else if let activeText {
                Text(activeText)
                    .subtitleBubble(fontSize: 28)
            }
        }
    }
}

private struct PlayerStartupLoadingOverlay: View {
    let launch: PlayerLaunch
    let onClose: () -> Void
    @State private var pulse = false
    @State private var visible = false

    // Prefer the series' landscape backdrop so a 16:9 image fills the 16:9
    // window with no visible crop/zoom. Poster (portrait) and episode still are
    // last-resort fallbacks only.
    private var backdropURL: URL? {
        [launch.background, launch.poster, launch.episodeThumbnail].compactMap { $0 }.compactMap(URL.init(string:)).first
    }

    var body: some View {
        ZStack {
            Color.black

            if let backdropURL {
                CachedAsyncImage(url: backdropURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
                .ignoresSafeArea()
            }

            // Sharp backdrop (no blur); just a soft centered vignette so the
            // logo + caption stay legible against bright artwork.
            RadialGradient(
                colors: [.black.opacity(0.55), .black.opacity(0.12), .clear],
                center: .center,
                startRadius: 40,
                endRadius: 520
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }
                Spacer()
            }

            VStack(spacing: 18) {
                Spacer()

                if let logoURL = launch.logo.flatMap(URL.init) {
                    CachedAsyncImage(url: logoURL) { image in
                        image.resizable().scaledToFit()
                            .frame(width: 300, height: 180)
                            .shadow(color: .black.opacity(0.6), radius: 12, x: 0, y: 4)
                    } placeholder: {
                        titleText
                    }
                    .id(launch.logo)
                    .opacity(visible ? 1 : 0)
                    .scaleEffect(pulse ? 1.06 : 0.98)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulse)
                } else {
                    titleText
                        .opacity(visible ? 1 : 0)
                        .scaleEffect(pulse ? 1.06 : 0.98)
                        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulse)
                }

                Text("Setting the scene")
                    .font(.system(size: 12.5, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.6))

                Spacer()
            }
            .padding(.horizontal, 32)
        }
        .onAppear {
            pulse = true
            withAnimation(.easeIn(duration: 0.7)) { visible = true }
        }
    }

    private var titleText: some View {
        Text(launch.title)
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 2)
    }
}

private extension Text {
    func subtitleBubble(fontSize: CGFloat) -> some View {
        self
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .shadow(color: .black.opacity(0.95), radius: 4, x: 0, y: 2)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl, style: .continuous))
    }
}

private extension SubtitleItem {
    var displayTitle: String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return lang.isEmpty ? id : lang.uppercased()
    }
}

#if os(macOS)
private struct PlayerMouseTrackingView: NSViewRepresentable {
    let onMouseMoved: () -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onMouseMoved = onMouseMoved
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onMouseMoved = onMouseMoved
    }

    final class TrackingView: NSView {
        var onMouseMoved: (() -> Void)?
        private var trackingAreaRef: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingAreaRef {
                removeTrackingArea(trackingAreaRef)
            }

            let area = NSTrackingArea(
                rect: bounds,
                options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            trackingAreaRef = area
            addTrackingArea(area)
        }

        override func mouseMoved(with event: NSEvent) {
            onMouseMoved?()
            super.mouseMoved(with: event)
        }

        override func mouseEntered(with event: NSEvent) {
            onMouseMoved?()
            super.mouseEntered(with: event)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }
    }
}
#else
private struct PlayerMouseTrackingView: View {
    let onMouseMoved: () -> Void

    var body: some View {
        Color.clear.onHover { hovering in
            if hovering { onMouseMoved() }
        }
    }
}
#endif

/// Harbor's skip-intro pill: `rounded-full`, `bg-black/75`, 14px semibold
/// white text, border `white/20`, shadow `0 18px 50px -15px black/0.85`,
/// backdrop blur. Appears at the trailing edge and slides in with a 200ms
/// ease-out.
private struct SkipIntroPill: View {
    let onSkip: () -> Void
    let onDismiss: () -> Void
    @State private var appeared = false
    @State private var dismissed = false

    var body: some View {
        if !dismissed {
            HStack(spacing: 10) {
                Button(action: {
                    onSkip()
                    dismissed = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 14))
                        Text("Skip Intro")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.75))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .shadow(color: .black.opacity(0.85), radius: 25, y: 15)

                Button(action: {
                    onDismiss()
                    dismissed = true
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.75))
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .shadow(color: .black.opacity(0.85), radius: 25, y: 15)
            }
            .scaleEffect(appeared ? 1 : 0.96)
            .offset(y: appeared ? 0 : 8)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: appeared)
            .onAppear { withAnimation(.easeOut(duration: 0.2)) { appeared = true } }
        }
    }
}
