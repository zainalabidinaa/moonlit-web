import XCTest
@testable import MoonlitCore

/// Covers the "Horror Vault duplicates" bug: folders backed only by
/// tmdb.collection.* catalogs return the full franchise list in one shot and
/// ignore `skip`, so pagination must never run for them — and appending a next
/// page must never duplicate items already in the row.
final class FolderPaginationTests: XCTestCase {

    private func meta(_ id: String) -> MetaPreview {
        MetaPreview(id: id, type: .movie, name: id)
    }

    private func collectionCatalog(_ tmdbId: Int) -> DBFolderCatalog {
        DBFolderCatalog(id: "cat-\(tmdbId)", catalogId: "tmdb.collection.\(tmdbId)", mediaType: "movie")
    }

    // MARK: - sourcesSupportPagination

    func testFolderWithOnlyTMDBCollectionCatalogsDoesNotSupportPagination() {
        let sources = [collectionCatalog(735), collectionCatalog(8864), collectionCatalog(9743)]
        XCTAssertFalse(CatalogRepository.sourcesSupportPagination(normalizedSources: sources, rawSources: []))
    }

    func testFolderWithAnyNonCollectionCatalogSupportsPagination() {
        let sources = [
            collectionCatalog(735),
            DBFolderCatalog(id: "cat-x", catalogId: "tmdb.discover.movie.horror.abc", mediaType: "movie"),
        ]
        XCTAssertTrue(CatalogRepository.sourcesSupportPagination(normalizedSources: sources, rawSources: []))
    }

    func testFolderWithRawSourcesSupportsPagination() {
        let raw = [DBFolderSource(id: "src-1", provider: "tmdb", tmdbId: "820")]
        XCTAssertTrue(CatalogRepository.sourcesSupportPagination(normalizedSources: [collectionCatalog(735)], rawSources: raw))
    }

    func testFolderWithNoSourcesDoesNotSupportPagination() {
        XCTAssertFalse(CatalogRepository.sourcesSupportPagination(normalizedSources: [], rawSources: []))
    }

    // MARK: - folderRow(appending:) dedup

    func testAppendingNextPageDropsItemsAlreadyInRow() {
        let row = CatalogRow(
            id: "folder-vault",
            title: "Horror Vault",
            items: [meta("tt1"), meta("tt2")],
            page: 0,
            hasMore: true
        )
        let nextPage = [meta("tt2"), meta("tt3"), meta("tt1"), meta("tt4")]

        let updated = CatalogRepository.folderRow(row, appending: nextPage, pageSize: 50)

        XCTAssertEqual(updated.items.map(\.id), ["tt1", "tt2", "tt3", "tt4"])
        XCTAssertEqual(updated.page, 1)
    }

    func testAppendingAllDuplicatePageKeepsItemsAndStopsPagination() {
        let items = (0..<60).map { meta("tt\($0)") }
        let row = CatalogRow(
            id: "folder-vault",
            title: "Horror Vault",
            items: items,
            page: 0,
            hasMore: true
        )

        let updated = CatalogRepository.folderRow(row, appending: items, pageSize: 50)

        XCTAssertEqual(updated.items.map(\.id), items.map(\.id))
        XCTAssertFalse(updated.hasMore)
    }

    func testAppendingFullPageWithSomeNewItemsKeepsPaginating() {
        let existing = (0..<40).map { meta("tt\($0)") }
        let nextPage = (30..<80).map { meta("tt\($0)") }
        let row = CatalogRow(
            id: "folder-vault",
            title: "Horror Vault",
            items: existing,
            page: 0,
            hasMore: true
        )

        let updated = CatalogRepository.folderRow(row, appending: nextPage, pageSize: 50)

        XCTAssertEqual(updated.items.map(\.id), (0..<80).map { "tt\($0)" })
        XCTAssertTrue(updated.hasMore)
    }
}
