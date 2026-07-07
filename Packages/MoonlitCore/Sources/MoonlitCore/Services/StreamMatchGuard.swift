import Foundation

public enum StreamMatchGuard {

    /// Returns true if the stream should be kept for the given media request.
    ///
    /// - Parameters:
    ///   - stream:  The stream candidate.
    ///   - type:    Stremio type string ("movie" or "series").
    ///   - id:      Stremio ID — `tt1234567` for movies, `tt1234567:S:E` for series.
    ///   - title:   Human-readable title of the show / movie (used for filename validation).
    ///   - year:    Release year of the movie (used for filename year cross-check).
    public static func shouldKeep(
        _ stream: StreamItem,
        type: String,
        id: String,
        title: String? = nil,
        year: Int? = nil
    ) -> Bool {
        let text = searchableText(for: stream)
        let expectedImdbId = id.components(separatedBy: ":").first ?? id

        // IMDB cross-check removed — addons like AIOStreams aggregate from multiple
        // providers and descriptions often reference other IMDB IDs legitimately.
        // Harbor has no equivalent filter.

        // ── Series: episode + season validation ─────────────────────────────
        if type == "series", let ep = expectedSeriesEpisode(from: id) {
            // 1. Filename is authoritative when present: it encodes the real
            //    episode/season more reliably than freeform description text.
            if let filename = stream.behaviorHints?.filename {
                let fn = filename.lowercased()
                // Wrong episode inside a named file
                if containsDifferentEpisode(in: fn, expected: ep) { return false }
                // Season pack for the wrong season (e.g. "S02.Complete")
                if containsDifferentSeasonPack(in: fn, expected: ep.season) { return false }
            }
            // 2. Fallback: combined description text
            if containsDifferentEpisode(in: text, expected: ep) { return false }

            // 3. Show title cross-check from filename (conservative: only reject
            //    if the filename clearly belongs to a different show)
            if let filename = stream.behaviorHints?.filename, let title {
                if !filenameShowMatches(filename, showTitle: title, season: ep.season) { return false }
            }
        }

        // ── Movies: title + year validation from filename ───────────────────
        if type == "movie", let filename = stream.behaviorHints?.filename, let title {
            if !filenameMovieMatches(filename, title: title, year: year) { return false }
        }

        return true
    }

    // MARK: - Searchable text

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

    // MARK: - IMDB cross-check

    private static func containsDifferentImdbId(in text: String, expected: String) -> Bool {
        matches(pattern: #"\btt\d{5,10}\b"#, in: text).contains { $0 != expected.lowercased() }
    }

    // MARK: - Series helpers

    private static func expectedSeriesEpisode(from id: String) -> (season: Int, episode: Int)? {
        let parts = id.components(separatedBy: ":")
        guard parts.count >= 3,
              let season = Int(parts[1]),
              let episode = Int(parts[2]) else { return nil }
        return (season, episode)
    }

    /// Returns true if `text` contains an explicit S/E marker for a DIFFERENT episode.
    /// Streams with no episode markers pass through (e.g. loose quality-info-only descriptions).
    private static func containsDifferentEpisode(
        in text: String,
        expected: (season: Int, episode: Int)
    ) -> Bool {
        let patterns = [
            // S01E02, S1E2, S01 E02, S01.E02, S01-E02, S01·E02
            #"s\s*(\d{1,2})\s*[.\-_· ]*\s*e\s*(\d{1,3})"#,
            // 1x02, 01x02
            #"\b(\d{1,2})\s*x\s*(\d{1,3})\b"#,
            // "season 1 episode 2" / "season 1, episode 2"
            #"season\s*(\d{1,2}).{0,12}episode\s*(\d{1,3})"#,
            // Multi-episode: S01E01E02 — we check if target episode is in range
            #"s\s*(\d{1,2})\s*e\s*(\d{1,3})\s*(?:e\s*(\d{1,3}))+"#,
        ]

        for pattern in patterns {
            for groups in captureGroups(pattern: pattern, in: text) {
                guard groups.count >= 2,
                      let season = Int(groups[0]),
                      let episodeStart = Int(groups[1]) else { continue }
                if season != expected.season { return true }
                // For multi-episode, check if target is within the episode range
                let episodeEnd = groups.count >= 3 ? (Int(groups[2]) ?? episodeStart) : episodeStart
                let range = min(episodeStart, episodeEnd)...max(episodeStart, episodeEnd)
                if !range.contains(expected.episode) { return true }
            }
        }
        return false
    }

    /// Returns true if `filename` contains a season-only marker (pack) for the WRONG season.
    /// A standalone `S02` (not followed by an episode number) indicates a season pack.
    private static func containsDifferentSeasonPack(in filename: String, expected season: Int) -> Bool {
        let patterns = [
            // S01 not immediately followed by E\d  →  season pack marker
            #"\bs(\d{1,2})(?![\s.\-_]*e\d)"#,
            // "Season 2" not followed by "Episode"
            #"season\s+(\d{1,2})(?!\s*episode)"#,
            // "Complete Season 2"
            #"complete\s+season\s+(\d{1,2})"#,
        ]
        var foundPack = false
        for pattern in patterns {
            for groups in captureGroups(pattern: pattern, in: filename) {
                guard let found = Int(groups[0]) else { continue }
                foundPack = true
                if found != season { return true }
            }
        }
        _ = foundPack
        return false
    }

    /// Extracts the show name from the filename (text before the S/E marker),
    /// normalises it, and checks token overlap against the expected show title.
    /// Conservative: only rejects when the filename clearly belongs to another show.
    private static func filenameShowMatches(_ filename: String, showTitle: String, season: Int) -> Bool {
        // Find the position of the first SxxEyy or Sx alone marker in the filename
        let fn = filename.lowercased()
        let episodePatterns = [
            #"\bs\d{1,2}[\s.\-_]*e\d{1,3}"#,
            #"\bs\d{1,2}\b"#,
        ]
        var cutIndex: String.Index? = nil
        for pattern in episodePatterns {
            if let range = fn.range(of: pattern, options: .regularExpression) {
                if cutIndex == nil || range.lowerBound < cutIndex! {
                    cutIndex = range.lowerBound
                }
            }
        }
        guard let cut = cutIndex, cut > fn.startIndex else { return true }

        let filenameShowPart = normaliseForComparison(String(fn[fn.startIndex..<cut]))
        let expectedTokens = titleTokens(showTitle)
        let filenameTokensSet = Set(filenameShowPart.components(separatedBy: .whitespaces).filter { !$0.isEmpty })

        guard !expectedTokens.isEmpty else { return true }

        let hits = expectedTokens.filter { filenameTokensSet.contains($0) }.count
        let ratio = Double(hits) / Double(expectedTokens.count)

        // Require at least 40 % of the show's significant words to appear.
        // Below that we're confident it's a different title.
        return ratio >= 0.4
    }

    /// Validates that a movie filename plausibly matches the expected title + optional year.
    /// Only rejects when we're confident the filename names a different movie.
    private static func filenameMovieMatches(_ filename: String, title: String, year: Int?) -> Bool {
        let fn = normaliseFilenameForTitle(filename)

        // ── Year check ──────────────────────────────────────────────────────
        if let year {
            let yearPattern = #"\b(19|20)(\d{2})\b"#
            let yearsFound = captureGroups(pattern: yearPattern, in: fn).compactMap { groups -> Int? in
                guard groups.count == 2 else { return nil }
                return Int(groups[0] + groups[1])
            }
            // If filename has a year and it's more than 1 year off → wrong movie
            if let foundYear = yearsFound.first, abs(foundYear - year) > 1 { return false }
        }

        // ── Title token match ───────────────────────────────────────────────
        // Isolate the title portion of the filename (before quality / year markers)
        let titlePortion = extractTitlePortion(from: fn, year: year)
        let expectedTokens = titleTokens(title)
        let fileTokensSet = Set(titlePortion.components(separatedBy: .whitespaces).filter { !$0.isEmpty })

        guard !expectedTokens.isEmpty else { return true }

        let hits = expectedTokens.filter { fileTokensSet.contains($0) }.count
        let ratio = Double(hits) / Double(expectedTokens.count)

        // 40 % token overlap required — lenient enough to survive subtitle differences
        // (e.g. "Mission: Impossible – Fallout" vs "Mission Impossible Fallout")
        return ratio >= 0.4
    }

    // MARK: - Text helpers

    private static let stopWords: Set<String> = [
        "the", "a", "an", "of", "in", "and", "to", "for", "at",
        "by", "from", "with", "its", "is", "&", "vs", "part",
    ]

    /// Significant tokens from a human-readable title (lowercase, no stop words, ≥ 2 chars).
    private static func titleTokens(_ title: String) -> [String] {
        title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !stopWords.contains($0) }
    }

    /// Normalize a filename segment for comparison (dots/underscores → spaces, lowercase).
    private static func normaliseForComparison(_ text: String) -> String {
        text.replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
    }

    private static func normaliseFilenameForTitle(_ filename: String) -> String {
        // Strip common extensions
        var fn = filename
        for ext in [".mkv", ".mp4", ".avi", ".mov"] {
            if fn.lowercased().hasSuffix(ext) { fn = String(fn.dropLast(ext.count)) }
        }
        return normaliseForComparison(fn)
    }

    private static let qualityMarkers = [
        "1080p", "720p", "2160p", "4k", "uhd", "fhd", "hd", "sdtv", "pdtv",
        "bluray", "bdrip", "bdremux", "webrip", "web-dl", "webdl", "hdtv",
        "dvdrip", "dvd", "hdrip", "remux", "hevc", "x264", "x265", "h264",
        "h265", "avc", "xvid", "divx",
    ]

    /// Extracts the title portion from a normalised filename string
    /// (everything before the year or first quality marker).
    private static func extractTitlePortion(from normalisedFn: String, year: Int?) -> String {
        var cutAt = normalisedFn.endIndex

        // Cut at year
        if let yearRange = normalisedFn.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) {
            if yearRange.lowerBound < cutAt { cutAt = yearRange.lowerBound }
        }
        // Cut at quality marker
        for marker in qualityMarkers {
            if let r = normalisedFn.range(of: marker) {
                if r.lowerBound < cutAt { cutAt = r.lowerBound }
            }
        }
        return String(normalisedFn[normalisedFn.startIndex..<cutAt])
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Regex utilities

    private static func matches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    private static func captureGroups(pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) }
            }
        }
    }
}
