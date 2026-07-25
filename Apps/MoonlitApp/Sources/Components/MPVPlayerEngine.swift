import SwiftUI
import UIKit
import Combine
import MoonlitCore
import Libmpv

// Main-thread hang detector: a background queue checks every second whether the main
// thread is responsive. When it stalls, it logs the most recent "breadcrumb" — so we can
// see WHAT the main thread was doing when it froze (engine work vs a SwiftUI render).
enum MainHangDiagnostics {
    private static let lock = NSLock()
    private static var breadcrumb = "start"
    private static var breadcrumbAt = Date()
    private static var lastMainAlive = Date()
    private static var started = false
    private static let watchQueue = DispatchQueue(label: "moonlit.hang.watchdog")

    static func mark(_ label: String) {
        lock.lock(); breadcrumb = label; breadcrumbAt = Date(); lock.unlock()
    }

    static func start() {
        lock.lock()
        let already = started; started = true; lastMainAlive = Date()
        lock.unlock()
        guard !already else { return }
        watch()
    }

    private static func watch() {
        watchQueue.asyncAfter(deadline: .now() + 1.0) {
            lock.lock()
            let stalled = Date().timeIntervalSince(lastMainAlive)
            let crumb = breadcrumb
            let crumbAge = Date().timeIntervalSince(breadcrumbAt)
            lock.unlock()
            if stalled > 2.0 {
                NSLog("[Moonlit][HANG] main stalled %.1fs — last breadcrumb '%@' (set %.1fs ago)", stalled, crumb, crumbAge)
            }
            DispatchQueue.main.async { lock.lock(); lastMainAlive = Date(); lock.unlock() }
            watch()
        }
    }
}

@MainActor
public class MPVPlayerEngine: ObservableObject {
    @Published private var playerView: UIView?
    private var progressTimer: Timer?
    private var positionTimer: DispatchSourceTimer?

    // ... (keep other properties)
    private var currentLaunch: PlayerLaunch?
    private var lastPlaybackSpeed: Float = 1.0
    private var pendingInitialSeekSeconds: Double?
    private var didApplyInitialSeek = false
    public private(set) var launchToken = 0
    private var didScheduleFirstFrameReveal = false
    private var launchStartedAt = CACurrentMediaTime()
    private var didReachReadyToPlay = false

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
    @Published public var availableAudioTracks: [String] = []
    @Published public var selectedAudioTrack: String?
    @Published public var isMuted = false
    @Published public var loadedCues: [SubtitleCue] = []
    @Published public var isFillingVideo = false
    @Published public var didEncounterError = false

    public let positionPublisher = PassthroughSubject<Double, Never>()
    public let bufferedPositionPublisher = PassthroughSubject<Double, Never>()

    // mpv internals
    private var mpv: OpaquePointer?
    private var metalLayer: MetalLayer?
    private var displayLink: CADisplayLink?
    private var eventQueue = DispatchQueue(label: "mpv", qos: .userInitiated)

    // Track enumeration state (populated from mpv's track-list)
    private var audioTrackIds: [Int64] = []            // availableAudioTracks index → mpv aid
    private var subtitleTrackIds: [String: Int64] = [:] // SubtitleItem.id → mpv sid (embedded)
    private var embeddedSubtitles: [SubtitleItem] = []
    private var externalSubtitles: [SubtitleItem] = []

    public init() {}

    deinit {
        // Safety net: if a player screen is torn down without stop()/cleanup() running,
        // make sure this engine's mpv instance (and its audio) doesn't keep playing.
        if let mpv {
            mpv_terminate_destroy(mpv)
        }
    }

    public var displayView: UIView? { playerView }

    public func launch(_ launch: PlayerLaunch) {
        MainHangDiagnostics.start()
        MainHangDiagnostics.mark("engine.launch")
        cleanup()
        guard let url = URL(string: launch.sourceUrl) else { isLoading = false; return }
        StreamPlaybackDiagnostics.logLaunch(launch)
        currentLaunch = launch
        let fmt = formatLabel(for: launch)
        pendingInitialSeekSeconds = (fmt == "mkv" || fmt == "webm" || fmt == "avi")
            ? nil
            : launch.initialPositionMs.map { $0 / 1000 }.flatMap { $0 > 0 ? $0 : nil }
        didApplyInitialSeek = false
        isLoading = true; isPlaying = false; isEnded = false
        launchStartedAt = CACurrentMediaTime()
        didReachReadyToPlay = false

        setupPlayer(with: url)
        loadSubtitles(from: launch.subtitles ?? [])
        startProgressTimer()
        print("[Moonlit][MPV] launch.done host=\(url.host ?? "nil") format=\(fmt)")
        // Full URL + header keys so the exact source can be curl-tested outside the app.
        NSLog("[Moonlit][MPV] url=%@", url.absoluteString)
        NSLog("[Moonlit][MPV] headerKeys=%@", (currentLaunch?.sourceHeaders ?? [:]).keys.sorted().joined(separator: ","))
        scheduleOpenTimeout(for: launchToken, launch: launch, isHLS: isLikelyHLS(launch))
    }

    public func play() {
        setFlag("pause", false)
        isPlaying = true; isEnded = false
        print("[Moonlit][MPV] play")
    }

    public func pause() {
        setFlag("pause", true)
        isPlaying = false
        print("[Moonlit][MPV] pause")
    }

    public func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    public func seek(to seconds: Double) {
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

    public func skipForward() { seekBy(30) }
    public func skipBack() { seekBy(-15) }
    public func skipForward15() { seekBy(15) }
    public func skipBack15() { seekBy(-15) }

    public func toggleMute() {
        isMuted.toggle()
        setFlag("mute", isMuted)
    }

    public func setVideoFill(_ fill: Bool) {
        isFillingVideo = fill
        setFlag("keepaspect", !fill)
    }

    public func selectAudioTrack(named trackName: String) {
        guard let idx = availableAudioTracks.firstIndex(of: trackName), idx < audioTrackIds.count else { return }
        var aid = audioTrackIds[idx]
        mpv_set_property(mpv, "aid", MPV_FORMAT_INT64, &aid)
        selectedAudioTrack = trackName
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

        // "Off" — disable mpv subtitle rendering.
        guard let subtitle else {
            setStringProperty("sid", "no")
            return
        }

        // Embedded mkv track — let mpv/libass render it via sid.
        if let sid = subtitleTrackIds[subtitle.id] {
            var id = sid
            mpv_set_property(mpv, "sid", MPV_FORMAT_INT64, &id)
            return
        }

        // External subtitle URL — app renders parsed cues; keep mpv's own sub off.
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

    // MARK: - mpv Setup

    private func setupPlayer(with url: URL) {
        mpv = mpv_create()
        guard let mpv else { return }

        checkError("vo", mpv_set_option_string(mpv, "vo", "gpu-next"))
        checkError("gpu-api", mpv_set_option_string(mpv, "gpu-api", "vulkan"))
        checkError("gpu-context", mpv_set_option_string(mpv, "gpu-context", "moltenvk"))
        checkError("hwdec", mpv_set_option_string(mpv, "hwdec", "videotoolbox-copy"))
        checkError("ao", mpv_set_option_string(mpv, "ao", "audiounit"))
        checkError("subs-match-os", mpv_set_option_string(mpv, "subs-match-os-language", "yes"))
        checkError("subs-fallback", mpv_set_option_string(mpv, "subs-fallback", "yes"))
        checkError("log", mpv_request_log_messages(mpv, "v"))

        // HTTP MKV streaming from remote proxies: FFmpeg probes too much data
        // on the initial connection (default probesize=5MB), and MKV cues are at
        // the end of the file. Cache + force-seekable let mpv buffer and fake seeks
        // instead of requiring server Range support.
        checkError("cache", mpv_set_option_string(mpv, "cache", "yes"))
        checkError("force-seekable", mpv_set_option_string(mpv, "force-seekable", "yes"))
        checkError("demuxer-lavf-o", mpv_set_option_string(mpv, "demuxer-lavf-o",
            "probesize=32768,analyzeduration=1000000,protocol_whitelist=file,http,https,tcp,tls,crypto,httpproxy"))

        // HTTP headers — mpv's comma-separated "Key: Value, Key: Value" format.
        // Only set when there are actual headers; setting an empty string can
        // trigger mpv option error -7.
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

        // Embed mpv in a self-sizing Metal container. The container resizes the layer
        // and its drawableSize on every layout pass (like the reference layoutMetalLayer);
        // a fixed UIScreen.bounds frame left the video rendering tiny in the top-left.
        let container = MPVContainerView(frame: UIScreen.main.bounds)
        let layer = container.metalLayer
        self.metalLayer = layer
        self.playerView = container

        var metalLayerPtr = Unmanaged.passUnretained(layer).toOpaque()
        checkError(mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &metalLayerPtr))

        let initResult = mpv_initialize(mpv)
        checkError(initResult)
        NSLog("[Moonlit][MPV] initialize result=%d (0=ok, <0=failed → no events will fire)", initResult)

        // Observe ONLY low-frequency state. Crucially NOT time-pos: mpv fires time-pos
        // change events dozens of times/second, and each one hops to the main thread and
        // mutates @Published state → a SwiftUI re-render storm that freezes the controls
        // while mpv keeps playing. Like the reference, position/duration are POLLED (positionTimer).
        mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "eof-reached", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "track-list/count", MPV_FORMAT_INT64)

        mpv_set_wakeup_callback(mpv, { ctx in
            let client = Unmanaged<MPVPlayerEngine>.fromOpaque(ctx!).takeUnretainedValue()
            client.readEvents()
        }, Unmanaged.passUnretained(self).toOpaque())

        // Load URL — log the result so load failures are visible
        let loadResult = mpv_command_string(mpv, "loadfile \"\(url.absoluteString)\" replace")
        if loadResult < 0 {
            let msg = String(cString: mpv_error_string(loadResult))
            print("[Moonlit][MPV] loadfile failed: \(loadResult) \(msg)")
        }

        // Poll position/duration at a low rate (the reference model: ~4x/sec) instead of
        // per-frame CADisplayLink polling or observing time-pos. Cheap, and it keeps the
        // main thread free so the controls stay responsive.
        startPositionTimer()
    }

    private func startPositionTimer() {
        positionTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: eventQueue)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in
            guard let self, let mpv = self.mpv else { return }
            MainHangDiagnostics.mark("engine.positionPoll")
            let pos = self.getDouble("time-pos")
            let dur = self.getDouble("duration")
            let finPos = pos.isFinite ? pos : nil
            let finDur = dur.isFinite ? dur : nil
            guard let currentPos = finPos, let currentDur = finDur else { return }
            DispatchQueue.main.async {
                if abs(currentPos - self.currentPosition) > 0.1 {
                    self.currentPosition = currentPos
                    self.positionPublisher.send(currentPos)
                }
                if currentDur > 0, currentDur != self.duration {
                    self.duration = currentDur
                }
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
                // Read the value HERE on the event thread — prop.data is only valid until the
                // next mpv_wait_event, and we must not touch mpv from the main thread.
                switch name {
                case "pause", "paused-for-cache", "eof-reached":
                    let flag = (prop.data?.load(as: Int32.self) ?? 0) != 0
                    DispatchQueue.main.async { [weak self] in self?.applyFlag(name, flag) }
                case "track-list/count":
                    DispatchQueue.main.async { [weak self] in self?.refreshTracks() }
                default:
                    break
                }
            }
        case MPV_EVENT_FILE_LOADED:
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.didReachReadyToPlay = true
                self.isLoading = false  // immediate — don't wait for 350ms timer
                self.refreshTracks()
                if !self.hasRenderedFrame, !self.didScheduleFirstFrameReveal {
                    self.didScheduleFirstFrameReveal = true
                    let token = self.launchToken
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(350))
                        guard let self, self.launchToken == token, !self.hasRenderedFrame else { return }
                        self.hasRenderedFrame = true
                    }
                }
            }
        case MPV_EVENT_END_FILE:
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let reason = event.pointee.data?.load(as: mpv_end_file_reason.self) ?? MPV_END_FILE_REASON_EOF
                if reason == MPV_END_FILE_REASON_EOF {
                    self.isEnded = true
                    self.isPlaying = false
                    self.isLoading = false
                } else if reason != MPV_END_FILE_REASON_STOP {
                    self.isLoading = false
                    self.isPlaying = false
                    self.didEncounterError = true
                }
            }
        case MPV_EVENT_SHUTDOWN:
            mpv_terminate_destroy(mpv)
            self.mpv = nil
        case MPV_EVENT_LOG_MESSAGE:
            let msg = UnsafeMutablePointer<mpv_event_log_message>(OpaquePointer(event.pointee.data))
            if let msg {
                let prefix = String(cString: msg.pointee.prefix)
                let level = String(cString: msg.pointee.level)
                let text = String(cString: msg.pointee.text).trimmingCharacters(in: .whitespacesAndNewlines)
                // NSLog (not print) so lines survive devicectl --console stdout buffering.
                NSLog("[mpv][%@][%@] %@", prefix, level, text)
            }
        default:
            break
        }
    }

    // Applied on the main thread with a value already extracted from the event (no mpv reads).
    private func applyFlag(_ name: String, _ value: Bool) {
        switch name {
        case "pause":
            if value == isPlaying { isPlaying = !value }
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

    /// Enumerate mpv's track-list into audio labels (+ aid map) and subtitle items
    /// (embedded tracks carry an `mpv-embedded:<sid>` url so setSubtitle can route them).
    public func refreshTracks() {
        // Read the track-list OFF the main thread — these are many synchronous mpv
        // property reads that block during decode contention and freeze the controls.
        // Only the resulting arrays are published back on main.
        eventQueue.async { [weak self] in
            guard let self, self.mpv != nil else { return }
            let count = self.getInt("track-list/count")

            var audioLabels: [String] = []
            var audioIds: [Int64] = []
            var selectedAudioLabel: String?
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
                    let label = self.trackLabel(title: title, lang: lang, index: audioLabels.count, kind: "Audio")
                    audioLabels.append(label)
                    audioIds.append(id)
                    if selected { selectedAudioLabel = label }
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
                self.audioTrackIds = audioIds
                self.availableAudioTracks = audioLabels
                if let selectedAudioLabel {
                    self.selectedAudioTrack = selectedAudioLabel
                } else if self.selectedAudioTrack == nil {
                    self.selectedAudioTrack = audioLabels.first
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

    private func scheduleOpenTimeout(for token: Int, launch: PlayerLaunch, isHLS: Bool) {
        guard !isHLS else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.launchToken == token,
                  !self.didReachReadyToPlay,
                  self.currentLaunch?.sourceUrl == launch.sourceUrl else { return }
            // Did FFmpeg pull ANY media bytes? If both are ~0, the source delivered
            // nothing (DNS/TLS/HTTP/redirect failure — see [mpv] lines). If non-zero,
            // it connected but the demuxer/probe stalled.
            let cacheState = self.getDouble("cache-buffering-state")
            let demuxTime = self.getDouble("demuxer-cache-time")
            NSLog("[Moonlit][MPV] open.timeout cacheBufferingState=%.0f demuxerCacheTime=%.2f", cacheState, demuxTime)
            self.isLoading = false
            self.isPlaying = false
            self.didEncounterError = true
        }
    }

    private func startProgressTimer() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let launch = self.currentLaunch,
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
        displayLink?.invalidate(); displayLink = nil
        if let mpv {
            mpv_terminate_destroy(mpv)
            self.mpv = nil
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
        currentPosition = 0; duration = 0; lastPlaybackSpeed = 1.0
        bufferedPosition = 0
        availableSubtitles = []
        selectedSubtitle = nil
        availableAudioTracks = []
        selectedAudioTrack = nil
        loadedCues = []
    }

    private func persistProgress(launch: PlayerLaunch?, positionSeconds: Double, durationSeconds: Double, completed: Bool) async {
        guard let launch, let profile = ProfileManager.shared.currentProfile,
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
