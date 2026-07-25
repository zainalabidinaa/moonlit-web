import Foundation

public enum StreamSourceType: String, Codable, Sendable {
    case url
    case torrent
    case youtube
    case external
    case playerFrame
    case unknown
}

public struct StreamItem: Codable, Sendable, Identifiable, Hashable {
    public let name: String?
    public let title: String?
    public let description: String?
    public let url: String?
    public let infoHash: String?
    public let fileIdx: Int?
    public let externalUrl: String?
    public let ytId: String?
    public let playerFrameUrl: String?
    public let thumbnail: String?
    public let sources: [String]?
    public let sourceName: String?
    public let addonName: String?
    public let addonId: String?
    public let behaviorHints: StreamBehaviorHints?
    public let subtitles: [SubtitleItem]?

    public var id: String { url ?? infoHash ?? ytId ?? externalUrl ?? playerFrameUrl ?? UUID().uuidString }

    public init(
        name: String? = nil,
        title: String? = nil,
        description: String? = nil,
        url: String? = nil,
        infoHash: String? = nil,
        fileIdx: Int? = nil,
        externalUrl: String? = nil,
        ytId: String? = nil,
        playerFrameUrl: String? = nil,
        thumbnail: String? = nil,
        sources: [String]? = nil,
        sourceName: String? = nil,
        addonName: String? = nil,
        addonId: String? = nil,
        behaviorHints: StreamBehaviorHints? = nil,
        subtitles: [SubtitleItem]? = nil
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.url = url
        self.infoHash = infoHash
        self.fileIdx = fileIdx
        self.externalUrl = externalUrl
        self.ytId = ytId
        self.playerFrameUrl = playerFrameUrl
        self.thumbnail = thumbnail
        self.sources = sources
        self.sourceName = sourceName
        self.addonName = addonName
        self.addonId = addonId
        self.behaviorHints = behaviorHints
        self.subtitles = subtitles
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: StreamItem, rhs: StreamItem) -> Bool {
        lhs.id == rhs.id
    }

    public var displayName: String {
        if let title = title, !title.isEmpty { return title }
        if let name = name, !name.isEmpty { return name }
        if let description = description, !description.isEmpty { return description }
        return sourceName ?? addonName ?? "Unknown"
    }

    public var sourceType: StreamSourceType {
        if ytId != nil { return .youtube }
        if infoHash != nil { return .torrent }
        if externalUrl != nil { return .external }
        if playerFrameUrl != nil { return .playerFrame }
        if url != nil { return .url }
        return .unknown
    }

    public var hasDirectUrl: Bool {
        sourceType == .url
    }

    public var isLocallyPlayable: Bool {
        switch sourceType {
        case .url, .youtube: return true
        case .torrent, .external, .playerFrame, .unknown: return false
        }
    }

    private static let webUnfriendlyAudio = [
        "truehd", "atmos", "dts:x", "dtsx", "dts-hd", "dtshd", "dts",
    ]

    public var isAudioCompatible: Bool {
        let raw = [name, title, description]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        return !Self.webUnfriendlyAudio.contains { raw.contains($0) }
    }

    public var qualityScore: Int {
        let raw = [name, title, description]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        var score = isAudioCompatible ? 100 : 0
        if raw.contains("2160") || raw.contains("4k") { score += 30 }
        if raw.contains("1080") { score += 20 }
        if raw.contains("720") { score += 10 }
        if raw.contains("aac") || raw.contains("eac3") || raw.contains("dd+") { score += 10 }
        if raw.contains("hdr") || raw.contains("dolby vision") || raw.contains("dv") { score += 5 }
        if raw.contains("h265") || raw.contains("hevc") || raw.contains("x265") { score += 5 }
        return score
    }
}

public struct StreamBehaviorHints: Codable, Sendable {
    public let notWebReady: Bool?
    public let bingeGroup: String?
    public let countryWhitelist: [String]?
    public let proxyHeaders: StreamProxyHeaders?
    public let filename: String?
    public let videoHash: String?
    public let videoSize: Int64?
    /// True when the stream is pre-cached and ready for instant playback.
    /// These start instantly — no download or resolution delay needed.
    public let cached: Bool?

    public init(
        notWebReady: Bool? = nil,
        bingeGroup: String? = nil,
        countryWhitelist: [String]? = nil,
        proxyHeaders: StreamProxyHeaders? = nil,
        filename: String? = nil,
        videoHash: String? = nil,
        videoSize: Int64? = nil,
        cached: Bool? = nil
    ) {
        self.notWebReady = notWebReady
        self.bingeGroup = bingeGroup
        self.countryWhitelist = countryWhitelist
        self.proxyHeaders = proxyHeaders
        self.filename = filename
        self.videoHash = videoHash
        self.videoSize = videoSize
        self.cached = cached
    }
}

public struct StreamProxyHeaders: Codable, Sendable {
    public let request: [String: String]?
    public let response: [String: String]?

    public init(request: [String: String]? = nil, response: [String: String]? = nil) {
        self.request = request
        self.response = response
    }
}

public struct SubtitleItem: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let url: String
    public let lang: String
    public let name: String?

    public init(id: String, url: String, lang: String, name: String? = nil) {
        self.id = id
        self.url = url
        self.lang = lang
        self.name = name
    }
}

public struct PlayerLaunch: Codable, Sendable, Identifiable, Hashable {
    public var id: String { videoId }
    public let title: String
    public let sourceUrl: String
    public let sourceHeaders: [String: String]?
    public let sourceResponseHeaders: [String: String]?
    public let sourceContentType: String?
    public let sourceVideoSize: Int64?
    public let logo: String?
    public let poster: String?
    public let episodeThumbnail: String?
    public let background: String?
    public let seasonNumber: Int?
    public let episodeNumber: Int?
    public let streamTitle: String?
    public let providerName: String?
    public let contentType: MediaType
    public let videoId: String
    public let parentMetaId: String?
    public let parentMetaType: String?
    public let initialPositionMs: Double?
    public let subtitles: [SubtitleItem]?

    public init(
        title: String,
        sourceUrl: String,
        sourceHeaders: [String: String]? = nil,
        sourceResponseHeaders: [String: String]? = nil,
        sourceContentType: String? = nil,
        sourceVideoSize: Int64? = nil,
        logo: String? = nil,
        poster: String? = nil,
        episodeThumbnail: String? = nil,
        background: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        streamTitle: String? = nil,
        providerName: String? = nil,
        contentType: MediaType,
        videoId: String,
        parentMetaId: String? = nil,
        parentMetaType: String? = nil,
        initialPositionMs: Double? = nil,
        subtitles: [SubtitleItem]? = nil
    ) {
        self.title = title
        self.sourceUrl = sourceUrl
        self.sourceHeaders = sourceHeaders
        self.sourceResponseHeaders = sourceResponseHeaders
        self.sourceContentType = sourceContentType
        self.sourceVideoSize = sourceVideoSize
        self.logo = logo
        self.poster = poster
        self.episodeThumbnail = episodeThumbnail
        self.background = background
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.streamTitle = streamTitle
        self.providerName = providerName
        self.contentType = contentType
        self.videoId = videoId
        self.parentMetaId = parentMetaId
        self.parentMetaType = parentMetaType
        self.initialPositionMs = initialPositionMs
        self.subtitles = subtitles
    }
}
