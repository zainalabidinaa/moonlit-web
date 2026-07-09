#if canImport(Libmpv)
import SwiftUI
import AppKit
import Combine
import CryptoKit
import MoonlitCore
import Libmpv

/// Generates seek-preview thumbnails using a **second, in-process libmpv handle**
/// that runs headless (`vo=null`, no audio) alongside the real player.
///
/// This is Harbor's on-the-fly frame-extraction technique, but where Harbor spawns
/// an external `mpv` subprocess and talks to it over a JSON IPC pipe, we drive a
/// libmpv handle directly in-process — no subprocess, no pipe, no external binary.
/// `screenshot-to-file` runs synchronously on our own serial queue, so we don't
/// need request-id matching either.
///
/// Threading mirrors `MPVPlayerEngine`: the class is `@MainActor` for its
/// `@Published` state, but every libmpv call happens on the private serial
/// `thumbQueue`. The in-memory cache and bookkeeping are guarded by `lock` so the
/// SwiftUI-side `frame(at:)` read is safe against the worker's writes.
@MainActor
public final class PlayerThumbnailer: ObservableObject {

    // Bumped each time a new frame lands so a hovering `SeekPreviewCard` re-renders.
    @Published public private(set) var revision = 0

    // MARK: Tunables
    private let bucketSeconds: Double = 2.0        // one frame per 2s of video (matches Harbor)
    private let thumbWidth = 320                   // shadow scales frames to this width
    private let jpegQuality = 80
    private let seekWaitSeconds: Double = 4.0      // max wait for a keyframe seek to land
    /// How far the nearest-frame fallback may reach, in buckets (≈30s each side).
    let nearestWindowBuckets: UInt32 = 15
    /// How many neighbour buckets to prefetch on each side of the hovered one.
    let prefetchRadius: UInt32 = 1

    // MARK: libmpv (touched only on thumbQueue)
    private let thumbQueue = DispatchQueue(label: "mpv.thumbs", qos: .userInitiated)
    private var mpv: OpaquePointer?
    private var isFileLoaded = false

    // MARK: shared state (guarded by lock)
    private let lock = NSLock()
    private var memoryCache: [UInt32: MoonlitImage] = [:]
    private var requested: [UInt32] = []           // wanted, not yet produced (FIFO-ish)
    private var failed: Set<UInt32> = []           // gave up — treated as unavailable
    private var workerRunning = false
    private var focusBucket: UInt32 = 0            // most recently hovered bucket (priority)

    // MARK: configuration
    private var enabled = false                    // false for live/IPTV or when unconfigured
    private var streamKey = ""                     // stable per-source key for the disk cache
    private var restrictToBuffered = false         // gate un-downloaded regions (torrent servers)
    private var bufferedUpTo: Double = 0

    public init() {}

    deinit {
        // `mpv` is only ever mutated on thumbQueue; capture it and destroy off-main.
        if let handle = mpv {
            thumbQueue.async { mpv_terminate_destroy(handle) }
        }
    }

    // MARK: - Public API

    /// (Re)point the shadow at a stream from a full launch. Live/IPTV disables preview.
    public func configure(launch: PlayerLaunch) {
        let live = launch.contentType == .tv || launch.contentType == .channel
        configure(url: launch.sourceUrl, headers: launch.sourceHeaders ?? [:], isLive: live)
    }

    /// (Re)point the shadow at a raw source URL (used by in-player source/quality
    /// switches that keep the same media). No-ops into a disabled state for live/IPTV,
    /// where seeking is meaningless and would only stall the decoder.
    public func configure(url: String, headers rawHeaders: [String: String], isLive live: Bool) {
        guard !live, !url.isEmpty else {
            teardownHandle()
            lock.lock(); enabled = false; memoryCache.removeAll(); requested.removeAll(); failed.removeAll(); lock.unlock()
            return
        }

        let key = Self.stableKey(for: url)
        let restrict = Self.looksBufferConstrained(url)
        let headers = rawHeaders.filter { k, v in
            !k.trimmingCharacters(in: .whitespaces).isEmpty
                && !v.trimmingCharacters(in: .whitespaces).isEmpty
                && k.caseInsensitiveCompare("Range") != .orderedSame
        }

        lock.lock()
        enabled = true
        streamKey = key
        restrictToBuffered = restrict
        memoryCache.removeAll()
        requested.removeAll()
        failed.removeAll()
        lock.unlock()

        thumbQueue.async { [weak self] in
            self?.spawnHandle(url: url, headers: headers)
        }
    }

    /// Disable previews and destroy the shadow handle (call when the player closes).
    public func stop() {
        lock.lock()
        enabled = false
        memoryCache.removeAll()
        requested.removeAll()
        failed.removeAll()
        lock.unlock()
        teardownHandle()
    }

    /// Latest known buffered position from the real player, used for gating.
    public func updateBuffered(_ seconds: Double) {
        lock.lock(); bufferedUpTo = seconds; lock.unlock()
    }

    /// Returns the frame to display for `time` **right now** (exact bucket, a nearby
    /// cached frame, or nil) and schedules generation of anything missing. Cheap and
    /// synchronous so it can be called straight from a SwiftUI view body on hover.
    ///
    /// - Returns: `(image, isExact)`. `isExact == false` means `image` is a
    ///   nearest-neighbour stand-in that the card should dim slightly while the real
    ///   frame loads. `image == nil` means show the timestamp-only label.
    public func frame(at time: Double) -> (image: MoonlitImage?, isExact: Bool) {
        let bucket = self.bucket(for: time)

        lock.lock()
        guard enabled else { lock.unlock(); return (nil, false) }
        focusBucket = bucket
        let (display, isExact, toFetch) = resolve(bucket: bucket, cache: memoryCache)
        var startWorker = false
        for b in toFetch where allowed(b) && !failed.contains(b) && memoryCache[b] == nil && !requested.contains(b) {
            requested.append(b)
        }
        if !workerRunning && !requested.isEmpty {
            workerRunning = true
            startWorker = true
        }
        lock.unlock()

        if startWorker {
            thumbQueue.async { [weak self] in self?.runWorker() }
        }
        return (display, isExact)
    }

    // MARK: - Bucket resolution (learning-mode contribution point)

    /// Decide what to paint immediately and what to fetch for a hovered `bucket`,
    /// given the current in-memory `cache`.
    ///
    /// TODO(you): This is the function that shapes how the preview *feels*. The
    /// placeholder below is deliberately minimal — exact hit only, fetch just the
    /// hovered bucket. Extend it to:
    ///   1. Fall back to the nearest cached bucket within `nearestWindowBuckets`
    ///      when there's no exact hit, returning it with `isExact = false` so the
    ///      card dims it while the real frame loads (avoids a blank card on fast scrub).
    ///   2. Prefetch neighbours within `prefetchRadius` so dragging feels instant
    ///      instead of one frame behind.
    /// The trade-off is instant-but-approximate vs. accurate-but-occasionally-blank.
    func resolve(
        bucket: UInt32,
        cache: [UInt32: MoonlitImage]
    ) -> (display: MoonlitImage?, isExact: Bool, toFetch: [UInt32]) {
        // --- placeholder: exact hit only, no fallback, no prefetch ---
        if let exact = cache[bucket] {
            return (exact, true, [])
        }
        return (nil, false, [bucket])
    }

    // MARK: - Worker (thumbQueue)

    private func runWorker() {
        ensureFileLoaded()
        while true {
            lock.lock()
            guard enabled, let next = popRequested() else {
                workerRunning = false
                lock.unlock()
                return
            }
            let key = streamKey
            lock.unlock()

            if let image = produceFrame(bucket: next, streamKey: key) {
                lock.lock(); memoryCache[next] = image; lock.unlock()
            } else {
                lock.lock(); failed.insert(next); lock.unlock()
            }
            DispatchQueue.main.async { [weak self] in self?.revision &+= 1 }
        }
    }

    /// Pop the outstanding bucket closest to the most recent hover, so the frame the
    /// user is actually looking at wins over stale prefetch requests. Caller holds `lock`.
    private func popRequested() -> UInt32? {
        guard !requested.isEmpty else { return nil }
        let focus = focusBucket
        var bestIdx = 0
        var bestDist = UInt32.max
        for (i, b) in requested.enumerated() {
            let d = b > focus ? b - focus : focus - b
            if d < bestDist { bestDist = d; bestIdx = i }
        }
        return requested.remove(at: bestIdx)
    }

    /// Disk cache → else seek + screenshot. Runs on thumbQueue. Returns nil on failure.
    private func produceFrame(bucket: UInt32, streamKey: String) -> MoonlitImage? {
        if let url = Self.diskURL(streamKey: streamKey, bucket: bucket),
           let data = MoonlitImageCache.cachedData(for: url),
           let image = MoonlitImage(data: data) {
            return image
        }
        guard let mpv, isFileLoaded else { return nil }

        let target = Double(bucket) * bucketSeconds
        sendCommand("seek", [String(target), "absolute", "keyframes"])
        guard waitFor(MPV_EVENT_PLAYBACK_RESTART, timeout: seekWaitSeconds) else { return nil }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("moonlit-thumb-\(bucket).jpg")
        sendCommand("screenshot-to-file", [tmp.path, "video"])

        guard let data = try? Data(contentsOf: tmp), let image = MoonlitImage(data: data) else { return nil }
        try? FileManager.default.removeItem(at: tmp)
        if let url = Self.diskURL(streamKey: streamKey, bucket: bucket) {
            MoonlitImageCache.store(data: data, for: url)
        }
        return image
    }

    // MARK: - libmpv setup / teardown (thumbQueue)

    private func spawnHandle(url: String, headers: [String: String]) {
        teardownHandleLocked()
        let handle = mpv_create()
        guard let handle else { return }

        func opt(_ name: String, _ value: String) { mpv_set_option_string(handle, name, value) }
        opt("vo", "null")                 // headless — no window/render context
        opt("audio", "no")
        opt("hwdec", "no")                // software decode: reliable single-frame screenshots
        opt("pause", "yes")
        opt("keep-open", "yes")
        opt("idle", "yes")
        opt("load-scripts", "no")
        opt("ytdl", "no")
        opt("sub", "no")
        opt("hr-seek", "no")              // keyframe-only seeks — fast
        opt("cache", "yes")
        opt("demuxer-max-bytes", "32MiB")
        opt("force-seekable", "yes")
        opt("network-timeout", "15")
        opt("vf", "scale=\(thumbWidth):-2")
        opt("screenshot-format", "jpg")
        opt("screenshot-jpeg-quality", "\(jpegQuality)")
        opt("screenshot-tag-colorspace", "no")

        if !headers.isEmpty {
            let serialized = headers
                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                .map { k, v in
                    let escaped = v.replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: ",", with: "\\,")
                    return "\(k): \(escaped)"
                }
                .joined(separator: ",")
            opt("http-header-fields", serialized)
        }

        guard mpv_initialize(handle) >= 0 else {
            mpv_terminate_destroy(handle)
            return
        }
        mpv = handle
        isFileLoaded = false
        sendCommand("loadfile", [url, "replace"])
    }

    /// Drain events until the shadow file is loaded (bounded), so the first seek has
    /// something to seek within.
    private func ensureFileLoaded() {
        guard let mpv, !isFileLoaded else { return }
        _ = waitFor(MPV_EVENT_FILE_LOADED, timeout: 15.0)
        isFileLoaded = true
        _ = mpv // silence unused in case of future refactors
    }

    /// Block on the shadow's event queue until `wanted` (or SHUTDOWN) arrives, or the
    /// timeout elapses. Safe because nothing else reads this handle's events.
    private func waitFor(_ wanted: mpv_event_id, timeout: Double) -> Bool {
        guard let mpv else { return false }
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { return false }
            guard let ev = mpv_wait_event(mpv, remaining) else { continue }
            let id = ev.pointee.event_id
            if id == wanted { return true }
            if id == MPV_EVENT_SHUTDOWN { return false }
        }
    }

    private func sendCommand(_ command: String, _ args: [String]) {
        guard let mpv else { return }
        var cargs = ([command] + args + [nil]).map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
        defer { cargs.forEach { if let p = $0 { free(UnsafeMutablePointer(mutating: p)) } } }
        mpv_command(mpv, &cargs)
    }

    private func teardownHandle() {
        thumbQueue.async { [weak self] in self?.teardownHandleLocked() }
    }

    /// Must run on thumbQueue.
    private func teardownHandleLocked() {
        if let handle = mpv {
            mpv = nil
            isFileLoaded = false
            mpv_terminate_destroy(handle)
        }
    }

    // MARK: - Helpers

    private func bucket(for time: Double) -> UInt32 {
        UInt32(max(0, (time / bucketSeconds).rounded()))
    }

    /// Whether a bucket may be generated given buffered-region gating. Caller holds `lock`.
    private func allowed(_ bucket: UInt32) -> Bool {
        guard restrictToBuffered, bufferedUpTo > 0 else { return true }
        return Double(bucket) * bucketSeconds <= bufferedUpTo + bucketSeconds
    }

    /// Public gate check for the view (so it can show a label instead of spinning
    /// forever on a region that will never be produced).
    public func isGatedOut(at time: Double) -> Bool {
        let b = bucket(for: time)
        lock.lock(); defer { lock.unlock() }
        guard enabled else { return true }
        if failed.contains(b) { return true }
        return !allowed(b)
    }

    /// Stable, session-independent key for the disk cache (SHA256 of the source URL).
    private static func stableKey(for url: String) -> String {
        let digest = SHA256.hash(data: Data(url.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func diskURL(streamKey: String, bucket: UInt32) -> URL? {
        URL(string: "moonlit-seekpreview://\(streamKey)/\(bucket)")
    }

    /// Heuristic: torrent-streaming servers run on loopback and only serve downloaded
    /// ranges, so we gate un-buffered regions there. Remote HTTP/debrid is fully
    /// seekable and needs no gating.
    private static func looksBufferConstrained(_ url: String) -> Bool {
        guard let host = URL(string: url)?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local")
    }
}
#endif
