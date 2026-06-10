import Foundation

/// Central poster provider — all collections use the btttr poster service
/// for items with a plain IMDb id.
public enum PosterService {
    /// Returns the btttr poster URL for a plain IMDb id ("tt1234567"),
    /// or nil for non-IMDb ids (episode ids like "tt1:1:2", tmdb ids, etc.).
    public static func posterURL(forImdbId id: String?) -> String? {
        guard let id,
              id.hasPrefix("tt"),
              id.count > 2,
              id.dropFirst(2).allSatisfy(\.isNumber) else { return nil }
        return "https://btttr.cc/poster-g/imdb/poster-default/\(id).jpg"
    }
}
