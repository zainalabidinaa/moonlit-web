import Foundation

/// Maps a streaming service's display name to its TMDB watch-provider id, used
/// to query `/discover/{movie|tv}?with_watch_providers=`. One id space is
/// shared between movies and TV on TMDB, unlike genres.
public enum TMDBProviderIDs {
    private static let mapping: [String: Int] = [
        "netflix": 8,
        "prime video": 119,
        "amazon prime video": 119,
        "apple tv+": 350,
        "apple tv plus": 350,
        "disney+": 337,
        "disney plus": 337,
        "max": 1899,
        "hbo max": 1899,
        "hulu": 15,
        "paramount+": 531,
        "paramount plus": 531,
        "peacock": 386,
        "crunchyroll": 283,
    ]

    public static func id(for serviceName: String) -> Int? {
        mapping[GenreCatalog.normalize(serviceName)]
    }
}
