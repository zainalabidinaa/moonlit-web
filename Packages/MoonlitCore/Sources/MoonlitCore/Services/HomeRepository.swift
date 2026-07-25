import Foundation

@MainActor
public class HomeRepository: ObservableObject {
    public static let shared = HomeRepository()

    @Published public var continueWatchingItems: [ContinueWatchingItem] = []
    @Published public var isLoadingContinueWatching = false

    private let syncService = SyncService.shared

    private init() {}

    public nonisolated static func latestEntriesForContinueWatching(
        _ progress: [WatchProgressEntry],
        limit: Int = 10
    ) -> [WatchProgressEntry] {
        let sorted = progress
            .filter { !$0.completed && $0.positionSeconds > 0 }
            .sorted { a, b in
                // Prefer entries whose mediaId explicitly encodes a specific episode
                // (e.g. "tt9813792:4:9") over bare series IDs (e.g. "tt9813792").
                // A ghost entry (series-only mediaId) can end up with a newer timestamp
                // when the app re-saves with no episode suffix, pushing a real episode
                // entry out of Continue Watching.
                let aIsEpisodeSpecific = a.decodedMediaId.components(separatedBy: ":").count >= 3
                let bIsEpisodeSpecific = b.decodedMediaId.components(separatedBy: ":").count >= 3
                if aIsEpisodeSpecific != bIsEpisodeSpecific { return aIsEpisodeSpecific }
                return a.updatedAt > b.updatedAt
            }

        var seenKeys = Set<String>()
        var entries: [WatchProgressEntry] = []
        for entry in sorted {
            let type = entry.mediaType.lowercased()
            let key: String
            switch type {
            case "series", "tv", "show", "shows", "anime":
                key = "series:\(entry.parentOrSelfMediaId)"
            default:
                key = "\(type):\(entry.decodedMediaId)"
            }

            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            entries.append(entry)
            if entries.count == limit { break }
        }
        return entries
    }

    public func loadContinueWatching(profileId: String) async {
        isLoadingContinueWatching = true
        defer { isLoadingContinueWatching = false }

        do {
            let progress = try await syncService.pullWatchProgress(profileId: profileId)

            // Clean up ghost entries: bare series IDs (e.g. "tt9813792") that were
            // stored without episode suffix. These can overwrite real episode-specific
            // entries (e.g. "tt9813792:4:9") if the mediaId wasn't resolved correctly.
            // We only delete them when a proper episode-specific entry exists for the
            // same series, so we're not losing data — just removing the stale ghost.
            let seriesProgress = progress.filter { entry in
                let type = entry.mediaType.lowercased()
                return ["series", "tv", "show", "shows", "anime"].contains(type)
            }
            let episodeSpecificIds = Set(seriesProgress.compactMap { entry -> String? in
                guard entry.decodedMediaId.components(separatedBy: ":").count >= 3 else { return nil }
                return entry.parentOrSelfMediaId
            })
            let ghostEntries = seriesProgress.filter { entry in
                guard entry.decodedMediaId.components(separatedBy: ":").count == 1 else { return false }
                return episodeSpecificIds.contains(entry.parentOrSelfMediaId)
            }
            for ghost in ghostEntries {
                try? await syncService.deleteWatchProgress(id: ghost.id)
            }
            let cleanedProgress = ghostEntries.isEmpty ? progress : progress.filter { p in
                !ghostEntries.contains(where: { $0.id == p.id })
            }
            let incomplete = Self.latestEntriesForContinueWatching(cleanedProgress, limit: 10)

            // Snapshot the enabled addons on the MainActor before entering the task group
            let addonRepo = AddonRepository.shared
            var items: [ContinueWatchingItem] = []
            // Snapshot catalog items on the main actor so task-group closures don't cross-actor
            let catalogItems = CatalogRepository.shared.allCatalogItems
            // Preserve last-known resolved names so a slow metadata fetch on reload doesn't
            // flash the raw media id on a tile that already had a proper title.
            let previousNames: [String: String] = Dictionary(
                continueWatchingItems.map { ($0.mediaId, $0.name) },
                uniquingKeysWith: { first, _ in first }
            )

            await withTaskGroup(of: ContinueWatchingItem.self) { group in
                for entry in incomplete {
                    // Find addons that support the meta resource for this media type
                    let addons = addonRepo.findAddonWithMetaResource(type: entry.mediaType)
                    group.addTask {
                        // Supabase stores mediaId URL-encoded (e.g. "tt9813792%3A1%3A2").
                        // Decode first so split on ":" correctly yields the base series ID.
                        let decodedMediaId = entry.decodedMediaId
                        let metaLookupId = entry.parentOrSelfMediaId

                        // Normalize media type: "tv"/"show" → "series" so the meta URL is valid
                        let normalizedType: String = {
                            switch entry.mediaType.lowercased() {
                            case "tv", "show", "shows", "anime": return "series"
                            default: return entry.mediaType.lowercased()
                            }
                        }()
                        let altType = normalizedType == "series" ? "movie" : "series"

                        // Use the same enriched metadata path as DetailScreen so episode
                        // stills include TVDB/TMDB fallbacks when configured.
                        var meta = await MetaRepository.shared.fetchDetail(
                            type: normalizedType,
                            id: metaLookupId,
                            addons: addons
                        )
                        if meta?.name == "Unknown" || meta == nil {
                            meta = await MetaRepository.shared.fetchDetail(
                                type: altType,
                                id: metaLookupId,
                                addons: addons
                            )
                        }

                        // Treat raw IMDb/Stremio IDs (e.g. "tt9813792" or "tt9813792:1:2") as
                        // absent names — they're IDs, not display titles.
                        func isRawId(_ str: String?) -> Bool {
                            guard let str else { return false }
                            return str.range(of: #"^tt\d{4,}"#, options: .regularExpression) != nil
                        }

                        // AIOMetadata may echo back the decoded compound ID as the meta name
                        // (e.g. "tt9813792:1:2"). Reject those as non-titles.
                        // Capture artwork first — meta is discarded when the name is a raw ID,
                        // but the poster/background/logo are still valid.
                        let cwBackground = meta?.background
                        if let metaName = meta?.name, isRawId(metaName) {
                            meta = nil
                        }

                        // Fallback: try the already-loaded catalog rows for name + poster,
                        // then URL-decode the stored ID as last resort.
                        // Treat "Unknown" and raw IMDb IDs as absent.
                        let rawName = meta?.name ?? (isRawId(entry.name) ? nil : entry.name)
                        var cwName: String? = (rawName == nil || rawName == "Unknown" || rawName?.isEmpty == true) ? nil : rawName
                        var cwPoster = meta?.poster ?? entry.poster
                        var cwLogo = meta?.logo

                        if cwName == nil || cwPoster == nil || cwLogo == nil, let catalogItem = catalogItems.first(where: {
                            $0.id == metaLookupId || $0.id == decodedMediaId || $0.id == entry.mediaId
                        }) {
                            if cwName == nil { cwName = catalogItem.name }
                            if cwPoster == nil { cwPoster = catalogItem.poster }
                            if cwLogo == nil { cwLogo = catalogItem.logo }
                        }

                        // Resolve effective season/episode:
                        // 1. Use the stored entry values if present (new entries post-fix).
                        // 2. Fall back to parsing from mediaId "parentId:season:episode"
                        //    format (entries saved after the episode-specific ID fix).
                        let effectiveSeason = entry.inferredSeason
                        let effectiveEpisode = entry.inferredEpisode

                        // Find the matching episode for thumbnail + title.
                        // Try flat videos array first (standard Stremio), then
                        // fall back to structured seasons (AIOMetadata / TVDB style
                        // where episodes live inside seasons and season is nil on each video).
                        let matchingVideo: MetaVideo? = {
                            if let video = meta?.videos?.first(where: { $0.id == decodedMediaId }) {
                                return video
                            }
                            if let seasons = meta?.seasons {
                                for season in seasons {
                                    if let ep = season.episodes?.first(where: { $0.id == decodedMediaId }) {
                                        return ep
                                    }
                                }
                            }
                            if let s = effectiveSeason, let e = effectiveEpisode {
                                if let video = meta?.videos?.first(where: {
                                    $0.season == s && $0.episode == e
                                }) { return video }
                                if let seasons = meta?.seasons {
                                    for season in seasons where season.number == s {
                                        if let ep = season.episodes?.first(where: { $0.episode == e }) {
                                            return ep
                                        }
                                    }
                                }
                            }
                            return nil
                        }()
                        let fallbackThumbnail: String? = {
                            matchingVideo?.thumbnail ?? entry.thumbnailFallbackForContinueWatching
                        }()
                        let directAIOMetadataThumbnail: String? = {
                            guard fallbackThumbnail == nil,
                                  effectiveSeason != nil || effectiveEpisode != nil,
                                  let manifestURL = MoonlitConfig.defaultAddons.first(where: { $0.contains("aiometadata") }) else {
                                return nil
                            }
                            return manifestURL.replacingOccurrences(of: "/manifest.json", with: "")
                        }()
                        let resolvedThumbnail: String?
                        if let directAIOMetadataThumbnail,
                           let directMeta = try? await MetaService.shared.fetchMeta(
                                type: normalizedType,
                                id: metaLookupId,
                                baseURL: directAIOMetadataThumbnail
                           ) {
                            resolvedThumbnail = Self.matchEpisode(
                                in: directMeta,
                                decodedMediaId: decodedMediaId,
                                season: effectiveSeason,
                                episode: effectiveEpisode
                            )?.thumbnail
                        } else {
                            resolvedThumbnail = fallbackThumbnail
                        }

                        let decodedFallback = (entry.mediaId.removingPercentEncoding ?? entry.mediaId)
                            .split(separator: ":").first.map(String.init) ?? entry.mediaId
                        // Prefer a freshly-resolved name; else the last-known name from a
                        // previous load; only show the raw id as an absolute last resort.
                        let previousName = previousNames[entry.mediaId]
                        let resolvedName = cwName
                            ?? (isRawId(previousName) ? nil : previousName)
                            ?? decodedFallback
                        return ContinueWatchingItem(
                            mediaId: entry.mediaId,
                            parentMediaId: metaLookupId,
                            mediaType: entry.mediaType,
                            name: resolvedName,
                            poster: cwPoster,
                            logo: cwLogo,
                            background: cwBackground,
                            resumePositionMs: entry.positionSeconds * 1000,
                            durationMs: entry.durationSeconds * 1000,
                            progressFraction: entry.progressFraction,
                            seasonNumber: effectiveSeason,
                            episodeNumber: effectiveEpisode,
                            episodeTitle: matchingVideo?.title,
                            thumbnail: resolvedThumbnail
                        )
                    }
                }
                for await item in group {
                    items.append(item)
                }
            }

            // Re-sort to match original updatedAt order (task group doesn't preserve order)
            let sortedIds = incomplete.map(\.mediaId)
            continueWatchingItems = items.sorted {
                let ia = sortedIds.firstIndex(of: $0.mediaId) ?? Int.max
                let ib = sortedIds.firstIndex(of: $1.mediaId) ?? Int.max
                return ia < ib
            }
        } catch {
            // Preserve existing items on transient errors — don't blank the row
            if continueWatchingItems.isEmpty { continueWatchingItems = [] }
        }
    }

    public func loadCatalogRows(addons: [AddonManifest]) async -> [CatalogRow] {
        await CatalogRepository.shared.loadAllCatalogs(addons: addons)
        return CatalogRepository.shared.catalogRows
    }

    private nonisolated static let dismissedKey = "com.moonlit.continueWatching.dismissedIds"

    private nonisolated static func dismissedIds() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? [])
    }

    private nonisolated static func addDismissedId(_ id: String) {
        var ids = dismissedIds()
        ids.insert(id)
        UserDefaults.standard.set(Array(ids), forKey: dismissedKey)
    }

    /// Reactive advance pass over the Continue Watching row: any card whose
    /// current episode is watched — via `watched_items` (the eye toggle /
    /// context menu) OR a completed progress row (finished playback) — flips
    /// in place to the next unwatched episode: **Up Next** if it has aired,
    /// **Upcoming + air date** if not, removed only when the series has no
    /// further episodes. Also appends cards for recently-finished series that
    /// aren't in the row at all. Re-run this whenever watched state changes,
    /// not just at startup.
    public func advanceContinueWatching(profileId: String) async {
        let watchedRepo = WatchProgressRepository.shared
        if watchedRepo.watchedItems.isEmpty && watchedRepo.progressEntries.isEmpty {
            await watchedRepo.loadAll(profileId: profileId)
        }

        // Snapshot watched state into a plain Sendable set so the resolver
        // task group doesn't hop actors per episode check.
        var watchedKeys = Set<String>()
        for item in watchedRepo.watchedItems {
            guard let s = item.season, let e = item.episode else { continue }
            let parent = Self.parentId(fromMediaId: item.mediaId)
            watchedKeys.insert(Self.watchedKey(parent, s, e))
        }
        for entry in watchedRepo.progressEntries where entry.completed {
            if let s = entry.inferredSeason, let e = entry.inferredEpisode {
                watchedKeys.insert(Self.watchedKey(entry.parentOrSelfMediaId, s, e))
            }
        }

        let addonRepo = AddonRepository.shared
        let dismissed = Self.dismissedIds()
        let seriesTypes: Set<String> = ["series", "tv", "show", "shows", "anime"]
        let keys = watchedKeys

        // ── Pass 1: advance existing cards in place (keeps row order) ──
        let snapshot = continueWatchingItems
        var resolved: [String: ContinueWatchingItem?] = [:]
        await withTaskGroup(of: (String, ContinueWatchingItem??).self) { group in
            for item in snapshot {
                guard seriesTypes.contains(item.mediaType.lowercased()) else { continue }
                let addons = addonRepo.findAddonWithMetaResource(type: item.mediaType)
                group.addTask {
                    (item.mediaId, await Self.advancedCard(for: item, watchedKeys: keys, addons: addons))
                }
            }
            for await (id, result) in group {
                // Inner optional distinguishes "no change" (nil) from
                // "resolved to a new card or removal" (.some).
                if let result { resolved[id] = result }
            }
        }
        if !resolved.isEmpty {
            continueWatchingItems = continueWatchingItems.compactMap { item in
                guard let change = resolved[item.mediaId] else { return item }
                return change  // new card, or nil → series exhausted, drop it
            }
        }

        // ── Pass 2: append cards for finished series not in the row ──
        let recentWindow: TimeInterval = 45 * 24 * 3600
        let inRowParents = Set(continueWatchingItems.map { ($0.parentMediaId ?? $0.mediaId).lowercased() })
        var seenParents = Set<String>()
        var candidates: [(parent: String, season: Int, episode: Int, mediaType: String)] = []
        for item in watchedRepo.watchedItems.sorted(by: { $0.markedAt > $1.markedAt }) {
            guard seriesTypes.contains(item.mediaType.lowercased()),
                  let s = item.season, let e = item.episode,
                  Date().timeIntervalSince(item.markedAt) < recentWindow else { continue }
            let parent = Self.parentId(fromMediaId: item.mediaId)
            let key = parent.lowercased()
            guard !inRowParents.contains(key), !dismissed.contains(parent), !seenParents.contains(key) else { continue }
            seenParents.insert(key)
            candidates.append((parent, s, e, item.mediaType))
        }
        guard !candidates.isEmpty else { return }

        var newItems: [ContinueWatchingItem] = []
        await withTaskGroup(of: ContinueWatchingItem?.self) { group in
            for candidate in candidates.prefix(6) {
                let addons = addonRepo.findAddonWithMetaResource(type: candidate.mediaType)
                group.addTask {
                    await Self.nextEpisodeCard(
                        parentId: candidate.parent,
                        after: (candidate.season, candidate.episode),
                        mediaType: candidate.mediaType,
                        watchedKeys: keys,
                        addons: addons
                    )
                }
            }
            for await item in group {
                if let item { newItems.append(item) }
            }
        }
        if !newItems.isEmpty {
            continueWatchingItems.append(contentsOf: newItems)
        }
    }

    /// Resolves what a Continue Watching card should become given current
    /// watched state. Returns `nil` for "leave unchanged", `.some(nil)` for
    /// "remove — series exhausted", `.some(card)` for an in-place flip.
    private nonisolated static func advancedCard(
        for item: ContinueWatchingItem,
        watchedKeys: Set<String>,
        addons: [AddonManifest]
    ) async -> ContinueWatchingItem?? {
        guard let season = item.seasonNumber, let episode = item.episodeNumber else { return nil }
        let parentId = item.parentMediaId ?? parentId(fromMediaId: item.mediaId)
        let currentWatched = watchedKeys.contains(watchedKey(parentId, season, episode))

        if item.isUpcoming && !currentWatched {
            // The episode may have aired since the card was made — flip the
            // badge without moving to a different episode.
            if let airsAt = item.upcomingAirsAt, airsAt <= Date() {
                return .some(remade(item, parentId: parentId, season: season, episode: episode, upNext: true, airsAt: nil))
            }
            return nil
        }
        guard currentWatched else { return nil }
        return .some(await nextEpisodeCard(
            parentId: parentId, after: (season, episode), mediaType: item.mediaType,
            watchedKeys: watchedKeys, addons: addons,
            fallbackName: item.name, fallbackPoster: item.poster,
            fallbackLogo: item.logo, fallbackBackground: item.background
        ))
    }

    /// Builds an Up Next / Upcoming card for the first unwatched episode
    /// after `current`, or `nil` when the series has nothing further.
    private nonisolated static func nextEpisodeCard(
        parentId: String,
        after current: (season: Int, episode: Int),
        mediaType: String,
        watchedKeys: Set<String>,
        addons: [AddonManifest],
        fallbackName: String? = nil,
        fallbackPoster: String? = nil,
        fallbackLogo: String? = nil,
        fallbackBackground: String? = nil
    ) async -> ContinueWatchingItem? {
        guard let meta = await MetaRepository.shared.fetchDetail(type: "series", id: parentId, addons: addons) else { return nil }
        let ordered = orderedEpisodes(in: meta)
        guard let next = ordered.first(where: { video in
            guard let vs = video.season, let ve = video.episode, vs >= 1 else { return false }
            guard (vs, ve) > (current.season, current.episode) else { return false }
            return !watchedKeys.contains(watchedKey(parentId, vs, ve))
        }) else { return nil }

        let nextSeason = next.season ?? current.season
        let nextEpisode = next.episode ?? current.episode + 1
        let airDate = parseReleaseDate(next.released)
        let hasAired = airDate.map { $0 <= Date() } ?? true
        let name = meta.name == "Unknown" ? (fallbackName ?? meta.name) : meta.name

        return ContinueWatchingItem(
            mediaId: "\(parentId):\(nextSeason):\(nextEpisode)",
            parentMediaId: parentId,
            mediaType: mediaType,
            name: name,
            poster: meta.poster ?? fallbackPoster,
            logo: meta.logo ?? fallbackLogo,
            background: meta.background ?? fallbackBackground,
            seasonNumber: nextSeason,
            episodeNumber: nextEpisode,
            episodeTitle: next.title,
            thumbnail: next.thumbnail,
            isUpNext: hasAired,
            isUpcoming: !hasAired,
            upcomingAirsAt: hasAired ? nil : airDate
        )
    }

    private nonisolated static func remade(
        _ item: ContinueWatchingItem, parentId: String, season: Int, episode: Int,
        upNext: Bool, airsAt: Date?
    ) -> ContinueWatchingItem {
        ContinueWatchingItem(
            mediaId: item.mediaId, parentMediaId: parentId, mediaType: item.mediaType,
            name: item.name, poster: item.poster, logo: item.logo, background: item.background,
            seasonNumber: season, episodeNumber: episode,
            episodeTitle: item.episodeTitle, thumbnail: item.thumbnail,
            isUpNext: upNext, isUpcoming: !upNext, upcomingAirsAt: airsAt
        )
    }

    private nonisolated static func orderedEpisodes(in meta: MetaDetail) -> [MetaVideo] {
        let all: [MetaVideo]
        if let videos = meta.videos, !videos.isEmpty {
            all = videos
        } else if let seasons = meta.seasons {
            all = seasons.flatMap { $0.episodes ?? [] }
        } else {
            return []
        }
        return all.sorted { (($0.season ?? 0), ($0.episode ?? 0)) < (($1.season ?? 0), ($1.episode ?? 0)) }
    }

    private nonisolated static func watchedKey(_ parent: String, _ season: Int, _ episode: Int) -> String {
        "\(parent.lowercased())|\(season)|\(episode)"
    }

    private nonisolated static func parentId(fromMediaId mediaId: String) -> String {
        let decoded = mediaId.removingPercentEncoding ?? mediaId
        return decoded.split(separator: ":").first.map(String.init) ?? decoded
    }

    /// Removes a card from Continue Watching. For a real in-progress entry
    /// this also deletes the underlying synced watch-progress row; for a
    /// synthetic Up Next / Upcoming card (nothing to delete server-side) it
    /// just remembers the dismissal locally so it doesn't reappear.
    public func removeFromContinueWatching(_ item: ContinueWatchingItem) async {
        continueWatchingItems.removeAll { $0.mediaId == item.mediaId }
        if item.isUpNext || item.isUpcoming {
            Self.addDismissedId(item.parentMediaId ?? item.mediaId)
            return
        }
        guard let entry = WatchProgressRepository.shared.progressEntries.first(where: { $0.mediaId == item.mediaId }) else { return }
        try? await syncService.deleteWatchProgress(id: entry.id)
    }

    private nonisolated static func parseReleaseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let date = ISO8601DateFormatter().date(from: raw) { return date }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: String(raw.prefix(10)))
    }

    private nonisolated static func matchEpisode(
        in meta: MetaDetail,
        decodedMediaId: String,
        season: Int?,
        episode: Int?
    ) -> MetaVideo? {
        if let video = meta.videos?.first(where: { $0.id == decodedMediaId }) {
            return video
        }
        if let seasons = meta.seasons {
            for seasonGroup in seasons {
                if let video = seasonGroup.episodes?.first(where: { $0.id == decodedMediaId }) {
                    return video
                }
            }
        }
        guard let season, let episode else { return nil }
        if let video = meta.videos?.first(where: { $0.season == season && $0.episode == episode }) {
            return video
        }
        if let seasons = meta.seasons {
            for seasonGroup in seasons where seasonGroup.number == season {
                if let video = seasonGroup.episodes?.first(where: { $0.episode == episode }) {
                    return video
                }
            }
        }
        return nil
    }
}
