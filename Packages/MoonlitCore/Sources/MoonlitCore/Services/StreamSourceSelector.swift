import Foundation

public enum StreamQuality: Int, Sendable, Comparable {
    case unknown = 0
    case hd1080 = 1080
    case ultraHD4K = 2160

    public static func < (lhs: StreamQuality, rhs: StreamQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum StreamSourceSelector {
    public static func playbackCandidates(from streams: [StreamItem]) -> [StreamItem] {
        deduplicated(streams.filter(isPlaybackCandidate))
    }

    /// All playback candidates ranked by quality/cache score. Cached/debrid streams
    /// appear first due to their ranking bonus; non-cached streams follow. Use this
    /// wherever the full list should be visible (Sources Panel, manual picker failover).
    public static func rankedCandidates(from streams: [StreamItem], prefer4K: Bool = false) -> [StreamItem] {
        rankedStreams(playbackCandidates(from: streams), prefer4K: prefer4K)
    }

    /// Returns only cached/debrid streams + the currently playing stream.
    /// Falls back to all candidates when no cached streams exist.
    public static func cachedCandidates(currentUrl: String?, from streams: [StreamItem], prefer4K: Bool = false) -> [StreamItem] {
        let all = playbackCandidates(from: streams)
        let cached = all.filter { isCachedStream($0) }
        if cached.isEmpty { return rankedStreams(all, prefer4K: prefer4K) }
        var ranked = rankedStreams(cached, prefer4K: prefer4K)
        if let url = currentUrl,
           !ranked.contains(where: { $0.url == url }),
           let current = all.first(where: { $0.url == url }) {
            ranked.append(current)
        }
        return ranked
    }

    public static func hasMultiplePlaybackCandidates(in streams: [StreamItem]) -> Bool {
        var count = 0
        for stream in streams where isPlaybackCandidate(stream) {
            count += 1
            if count > 1 { return true }
        }
        return false
    }

    public static func has4KPlaybackCandidate(in streams: [StreamItem], excludingSourceUrl: String?) -> Bool {
        streams.contains { stream in
            isPlaybackCandidate(stream) &&
            stream.url != excludingSourceUrl &&
            quality(of: stream) == .ultraHD4K
        }
    }

    public static func initialStream(from streams: [StreamItem], prefer4K: Bool, installOrder: [String] = []) -> StreamItem? {
        rankedStreams(playbackCandidates(from: streams), prefer4K: prefer4K, installOrder: installOrder).first
    }

    /// Ordered list of auto-playable candidates for silent cycling (Nuvio-style).
    /// Debrid-ready streams first, then addons by install order, rest by score.
    /// When the first candidate fails, the caller iterates through the list
    /// without showing an error until all are exhausted.
    public static func candidatesForAutoPlay(from streams: [StreamItem], prefer4K: Bool, installOrder: [String] = []) -> [StreamItem] {
        rankedStreams(playbackCandidates(from: streams), prefer4K: prefer4K, installOrder: installOrder)
            .filter(isAutoPlayable)
    }

    /// Whether a stream can be launched immediately. Excludes:
    /// - Magnet/torrent links (need P2P resolution)
    /// - Debrid streams that aren't cached yet (return "Torrent not downloaded")
    /// - Resolve/uncached URLs that need server-side preparation
    public static func isAutoPlayable(_ stream: StreamItem) -> Bool {
        guard let url = stream.url, !url.isEmpty else { return false }
        let lower = url.lowercased()
        if lower.hasPrefix("magnet:") || lower.hasPrefix("torrent:") { return false }
        if isPendingDebrid(stream) { return false }
        return true
    }

    /// Detects debrid streams that aren't ready to play yet ("Torrent not downloaded yet").
    /// These streams have a URL but the debrid service hasn't finished caching the torrent.
    public static func isPendingDebrid(_ stream: StreamItem) -> Bool {
        // Explicitly marked as not cached by the addon
        if stream.behaviorHints?.cached == false { return true }

        let text = searchableText(for: stream)
        let url = stream.url?.lowercased() ?? ""

        // URL patterns indicating torrent still resolving
        let urlMarkers = ["/torrent/", "/resolve/", "/uncached/", "/fetch/", "/pending/"]
        if urlMarkers.contains(where: { url.contains($0) }) { return true }

        // Text markers indicating not ready
        let textMarkers = [
            "not downloaded", "not cached", "not yet cached",
            "downloading", "caching", "queued", "waiting",
            "try again shortly", "retry later",
            "internal provider issue",
        ]
        if textMarkers.contains(where: { text.contains($0) }) { return true }

        // Has an infoHash (torrent identifier) but no cached URL — needs resolution
        if stream.infoHash != nil && stream.behaviorHints?.cached != true
            && !isDirectDebridStream(stream) {
            return true
        }

        return false
    }

    /// Whether the stream URL points directly to a debrid CDN file
    /// (real-debrid, alldebrid, premiumize, etc.) rather than a proxy/resolver.
    private static func isDirectDebridStream(_ stream: StreamItem) -> Bool {
        let url = stream.url?.lowercased() ?? ""
        return url.contains("real-debrid.com") || url.contains("alldebrid.com")
            || url.contains("premiumize.me") || url.contains("debrid-link.com")
            || url.contains("put.io") || url.contains("offcloud.com")
    }

    public static func best4KStream(from streams: [StreamItem], excluding current: StreamItem?) -> StreamItem? {
        rankedStreams(streams.filter(isPlaybackCandidate), prefer4K: true)
            .first { quality(of: $0) == .ultraHD4K && !sameStream($0, current) }
    }

    public static func nextStream(
        after current: StreamItem?,
        currentSourceUrl: String? = nil,
        from streams: [StreamItem],
        prefer4K: Bool
    ) -> StreamItem? {
        let ranked = rankedStreams(playbackCandidates(from: streams), prefer4K: prefer4K)
            .filter { !sameStream($0, current) && !sameSourceUrl($0, currentSourceUrl) }
        let currentQuality = current.map(quality)

        if let currentQuality,
           let sameQuality = ranked.first(where: { quality(of: $0) == currentQuality }) {
            return sameQuality
        }
        if prefer4K, let fourK = ranked.first(where: { quality(of: $0) == .ultraHD4K }) {
            return fourK
        }
        return ranked.first(where: { quality(of: $0) == .hd1080 }) ?? ranked.first
    }

    public static func quality(of stream: StreamItem) -> StreamQuality {
        let text = searchableText(for: stream)
        if text.contains("2160") || text.contains("4k") || text.contains("uhd") {
            return .ultraHD4K
        }
        if text.contains("1080") || text.contains("fhd") || text.contains("fullhd") {
            return .hd1080
        }
        return .unknown
    }

    public static func isPlaybackCandidate(_ stream: StreamItem) -> Bool {
        guard let url = stream.url, !url.isEmpty else { return false }
        let text = searchableText(for: stream)
        if stream.sourceType == .youtube || stream.sourceType == .external || stream.sourceType == .playerFrame {
            return false
        }
        if stream.behaviorHints?.notWebReady == true {
            return false
        }
        if stream.behaviorHints?.bingeGroup?.lowercased() == "trailer" {
            return false
        }
        if text.contains("trailer") || text.contains("teaser") {
            return false
        }
        return true
    }

    private static func isCachedStream(_ stream: StreamItem) -> Bool {
        let text = searchableText(for: stream)
        let url = stream.url?.lowercased() ?? ""
        let isDebridUrl = url.contains("real-debrid.com") || url.contains("alldebrid.com")
            || url.contains("premiumize.me") || url.contains("debrid-link.com")
            || url.contains("put.io") || url.contains("offcloud.com")
        return stream.behaviorHints?.cached == true
            || hasCachedEmojiMarker(in: text)
            || isDebridUrl
            || text.contains("cached") || text.contains("[cache]")
            || text.contains("rd+") || text.contains("ad+") || text.contains("tb+")
            || text.contains("[rd]") || text.contains("[ad]") || text.contains("[tb]")
    }

    private static func rankedStreams(_ streams: [StreamItem], prefer4K: Bool, installOrder: [String] = []) -> [StreamItem] {
        streams
            .map { (
                score: rankingScore(for: $0, prefer4K: prefer4K),
                name: $0.displayName,
                isDebrid: isDirectDebridStream($0),
                addonRank: installOrderRank(for: $0, in: installOrder),
                item: $0
            ) }
            .sorted { lhs, rhs in
                // 1. Score first (cached/debrid > labelled > size/speed > uncached, + resolution bonus)
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                // 2. Install order as tiebreaker (lower rank = earlier install)
                if lhs.addonRank != rhs.addonRank { return lhs.addonRank < rhs.addonRank }
                // 3. Alphabetical tiebreaker
                return lhs.name < rhs.name
            }
            .map(\.item)
    }

    private static func installOrderRank(for stream: StreamItem, in installOrder: [String]) -> Int {
        guard let addonName = stream.addonName, !installOrder.isEmpty else { return Int.max }
        return installOrder.firstIndex(of: addonName) ?? Int.max
    }

    private static func rankingScore(for stream: StreamItem, prefer4K: Bool) -> Double {
        let text = searchableText(for: stream)
        var score = Double(stream.qualityScore)

        // Penalise cam / telesync rips
        if text.contains("cam") || text.contains("hdcam") || text.contains("telesync") || text.contains(" ts ") {
            score -= 80
        }

        // Penalise debrid streams that aren't ready yet ("Torrent not downloaded").
        // They're still shown in the sources panel for manual selection but rank below
        // ready-to-play streams so auto-play won't pick them.
        if isPendingDebrid(stream) {
            score -= 50_000
        }

        // ── Tier 1: debrid-cached / instant ─────────────────────────────
        // behaviorHints.cached is the canonical signal (Torrentio, Comet, etc.)
        // bolt ⚡ in stream text is a display-only fallback for older addons
        // debrid CDN URLs are always cached by definition
        let streamUrl = stream.url?.lowercased() ?? ""
        let isDebridUrl = streamUrl.contains("real-debrid.com") || streamUrl.contains("alldebrid.com")
            || streamUrl.contains("premiumize.me") || streamUrl.contains("debrid-link.com")
            || streamUrl.contains("put.io") || streamUrl.contains("offcloud.com")
        if stream.behaviorHints?.cached == true || hasCachedEmojiMarker(in: text) || isDebridUrl {
            score += 10_000
        }
        // ── Tier 2: explicitly labelled as cached ───────────────────────
        // includes common debrid shorthand badges: RD+, AD+, TB+, [RD], [AD]
        else if text.contains("cached") || text.contains("[cache]")
            || text.contains("rd+") || text.contains("ad+") || text.contains("tb+")
            || text.contains("[rd]") || text.contains("[ad]") || text.contains("[tb]") {
            score += 5_000
        }
        // ── Tier 3: rank by speed/size signals ──────────────────────────
        // Real-world streams rarely include explicit "Mbps" labels; they
        // show file size in GB (e.g. "💾 8.9 GB").  We combine all three
        // signals and cap at 900 pts so this tier stays below "cached".
        else {
            var bonus: Double = 0
            // 3a. Explicit Mbps label
            if let mbps = extractMbps(from: text) { bonus = max(bonus, min(mbps * 10, 900)) }
            // 3b. behaviorHints.videoSize (bytes) — populated by Torrentio & many addons
            if let bytes = stream.behaviorHints?.videoSize, bytes > 0 {
                let gb = Double(bytes) / 1_073_741_824
                bonus = max(bonus, min(gb * 25, 900))
            }
            // 3c. File-size text in stream name/title ("8.9 GB", "💾 4.2 GB", etc.)
            if let gb = extractGB(from: text) { bonus = max(bonus, min(gb * 25, 900)) }
            score += bonus
        }

        // Resolution bonus is always applied on top of the tier score
        switch quality(of: stream) {
        case .ultraHD4K: score += prefer4K ? 30 : 0
        case .hd1080:    score += prefer4K ? 20 : 25
        case .unknown:   break
        }
        return score
    }

    private static func hasCachedEmojiMarker(in text: String) -> Bool {
        text.contains("\u{26A1}") || text.contains(":zap:") || text.contains("⚡")
            || text.contains("\u{1F9E7}") || text.contains("🧧")
    }

    // Compiled once. `NSRegularExpression(pattern:)` is expensive; building it on every
    // call (the ranking sort calls these per stream) was a major main-thread cost.
    private static let mbpsRegex = try? NSRegularExpression(
        pattern: #"(\d+(?:\.\d+)?)\s*(?:mbps|mb/s|mib/s)"#, options: .caseInsensitive)
    private static let gbRegex = try? NSRegularExpression(
        pattern: #"(?:💾\s*)?(\d+(?:\.\d+)?)\s*(gb|mb)\b"#, options: .caseInsensitive)

    /// Parses explicit bitrate labels: "50 Mbps", "12 Mb/s", "5 MiB/s".
    private static func extractMbps(from text: String) -> Double? {
        guard let regex = mbpsRegex else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match -> Double? in
            Range(match.range(at: 1), in: text).flatMap { Double(text[$0]) }
        }.max()
    }

    /// Parses file-size labels: "8.9 GB", "💾 4.2 GB", "1.4 gb", "1400 MB" → returns GB.
    private static func extractGB(from text: String) -> Double? {
        guard let regex = gbRegex else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let values: [Double] = regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges >= 3,
                  let numRange  = Range(match.range(at: 1), in: text),
                  let unitRange = Range(match.range(at: 2), in: text),
                  let value = Double(text[numRange]) else { return nil }
            let unit = text[unitRange].lowercased()
            return unit == "mb" ? value / 1024 : value   // normalise to GB
        }
        return values.max()
    }

    private static func searchableText(for stream: StreamItem) -> String {
        ([
            stream.name,
            stream.title,
            stream.description,
            stream.sourceName,
            stream.addonName,
            stream.behaviorHints?.filename,
        ] + (stream.sources ?? []))
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
    }

    private static func sameStream(_ lhs: StreamItem, _ rhs: StreamItem?) -> Bool {
        guard let rhs else { return false }
        return lhs.id == rhs.id
    }

    private static func sameSourceUrl(_ stream: StreamItem, _ sourceUrl: String?) -> Bool {
        guard let sourceUrl else { return false }
        return stream.url == sourceUrl
    }

    public static func deduplicated(_ streams: [StreamItem]) -> [StreamItem] {
        var seenVideoHash = Set<String>()
        var seenInfoHash = Set<String>()
        var seenUrl = Set<String>()
        var result: [StreamItem] = []
        for stream in streams {
            if let hash = stream.behaviorHints?.videoHash, !hash.isEmpty {
                if seenVideoHash.insert(hash).inserted {
                    result.append(stream)
                    continue
                }
                continue
            }
            if let hash = stream.infoHash, !hash.isEmpty {
                if seenInfoHash.insert(hash).inserted {
                    result.append(stream)
                    continue
                }
                continue
            }
            if let url = stream.url, !url.isEmpty {
                let normalized = url.split(separator: "?")[0].lowercased()
                if seenUrl.insert(normalized).inserted {
                    result.append(stream)
                }
            }
        }
        return result
    }
}
