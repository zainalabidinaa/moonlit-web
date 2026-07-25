import Foundation

public struct WatchProgressEntry: Codable, Sendable, Identifiable {
    public let id: String
    public let profileId: String
    public let mediaId: String
    public let mediaType: String
    public let positionSeconds: Double
    public let durationSeconds: Double
    public let completed: Bool
    public let updatedAt: Date
    public let name: String?
    public let poster: String?
    public let parentMetaId: String?
    public let season: Int?
    public let episode: Int?

    enum CodingKeys: String, CodingKey {
        case id, completed, name, poster, season, episode
        case profileId = "profile_id"
        case mediaId = "media_id"
        case mediaType = "media_type"
        case positionSeconds = "position_seconds"
        case durationSeconds = "duration_seconds"
        case updatedAt = "updated_at"
        case parentMetaId = "parent_meta_id"
    }

    public var progressFraction: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(positionSeconds / durationSeconds, 1.0)
    }

    public init(
        id: String,
        profileId: String,
        mediaId: String,
        mediaType: String,
        positionSeconds: Double = 0,
        durationSeconds: Double = 0,
        completed: Bool = false,
        updatedAt: Date = Date(),
        name: String? = nil,
        poster: String? = nil,
        parentMetaId: String? = nil,
        season: Int? = nil,
        episode: Int? = nil
    ) {
        self.id = id
        self.profileId = profileId
        self.mediaId = mediaId
        self.mediaType = mediaType
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.completed = completed
        self.updatedAt = updatedAt
        self.name = name
        self.poster = poster
        self.parentMetaId = parentMetaId
        self.season = season
        self.episode = episode
    }
}

public extension WatchProgressEntry {
    var decodedMediaId: String {
        mediaId.removingPercentEncoding ?? mediaId
    }

    var parentOrSelfMediaId: String {
        if let parentMetaId, !parentMetaId.isEmpty {
            return parentMetaId
        }
        return decodedMediaId.split(separator: ":").first.map(String.init) ?? decodedMediaId
    }

    var inferredSeason: Int? {
        season ?? decodedMediaId.split(separator: ":").dropFirst().first.flatMap { Int($0) }
    }

    var inferredEpisode: Int? {
        episode ?? decodedMediaId.split(separator: ":").dropFirst(2).first.flatMap { Int($0) }
    }

    var thumbnailFallbackForContinueWatching: String? {
        guard inferredSeason != nil || inferredEpisode != nil else { return nil }
        return poster
    }

    func matchesMedia(id: String) -> Bool {
        let decodedId = id.removingPercentEncoding ?? id
        return decodedMediaId == decodedId || parentOrSelfMediaId == decodedId
    }
}

public struct ContinueWatchingItem: Codable, Sendable, Identifiable {
    public let mediaId: String
    public let parentMediaId: String?
    public let mediaType: String
    public let name: String
    public let poster: String?
    public let logo: String?
    public let background: String?
    public let resumePositionMs: Double
    public let durationMs: Double
    public let progressFraction: Double
    public let seasonNumber: Int?
    public let episodeNumber: Int?
    public let episodeTitle: String?
    public let thumbnail: String?
    /// True when this card represents the next episode of a finished series
    /// rather than an in-progress watch — the episode has aired but hasn't
    /// been started yet, so there's nothing to resume. Computed client-side
    /// by `HomeRepository.loadUpNextAndUpcoming`, never synced.
    public let isUpNext: Bool
    /// True when this card represents a finished series' next episode that
    /// hasn't aired yet. Mutually exclusive with `isUpNext`.
    public let isUpcoming: Bool
    /// Air date for the upcoming episode, only set when `isUpcoming` is true.
    public let upcomingAirsAt: Date?

    enum CodingKeys: String, CodingKey {
        case name, poster, logo, background, thumbnail
        case mediaId = "media_id"
        case parentMediaId = "parent_media_id"
        case mediaType = "media_type"
        case resumePositionMs = "resume_position_ms"
        case durationMs = "duration_ms"
        case progressFraction = "progress_fraction"
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case episodeTitle = "episode_title"
        case isUpNext = "is_up_next"
        case isUpcoming = "is_upcoming"
        case upcomingAirsAt = "upcoming_airs_at"
    }

    public var id: String { mediaId }

    public init(
        mediaId: String,
        parentMediaId: String? = nil,
        mediaType: String,
        name: String,
        poster: String? = nil,
        logo: String? = nil,
        background: String? = nil,
        resumePositionMs: Double = 0,
        durationMs: Double = 0,
        progressFraction: Double = 0,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeTitle: String? = nil,
        thumbnail: String? = nil,
        isUpNext: Bool = false,
        isUpcoming: Bool = false,
        upcomingAirsAt: Date? = nil
    ) {
        self.mediaId = mediaId
        self.parentMediaId = parentMediaId
        self.mediaType = mediaType
        self.name = name
        self.poster = poster
        self.logo = logo
        self.background = background
        self.resumePositionMs = resumePositionMs
        self.durationMs = durationMs
        self.progressFraction = progressFraction
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.episodeTitle = episodeTitle
        self.thumbnail = thumbnail
        self.isUpNext = isUpNext
        self.isUpcoming = isUpcoming
        self.upcomingAirsAt = upcomingAirsAt
    }
}

public struct WatchedItem: Codable, Sendable, Identifiable {
    public let id: String
    public let profileId: String
    public let mediaId: String
    public let mediaType: String
    public let name: String?
    public let poster: String?
    public let season: Int?
    public let episode: Int?
    public let markedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, poster, season, episode
        case profileId = "profile_id"
        case mediaId = "media_id"
        case mediaType = "media_type"
        case markedAt = "marked_at"
    }

    public init(
        id: String,
        profileId: String,
        mediaId: String,
        mediaType: String,
        name: String? = nil,
        poster: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        markedAt: Date = Date()
    ) {
        self.id = id
        self.profileId = profileId
        self.mediaId = mediaId
        self.mediaType = mediaType
        self.name = name
        self.poster = poster
        self.season = season
        self.episode = episode
        self.markedAt = markedAt
    }
}

public struct LibraryItem: Codable, Sendable, Identifiable {
    public let id: String
    public let profileId: String
    public let mediaId: String
    public let mediaType: String
    public let name: String?
    public let poster: String?
    public let banner: String?
    public let savedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, poster, banner
        case profileId = "profile_id"
        case mediaId = "media_id"
        case mediaType = "media_type"
        case savedAt = "saved_at"
    }

    public init(
        id: String,
        profileId: String,
        mediaId: String,
        mediaType: String,
        name: String? = nil,
        poster: String? = nil,
        banner: String? = nil,
        savedAt: Date = Date()
    ) {
        self.id = id
        self.profileId = profileId
        self.mediaId = mediaId
        self.mediaType = mediaType
        self.name = name
        self.poster = poster
        self.banner = banner
        self.savedAt = savedAt
    }
}

public struct InviteCode: Codable, Sendable, Identifiable {
    public let code: String
    public let createdBy: String
    public let usedBy: String?
    public let usedAt: Date?
    public let createdAt: Date
    public let maxUses: Int
    public let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case code
        case createdBy = "created_by"
        case usedBy = "used_by"
        case usedAt = "used_at"
        case createdAt = "created_at"
        case maxUses = "max_uses"
        case isActive = "is_active"
    }

    public var id: String { code }

    public init(
        code: String,
        createdBy: String,
        usedBy: String? = nil,
        usedAt: Date? = nil,
        createdAt: Date = Date(),
        maxUses: Int = 1,
        isActive: Bool = true
    ) {
        self.code = code
        self.createdBy = createdBy
        self.usedBy = usedBy
        self.usedAt = usedAt
        self.createdAt = createdAt
        self.maxUses = maxUses
        self.isActive = isActive
    }

    public var isUsed: Bool { usedBy != nil }
}

public struct AdminStats: Codable, Sendable {
    public let totalUsers: Int
    public let totalProfiles: Int
    public let activeInviteCodes: Int
    public let totalWatchlistItems: Int
    public let totalWatchedItems: Int
    public let activeUsers: Int

    enum CodingKeys: String, CodingKey {
        case totalUsers = "total_users"
        case totalProfiles = "total_profiles"
        case activeInviteCodes = "active_invite_codes"
        case totalWatchlistItems = "total_watchlist_items"
        case totalWatchedItems = "total_watched_items"
        case activeUsers = "active_users"
    }

    public init(
        totalUsers: Int = 0,
        totalProfiles: Int = 0,
        activeInviteCodes: Int = 0,
        totalWatchlistItems: Int = 0,
        totalWatchedItems: Int = 0,
        activeUsers: Int = 0
    ) {
        self.totalUsers = totalUsers
        self.totalProfiles = totalProfiles
        self.activeInviteCodes = activeInviteCodes
        self.totalWatchlistItems = totalWatchlistItems
        self.totalWatchedItems = totalWatchedItems
        self.activeUsers = activeUsers
    }
}
