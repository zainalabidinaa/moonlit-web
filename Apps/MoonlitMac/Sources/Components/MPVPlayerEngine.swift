#if canImport(Libmpv)
import SwiftUI
import AppKit
import Combine
import MoonlitCore
import Libmpv

public struct AudioTrackInfo: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let label: String
    public let lang: String
    public let codec: String
    public let channels: String
    public let isDefault: Bool
}

@MainActor
public class MPVPlayerEngine: ObservableObject {
    @Published private var playerView: NSView?
    private var progressTimer: Timer?
    private var positionTimer: DispatchSourceTimer?

    private var currentLaunch: PlayerLaunch?
    private var lastPlaybackSpeed: Float = 1.0
    private var pendingInitialSeekSeconds: Double?
    private var didApplyInitialSeek = false
    public private(set) var launchToken = 0
    private var didScheduleFirstFrameReveal = false
    private var launchStartedAt = CACurrentMediaTime()
    private var didReachReadyToPlay = false
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var wasUserPaused = false

    @Published public var isPlaying = false
    @Published public var isLoading = true
    @Published public var isEnded = false
    @Published public var hasRenderedFrame = false
    @Published public var currentPosition: Double = 0
    @Published public var duration: Double = 0
    @Published public var bufferedPosition: Double = 0
    @Published public var playbackSpeed: Float = 1.0
    @Published public var availableSubtitles: [SubtitleItem] = []
    @Published public var selectedSubtitle: SubtitleItem?
    @Published public var availableAudioTracks: [AudioTrackInfo] = []
    @Published public var selectedAudioTrackId: Int64?
    @Published public var isMuted = false
    @Published public var volume: Float = 1.0
    @Published public var subDelaySec: Double = 0
    @Published public var audioDelaySec: Double = 0
    @Published public var loadedCues: [SubtitleCue] = []
    @Published public var isFillingVideo = false
    @Published public var didEncounterError = false
    /// Display aspect ratio of the current video (width / height), accounting for
    /// anamorphic pixel aspect and rotation. `nil` until the first video params
    /// arrive. Used to size the player window to the video's dimensions.
    @Published public var videoAspectRatio: CGFloat?

    public let positionPublisher = PassthroughSubject<Double, Never>()
    public let bufferedPositionPublisher = PassthroughSubject<Double, Never>()

    private var mpv: OpaquePointer?
    private var mpvGL: OpaquePointer?
    private weak var glView: MPVGLView?
    private var eventQueue = DispatchQueue(label: "mpv", qos: .userInitiated)

    private var subtitleTrackIds: [String: Int64] = [:]
    private var embeddedSubtitles: [SubtitleItem] = []
    private var externalSubtitles: [SubtitleItem] = []

    /// Monotonic timestamp of the last user seek. For a short window after a seek
    /// the position poller won't overwrite the optimistic `currentPosition`, so the
    /// scrubber shows the new spot instantly instead of snapping back to mpv's
    /// pre-seek position while the exact seek is still settling.
    private var lastSeekMonotonic: CFTimeInterval = 0
    private let seekSettleWindow: CFTimeInterval = 0.5

    public init() {}

    deinit {
        if let renderCtx = mpvGL {
            mpvGL = nil
            mpv_render_context_free(renderCtx)
        }
        guard let ctx = mpv else { return }
        mpv = nil
        mpv_terminate_destroy(ctx)
    }

    public var displayView: NSView? { playerView }

    public func launch(_ launch: PlayerLaunch) {
        cleanup()
        guard let url = URL(string: launch.sourceUrl) else { isLoading = false; return }
        currentLaunch = launch
        let fmt = formatLabel(for: launch)
        pendingInitialSeekSeconds = (fmt == "mkv" || fmt == "webm" || fmt == "avi")
            ? nil
            : launch.initialPositionMs.map { $0 / 1000 }.flatMap { $0 > 0 ? $0 : nil }
        didApplyInitialSeek = false
        isLoading = true; isPlaying = false; isEnded = false
        wasUserPaused = false
        launchStartedAt = CACurrentMediaTime()
        didReachReadyToPlay = false

        if !isLikelyHLS(launch) {
            Task.detached {
                let headers = launch.sourceHeaders ?? [:]
                let _ = await StreamPreflight.isReachable(url: url.absoluteString, headers: headers)
            }
        }

        setupPlayer(with: url)
        setupLifecycle()
        loadSubtitles(from: launch.subtitles ?? [])
        startProgressTimer()
        print("[Moonlit][MPV] launch.done host=\(url.host ?? "nil") format=\(fmt)")
        NSLog("[Moonlit][MPV] url=%@", url.absoluteString)
        NSLog("[Moonlit][MPV] headerKeys=%@", (launch.sourceHeaders ?? [:]).keys.sorted().joined(separator: ","))
        // Open timeout removed — mpv handles its own buffering and will report
        // actual errors via the event loop (MPV_EVENT_END_FILE).
    }

    public func loadURL(_ urlString: String, headers: [String: String] = [:]) {
        guard let mpv else { return }
        didEncounterError = false
        isLoading = true
        isPlaying = false
        isEnded = false
        hasRenderedFrame = false
        didReachReadyToPlay = false
        didScheduleFirstFrameReveal = false
        wasUserPaused = false
        videoAspectRatio = nil
        launchToken += 1
        setFlag("pause", true)
        applyRequestHeaders(headers)
        let rawUrl = urlString
        command("loadfile", args: [rawUrl, "replace"])
        // Open timeout removed — mpv handles its own buffering.
        print("[Moonlit][MPV] reload.done url=\(rawUrl)")
    }

    private func applyRequestHeaders(_ headers: [String: String]) {
        guard let mpv else { return }
        if headers.isEmpty {
            checkError(mpv_set_property_string(mpv, "http-header-fields", ""))
            return
        }
        let serialized = headers
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { key, value in
                let escaped = value
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: ",", with: "\\,")
                return "\(key): \(escaped)"
            }
            .joined(separator: ",")
        checkError("http-header-fields", mpv_set_property_string(mpv, "http-header-fields", serialized))
    }

    public func play() {
        setStringProperty("vid", "auto")
        setFlag("pause", false)
        isPlaying = true; isEnded = false; wasUserPaused = false
        print("[Moonlit][MPV] play")
    }

    public func pause() {
        setFlag("pause", true)
        isPlaying = false; wasUserPaused = true
        print("[Moonlit][MPV] pause")
    }

    private func pauseForLifecycle() {
        setFlag("pause", true)
        isPlaying = false
        print("[Moonlit][MPV] lifecycle.pause")
    }

    public func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    public func seek(to seconds: Double) {
        lastSeekMonotonic = CACurrentMediaTime()
        command("seek", args: [String(seconds), "absolute"])
        currentPosition = seconds
    }

    public func seekBy(_ seconds: Double) {
        seek(to: min(max(currentPosition + seconds, 0), duration))
    }

    public func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed; lastPlaybackSpeed = speed
        var s = Double(speed)
        mpv_set_property(mpv, "speed", MPV_FORMAT_DOUBLE, &s)
    }

    /// Writes a screenshot of the current frame (video + rendered subtitles, no
    /// player OSD) to `fileURL` via libmpv's `screenshot-to-file`.
    public func takeScreenshot(to fileURL: URL) {
        command("screenshot-to-file", args: [fileURL.path, "subtitles"])
    }

    public func skipForward() { seekBy(30) }
    public func skipBack() { seekBy(-15) }
    public func skipForward15() { seekBy(15) }
    public func skipBack15() { seekBy(-15) }

    public func toggleMute() {
        isMuted.toggle()
        setFlag("mute", isMuted)
    }

    public func setVolume(_ v: Float) {
        volume = max(0, min(1, v))
        var data = Double(volume) * 100
        mpv_set_property(mpv, "volume", MPV_FORMAT_DOUBLE, &data)
    }

    public func setSubtitleDelay(_ sec: Double) {
        subDelaySec = sec
        var data = sec
        mpv_set_property(mpv, "sub-delay", MPV_FORMAT_DOUBLE, &data)
    }

    public func setAudioDelay(_ sec: Double) {
        audioDelaySec = sec
        var data = sec
        mpv_set_property(mpv, "audio-delay", MPV_FORMAT_DOUBLE, &data)
    }

    public func setVideoFill(_ fill: Bool) {
        isFillingVideo = fill
        // "Fill" = zoom the video to cover the whole window, cropping the
        // overflow while keeping the aspect ratio (panscan=1). "Fit" = classic
        // letterbox (panscan=0). We keep keepaspect on for both so the image is
        // never stretched — matching the fit/fill toggle in players like Fusion.
        var value = fill ? 1.0 : 0.0
        mpv_set_property(mpv, "panscan", MPV_FORMAT_DOUBLE, &value)
    }

    public func toggleVideoFill() {
        setVideoFill(!isFillingVideo)
    }

    public func selectAudioTrack(id: Int64) {
        var aid = id
        mpv_set_property(mpv, "aid", MPV_FORMAT_INT64, &aid)
        selectedAudioTrackId = id
    }

    public func loadSubtitles(from subtitles: [SubtitleItem]) {
        externalSubtitles = subtitles
        rebuildSubtitleList()
    }

    public func cycleSubtitle() {
        guard !availableSubtitles.isEmpty else { return }
        if let current = selectedSubtitle,
           let idx = availableSubtitles.firstIndex(where: { $0.id == current.id }) {
            selectedSubtitle = availableSubtitles[(idx + 1) % availableSubtitles.count]
        } else { selectedSubtitle = availableSubtitles.first }
    }

    public func setSubtitle(_ subtitle: SubtitleItem?) {
        selectedSubtitle = subtitle
        loadedCues = []

        guard let subtitle else {
            setStringProperty("sid", "no")
            return
        }

        if let sid = subtitleTrackIds[subtitle.id] {
            var id = sid
            mpv_set_property(mpv, "sid", MPV_FORMAT_INT64, &id)
            return
        }

        setStringProperty("sid", "no")
        guard let url = URL(string: subtitle.url) else { return }
        let token = launchToken
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            let cues: [SubtitleCue] = await Task.detached(priority: .utility) {
                guard let content = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else { return [] }
                return SubtitleCue.parse(content)
            }.value
            await MainActor.run {
                guard self.launchToken == token else { return }
                self.loadedCues = cues
            }
        }
    }

    public func stop() {
        let launch = currentLaunch
        let position = currentPosition
        let total = duration
        Task { @MainActor in
            await persistProgress(launch: launch, positionSeconds: position, durationSeconds: total, completed: false)
        }
        cleanup()
    }

    public func refreshAudioTracks() {
        refreshTracks()
    }

    public func setShader(_ path: String?) {
        guard let mpv else { return }
        if let path {
            checkError(mpv_set_option_string(mpv, "glsl-shaders", path))
        } else {
            checkError(mpv_set_option_string(mpv, "glsl-shaders", ""))
        }
    }

    // MARK: - mpv Setup

    /// Creates the libmpv OpenGL render context bound to `glView`'s CGL context,
    /// then wires the render-update callback so mpv can ask the view to redraw
    /// (new frame decoded, or a repaint needed after resize). Must run after
    /// `mpv_initialize` and on the main thread (the GL context lives here).
    private func setupRenderContext(for glView: MPVGLView) {
        guard let mpv, let cglContext = glView.openGLContext?.cglContextObj else { return }
        CGLLockContext(cglContext)
        CGLSetCurrentContext(cglContext)
        defer { CGLUnlockContext(cglContext) }

        let apiType = UnsafeMutableRawPointer(mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String)
        var initParams = mpv_opengl_init_params(
            get_proc_address: { ctx, name in MPVGLView.getProcAddress(ctx, name) },
            get_proc_address_ctx: nil
        )

        withUnsafeMutablePointer(to: &initParams) { initParamsPtr in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiType),
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: initParamsPtr),
                mpv_render_param()
            ]
            var renderCtx: OpaquePointer?
            let result = mpv_render_context_create(&renderCtx, mpv, &params)
            if result < 0 {
                NSLog("[Moonlit][MPV] render context create failed: %d %s", result, mpv_error_string(result))
                return
            }
            self.mpvGL = renderCtx
            glView.mpvGL = renderCtx
            mpv_render_context_set_update_callback(renderCtx, { ctx in
                let engine = Unmanaged<MPVPlayerEngine>.fromOpaque(ctx!).takeUnretainedValue()
                engine.glView?.requestRedraw()
            }, Unmanaged.passUnretained(self).toOpaque())
        }
    }

    private func setupPlayer(with url: URL) {
        mpv = mpv_create()
        guard let mpv else { return }

        // Render via the libmpv OpenGL render API (app-owned render loop), not
        // wid/MoltenVK embedding. This is what makes live window resize work: we
        // hand mpv a freshly-sized FBO on every draw, so the render target can
        // never go stale (unlike MoltenVK's swapchain on the wid path). The
        // matching render context is created against `MPVGLView`'s GL context in
        // `setupRenderContext(for:)` after `mpv_initialize`.
        checkError("vo", mpv_set_option_string(mpv, "vo", "libmpv"))

        checkError("hwdec", mpv_set_option_string(mpv, "hwdec", "videotoolbox"))
        checkError("target-colorspace-hint", mpv_set_option_string(mpv, "target-colorspace-hint", "yes"))
        checkError("tone-mapping", mpv_set_option_string(mpv, "tone-mapping", "auto"))
        checkError("hdr-compute-peak", mpv_set_option_string(mpv, "hdr-compute-peak", "yes"))
        checkError("ao", mpv_set_option_string(mpv, "ao", "avfoundation,audiounit,"))
        checkError("audio-fallback-to-null", mpv_set_option_string(mpv, "audio-fallback-to-null", "yes"))
        checkError("audio-channels", mpv_set_option_string(mpv, "audio-channels", "auto"))
        checkError("keep-open", mpv_set_option_string(mpv, "keep-open", "yes"))
        // Start paused so audio can't begin before the first video frame is
        // decoded. We flip pause off in `markVideoReady()` once mpv signals the
        // frame is ready (playback-restart / vo-configured), so audio+video
        // start together instead of audio running over a black screen.
        checkError("pause", mpv_set_option_string(mpv, "pause", "yes"))
        checkError("video-rotate", mpv_set_option_string(mpv, "video-rotate", "no"))

        // Preferred audio/subtitle languages. mpv natively auto-selects a
        // matching embedded track on load — no scanning. When set, the
        // subtitle preference takes over from the OS-language fallback.
        let prefs = VideoPlayerPreferenceStore.shared
        if let audioLang = prefs.preferredAudioLanguage,
           let language = PlaybackLanguage.named(audioLang) {
            let value = ([language.code] + language.aliases).joined(separator: ",")
            checkError("alang", mpv_set_option_string(mpv, "alang", value))
        }
        if let subLang = prefs.preferredSubtitleLanguage,
           let language = PlaybackLanguage.named(subLang) {
            let value = ([language.code] + language.aliases).joined(separator: ",")
            checkError("slang", mpv_set_option_string(mpv, "slang", value))
            checkError("subs-match-os", mpv_set_option_string(mpv, "subs-match-os-language", "no"))
        } else {
            checkError("subs-match-os", mpv_set_option_string(mpv, "subs-match-os-language", "yes"))
        }
        checkError("subs-fallback", mpv_set_option_string(mpv, "subs-fallback", "yes"))
        checkError("log", mpv_request_log_messages(mpv, "warn"))

        checkError("network-timeout", mpv_set_option_string(mpv, "network-timeout", "15"))

        checkError("cache", mpv_set_option_string(mpv, "cache", "yes"))
        checkError("cache-initial", mpv_set_option_string(mpv, "cache-initial", "no"))
        checkError("cache-secs", mpv_set_option_string(mpv, "cache-secs", "5"))
        checkError("cache-pause", mpv_set_option_string(mpv, "cache-pause", "yes"))

        // Seeking feel: keep a generous back-buffer of already-demuxed data so a
        // short backward jump (the −10s skip) replays instantly without re-hitting
        // the network. Seeks stay frame-precise (hr-seek=yes) but drop frames while
        // seeking so reaching the exact target is as fast as possible.
        checkError("demuxer-max-back-bytes", mpv_set_option_string(mpv, "demuxer-max-back-bytes", "50MiB"))
        checkError("hr-seek", mpv_set_option_string(mpv, "hr-seek", "yes"))
        checkError("hr-seek-framedrop", mpv_set_option_string(mpv, "hr-seek-framedrop", "yes"))

        checkError("cache", mpv_set_option_string(mpv, "cache", "yes"))
        checkError("force-seekable", mpv_set_option_string(mpv, "force-seekable", "yes"))
        checkError("demuxer-lavf-o", mpv_set_option_string(mpv, "demuxer-lavf-o",
            "probesize=32768,analyzeduration=1000000,timeout=15000000,protocol_whitelist=file,http,https,tcp,tls,crypto,httpproxy"))

        let sourceHeaders = currentLaunch?.sourceHeaders ?? [:]
        let sanitized = sourceHeaders.filter { key, value in
            !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && key.caseInsensitiveCompare("Range") != .orderedSame
        }
        if !sanitized.isEmpty {
            let serialized = sanitized
                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                .map { key, value in
                    let escaped = value
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: ",", with: "\\,")
                    return "\(key): \(escaped)"
                }
                .joined(separator: ",")
            checkError("http-header-fields", mpv_set_option_string(mpv, "http-header-fields", serialized))
        }

        let glView = MPVGLView(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080))
        glView.autoresizingMask = [.width, .height]
        self.glView = glView
        self.playerView = glView

        let initResult = mpv_initialize(mpv)
        checkError(initResult)
        NSLog("[Moonlit][MPV] initialize result=%d (0=ok, <0=failed)", initResult)

        setupRenderContext(for: glView)

        mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "eof-reached", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "track-list/count", MPV_FORMAT_INT64)
        mpv_observe_property(mpv, 0, "vo-configured", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "video-params/aspect", MPV_FORMAT_DOUBLE)

        mpv_set_wakeup_callback(mpv, { ctx in
            let client = Unmanaged<MPVPlayerEngine>.fromOpaque(ctx!).takeUnretainedValue()
            client.readEvents()
        }, Unmanaged.passUnretained(self).toOpaque())

        let rawUrl = url.absoluteString
        var cargs = (
            strdup("loadfile"),
            strdup(rawUrl),
            strdup("replace"),
            nil
        ) as (UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<CChar>?)
        var argv: [UnsafePointer<CChar>?] = [
            UnsafePointer(cargs.0),
            UnsafePointer(cargs.1),
            UnsafePointer(cargs.2),
            nil
        ]
        let asyncResult = mpv_command_async(mpv, 0, &argv)
        if asyncResult < 0 {
            let msg = String(cString: mpv_error_string(asyncResult))
            print("[Moonlit][MPV] loadfile async failed: \(asyncResult) \(msg)")
        }
        defer {
            free(cargs.0)
            free(cargs.1)
            free(cargs.2)
        }

        startPositionTimer()
    }

    private func startPositionTimer() {
        positionTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: eventQueue)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in
            guard let self, let mpv = self.mpv else { return }
            let pos = self.getDouble("time-pos")
            let dur = self.getDouble("duration")
            let finPos = pos.isFinite ? pos : nil
            let finDur = dur.isFinite ? dur : nil
            guard let currentPos = finPos, let currentDur = finDur else { return }
            DispatchQueue.main.async {
                // Don't fight the optimistic seek: within the settle window keep the
                // position the user seeked to instead of mpv's still-catching-up value.
                let settling = CACurrentMediaTime() - self.lastSeekMonotonic < self.seekSettleWindow
                if !settling, abs(currentPos - self.currentPosition) > 0.1 {
                    self.currentPosition = currentPos
                    self.positionPublisher.send(currentPos)
                }
                if currentDur > 0, currentDur != self.duration {
                    self.duration = currentDur
                }
                // Stall detector removed — mpv handles its own buffering.
                // mpv will report actual errors via the event loop (MPV_EVENT_END_FILE).
            }
        }
        timer.resume()
        positionTimer = timer
    }

    // MARK: - mpv Event Loop

    private func readEvents() {
        eventQueue.async { [weak self] in
            guard let self, let mpv = self.mpv else { return }
            while self.mpv != nil {
                let event = mpv_wait_event(mpv, 0)
                if let event, event.pointee.event_id == MPV_EVENT_NONE { break }
                if let event { self.handleEvent(event) }
            }
        }
    }

    private func handleEvent(_ event: UnsafePointer<mpv_event>) {
        let eventID = event.pointee.event_id
        switch eventID {
        case MPV_EVENT_PROPERTY_CHANGE:
            let data = OpaquePointer(event.pointee.data)
            if let prop = UnsafePointer<mpv_event_property>(data)?.pointee {
                let name = String(cString: prop.name)
                switch name {
                case "pause", "paused-for-cache", "eof-reached":
                    let flag = (prop.data?.load(as: Int32.self) ?? 0) != 0
                    DispatchQueue.main.async { [weak self] in self?.applyFlag(name, flag) }
                case "vo-configured":
                    let flag = (prop.data?.load(as: Int32.self) ?? 0) != 0
                    if flag { DispatchQueue.main.async { [weak self] in self?.markVideoReady() } }
                case "track-list/count":
                    DispatchQueue.main.async { [weak self] in self?.refreshTracks() }
                case "video-params/aspect":
                    let aspect = prop.data?.load(as: Double.self) ?? 0
                    if aspect > 0 {
                        DispatchQueue.main.async { [weak self] in
                            self?.videoAspectRatio = CGFloat(aspect)
                        }
                    }
                default:
                    break
                }
            }
        case MPV_EVENT_FILE_LOADED:
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.didReachReadyToPlay = true
                self.isLoading = false
                self.refreshTracks()
                // Fallback only: if mpv never emits playback-restart / vo-configured
                // for this stream (some codecs/containers), reveal + unpause after a
                // short grace so we never get stuck on the loading overlay.
                if !self.hasRenderedFrame, !self.didScheduleFirstFrameReveal {
                    self.didScheduleFirstFrameReveal = true
                    let token = self.launchToken
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(2))
                        guard let self, self.launchToken == token else { return }
                        self.markVideoReady()
                    }
                }
            }
        case MPV_EVENT_PLAYBACK_RESTART:
            // Fires once the first frame is decoded and ready to display — the
            // real "video is up" signal. Reveal the video and unpause here so
            // audio and video begin together.
            DispatchQueue.main.async { [weak self] in self?.markVideoReady() }
        case MPV_EVENT_END_FILE:
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let reason = event.pointee.data?.load(as: mpv_end_file_reason.self) ?? MPV_END_FILE_REASON_EOF
                if reason == MPV_END_FILE_REASON_EOF {
                    if self.currentPosition < 2, self.duration > 0, self.duration < 5 {
                        NSLog("[Moonlit][MPV] short eof position=%.2f duration=%.2f", self.currentPosition, self.duration)
                        self.isLoading = false
                        self.isPlaying = false
                        self.didEncounterError = true
                    } else {
                        self.isEnded = true
                        self.isPlaying = false
                        self.isLoading = false
                    }
                } else if reason != MPV_END_FILE_REASON_STOP {
                    self.isLoading = false
                    self.isPlaying = false
                    self.didEncounterError = true
                }
            }
        case MPV_EVENT_SHUTDOWN:
            if let ctx = mpv {
                mpv = nil
                mpv_terminate_destroy(ctx)
            }
        case MPV_EVENT_LOG_MESSAGE:
            let msg = UnsafeMutablePointer<mpv_event_log_message>(OpaquePointer(event.pointee.data))
            if let msg {
                let prefix = String(cString: msg.pointee.prefix)
                let level = String(cString: msg.pointee.level)
                let text = String(cString: msg.pointee.text).trimmingCharacters(in: .whitespacesAndNewlines)
                NSLog("[mpv][%@][%@] %@", prefix, level, text)
            }
        default:
            break
        }
    }

    /// Called when mpv confirms the first video frame is decoded and ready.
    /// Reveals the video (hides the loading overlay via `hasRenderedFrame`) and
    /// unpauses so audio+video start together — unless the user paused during load.
    private func markVideoReady() {
        guard !hasRenderedFrame else { return }
        hasRenderedFrame = true
        if !wasUserPaused { play() }
    }

    private func applyFlag(_ name: String, _ value: Bool) {
        switch name {
        case "pause":
            isPlaying = !value
        case "paused-for-cache":
            if hasRenderedFrame { isLoading = value }
        default:
            break
        }
    }

    // MARK: - mpv Commands

    private func getDouble(_ name: String) -> Double {
        guard let mpv else { return 0 }
        var data = Double()
        mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
        return data
    }

    private func setFlag(_ name: String, _ flag: Bool) {
        guard let mpv else { return }
        var data: Int = flag ? 1 : 0
        mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data)
    }

    private func command(_ command: String, args: [String?] = []) {
        guard let mpv else { return }
        var cargs = ([command] + args + [nil]).map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
        defer { cargs.forEach { if let p = $0 { free(UnsafeMutablePointer(mutating: p)) } } }
        mpv_command(mpv, &cargs)
    }

    private func getString(_ name: String) -> String? {
        guard let mpv else { return nil }
        guard let cstr = mpv_get_property_string(mpv, name) else { return nil }
        defer { mpv_free(cstr) }
        return String(cString: cstr)
    }

    private func getInt(_ name: String) -> Int {
        guard let mpv else { return 0 }
        var data = Int64()
        mpv_get_property(mpv, name, MPV_FORMAT_INT64, &data)
        return Int(data)
    }

    private func getFlag(_ name: String) -> Bool {
        guard let mpv else { return false }
        var data = Int64()
        mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &data)
        return data != 0
    }

    private func setStringProperty(_ name: String, _ value: String) {
        guard let mpv else { return }
        mpv_set_property_string(mpv, name, value)
    }

    private func rebuildSubtitleList() {
        availableSubtitles = embeddedSubtitles + externalSubtitles
    }

    private func trackLabel(title: String, lang: String, index: Int, kind: String) -> String {
        if !title.isEmpty { return title }
        if !lang.isEmpty {
            return (Locale.current.localizedString(forLanguageCode: lang) ?? lang).capitalized
        }
        return "\(kind) \(index + 1)"
    }

    private func channelsLabel(_ count: Int) -> String {
        switch count {
        case 0: return ""
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(count)ch"
        }
    }

    public func refreshTracks() {
        eventQueue.async { [weak self] in
            guard let self, self.mpv != nil else { return }
            let count = self.getInt("track-list/count")

            var audioTracks: [AudioTrackInfo] = []
            var selectedAudioId: Int64?
            var subs: [SubtitleItem] = []
            var subIds: [String: Int64] = [:]
            var selectedEmbeddedSub: SubtitleItem?

            for i in 0..<max(count, 0) {
                let type = self.getString("track-list/\(i)/type") ?? ""
                let id = Int64(self.getInt("track-list/\(i)/id"))
                let title = (self.getString("track-list/\(i)/title") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let lang = (self.getString("track-list/\(i)/lang") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let selected = self.getFlag("track-list/\(i)/selected")

                if type == "audio" {
                    let label = self.trackLabel(title: title, lang: lang, index: audioTracks.count, kind: "Audio")
                    let codec = (self.getString("track-list/\(i)/codec") ?? "").uppercased()
                    let channelCount = self.getInt("track-list/\(i)/demux-channel-count")
                    let isDefault = self.getFlag("track-list/\(i)/default")
                    audioTracks.append(
                        AudioTrackInfo(
                            id: id,
                            label: label,
                            lang: lang,
                            codec: codec,
                            channels: self.channelsLabel(channelCount),
                            isDefault: isDefault
                        )
                    )
                    if selected { selectedAudioId = id }
                } else if type == "sub" {
                    let item = SubtitleItem(
                        id: "mpv-embedded-\(id)",
                        url: "mpv-embedded:\(id)",
                        lang: lang.isEmpty ? "und" : lang,
                        name: title.isEmpty ? self.trackLabel(title: "", lang: lang, index: subs.count, kind: "Subtitle") : title
                    )
                    subs.append(item)
                    subIds[item.id] = id
                    if selected { selectedEmbeddedSub = item }
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.availableAudioTracks = audioTracks
                if let selectedAudioId {
                    self.selectedAudioTrackId = selectedAudioId
                } else if self.selectedAudioTrackId == nil {
                    self.selectedAudioTrackId = audioTracks.first?.id
                }
                self.embeddedSubtitles = subs
                self.subtitleTrackIds = subIds
                self.rebuildSubtitleList()
                if self.selectedSubtitle == nil, let selectedEmbeddedSub {
                    self.selectedSubtitle = selectedEmbeddedSub
                }
            }
        }
    }

    private func checkError(_ status: CInt) {
        if status < 0 {
            let msg = String(cString: mpv_error_string(status))
            print("[Moonlit][MPV] error: \(status) \(msg)")
        }
    }

    private func checkError(_ opt: String, _ status: CInt) {
        if status < 0 {
            let msg = String(cString: mpv_error_string(status))
            print("[Moonlit][MPV] option [\(opt)] fail: \(status) \(msg)")
        }
    }

    // MARK: - Internal

    private func isLikelyHLS(_ launch: PlayerLaunch) -> Bool {
        let contentType = launch.sourceContentType?.lowercased() ?? ""
        if contentType.contains("mpegurl") || contentType.contains("x-mpegurl") { return true }
        guard let path = URL(string: launch.sourceUrl)?.path.lowercased() else { return false }
        return path.hasSuffix(".m3u8")
    }

    private func formatLabel(for launch: PlayerLaunch) -> String {
        let contentType = launch.sourceContentType?.lowercased() ?? ""
        if contentType.contains("mpegurl") || contentType.contains("x-mpegurl") { return "hls" }
        guard let path = URL(string: launch.sourceUrl)?.path.lowercased() else { return "unknown" }
        if path.hasSuffix(".m3u8") { return "hls" }
        if path.hasSuffix(".mp4") || path.hasSuffix(".m4v") { return "mp4" }
        if path.hasSuffix(".mkv") { return "mkv" }
        if path.hasSuffix(".avi") { return "avi" }
        if path.hasSuffix(".webm") { return "webm" }
        return "unknown"
    }

    private func startProgressTimer() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let launch = self.currentLaunch,
                      !Self.isLivePlayback(launch),
                      let profile = ProfileManager.shared.currentProfile else { return }
                await WatchProgressRepository.shared.updateProgress(
                    profileId: profile.id, mediaId: launch.videoId,
                    mediaType: launch.contentType.rawValue,
                    positionSeconds: self.currentPosition, durationSeconds: self.duration,
                    completed: false, name: launch.title, poster: launch.episodeThumbnail ?? launch.poster,
                    parentMetaId: launch.parentMetaId, season: launch.seasonNumber,
                    episode: launch.episodeNumber)
            }
        }
    }

    private func cleanup() {
        progressTimer?.invalidate(); progressTimer = nil
        positionTimer?.cancel(); positionTimer = nil
        teardownLifecycle()
        // Free the render context before terminating mpv, on the main thread where
        // the GL context lives. This unbinds mpv from the GL view so no further
        // draws touch a dead context.
        if let renderCtx = mpvGL {
            mpvGL = nil
            glView?.mpvGL = nil
            mpv_render_context_free(renderCtx)
        }
        glView = nil
        if let ctx = mpv {
            mpv = nil
            eventQueue.async {
                mpv_terminate_destroy(ctx)
            }
        }
        playerView = nil
        currentLaunch = nil
        pendingInitialSeekSeconds = nil
        didApplyInitialSeek = false
        didScheduleFirstFrameReveal = false
        didReachReadyToPlay = false
        launchToken += 1
        isPlaying = false; isLoading = true; isEnded = false; hasRenderedFrame = false
        didEncounterError = false
        wasUserPaused = false
        currentPosition = 0; duration = 0; lastPlaybackSpeed = 1.0
        bufferedPosition = 0
        availableSubtitles = []
        selectedSubtitle = nil
        availableAudioTracks = []
        selectedAudioTrackId = nil
        subDelaySec = 0
        audioDelaySec = 0
        loadedCues = []
    }

    private func setupLifecycle() {
        teardownLifecycle()
        var observers: [NSObjectProtocol] = []
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, self.mpv != nil else { return }
                self.pauseForLifecycle()
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, self.mpv != nil else { return }
                self.setStringProperty("vid", "auto")
                if !self.wasUserPaused { self.play() }
            }
        )
        lifecycleObservers = observers
    }

    private func teardownLifecycle() {
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        lifecycleObservers = []
    }

    /// Live IPTV channels have no meaningful resume position, so we don't persist
    /// watch-progress for them — otherwise they'd pollute "Continue Watching".
    private static func isLivePlayback(_ launch: PlayerLaunch) -> Bool {
        launch.contentType == .channel || launch.contentType == .tv
    }

    private func persistProgress(launch: PlayerLaunch?, positionSeconds: Double, durationSeconds: Double, completed: Bool) async {
        guard let launch, !Self.isLivePlayback(launch),
              let profile = ProfileManager.shared.currentProfile,
              positionSeconds > 0 || durationSeconds > 0 else { return }
        let repo = WatchProgressRepository.shared
        await repo.updateProgress(
            profileId: profile.id, mediaId: launch.videoId,
            mediaType: launch.contentType.rawValue,
            positionSeconds: positionSeconds, durationSeconds: durationSeconds,
            completed: completed, name: launch.title,
            poster: launch.episodeThumbnail ?? launch.poster,
            parentMetaId: launch.parentMetaId, season: launch.seasonNumber,
            episode: launch.episodeNumber)
        if completed {
            await repo.markWatched(
                profileId: profile.id, mediaId: launch.videoId,
                mediaType: launch.contentType.rawValue,
                name: launch.title, poster: launch.episodeThumbnail ?? launch.poster,
                season: launch.seasonNumber, episode: launch.episodeNumber)
        }
    }
}
#endif
