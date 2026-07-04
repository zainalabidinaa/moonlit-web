import Foundation

public struct DBCollection: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let sortOrder: Int
    public let backdropImage: String?
    public let viewMode: String?
    public let showAllTab: Bool?
    public let focusGlowEnabled: Bool?
    public let pinToTop: Bool?
    public let showOnHome: Bool?
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case sortOrder = "sort_order"
        case backdropImage = "backdrop_image"
        case viewMode = "view_mode"
        case showAllTab = "show_all_tab"
        case focusGlowEnabled = "focus_glow_enabled"
        case pinToTop = "pin_to_top"
        case showOnHome = "show_on_home"
        case createdAt = "created_at"
    }

    public init(
        id: String,
        name: String = "",
        sortOrder: Int = 0,
        backdropImage: String? = nil,
        viewMode: String? = nil,
        showAllTab: Bool? = nil,
        focusGlowEnabled: Bool? = nil,
        pinToTop: Bool? = nil,
        showOnHome: Bool? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.backdropImage = backdropImage
        self.viewMode = viewMode
        self.showAllTab = showAllTab
        self.focusGlowEnabled = focusGlowEnabled
        self.pinToTop = pinToTop
        self.showOnHome = showOnHome
        self.createdAt = createdAt
    }
}

public struct DBFolder: Codable, Identifiable, Sendable {
    public let id: String
    public let collectionId: String
    public let name: String
    public let sortOrder: Int
    public let coverImage: String?
    public let focusGif: String?
    public let titleLogo: String?
    public let heroBackdrop: String?
    public let heroVideoUrl: String?
    public let hideTitle: Bool?
    public let tileShape: String?
    public let focusGifEnabled: Bool?
    public let enabled: Bool?
    public let genre: String?
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case collectionId = "collection_id"
        case sortOrder = "sort_order"
        case coverImage = "cover_image"
        case focusGif = "focus_gif"
        case titleLogo = "title_logo"
        case heroBackdrop = "hero_backdrop"
        case heroVideoUrl = "hero_video_url"
        case hideTitle = "hide_title"
        case tileShape = "tile_shape"
        case focusGifEnabled = "focus_gif_enabled"
        case enabled
        case genre
        case createdAt = "created_at"
    }

    public init(
        id: String,
        collectionId: String = "",
        name: String = "",
        sortOrder: Int = 0,
        coverImage: String? = nil,
        focusGif: String? = nil,
        titleLogo: String? = nil,
        heroBackdrop: String? = nil,
        heroVideoUrl: String? = nil,
        hideTitle: Bool? = nil,
        tileShape: String? = nil,
        focusGifEnabled: Bool? = nil,
        enabled: Bool? = nil,
        genre: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.collectionId = collectionId
        self.name = name
        self.sortOrder = sortOrder
        self.coverImage = coverImage
        self.focusGif = focusGif
        self.titleLogo = titleLogo
        self.heroBackdrop = heroBackdrop
        self.heroVideoUrl = heroVideoUrl
        self.hideTitle = hideTitle
        self.tileShape = tileShape
        self.focusGifEnabled = focusGifEnabled
        self.enabled = enabled
        self.genre = genre
        self.createdAt = createdAt
    }
}

public struct DBFolderCatalog: Codable, Identifiable, Sendable {
    public let id: String
    public let folderId: String
    public let catalogId: String
    public let mediaType: String
    public let genre: String?
    /// Additional extras passed as-is to the catalog query URL (e.g. release year ranges).
    public let extras: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id, genre, extras
        case folderId = "folder_id"
        case catalogId = "catalog_id"
        case mediaType = "media_type"
    }

    public init(
        id: String,
        folderId: String = "",
        catalogId: String = "",
        mediaType: String = "",
        genre: String? = nil,
        extras: [String: String]? = nil
    ) {
        self.id = id
        self.folderId = folderId
        self.catalogId = catalogId
        self.mediaType = mediaType
        self.genre = genre
        self.extras = extras
    }
}

public struct DBFolderSource: Codable, Identifiable, Sendable {
    public let id: String
    public let folderId: String
    public let provider: String
    public let title: String?
    public let tmdbId: String?
    public let mediaType: String?
    public let tmdbSourceType: String?
    public let sortBy: String?
    public let filtersJson: String?
    public let rawJson: String?
    public let sortOrder: Int?
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, provider, title
        case folderId = "folder_id"
        case tmdbId = "tmdb_id"
        case mediaType = "media_type"
        case tmdbSourceType = "tmdb_source_type"
        case sortBy = "sort_by"
        case filtersJson = "filters_json"
        case rawJson = "raw_json"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }

    public init(
        id: String,
        folderId: String = "",
        provider: String = "",
        title: String? = nil,
        tmdbId: String? = nil,
        mediaType: String? = nil,
        tmdbSourceType: String? = nil,
        sortBy: String? = nil,
        filtersJson: String? = nil,
        rawJson: String? = nil,
        sortOrder: Int? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.folderId = folderId
        self.provider = provider
        self.title = title
        self.tmdbId = tmdbId
        self.mediaType = mediaType
        self.tmdbSourceType = tmdbSourceType
        self.sortBy = sortBy
        self.filtersJson = filtersJson
        self.rawJson = rawJson
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

public struct CollectionDisplayPreferences: Codable, Sendable, Equatable {
    public let enabledCollectionIds: Set<String>
    public let expandedCollectionIds: Set<String>
    public let hiddenFolderIds: Set<String>

    public init(
        enabledCollectionIds: Set<String>,
        expandedCollectionIds: Set<String>,
        hiddenFolderIds: Set<String>
    ) {
        self.enabledCollectionIds = enabledCollectionIds
        self.expandedCollectionIds = expandedCollectionIds
        self.hiddenFolderIds = hiddenFolderIds
    }
}
