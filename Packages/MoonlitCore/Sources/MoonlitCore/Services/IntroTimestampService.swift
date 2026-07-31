import Foundation

public enum PlaybackSegmentKind: String, Codable, Sendable, CaseIterable {
    case recap, intro, outro
}

public enum PlaybackSegmentSource: String, Codable, Sendable {
    case embedded
    case audioFingerprint
    case jellyfin
    case plex
    case localCorrection
    case skipDB
    case theIntroDB
    case aniSkip
    case introDB
}

public enum PlaybackSegmentMatch: String, Codable, Sendable {
    case exact
    case shifted
    case agnostic
}

public struct PlaybackSegment: Sendable, Equatable {
    public let kind: PlaybackSegmentKind
    public let start: Double
    public let end: Double
    public let confidence: Double
    public let source: PlaybackSegmentSource
    public let match: PlaybackSegmentMatch

    public init(
        kind: PlaybackSegmentKind,
        start: Double,
        end: Double,
        confidence: Double = 1,
        source: PlaybackSegmentSource = .introDB,
        match: PlaybackSegmentMatch = .agnostic
    ) {
        self.kind = kind
        self.start = start
        self.end = end
        self.confidence = confidence
        self.source = source
        self.match = match
    }

    public func contains(_ position: Double) -> Bool {
        position >= start && position < end
    }

    public var isReliable: Bool {
        confidence >= 0.6 && start >= 0 && end > start
    }
}

public extension PlaybackSegment {
    var canSeedAudioFingerprintReference: Bool {
        kind == .intro
            && match == .exact
            && confidence >= 0.8
            && start >= 0
            && (5...240).contains(end - start)
            && [.embedded, .skipDB, .theIntroDB, .localCorrection].contains(source)
    }
}

public struct PlaybackSegments: Sendable, Equatable {
    public let recap: PlaybackSegment?
    public let intro: PlaybackSegment?
    public let outro: PlaybackSegment?

    public init(
        recap: PlaybackSegment? = nil,
        intro: PlaybackSegment? = nil,
        outro: PlaybackSegment? = nil
    ) {
        self.recap = recap
        self.intro = intro
        self.outro = outro
    }

    public var isEmpty: Bool {
        recap == nil && intro == nil && outro == nil
    }

    public func action(at position: Double) -> PlaybackSegment? {
        [recap, intro]
            .compactMap { $0 }
            .first { $0.isReliable && $0.contains(position) }
    }

    /// Chooses one internally-consistent cut instead of averaging or merging
    /// timestamps from unrelated releases.
    public static func preferred(from candidates: [PlaybackSegments]) -> PlaybackSegments? {
        candidates
            .filter { !$0.isEmpty }
            .max { candidateRank($0) < candidateRank($1) }
    }

    public static func fromChapters(
        _ chapters: [PlaybackChapter],
        duration: Double
    ) -> PlaybackSegments? {
        let ordered = chapters
            .filter { $0.start >= 0 }
            .sorted { $0.start < $1.start }
        guard !ordered.isEmpty, duration > 0 else { return nil }

        var found: [PlaybackSegmentKind: PlaybackSegment] = [:]
        for (index, chapter) in ordered.enumerated() {
            guard let kind = chapter.kind else { continue }
            let nextStart = ordered.indices.contains(index + 1)
                ? ordered[index + 1].start
                : duration
            let end = min(max(nextStart, chapter.start), duration)
            let candidate = PlaybackSegment(
                kind: kind,
                start: chapter.start,
                end: end,
                confidence: 0.9,
                source: .embedded,
                match: .exact
            )
            guard candidate.isReliable else { continue }
            found[kind] = candidate
        }

        let segments = PlaybackSegments(
            recap: found[.recap],
            intro: found[.intro],
            outro: found[.outro]
        )
        return segments.isEmpty ? nil : segments
    }

    /// Compatibility decoder for existing callers and fixtures.
    public static func decode(data: Data) throws -> PlaybackSegments {
        try decodeIntroDB(data: data)
    }

    public static func decodeIntroDB(data: Data) throws -> PlaybackSegments {
        let response = try JSONDecoder().decode(IntroDBResponse.self, from: data)

        func segment(_ kind: PlaybackSegmentKind, from item: IntroDBItem?) -> PlaybackSegment? {
            guard let item,
                  item.submissionCount >= 2,
                  (item.confidence ?? 0) >= 0.6 else {
                return nil
            }
            let candidate = PlaybackSegment(
                kind: kind,
                start: item.startMilliseconds / 1_000,
                end: item.endMilliseconds / 1_000,
                confidence: item.confidence ?? 0,
                source: .introDB,
                match: .agnostic
            )
            return candidate.isReliable ? candidate : nil
        }

        return PlaybackSegments(
            recap: segment(.recap, from: response.recap),
            intro: segment(.intro, from: response.intro),
            outro: segment(.outro, from: response.outro)
        )
    }

    public static func decodeSkipDB(data: Data) throws -> PlaybackSegments? {
        let response = try JSONDecoder().decode(SkipDBResponse.self, from: data)

        func segment(_ kind: PlaybackSegmentKind, from item: SkipDBItem?) -> PlaybackSegment? {
            guard let item,
                  item.match != "out-of-range",
                  let match = PlaybackSegmentMatch(rawValue: item.match) else {
                return nil
            }
            let candidate = PlaybackSegment(
                kind: kind,
                start: item.startMilliseconds / 1_000,
                end: item.endMilliseconds / 1_000,
                confidence: item.confidence,
                source: .skipDB,
                match: match
            )
            return candidate.isReliable ? candidate : nil
        }

        let segments = PlaybackSegments(
            recap: segment(.recap, from: response.segments.recap),
            intro: segment(.intro, from: response.segments.intro),
            outro: segment(.outro, from: response.segments.outro)
        )
        return segments.isEmpty ? nil : segments
    }

    public static func skipDBIndicatesCutMismatch(data: Data) throws -> Bool {
        let response = try JSONDecoder().decode(SkipDBResponse.self, from: data)
        return [
            response.segments.intro,
            response.segments.recap,
            response.segments.outro
        ]
            .compactMap { $0 }
            .contains { $0.match == "out-of-range" }
    }

    public static func decodeTheIntroDB(
        data: Data,
        requestedDuration: Double,
        availableDurations: [Double]
    ) throws -> PlaybackSegments? {
        guard requestedDuration > 0,
              availableDurations.contains(where: {
                  $0 > 0 && abs($0 - requestedDuration) <= 2
              }) else {
            return nil
        }

        let response = try JSONDecoder().decode(TheIntroDBResponse.self, from: data)

        func segment(
            _ kind: PlaybackSegmentKind,
            from items: [TheIntroDBItem]?,
            defaultStart: Double? = nil,
            defaultEnd: Double? = nil
        ) -> PlaybackSegment? {
            guard let item = items?.first else { return nil }
            let startMilliseconds = item.startMilliseconds ?? defaultStart.map { $0 * 1_000 }
            let endMilliseconds = item.endMilliseconds ?? defaultEnd.map { $0 * 1_000 }
            guard let startMilliseconds, let endMilliseconds else { return nil }

            let candidate = PlaybackSegment(
                kind: kind,
                start: startMilliseconds / 1_000,
                end: endMilliseconds / 1_000,
                confidence: 0.8,
                source: .theIntroDB,
                match: .exact
            )
            return candidate.isReliable ? candidate : nil
        }

        let segments = PlaybackSegments(
            recap: segment(.recap, from: response.recap, defaultStart: 0),
            intro: segment(.intro, from: response.intro, defaultStart: 0),
            outro: segment(.outro, from: response.credits, defaultEnd: requestedDuration)
        )
        return segments.isEmpty ? nil : segments
    }

    static func decodeTheIntroDBDurations(data: Data) throws -> [Double] {
        let response = try JSONDecoder().decode(TheIntroDBVersionsResponse.self, from: data)
        return response.versions.map { $0.durationMilliseconds / 1_000 }
    }

    private static func candidateRank(_ segments: PlaybackSegments) -> Double {
        let values = [segments.recap, segments.intro, segments.outro].compactMap { $0 }
        let matchRank = values.map {
            switch $0.match {
            case .exact: 3
            case .shifted: 2
            case .agnostic: 1
            }
        }.max() ?? 0
        let sourceRank = values.map {
            switch $0.source {
            case .embedded: 5
            case .audioFingerprint, .jellyfin, .plex, .localCorrection: 4
            case .skipDB: 3
            case .theIntroDB, .aniSkip: 2
            case .introDB: 1
            }
        }.max() ?? 0
        let confidence = values.map(\.confidence).max() ?? 0
        return Double(matchRank * 100 + sourceRank * 10) + confidence
    }
}

public struct PlaybackChapter: Sendable, Equatable {
    public let title: String
    public let start: Double

    public init(title: String, start: Double) {
        self.title = title
        self.start = start
    }

    fileprivate var kind: PlaybackSegmentKind? {
        let normalized = title
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.contains("previously")
            || normalized.contains("recap")
            || normalized.contains("catch-up") {
            return .recap
        }
        if normalized.contains("opening credits")
            || normalized == "opening"
            || normalized.contains("title sequence")
            || normalized == "intro"
            || normalized.hasPrefix("intro ") {
            return .intro
        }
        if normalized.contains("end credits")
            || normalized.contains("closing credits")
            || normalized == "credits"
            || normalized == "outro"
            || normalized.hasPrefix("outro ") {
            return .outro
        }
        return nil
    }
}

public enum PlaybackStreamIdentity {
    /// Produces an opaque, stable identity without retaining signed query values.
    public static func make(
        providerName: String?,
        sourceURL: String,
        sourceSize: Int64?,
        streamTitle: String?
    ) -> String {
        let components = URLComponents(string: sourceURL)
        let sourcePath = [
            components?.scheme?.lowercased(),
            components?.host?.lowercased(),
            components?.port.map(String.init),
            components?.path
        ]
            .compactMap { $0 }
            .joined(separator: "|")
        let input = [
            providerName?.lowercased() ?? "",
            sourcePath,
            sourceSize.map(String.init) ?? "",
            streamTitle?.lowercased() ?? ""
        ].joined(separator: "|")

        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

public struct PlaybackSegmentRequest: Sendable, Equatable {
    public let imdbId: String
    public let tmdbId: Int?
    public let season: Int
    public let episode: Int
    public let duration: Double
    public let streamIdentity: String

    public init(
        imdbId: String,
        tmdbId: Int? = nil,
        season: Int,
        episode: Int,
        duration: Double,
        streamIdentity: String
    ) {
        self.imdbId = imdbId
        self.tmdbId = tmdbId
        self.season = season
        self.episode = episode
        self.duration = duration
        self.streamIdentity = streamIdentity
    }

    public var cacheKey: String {
        let durationBucket = Int(duration.rounded())
        return [
            imdbId,
            "s\(String(format: "%02d", season))e\(String(format: "%02d", episode))",
            "d\(durationBucket)",
            streamIdentity
        ].joined(separator: ":")
    }

    fileprivate func with(tmdbId: Int?) -> PlaybackSegmentRequest {
        PlaybackSegmentRequest(
            imdbId: imdbId,
            tmdbId: tmdbId,
            season: season,
            episode: episode,
            duration: duration,
            streamIdentity: streamIdentity
        )
    }
}

@MainActor
public final class IntroTimestampService {
    public static let shared = IntroTimestampService()

    private enum CacheEntry {
        case value(PlaybackSegments)
        case missing
    }

    private enum ProviderResult {
        case segments(PlaybackSegments)
        case cutMismatch
        case missing
    }

    private let client: PlaybackSegmentHTTPClient
    private var cache: [String: CacheEntry] = [:]

    private init() {
        client = PlaybackSegmentHTTPClient()
    }

    public func segments(
        request: PlaybackSegmentRequest,
        exactSegments: PlaybackSegments? = nil
    ) async -> PlaybackSegments? {
        if let exactSegments, !exactSegments.isEmpty {
            return exactSegments
        }
        guard VideoPlayerPreferenceStore.shared.useIntroDB else { return nil }

        if let cached = cache[request.cacheKey] {
            switch cached {
            case .value(let segments): return segments
            case .missing: return nil
            }
        }

        let resolvedTMDBId: Int?
        if let tmdbId = request.tmdbId {
            resolvedTMDBId = tmdbId
        } else {
            resolvedTMDBId = await resolveTMDBId(for: request.imdbId)
        }
        let resolvedRequest = request.with(tmdbId: resolvedTMDBId)
        let result: PlaybackSegments?
        switch await fetchDurationAwareSegments(request: resolvedRequest) {
        case .segments(let durationAware):
            result = durationAware
        case .cutMismatch:
            result = nil
        case .missing:
            result = await fetchIntroDBFallback(request: resolvedRequest)
        }

        cache[request.cacheKey] = result.map(CacheEntry.value) ?? .missing
        return result
    }

    /// Retained for older callers. New playback code should wait for MPV's
    /// duration and use `segments(request:)` so different cuts cannot share cache.
    public func segments(imdbId: String, season: Int, episode: Int) async -> PlaybackSegments? {
        let request = PlaybackSegmentRequest(
            imdbId: imdbId,
            season: season,
            episode: episode,
            duration: 0,
            streamIdentity: "episode-only"
        )
        return await fetchIntroDBFallback(request: request)
    }

    public func clearCache() {
        cache.removeAll()
    }

    private func fetchDurationAwareSegments(
        request: PlaybackSegmentRequest
    ) async -> ProviderResult {
        guard request.duration > 0 else { return .missing }

        switch await fetchSkipDB(request: request) {
        case .segments(let segments):
            return .segments(segments)
        case .cutMismatch:
            return .cutMismatch
        case .missing:
            break
        }
        switch await fetchTheIntroDB(request: request) {
        case .segments(let segments):
            return .segments(segments)
        case .cutMismatch:
            return .cutMismatch
        case .missing:
            return .missing
        }
    }

    private func fetchSkipDB(request: PlaybackSegmentRequest) async -> ProviderResult {
        var components = URLComponents(string: "https://api.skipdb.tv/api/segments")
        components?.queryItems = [
            .init(name: "imdb_id", value: request.imdbId),
            .init(name: "season", value: String(request.season)),
            .init(name: "episode", value: String(request.episode)),
            .init(name: "duration", value: String(Int(request.duration.rounded()))),
            .init(name: "adjust", value: "conservative")
        ]
        guard let url = components?.url,
              let data = await client.successfulData(from: url) else {
            return .missing
        }
        if (try? PlaybackSegments.skipDBIndicatesCutMismatch(data: data)) == true {
            return .cutMismatch
        }
        guard let segments = try? PlaybackSegments.decodeSkipDB(data: data) else {
            return .missing
        }
        return .segments(segments)
    }

    private func fetchTheIntroDB(request: PlaybackSegmentRequest) async -> ProviderResult {
        guard let tmdbId = request.tmdbId else { return .missing }

        var versionsComponents = URLComponents(string: "https://api.theintrodb.org/v3/media")
        versionsComponents?.queryItems = [
            .init(name: "tmdb_id", value: String(tmdbId)),
            .init(name: "season", value: String(request.season)),
            .init(name: "episode", value: String(request.episode)),
            .init(name: "duration_ms", value: String(Int((request.duration * 1_000).rounded()))),
            .init(name: "list_versions", value: "true")
        ]
        guard let versionsURL = versionsComponents?.url,
              let versionsData = await client.successfulData(from: versionsURL),
              let durations = try? PlaybackSegments.decodeTheIntroDBDurations(data: versionsData) else {
            return .missing
        }
        let positiveDurations = durations.filter { $0 > 0 }
        guard positiveDurations.contains(where: { abs($0 - request.duration) <= 2 }) else {
            return positiveDurations.isEmpty ? .missing : .cutMismatch
        }

        var segmentsComponents = URLComponents(string: "https://api.theintrodb.org/v3/media")
        segmentsComponents?.queryItems = [
            .init(name: "tmdb_id", value: String(tmdbId)),
            .init(name: "season", value: String(request.season)),
            .init(name: "episode", value: String(request.episode)),
            .init(name: "duration_ms", value: String(Int((request.duration * 1_000).rounded())))
        ]
        guard let segmentsURL = segmentsComponents?.url,
              let segmentsData = await client.successfulData(from: segmentsURL) else {
            return .missing
        }
        guard let segments = try? PlaybackSegments.decodeTheIntroDB(
            data: segmentsData,
            requestedDuration: request.duration,
            availableDurations: durations
        ) else {
            return .missing
        }
        return .segments(segments)
    }

    private func fetchIntroDBFallback(
        request: PlaybackSegmentRequest
    ) async -> PlaybackSegments? {
        var components = URLComponents(string: "https://api.introdb.app/segments")
        components?.queryItems = [
            .init(name: "imdb_id", value: request.imdbId),
            .init(name: "season", value: String(request.season)),
            .init(name: "episode", value: String(request.episode))
        ]
        guard let url = components?.url,
              let data = await client.successfulData(from: url),
              let segments = try? PlaybackSegments.decodeIntroDB(data: data),
              !segments.isEmpty else {
            return nil
        }
        return segments
    }

    private func resolveTMDBId(for imdbId: String) async -> Int? {
        guard let key = MetadataIntegrationStore.shared.effectiveTMDBAPIKey,
              !key.isEmpty else {
            return nil
        }
        var components = URLComponents(
            string: "https://api.themoviedb.org/3/find/\(imdbId)"
        )
        components?.queryItems = [
            .init(name: "api_key", value: key),
            .init(name: "external_source", value: "imdb_id")
        ]
        guard let url = components?.url,
              let data = await client.successfulData(from: url),
              let response = try? JSONDecoder().decode(TMDBFindResponse.self, from: data) else {
            return nil
        }
        return response.tvResults.first?.id ?? response.movieResults.first?.id
    }
}

@MainActor
private final class PlaybackSegmentHTTPClient {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 6
        session = URLSession(configuration: configuration)
    }

    func successfulData(from url: URL) async -> Data? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }
}

private struct IntroDBResponse: Decodable {
    let intro: IntroDBItem?
    let recap: IntroDBItem?
    let outro: IntroDBItem?
}

private struct IntroDBItem: Decodable {
    let startMilliseconds: Double
    let endMilliseconds: Double
    let confidence: Double?
    let submissionCount: Int

    enum CodingKeys: String, CodingKey {
        case startMilliseconds = "start_ms"
        case endMilliseconds = "end_ms"
        case confidence
        case submissionCount = "submission_count"
    }
}

private struct SkipDBResponse: Decodable {
    let segments: SkipDBSegments
}

private struct SkipDBSegments: Decodable {
    let intro: SkipDBItem?
    let recap: SkipDBItem?
    let outro: SkipDBItem?
}

private struct SkipDBItem: Decodable {
    let startMilliseconds: Double
    let endMilliseconds: Double
    let match: String
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case startMilliseconds = "start_ms"
        case endMilliseconds = "end_ms"
        case match
        case confidence
    }
}

private struct TheIntroDBResponse: Decodable {
    let intro: [TheIntroDBItem]?
    let recap: [TheIntroDBItem]?
    let credits: [TheIntroDBItem]?
}

private struct TheIntroDBItem: Decodable {
    let startMilliseconds: Double?
    let endMilliseconds: Double?

    enum CodingKeys: String, CodingKey {
        case startMilliseconds = "start_ms"
        case endMilliseconds = "end_ms"
    }
}

private struct TheIntroDBVersionsResponse: Decodable {
    let versions: [TheIntroDBVersion]
}

private struct TheIntroDBVersion: Decodable {
    let durationMilliseconds: Double

    enum CodingKeys: String, CodingKey {
        case durationMilliseconds = "duration_ms"
    }
}

private struct TMDBFindResponse: Decodable {
    let tvResults: [TMDBFindItem]
    let movieResults: [TMDBFindItem]

    enum CodingKeys: String, CodingKey {
        case tvResults = "tv_results"
        case movieResults = "movie_results"
    }
}

private struct TMDBFindItem: Decodable {
    let id: Int
}
