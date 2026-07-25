import Foundation

/// Builds TMDB `/discover` query parameters for titles that have not been
/// released yet — used as the paywall marquee's fallback content when a user
/// has an empty library. Kept as a pure function (no networking) so the
/// query-building logic is unit-testable without hitting TMDB.
public enum UpcomingReleasesQuery {
    public static func parameters(mediaKind: MediaType, today: String) -> [String: String] {
        let dateField = mediaKind == .movie ? "primary_release_date" : "first_air_date"
        return [
            "sort_by": "\(dateField).asc",
            "\(dateField).gte": today,
            "vote_count.gte": "5",
        ]
    }
}
