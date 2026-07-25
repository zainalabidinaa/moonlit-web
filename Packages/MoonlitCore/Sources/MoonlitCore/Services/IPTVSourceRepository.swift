// Packages/MoonlitCore/Sources/MoonlitCore/Services/IPTVSourceRepository.swift
//
// Owns the user's IPTV sources and their fetched channel lists. Follows the shape of
// AddonRepository: a @MainActor ObservableObject singleton, per-profile persistence.
//
// The (small, must-survive) source list lives in UserDefaults; the (large,
// re-fetchable) channel cache lives in a JSON file under Caches so we don't bloat
// the prefs plist with multi-MB Xtream playlists.
import Foundation

@MainActor
public final class IPTVSourceRepository: ObservableObject {
    public static let shared = IPTVSourceRepository()

    /// The user's saved sources (playlists / Xtream logins / EPG feeds).
    @Published public private(set) var sources: [IPTVPlaylistSource] = []
    /// Fetched channel lists, keyed by source id.
    @Published public private(set) var playlists: [String: IPTVPlaylist] = [:]
    /// Source ids currently being fetched.
    @Published public private(set) var refreshing: Set<String> = []
    @Published public var errorMessage: String?

    /// Merged EPG across every source that has an XMLTV feed (or Xtream-derived one).
    @Published public private(set) var epg: EPGIndex?
    @Published public private(set) var isLoadingEPG = false
    /// Manual channel-id → tvg-id overrides for channels the guide couldn't match.
    @Published public private(set) var epgOverrides: [String: String] = [:]
    /// Lazily-fetched Xtream short-EPG now/next, keyed by channel id.
    @Published public private(set) var xtreamNowNext: [String: EPGNowNext] = [:]
    private var xtreamFallbackInFlight: Set<String> = []

    private let defaults: UserDefaults
    private var currentProfileId: String?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Derived

    /// All channels across every non-EPG source, in source order.
    public var allChannels: [IPTVChannel] {
        sources.flatMap { playlists[$0.id]?.channels ?? [] }
    }

    public var hasSources: Bool { !sources.isEmpty }

    // MARK: - Lifecycle

    /// Load persisted sources + cached channels for a profile. Auto-refreshes any
    /// source that has no cached channels yet (e.g. first run after adding on
    /// another device, or a cache that was cleared).
    public func load(profileId: String) async {
        currentProfileId = profileId
        sources = loadSources(profileId: profileId)
        playlists = loadPlaylistCache(profileId: profileId)
        epgOverrides = loadOverrides(profileId: profileId)
        for source in sources where source.kind != .epg && playlists[source.id] == nil {
            await refresh(source)
        }
        await refreshEPG()
    }

    // MARK: - Mutations

    public func addSource(_ source: IPTVPlaylistSource) async {
        sources.append(source)
        persistSources()
        if source.kind != .epg { await refresh(source) }
        await refreshEPG()
    }

    public func updateSource(_ source: IPTVPlaylistSource) async {
        guard let idx = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[idx] = source
        persistSources()
        if source.kind != .epg { await refresh(source) }
        await refreshEPG()
    }

    public func removeSource(id: String) {
        sources.removeAll { $0.id == id }
        playlists[id] = nil
        persistSources()
        persistPlaylistCache()
        Task { await refreshEPG() }
    }

    public func refreshAll() async {
        for source in sources where source.kind != .epg {
            await refresh(source)
        }
        await refreshEPG()
    }

    // MARK: - Fetching

    /// Fetch + parse a single source, updating its cached channel list. Errors are
    /// surfaced on `errorMessage` and leave any prior cache intact.
    public func refresh(_ source: IPTVPlaylistSource) async {
        guard source.kind != .epg else { return }
        refreshing.insert(source.id)
        defer { refreshing.remove(source.id) }

        do {
            let playlist: IPTVPlaylist
            switch IPTVSourceDetector.detect(source) {
            case .xtream(let creds):
                playlist = try await fetchXtream(source: source, creds: creds)
            case .m3u(let url, let middleware):
                playlist = try await fetchM3U(source: source, url: url, middleware: middleware)
            case .epg:
                return
            case .invalid(let reason):
                throw XtreamError.network(reason)
            }
            playlists[source.id] = playlist
            persistPlaylistCache()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load “\(source.name)”: \(error.localizedDescription)"
        }
    }

    private func fetchXtream(source: IPTVPlaylistSource, creds: XtreamClient.ResolvedCreds) async throws -> IPTVPlaylist {
        let caps = try await XtreamClient.fetchUserInfo(creds)
        let channels = try await XtreamClient.fetchLiveChannels(creds, baseId: source.id, container: .ts, caps: caps)
        return makePlaylist(source: source, channels: channels)
    }

    private func fetchM3U(source: IPTVPlaylistSource, url: String, middleware: Bool) async throws -> IPTVPlaylist {
        // Try the given URL, then — for middleware URLs — the fallback candidates,
        // stopping at the first response that looks like an M3U document.
        var candidates = [url]
        if middleware { candidates += IPTVSourceDetector.middlewareCandidates(for: url) }

        var lastError: Error?
        for candidate in candidates {
            do {
                let text = try await fetchText(candidate)
                guard looksLikeM3U(text) else { continue }
                let channels = M3UParser.parse(text, baseId: source.id)
                return makePlaylist(source: source, channels: channels)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? XtreamError.network("No valid M3U playlist found at \(url).")
    }

    private func looksLikeM3U(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U")
    }

    private func makePlaylist(source: IPTVPlaylistSource, channels: [IPTVChannel]) -> IPTVPlaylist {
        // Distinct groups in first-seen order.
        var seen = Set<String>()
        var groups: [String] = []
        for channel in channels {
            guard let group = channel.group, !group.isEmpty, !seen.contains(group) else { continue }
            seen.insert(group)
            groups.append(group)
        }
        return IPTVPlaylist(id: source.id, name: source.name, channels: channels, groups: groups)
    }

    private func fetchText(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw XtreamError.network("Invalid URL: \(urlString)") }
        var request = URLRequest(url: url)
        // A neutral player UA — some providers reject the default URLSession agent.
        request.setValue("VLC/3.0.20 LibVLC/3.0.20", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw XtreamError.network("HTTP \(http.statusCode)")
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    // MARK: - EPG

    /// The effective XMLTV EPG URL for a source: explicit `epgUrl`, the `.epg`
    /// source's own url, or an Xtream-derived `xmltv.php`.
    private func epgURL(for source: IPTVPlaylistSource) -> String? {
        if let explicit = source.epgUrl, !explicit.isEmpty { return explicit }
        if source.kind == .epg, !source.url.isEmpty { return source.url }
        if source.kind == .xtream, let creds = IPTVSourceDetector.credsFromSource(source) {
            return "\(creds.base)/xmltv.php?username=\(creds.username)&password=\(creds.password)"
        }
        return nil
    }

    /// Fetch every source's EPG feed and merge into one index. Failures are skipped
    /// (a broken EPG shouldn't wipe out others).
    public func refreshEPG() async {
        let urls = Set(sources.compactMap(epgURL))
        guard !urls.isEmpty else { epg = nil; return }
        isLoadingEPG = true
        defer { isLoadingEPG = false }

        var mergedPrograms: [EPGProgram] = []
        var mergedMeta: [String: EPGChannelMeta] = [:]
        for url in urls {
            guard let result = try? await XMLTVParser.fetchAndParse(url: url) else { continue }
            mergedPrograms.append(contentsOf: result.programs)
            for (id, meta) in result.channelMeta where mergedMeta[id] == nil {
                mergedMeta[id] = meta
            }
        }
        epg = mergedPrograms.isEmpty && mergedMeta.isEmpty
            ? nil
            : EPGIndex(programs: mergedPrograms, channelMeta: mergedMeta)
    }

    /// Now/next for a channel from the XMLTV index. Falls back to any cached Xtream
    /// short-EPG. Sync — call `prefetchXtreamNowNext(for:)` to populate the fallback.
    public func nowNext(for channel: IPTVChannel) -> EPGNowNext {
        if let epg {
            let resolved = epg.nowNext(for: channel, overrides: epgOverrides)
            if resolved.current != nil || resolved.next != nil { return resolved }
        }
        return xtreamNowNext[channel.id] ?? .empty
    }

    /// For an Xtream channel with no XMLTV match, fetch its short-EPG once and cache
    /// the now/next. No-op for non-Xtream channels or ones already fetched.
    public func prefetchXtreamNowNext(for channel: IPTVChannel) async {
        guard xtreamNowNext[channel.id] == nil, !xtreamFallbackInFlight.contains(channel.id) else { return }
        // Only when the XMLTV index has nothing for this channel.
        if let epg {
            let resolved = epg.nowNext(for: channel, overrides: epgOverrides)
            if resolved.current != nil { return }
        }
        // Channel ids from XtreamClient look like "<sourceId>::xt::<streamId>".
        let parts = channel.id.components(separatedBy: "::")
        guard parts.count == 3, parts[1] == "xt" else { return }
        let sourceId = parts[0], streamId = parts[2]
        guard let source = sources.first(where: { $0.id == sourceId }),
              let creds = IPTVSourceDetector.credsFromSource(source) else { return }

        xtreamFallbackInFlight.insert(channel.id)
        defer { xtreamFallbackInFlight.remove(channel.id) }
        guard let entries = try? await XtreamClient.fetchShortEpg(creds, streamId: streamId), !entries.isEmpty else { return }

        let programs = entries
            .map { EPGProgram(channelTvgId: channel.tvgId ?? channel.id, title: $0.title, description: $0.description, startMs: $0.startMs, endMs: $0.endMs) }
            .sorted { $0.startMs < $1.startMs }
        xtreamNowNext[channel.id] = EPGIndex.findCurrent(programs, nowMs: Date().timeIntervalSince1970 * 1000)
    }

    /// Force a channel to a specific tvg-id (from the manual match sheet).
    public func setOverride(channelId: String, tvgId: String?) {
        if let tvgId, !tvgId.isEmpty { epgOverrides[channelId] = tvgId }
        else { epgOverrides[channelId] = nil }
        persistOverrides()
    }

    /// All tvg-ids present in the EPG, for the manual match picker.
    public var epgTvgIds: [String] {
        guard let epg else { return [] }
        return epg.byChannel.keys.sorted()
    }

    // MARK: - Persistence (sources → UserDefaults)

    private func sourcesKey(_ profileId: String) -> String { "moonlit.iptvSources.\(profileId)" }

    private func loadSources(profileId: String) -> [IPTVPlaylistSource] {
        guard let data = defaults.data(forKey: sourcesKey(profileId)),
              let decoded = try? JSONDecoder().decode([IPTVPlaylistSource].self, from: data) else { return [] }
        return decoded
    }

    private func persistSources() {
        guard let profileId = currentProfileId,
              let data = try? JSONEncoder().encode(sources) else { return }
        defaults.set(data, forKey: sourcesKey(profileId))
    }

    private func overridesKey(_ profileId: String) -> String { "moonlit.iptvEpgOverrides.\(profileId)" }

    private func loadOverrides(profileId: String) -> [String: String] {
        guard let data = defaults.data(forKey: overridesKey(profileId)),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return decoded
    }

    private func persistOverrides() {
        guard let profileId = currentProfileId,
              let data = try? JSONEncoder().encode(epgOverrides) else { return }
        defaults.set(data, forKey: overridesKey(profileId))
    }

    // MARK: - Persistence (channel cache → Caches file)

    private func cacheURL(profileId: String) -> URL? {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let folder = dir.appendingPathComponent("Moonlit", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("iptv-playlists-\(profileId).json")
    }

    private func loadPlaylistCache(profileId: String) -> [String: IPTVPlaylist] {
        guard let url = cacheURL(profileId: profileId),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: IPTVPlaylist].self, from: data) else { return [:] }
        return decoded
    }

    private func persistPlaylistCache() {
        guard let profileId = currentProfileId, let url = cacheURL(profileId: profileId) else { return }
        let snapshot = playlists
        // Encoding a large channel cache off the main actor keeps the UI smooth.
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
