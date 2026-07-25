import Foundation

/// The home screen's top-level category pill selection.
public enum HomeCategoryFilter: String, Sendable, Hashable {
    case featured = "Featured"
    case movies = "Movies"
    case shows = "Shows"
}

/// Category pill state: a top-level media-type filter, optionally refined by a
/// genre picked from the secondary genre menu that appears once Movies or Shows
/// is selected (focused browsing).
public struct HomeCategoryState: Equatable, Sendable {
    public var category: HomeCategoryFilter
    public var genre: String?

    public init(category: HomeCategoryFilter = .featured, genre: String? = nil) {
        self.category = category
        self.genre = genre
    }
}

public extension MetaPreview {
    var isMovieKind: Bool { type == .movie }
    var isShowKind: Bool { type == .series || type == .tv }
}

/// Whether an item passes the current category/genre selection. Folder tiles
/// (collections/franchise bundles) aren't a single media type, so they only
/// match "Featured".
public func matchesHomeCategory(_ item: MetaPreview, filter: HomeCategoryState) -> Bool {
    switch filter.category {
    case .featured:
        break
    case .movies:
        guard item.isMovieKind else { return false }
    case .shows:
        guard item.isShowKind else { return false }
    }
    guard let genre = filter.genre else { return true }
    return item.genres?.contains(genre) ?? false
}

/// Narrows a catalog row to the current category/genre selection. "Featured"
/// passes every row through unchanged (including folder/collection tiles); for
/// Movies/Shows, folder tiles are hidden and items are filtered to matching
/// media kind + genre — rows left with nothing are dropped.
public func filteredHomeRow(_ row: CatalogRow, filter: HomeCategoryState) -> CatalogRow? {
    guard filter.category != .featured else { return row }
    let items = row.items.filter { !$0.id.hasPrefix("folder_") && matchesHomeCategory($0, filter: filter) }
    guard !items.isEmpty else { return nil }
    var narrowed = row
    narrowed.items = items
    return narrowed
}

/// Genres present among the currently loaded Movies/Shows items, most common
/// first then alphabetized, for the secondary genre-refinement pill row.
public func availableHomeGenres(in rows: [CatalogRow], category: HomeCategoryFilter) -> [String] {
    guard category != .featured else { return [] }
    let items = rows.flatMap(\.items).filter { item in
        guard !item.id.hasPrefix("folder_") else { return false }
        switch category {
        case .featured: return true
        case .movies: return item.isMovieKind
        case .shows: return item.isShowKind
        }
    }
    var counts: [String: Int] = [:]
    for genre in items.compactMap(\.genres).flatMap({ $0 }) {
        counts[genre, default: 0] += 1
    }
    return counts.sorted { $0.value > $1.value }.prefix(14).map(\.key).sorted()
}
