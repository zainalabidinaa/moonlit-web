import Foundation

public enum MediaType: String, Codable, Sendable, CaseIterable {
    case movie = "movie"
    case series = "series"
    case channel = "channel"
    case tv = "tv"
}

/// What a folder-tile count badge is counting, so the label can read
/// "FILMS" / "SHOWS" (loaded leaf folders) or "COLLECTIONS" (franchise bundles
/// whose contents haven't been fetched yet).
public enum CountKind: String, Codable, Sendable {
    case films
    case shows
    case collections
}

public struct MetaPreview: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let type: MediaType
    public let name: String
    public let poster: String?
    public let banner: String?
    public let logo: String?
    public let posterShape: PosterShape?
    /// Clean backdrop art (e.g. a folder's heroBackdrop) for tiles that render their
    /// own title/badge overlay instead of baked-in cover typography.
    public let backdrop: String?
    /// Number of items behind a folder tile, when the folder is fully loaded.
    public let itemCount: Int?
    /// What `itemCount` represents on a folder tile (films / shows / collections).
    public let countKind: CountKind?
    public let description: String?
    public let releaseInfo: String?
    public let rawReleaseDate: String?
    public let released: String?
    public let runtime: String?
    public let popularity: Double?
    public let voteCount: Int?
    public let imdbRating: String?
    public let genres: [String]?
    public let status: String?
    public let behaviorHints: BehaviorHints?
    public let rankHint: Int?
    public let trailerStreams: [StreamItem]?
    public let focusGif: String?
    public let focusGifEnabled: Bool?

    public init(
        id: String,
        type: MediaType,
        name: String,
        poster: String? = nil,
        banner: String? = nil,
        logo: String? = nil,
        posterShape: PosterShape? = nil,
        backdrop: String? = nil,
        itemCount: Int? = nil,
        countKind: CountKind? = nil,
        description: String? = nil,
        releaseInfo: String? = nil,
        rawReleaseDate: String? = nil,
        released: String? = nil,
        runtime: String? = nil,
        popularity: Double? = nil,
        voteCount: Int? = nil,
        imdbRating: String? = nil,
        genres: [String]? = nil,
        status: String? = nil,
        behaviorHints: BehaviorHints? = nil,
        rankHint: Int? = nil,
        trailerStreams: [StreamItem]? = nil,
        focusGif: String? = nil,
        focusGifEnabled: Bool? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.poster = poster
        self.banner = banner
        self.logo = logo
        self.posterShape = posterShape
        self.backdrop = backdrop
        self.itemCount = itemCount
        self.countKind = countKind
        self.description = description
        self.releaseInfo = releaseInfo
        self.rawReleaseDate = rawReleaseDate
        self.released = released
        self.runtime = runtime
        self.popularity = popularity
        self.voteCount = voteCount
        self.imdbRating = imdbRating
        self.genres = genres
        self.status = status
        self.behaviorHints = behaviorHints
        self.rankHint = rankHint
        self.trailerStreams = trailerStreams
        self.focusGif = focusGif
        self.focusGifEnabled = focusGifEnabled
    }
}

public struct BehaviorHints: Codable, Sendable, Hashable {
    public let defaultVideoId: String?
    public let hasScheduledVideos: Bool?
}



public enum PosterShape: String, Codable, Sendable {
    case poster
    case square
    case landscape
}

public struct MetaDetail: Codable, Sendable, Identifiable {
    public let id: String
    public let type: MediaType
    public let name: String
    public let poster: String?
    public let rawPosterUrl: String?
    public let background: String?
    public let logo: String?
    public let description: String?
    public let releaseInfo: String?
    public let status: String?
    public let imdbRating: String?
    public let ageRating: String?
    public let runtime: String?
    public let genres: [String]?
    public let director: [Person]?
    public let writer: [Person]?
    public let cast: [Person]?
    public let trailers: [Trailer]?
    public let trailerStreams: [StreamItem]?
    public let videos: [MetaVideo]?
    public let seasons: [Season]?
    public let links: [MetaLink]?
    public let moreLikeThis: [MetaPreview]?
    public let collectionItems: [MetaPreview]?

    public init(
        id: String,
        type: MediaType,
        name: String,
        poster: String? = nil,
        rawPosterUrl: String? = nil,
        background: String? = nil,
        logo: String? = nil,
        description: String? = nil,
        releaseInfo: String? = nil,
        status: String? = nil,
        imdbRating: String? = nil,
        ageRating: String? = nil,
        runtime: String? = nil,
        genres: [String]? = nil,
        director: [Person]? = nil,
        writer: [Person]? = nil,
        cast: [Person]? = nil,
        trailers: [Trailer]? = nil,
        trailerStreams: [StreamItem]? = nil,
        videos: [MetaVideo]? = nil,
        seasons: [Season]? = nil,
        links: [MetaLink]? = nil,
        moreLikeThis: [MetaPreview]? = nil,
        collectionItems: [MetaPreview]? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.poster = poster
        self.rawPosterUrl = rawPosterUrl
        self.background = background
        self.logo = logo
        self.description = description
        self.releaseInfo = releaseInfo
        self.status = status
        self.imdbRating = imdbRating
        self.ageRating = ageRating
        self.runtime = runtime
        self.genres = genres
        self.director = director
        self.writer = writer
        self.cast = cast
        self.trailers = trailers
        self.trailerStreams = trailerStreams
        self.videos = videos
        self.seasons = seasons
        self.links = links
        self.moreLikeThis = moreLikeThis
        self.collectionItems = collectionItems
    }

    enum CodingKeys: String, CodingKey {
        case id, type, name, poster, background, logo, description, releaseInfo
        case status, imdbRating, ageRating, runtime, genres, director, writer, cast
        case trailers, trailerStreams, videos, seasons, links, moreLikeThis, collectionItems
        case rawPosterUrl = "_rawPosterUrl"
    }
}

public struct Season: Codable, Sendable, Identifiable {
    public let id: String
    public let number: Int
    public let name: String?
    public let poster: String?
    public let episodes: [MetaVideo]?

    public init(
        id: String,
        number: Int,
        name: String? = nil,
        poster: String? = nil,
        episodes: [MetaVideo]? = nil
    ) {
        self.id = id
        self.number = number
        self.name = name
        self.poster = poster
        self.episodes = episodes
    }
}

public struct MetaVideo: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let released: String?
    public let thumbnail: String?
    public let season: Int?
    public let episode: Int?
    public let overview: String?
    public let runtime: String?
    public let streams: [StreamItem]?
    public let trailerStreams: [StreamItem]?

    public init(
        id: String,
        title: String,
        released: String? = nil,
        thumbnail: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        overview: String? = nil,
        runtime: String? = nil,
        streams: [StreamItem]? = nil,
        trailerStreams: [StreamItem]? = nil
    ) {
        self.id = id
        self.title = title
        self.released = released
        self.thumbnail = thumbnail
        self.season = season
        self.episode = episode
        self.overview = overview
        self.runtime = runtime
        self.streams = streams
        self.trailerStreams = trailerStreams
    }
}

public struct Person: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let photo: String?
    public let character: String?

    public init(id: String, name: String, photo: String? = nil, character: String? = nil) {
        self.id = id
        self.name = name
        self.photo = photo
        self.character = character
    }
}

public struct Trailer: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String?
    public let thumbnail: String?
    public let youtubeId: String?

    public init(id: String, title: String? = nil, thumbnail: String? = nil, youtubeId: String? = nil) {
        self.id = id
        self.title = title
        self.thumbnail = thumbnail
        self.youtubeId = youtubeId
    }
}

public struct MetaLink: Codable, Sendable, Identifiable {
    public let name: String
    public let category: String?
    public let url: String

    public var id: String { url }

    public init(name: String, category: String? = nil, url: String) {
        self.name = name
        self.category = category
        self.url = url
    }
}

public struct CatalogRow: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public var items: [MetaPreview]
    public let addonName: String?
    public let addonId: String?
    public var page: Int
    public var hasMore: Bool

    public let tileShape: String?
    public let coverImage: String?
    public let focusGif: String?
    public let focusGifEnabled: Bool?
    public let titleLogo: String?
    public let heroBackdrop: String?
    public let heroVideoURL: String?
    public let hideTitle: Bool?
    public let focusGlowEnabled: Bool?
    public let viewMode: String?
    public let showAllTab: Bool?
    public let pinToTop: Bool?
    public let backdropImage: String?
    /// How many sources/sub-collections a folder has, known from its metadata
    /// before any items are fetched. Lets a group tile show a "N COLLECTIONS"
    /// badge for franchise bundles without loading their contents.
    public let sourceCount: Int?

    public init(
        id: String,
        title: String,
        items: [MetaPreview],
        addonName: String? = nil,
        addonId: String? = nil,
        page: Int = 0,
        hasMore: Bool = false,
        tileShape: String? = nil,
        coverImage: String? = nil,
        focusGif: String? = nil,
        focusGifEnabled: Bool? = nil,
        titleLogo: String? = nil,
        heroBackdrop: String? = nil,
        heroVideoURL: String? = nil,
        hideTitle: Bool? = nil,
        focusGlowEnabled: Bool? = nil,
        viewMode: String? = nil,
        showAllTab: Bool? = nil,
        pinToTop: Bool? = nil,
        backdropImage: String? = nil,
        sourceCount: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.items = items
        self.addonName = addonName
        self.addonId = addonId
        self.page = page
        self.hasMore = hasMore
        self.tileShape = tileShape
        self.coverImage = coverImage
        self.focusGif = focusGif
        self.focusGifEnabled = focusGifEnabled
        self.titleLogo = titleLogo
        self.heroBackdrop = heroBackdrop
        self.heroVideoURL = heroVideoURL
        self.hideTitle = hideTitle
        self.focusGlowEnabled = focusGlowEnabled
        self.viewMode = viewMode
        self.showAllTab = showAllTab
        self.pinToTop = pinToTop
        self.backdropImage = backdropImage
        self.sourceCount = sourceCount
    }
}
