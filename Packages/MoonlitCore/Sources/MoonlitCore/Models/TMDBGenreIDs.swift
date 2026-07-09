import Foundation

/// Maps Moonlit's canonical genre names (see `GenreCatalog.canonicalGenres`) to
/// TMDB's genre ids, separately for movies and TV — the two id spaces don't
/// match (e.g. movie "Action" is 28, TV's closest equivalent is "Action &
/// Adventure" at 10759). Some genres have no TV equivalent in TMDB at all
/// (Horror, Romance, Thriller); those resolve to `nil` for `tvId`.
public enum TMDBGenreIDs {
    private struct Mapping { let movieId: Int?; let tvId: Int? }

    private static let mapping: [String: Mapping] = [
        "Action": Mapping(movieId: 28, tvId: 10759),
        "Adventure": Mapping(movieId: 12, tvId: 10759),
        "Animation": Mapping(movieId: 16, tvId: 16),
        "Comedy": Mapping(movieId: 35, tvId: 35),
        "Crime": Mapping(movieId: 80, tvId: 80),
        "Documentary": Mapping(movieId: 99, tvId: 99),
        "Drama": Mapping(movieId: 18, tvId: 18),
        "Family": Mapping(movieId: 10751, tvId: 10751),
        "Fantasy": Mapping(movieId: 14, tvId: 10765),
        "Horror": Mapping(movieId: 27, tvId: nil),
        "Mystery": Mapping(movieId: 9648, tvId: 9648),
        "Romance": Mapping(movieId: 10749, tvId: nil),
        "Sci-Fi": Mapping(movieId: 878, tvId: 10765),
        "Thriller": Mapping(movieId: 53, tvId: nil),
        "War": Mapping(movieId: 10752, tvId: 10768),
        "Western": Mapping(movieId: 37, tvId: 37),
    ]

    /// The TMDB genre id for a canonical genre name and media kind, or `nil`
    /// when unmapped (unknown genre name, or no TV equivalent exists).
    public static func id(for genreName: String, mediaKind: MediaType) -> Int? {
        guard let entry = mapping[genreName] else { return nil }
        return mediaKind == .movie ? entry.movieId : entry.tvId
    }

    /// Canonical genre names in display order for the browse pills.
    public static let canonicalOrder: [String] = [
        "Action", "Adventure", "Animation", "Comedy", "Crime", "Documentary",
        "Drama", "Family", "Fantasy", "Horror", "Mystery", "Romance",
        "Sci-Fi", "Thriller", "War", "Western",
    ]

    /// Genres that actually resolve for a media kind — e.g. Horror/Romance/Thriller
    /// have no TV id, so they're dropped from the Series browse pills.
    public static func availableGenres(for mediaKind: MediaType) -> [String] {
        canonicalOrder.filter { id(for: $0, mediaKind: mediaKind) != nil }
    }
}
