import Foundation

/// Central poster provider — all collections use the btttr "BetterPosters" service
/// for items with a plain IMDb id. Which badges appear (trend / quality / genre /
/// rating / age) is user-configurable via `moonlit.poster.*` `UserDefaults` keys,
/// read synchronously here so this stays callable from non-isolated contexts
/// (e.g. `CatalogRepository`'s background task group).
public enum PosterService {
    public enum Key {
        public static let trend   = "moonlit.poster.trend"
        public static let genre   = "moonlit.poster.genre"
        public static let rating  = "moonlit.poster.rating"
        public static let quality = "moonlit.poster.quality"
        public static let age     = "moonlit.poster.age"
    }

    /// Registers the default badge set (Genre + Rating + Trend on) so a fresh
    /// install — where `bool(forKey:)` would otherwise return `false` — resolves to
    /// the same defaults the SwiftUI `@AppStorage` toggles declare. Call once at launch.
    public static func registerDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            Key.trend:   true,
            Key.genre:   true,
            Key.rating:  true,
            Key.quality: false,
            Key.age:     false,
        ])
    }

    /// Returns the btttr poster URL for a plain IMDb id ("tt1234567"), built from the
    /// user's current badge configuration. Returns `nil` for non-IMDb ids (episode
    /// ids like "tt1:1:2", tmdb ids, etc.) so callers fall back to their own art.
    public static func posterURL(forImdbId id: String?, defaults: UserDefaults = .standard) -> String? {
        guard let id,
              id.hasPrefix("tt"),
              id.count > 2,
              id.dropFirst(2).allSatisfy(\.isNumber) else { return nil }
        return PosterBadgeConfig(defaults: defaults).url(forImdbId: id)
    }
}

/// Maps the five badge toggles to a btttr poster URL of the form
/// `https://btttr.cc/poster-{flags}/imdb/poster-default/{id}.jpg?tag={none}&rs=IM`.
struct PosterBadgeConfig {
    var trend: Bool
    var genre: Bool
    var rating: Bool
    var quality: Bool
    var age: Bool

    init(trend: Bool, genre: Bool, rating: Bool, quality: Bool, age: Bool) {
        self.trend = trend
        self.genre = genre
        self.rating = rating
        self.quality = quality
        self.age = age
    }

    init(defaults: UserDefaults) {
        self.init(
            trend:   defaults.bool(forKey: PosterService.Key.trend),
            genre:   defaults.bool(forKey: PosterService.Key.genre),
            rating:  defaults.bool(forKey: PosterService.Key.rating),
            quality: defaults.bool(forKey: PosterService.Key.quality),
            age:     defaults.bool(forKey: PosterService.Key.age)
        )
    }

    /// btttr path segment. Genre + rating are the service defaults, so both-on omits
    /// the letters; exactly one drops to that single letter (`g`/`r`); neither uses
    /// the `n` (none) base. Quality/age append `q`/`a`. Letter order: [g|r|n][q][a].
    var pathSegment: String {
        var suffix: String
        switch (genre, rating) {
        case (true, true):   suffix = ""
        case (true, false):  suffix = "g"
        case (false, true):  suffix = "r"
        case (false, false): suffix = "n"
        }
        if quality { suffix += "q" }
        if age { suffix += "a" }
        return suffix.isEmpty ? "poster" : "poster-\(suffix)"
    }

    /// Trend tag: `tag=auto` when on, `tag=none` when off. The `auto` must be sent
    /// explicitly — omitting `tag` makes btttr render a WRONG rating on the
    /// genre+rating poster (e.g. Breaking Bad 9.1 instead of IMDb's 9.5); `tag=auto`
    /// keeps the trend tag AND the correct rating.
    func url(forImdbId id: String) -> String {
        let tag = trend ? "auto" : "none"
        return "https://btttr.cc/\(pathSegment)/imdb/poster-default/\(id).jpg?tag=\(tag)&rs=IM"
    }
}
