import Foundation

/// Tab contexts that a collection can be flagged to appear in.
public enum CollectionTab: String, Sendable, Hashable {
    case home
    case movies
    case series
}

public struct DBCollection: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let sortOrder: Int
    public let backdropImage: String?
    public let viewMode: String?
    public let showAllTab: Bool?
    public let focusGlowEnabled: Bool?
    public let pinToTop: Bool?
    public let showOnHome: Bool?
    public let showIosHome: Bool?
    public let showIosMovies: Bool?
    public let showIosSeries: Bool?
    public let showMacHome: Bool?
    public let showMacMovies: Bool?
    public let showMacSeries: Bool?
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
        case showIosHome = "show_ios_home"
        case showIosMovies = "show_ios_movies"
        case showIosSeries = "show_ios_series"
        case showMacHome = "show_mac_home"
        case showMacMovies = "show_mac_movies"
        case showMacSeries = "show_mac_series"
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
        showIosHome: Bool? = nil,
        showIosMovies: Bool? = nil,
        showIosSeries: Bool? = nil,
        showMacHome: Bool? = nil,
        showMacMovies: Bool? = nil,
        showMacSeries: Bool? = nil,
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
        self.showIosHome = showIosHome
        self.showIosMovies = showIosMovies
        self.showIosSeries = showIosSeries
        self.showMacHome = showMacHome
        self.showMacMovies = showMacMovies
        self.showMacSeries = showMacSeries
        self.createdAt = createdAt
    }

    /// Whether this collection should appear in the given tab on the current platform.
    /// Legacy layouts (no per-tab flags) fall back to `showOnHome` for the home tab.
    public func isVisible(in tab: CollectionTab) -> Bool {
        #if os(macOS)
        let flag: Bool?
        switch tab {
        case .home:   flag = showMacHome
        case .movies: flag = showMacMovies
        case .series: flag = showMacSeries
        }
        #else
        let flag: Bool?
        switch tab {
        case .home:   flag = showIosHome
        case .movies: flag = showIosMovies
        case .series: flag = showIosSeries
        }
        #endif
        if let flag { return flag }
        switch tab {
        case .home: return showOnHome ?? true
        case .movies, .series: return false
        }
    }

    /// A copy of this collection carrying the other collection's per-tab
    /// visibility flags (where set). Used by the organizer merge when the base
    /// subtree wins on content but the overlay holds the portal's tab settings.
    public func adoptingVisibilityFlags(from other: DBCollection) -> DBCollection {
        DBCollection(
            id: id,
            name: name,
            sortOrder: sortOrder,
            backdropImage: backdropImage,
            viewMode: viewMode,
            showAllTab: showAllTab,
            focusGlowEnabled: focusGlowEnabled,
            pinToTop: pinToTop,
            showOnHome: other.showOnHome ?? showOnHome,
            showIosHome: other.showIosHome ?? showIosHome,
            showIosMovies: other.showIosMovies ?? showIosMovies,
            showIosSeries: other.showIosSeries ?? showIosSeries,
            showMacHome: other.showMacHome ?? showMacHome,
            showMacMovies: other.showMacMovies ?? showMacMovies,
            showMacSeries: other.showMacSeries ?? showMacSeries,
            createdAt: createdAt
        )
    }
}

public struct DBFolder: Codable, Identifiable, Sendable, Equatable {
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

public struct DBFolderCatalog: Codable, Identifiable, Sendable, Equatable {
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

public struct DBFolderSource: Codable, Identifiable, Sendable, Equatable {
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
