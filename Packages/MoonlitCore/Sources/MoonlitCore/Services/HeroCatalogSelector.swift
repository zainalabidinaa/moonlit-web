import Foundation

/// Pure resolver for which catalog rows feed the hero carousel.
///
/// Mirrors Fusion's `home.hero.query`: a single trending/popular catalog by
/// default, overridable by the user to any installed catalog.
public enum HeroCatalogSelector {
    public static let defaultTrendingTitles = ["Trending Movies", "Trending TV Shows"]
    public static let defaultPopularTitles = ["Popular Movies", "Popular TV Shows"]

    /// Ordered rows the hero should draw from.
    ///
    /// - `selectedId`: user override (a `CatalogRow.id`). When set and still
    ///   installed, only that row feeds the hero. A stale id (catalog removed)
    ///   falls through to the default.
    /// - Default: available Trending rows, then available Popular rows, then any
    ///   `fallbackNamedTitles` rows, then all non-empty rows.
    public static func heroRows(
        from rows: [CatalogRow],
        selectedId: String?,
        fallbackNamedTitles: [String] = []
    ) -> [CatalogRow] {
        let nonEmpty = rows.filter { !$0.items.isEmpty }

        if let selectedId, let match = nonEmpty.first(where: { $0.id == selectedId }) {
            return [match]
        }

        let trending = defaultTrendingTitles.compactMap { title in
            nonEmpty.first { $0.title == title }
        }
        if !trending.isEmpty { return trending }

        let popular = defaultPopularTitles.compactMap { title in
            nonEmpty.first { $0.title == title }
        }
        if !popular.isEmpty { return popular }

        let named = nonEmpty.filter { fallbackNamedTitles.contains($0.title) }
        if !named.isEmpty { return named }

        return nonEmpty
    }
}

/// Builds the ordered TMDB poster URL ladder for a resolved `file_path`.
/// Highest useful portrait size first; consumers step down on load failure.
public enum TMDBPosterURL {
    public static let heroSizes = ["w780", "w500", "w342"]

    public static func candidates(filePath: String, sizes: [String] = heroSizes) -> [URL] {
        sizes.compactMap { size in
            URL(string: "https://image.tmdb.org/t/p/\(size)\(filePath)")
        }
    }
}
