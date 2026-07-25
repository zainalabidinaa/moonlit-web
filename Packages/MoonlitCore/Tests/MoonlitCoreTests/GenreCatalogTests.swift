import XCTest
@testable import MoonlitCore

final class GenreCatalogTests: XCTestCase {

    // MARK: Fixtures

    private func catalog(_ id: String, folder: String, catalogId: String) -> DBFolderCatalog {
        DBFolderCatalog(id: id, folderId: folder, catalogId: catalogId, mediaType: "all")
    }

    /// A small layout mirroring the *parsed* profile (CollectionOrganizerParser output):
    /// franchises and browse rails both arrive as DBFolderCatalog with synthesized catalog
    /// ids ("tmdb.collection.<id>", "tmdb.discover.movie.new-movies.<hash>"), never as titled
    /// DBFolderSource. The hub aggregation must work off those ids.
    private func org() -> OrganizedCollections {
        let collections = [
            DBCollection(id: "c-film", name: "Film Collections", sortOrder: 0),
            DBCollection(id: "c-genres", name: "Genres", sortOrder: 1),
            DBCollection(id: "c-hgenre", name: "Horror genre", sortOrder: 2),
            DBCollection(id: "c-hfran", name: "Horror Franchises", sortOrder: 3),
        ]
        let folders = [
            DBFolder(id: "f-actcoll", collectionId: "c-film", name: "Action Collections", sortOrder: 0),
            DBFolder(id: "f-badboys", collectionId: "c-film", name: "Bad Boys", sortOrder: 1),
            DBFolder(id: "f-diehard", collectionId: "c-film", name: "Die Hard", sortOrder: 2),
            DBFolder(id: "f-alien", collectionId: "c-film", name: "Alien", sortOrder: 3),
            DBFolder(id: "f-g-action", collectionId: "c-genres", name: "Action", sortOrder: 0),
            DBFolder(id: "f-g-drama", collectionId: "c-genres", name: "Drama", sortOrder: 1),
            DBFolder(id: "f-h-slasher", collectionId: "c-hgenre", name: "Slasher", sortOrder: 0),
            DBFolder(id: "f-h-halloween", collectionId: "c-hfran", name: "Halloween", sortOrder: 0),
        ]
        let catalogs = [
            // Bundle lists franchises as tmdb.collection.<id> catalog ids
            catalog("s1", folder: "f-actcoll", catalogId: "tmdb.collection.14890"),
            catalog("s2", folder: "f-actcoll", catalogId: "tmdb.collection.1570"),
            // Standalone franchise folders carry the same catalog ids
            catalog("s3", folder: "f-badboys", catalogId: "tmdb.collection.14890"),
            catalog("s4", folder: "f-diehard", catalogId: "tmdb.collection.1570"),
            catalog("s5", folder: "f-alien", catalogId: "tmdb.collection.8091"),
            // Genres → Action: New/Popular as movie+series discover catalogs
            catalog("s6", folder: "f-g-action", catalogId: "tmdb.discover.movie.new-movies.069d5312"),
            catalog("s7", folder: "f-g-action", catalogId: "tmdb.discover.series.new-series.76fc7ade"),
            catalog("s8", folder: "f-g-action", catalogId: "tmdb.discover.movie.popular-movies.29727d26"),
            catalog("s9", folder: "f-g-action", catalogId: "tmdb.discover.series.popular-series.20af3ad9"),
        ]
        return OrganizedCollections(
            collections: collections, folders: folders,
            folderCatalogs: catalogs, folderSources: []
        )
    }

    // MARK: Tests

    func testGenresIncludeCrimeEvenWithoutBrowseFolder() {
        let genres = GenreCatalog.genres(in: org()).map(\.name)
        XCTAssertTrue(genres.contains("Action"))
        XCTAssertTrue(genres.contains("Crime"), "Crime should be present even without a browse folder")
    }

    func testFranchiseBundlesAreNotInSections() {
        // Franchise expansion now happens in CatalogRepository.loadGenreHub
        // as media content rows, not folder tiles in sections.
        let sections = GenreCatalog.sections(for: "Action", in: org())
        let collections = sections.first { $0.title == "Collections" }
        XCTAssertNil(collections, "Collections are now handled as content rows in loadGenreHub")
    }

    func testThemedCollectionsBecomeLabeledSections() {
        let sections = GenreCatalog.sections(for: "Horror", in: org())
        let titles = sections.map(\.title)
        XCTAssertTrue(titles.contains("Sub-genres"), "‘Horror genre’ → Sub-genres")
        XCTAssertTrue(titles.contains("Franchises"), "‘Horror Franchises’ → Franchises")
        let franchises = sections.first { $0.title == "Franchises" }
        XCTAssertEqual(franchises?.folders.map(\.name), ["Halloween"])
    }

    func testBrowseRailsMergeMoviesAndSeriesPerCategory() {
        let rails = GenreCatalog.browseRails(for: "Action", in: org())
        let titles = rails.map(\.title)
        XCTAssertEqual(titles, ["New", "Popular"], "Movie+series variants collapse into one rail each, in order")
        let new = rails.first { $0.title == "New" }
        XCTAssertEqual(new?.catalogs.count, 2, "New rail merges New Movies + New Series")
    }

    func testGenreFilteredCatalogsBecomeIndividualCuratedRails() {
        // A genre folder whose catalogs are not New/Popular must preserve each list's
        // editorial identity rather than collapsing them into one anonymous Browse rail.
        let org = OrganizedCollections(
            collections: [DBCollection(id: "c-genres", name: "Genres", sortOrder: 0)],
            folders: [DBFolder(id: "f-war", collectionId: "c-genres", name: "War", sortOrder: 0)],
            folderCatalogs: [
                catalog("a", folder: "f-war", catalogId: "tmdb.discover.movie.movies.mo7bd2ar"),
                catalog("b", folder: "f-war", catalogId: "trakt.list.4973644"),
            ],
            folderSources: []
        )
        let rails = GenreCatalog.browseRails(for: "War", in: org)
        XCTAssertEqual(rails.map(\.title), ["Curated Collection", "100 Best Action Movies"])
        XCTAssertTrue(rails.allSatisfy { $0.catalogs.count == 1 })
    }

    func testGenreCuratedCatalogsRemainNamedRails() {
        let org = OrganizedCollections(
            collections: [DBCollection(id: "c-genres", name: "Genres", sortOrder: 0)],
            folders: [DBFolder(id: "f-action", collectionId: "c-genres", name: "Action", sortOrder: 0)],
            folderCatalogs: [
                catalog("new", folder: "f-action", catalogId: "tmdb.discover.movie.new-movies.069d5312"),
                catalog("top-action", folder: "f-action", catalogId: "mdblist.2407"),
                catalog("action-comedy", folder: "f-action", catalogId: "trakt.list.825738"),
            ],
            folderSources: []
        )

        XCTAssertEqual(
            GenreCatalog.browseRails(for: "Action", in: org).map(\.title),
            ["New", "Top Action Movies", "Action Comedy"]
        )
    }

    func testMartialArtsCatalogsDoNotAppearInActionRails() {
        let org = OrganizedCollections(
            collections: [DBCollection(id: "c-genres", name: "Genres", sortOrder: 0)],
            folders: [
                DBFolder(id: "f-action", collectionId: "c-genres", name: "Action", sortOrder: 0),
                DBFolder(id: "f-martial", collectionId: "c-genres", name: "Martial Arts", sortOrder: 1),
            ],
            folderCatalogs: [
                catalog("action", folder: "f-action", catalogId: "mdblist.2407"),
                catalog("bruce", folder: "f-martial", catalogId: "trakt.list.4467615"),
            ],
            folderSources: []
        )

        XCTAssertEqual(GenreCatalog.browseRails(for: "Action", in: org).map(\.title), ["Top Action Movies"])
    }

    func testCategoryFolderRailsAreIncludedInMatchingGenre() {
        let org = OrganizedCollections(
            collections: [
                DBCollection(id: "c-genres", name: "Genres", sortOrder: 0),
                DBCollection(id: "c-categories", name: "Categories", sortOrder: 1),
            ],
            folders: [
                DBFolder(id: "f-action", collectionId: "c-genres", name: "Action", sortOrder: 0),
                DBFolder(id: "f-category-action", collectionId: "c-categories", name: "Action", sortOrder: 0),
            ],
            folderCatalogs: [
                catalog("standard", folder: "f-action", catalogId: "tmdb.discover.movie.new-movies.069d5312"),
                catalog("editorial", folder: "f-category-action", catalogId: "mdblist.128037"),
            ],
            folderSources: []
        )

        XCTAssertEqual(GenreCatalog.browseRails(for: "Action", in: org).map(\.title), ["New", "New Action Releases"])
    }
}
