import XCTest
@testable import MoonlitCore

/// Per-tab visibility flags (`show_mac_movies` etc.) only exist in the Supabase
/// overlay — the bundled JSON has none. When the merge keeps the bundle's richer
/// subtree for a collection, it must still adopt the overlay's visibility flags,
/// otherwise portal tab settings silently vanish (Movies/Series tabs went almost
/// empty because nil flags default to hidden).
final class OrganizerMergeVisibilityTests: XCTestCase {

    private func catalog(_ id: String, folderId: String) -> DBFolderCatalog {
        DBFolderCatalog(id: id, folderId: folderId, catalogId: "mdblist.\(id)", mediaType: "movie")
    }

    func testMergeAdoptsOverlayVisibilityFlagsWhenBaseSubtreeWins() {
        let base = OrganizedCollections(
            collections: [DBCollection(id: "b1", name: "Trending Movies", sortOrder: 0)],
            folders: [
                DBFolder(id: "bf1", collectionId: "b1", name: "Trending", sortOrder: 0),
                DBFolder(id: "bf2", collectionId: "b1", name: "More Trending", sortOrder: 1),
            ],
            folderCatalogs: [
                catalog("1", folderId: "bf1"),
                catalog("2", folderId: "bf1"),
                catalog("3", folderId: "bf2"),
            ],
            folderSources: []
        )
        let overlay = OrganizedCollections(
            collections: [
                DBCollection(
                    id: "u1",
                    name: "Trending Movies",
                    sortOrder: 5,
                    showMacHome: true,
                    showMacMovies: true,
                    showMacSeries: false
                )
            ],
            folders: [DBFolder(id: "uf1", collectionId: "u1", name: "Trending", sortOrder: 0)],
            folderCatalogs: [catalog("9", folderId: "uf1")],
            folderSources: []
        )

        let merged = OrganizedCollections.merged(base: base, overlay: overlay)

        let collection = merged.collections.first { $0.name == "Trending Movies" }!
        XCTAssertEqual(
            merged.folders.map(\.id), ["bf1", "bf2"],
            "Base subtree is richer (2 folders vs 1) and must win"
        )
        XCTAssertEqual(collection.showMacHome, true)
        XCTAssertEqual(collection.showMacMovies, true)
        XCTAssertEqual(collection.showMacSeries, false)
    }

    func testMergeKeepsBaseVisibilityWhenOverlayFlagsAreNil() {
        let base = OrganizedCollections(
            collections: [
                DBCollection(id: "b1", name: "Asian Dramas", sortOrder: 0, showOnHome: false)
            ],
            folders: [
                DBFolder(id: "bf1", collectionId: "b1", name: "K-Drama", sortOrder: 0),
                DBFolder(id: "bf2", collectionId: "b1", name: "C-Drama", sortOrder: 1),
            ],
            folderCatalogs: [
                catalog("1", folderId: "bf1"),
                catalog("2", folderId: "bf2"),
            ],
            folderSources: []
        )
        let overlay = OrganizedCollections(
            collections: [DBCollection(id: "u1", name: "Asian Dramas", sortOrder: 3)],
            folders: [DBFolder(id: "uf1", collectionId: "u1", name: "K-Drama", sortOrder: 0)],
            folderCatalogs: [catalog("9", folderId: "uf1")],
            folderSources: []
        )

        let merged = OrganizedCollections.merged(base: base, overlay: overlay)

        let collection = merged.collections.first { $0.name == "Asian Dramas" }!
        XCTAssertEqual(collection.showOnHome, false, "Nil overlay flags must not clobber base flags")
        XCTAssertNil(collection.showMacMovies)
    }
}
