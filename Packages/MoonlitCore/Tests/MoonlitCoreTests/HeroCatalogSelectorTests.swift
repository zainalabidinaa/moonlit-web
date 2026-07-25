import XCTest
@testable import MoonlitCore

/// Covers the hero source resolver and the TMDB poster URL ladder that back
/// the Fusion-style hero (selectable catalog + textless poster selection).
final class HeroCatalogSelectorTests: XCTestCase {

    private func row(_ id: String, _ title: String, empty: Bool = false) -> CatalogRow {
        let items = empty ? [] : [MetaPreview(id: "\(id)-1", type: .movie, name: "Item")]
        return CatalogRow(id: id, title: title, items: items)
    }

    // MARK: - HeroCatalogSelector

    func testOverrideSelectsOnlyThatRow() {
        let rows = [row("a", "Trending Movies"), row("b", "Documentaries")]
        let result = HeroCatalogSelector.heroRows(from: rows, selectedId: "b")
        XCTAssertEqual(result.map(\.id), ["b"])
    }

    func testStaleOverrideFallsThroughToDefault() {
        let rows = [row("a", "Trending Movies"), row("b", "Trending TV Shows")]
        let result = HeroCatalogSelector.heroRows(from: rows, selectedId: "missing")
        XCTAssertEqual(result.map(\.title), ["Trending Movies", "Trending TV Shows"])
    }

    func testDefaultPrefersTrendingRows() {
        let rows = [row("p", "Popular Movies"), row("t", "Trending Movies")]
        let result = HeroCatalogSelector.heroRows(from: rows, selectedId: nil)
        XCTAssertEqual(result.map(\.title), ["Trending Movies"])
    }

    func testDefaultFallsBackToPopularWhenNoTrending() {
        let rows = [row("p1", "Popular Movies"), row("p2", "Popular TV Shows")]
        let result = HeroCatalogSelector.heroRows(from: rows, selectedId: nil)
        XCTAssertEqual(result.map(\.title), ["Popular Movies", "Popular TV Shows"])
    }

    func testFallsBackToNamedThenAllNonEmpty() {
        let rows = [row("x", "My List"), row("y", "Watchlist")]
        let named = HeroCatalogSelector.heroRows(
            from: rows, selectedId: nil, fallbackNamedTitles: ["Watchlist"]
        )
        XCTAssertEqual(named.map(\.title), ["Watchlist"])

        let all = HeroCatalogSelector.heroRows(from: rows, selectedId: nil)
        XCTAssertEqual(all.map(\.id), ["x", "y"])
    }

    func testEmptyRowsAreIgnored() {
        let rows = [row("t", "Trending Movies", empty: true), row("p", "Popular Movies")]
        let result = HeroCatalogSelector.heroRows(from: rows, selectedId: nil)
        XCTAssertEqual(result.map(\.title), ["Popular Movies"])
    }

    // MARK: - TMDBPosterURL

    func testCandidateLadderDescendsSizes() {
        let urls = TMDBPosterURL.candidates(filePath: "/abc.jpg")
        XCTAssertEqual(urls.map(\.absoluteString), [
            "https://image.tmdb.org/t/p/w780/abc.jpg",
            "https://image.tmdb.org/t/p/w500/abc.jpg",
            "https://image.tmdb.org/t/p/w342/abc.jpg",
        ])
    }
}
