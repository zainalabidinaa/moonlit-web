import XCTest
@testable import MoonlitCore

final class MoonlitCoreTests: XCTestCase {}

extension MoonlitCoreTests {
    func testKnownForCreditsAreUniqueTitlesOrderedByPopularity() {
        func credit(id: Int, title: String, popularity: Double) -> PersonCredit {
            PersonCredit(
                id: id,
                title: title,
                mediaType: "tv",
                character: "Guest",
                job: nil,
                department: nil,
                releaseDate: nil,
                posterPath: "/\(id).jpg",
                backdropPath: nil,
                voteAverage: nil,
                voteCount: nil,
                episodeCount: 1,
                popularity: popularity
            )
        }

        let credits = PersonCredits(
            cast: [
                credit(id: 10, title: "Family Guy", popularity: 90),
                credit(id: 10, title: "Family Guy", popularity: 80),
                credit(id: 20, title: "Breaking Bad", popularity: 70),
                credit(id: 30, title: "Drive", popularity: 60),
            ],
            crew: []
        )

        XCTAssertEqual(credits.knownFor.map(\.title), ["Family Guy", "Breaking Bad", "Drive"])
    }

    func testStremioErrorsExposeHumanReadableDescriptions() {
        let offline = StremioError.networkError(URLError(.notConnectedToInternet))
        XCTAssertEqual(
            offline.localizedDescription,
            "Check your internet connection and try again"
        )
        if case .networkError(let underlying) = offline {
            XCTAssertEqual((underlying as? URLError)?.code, .notConnectedToInternet)
        } else {
            XCTFail("Expected networkError to preserve its underlying error")
        }
        XCTAssertEqual(
            StremioError.httpError(404).localizedDescription,
            "Content not found on this addon"
        )
        XCTAssertEqual(
            StremioError.httpError(429).localizedDescription,
            "Too many requests — try again in a moment"
        )
        XCTAssertEqual(
            StremioError.httpError(503).localizedDescription,
            "Addon server error — try another addon"
        )
    }

    @MainActor
    func testCollectionRowDisplayStyleStorePersistsPerRow() {
        let defaults = UserDefaults(suiteName: "CollectionRowDisplayStyleStoreTests")!
        defaults.removePersistentDomain(forName: "CollectionRowDisplayStyleStoreTests")
        let store = CollectionRowDisplayStyleStore(defaults: defaults)

        XCTAssertEqual(store.style(forRowTitle: "Latest Movies"), .standard)

        store.setStyle(.heroBanner, forRowTitle: "Latest Movies")
        XCTAssertEqual(store.style(forRowTitle: "Latest Movies"), .heroBanner)

        let reloaded = CollectionRowDisplayStyleStore(defaults: defaults)
        XCTAssertEqual(reloaded.style(forRowTitle: "Latest Movies"), .heroBanner)
        XCTAssertEqual(reloaded.style(forRowTitle: "Latest TV Series"), .standard)
    }

    @MainActor
    func testCollectionRowDisplayStyleStoreFallsBackForInvalidStoredValues() {
        let defaults = UserDefaults(suiteName: "CollectionRowDisplayStyleStoreInvalidTests")!
        defaults.removePersistentDomain(forName: "CollectionRowDisplayStyleStoreInvalidTests")
        defaults.set(["Latest Movies": "made-up"], forKey: "moonlit.collectionRowDisplayStyles")

        let store = CollectionRowDisplayStyleStore(defaults: defaults)

        XCTAssertEqual(store.style(forRowTitle: "Latest Movies"), .standard)
    }

    func testEpisodeProgressResolvesParentMediaId() {
        let entry = WatchProgressEntry(
            id: "progress-1",
            profileId: "profile-1",
            mediaId: "tt0108778:1:2",
            mediaType: "series",
            parentMetaId: "tt0108778",
            season: 1,
            episode: 2
        )

        XCTAssertEqual(entry.parentOrSelfMediaId, "tt0108778")
        XCTAssertEqual(entry.inferredSeason, 1)
        XCTAssertEqual(entry.inferredEpisode, 2)
        XCTAssertTrue(entry.matchesMedia(id: "tt0108778"))
        XCTAssertTrue(entry.matchesMedia(id: "tt0108778:1:2"))
    }

    func testEpisodeProgressResolvesParentMediaIdFromEncodedCompoundId() {
        let entry = WatchProgressEntry(
            id: "progress-2",
            profileId: "profile-1",
            mediaId: "tt0108778%3A1%3A2",
            mediaType: "series"
        )

        XCTAssertEqual(entry.parentOrSelfMediaId, "tt0108778")
        XCTAssertTrue(entry.matchesMedia(id: "tt0108778"))
    }

    func testEpisodeProgressUsesStoredPosterAsThumbnailFallback() {
        let entry = WatchProgressEntry(
            id: "progress-3",
            profileId: "profile-1",
            mediaId: "tt0108778%3A1%3A2",
            mediaType: "series",
            poster: "https://cdn.example.com/stills/friends-s1e2.jpg"
        )

        XCTAssertEqual(entry.thumbnailFallbackForContinueWatching, "https://cdn.example.com/stills/friends-s1e2.jpg")
    }

    func testContinueWatchingKeepsOnlyLatestProgressPerSeries() {
        let olderEpisode = WatchProgressEntry(
            id: "progress-older",
            profileId: "profile-1",
            mediaId: "tt9813792%3A1%3A1",
            mediaType: "series",
            positionSeconds: 120,
            durationSeconds: 3000,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newerEpisode = WatchProgressEntry(
            id: "progress-newer",
            profileId: "profile-1",
            mediaId: "tt9813792%3A1%3A2",
            mediaType: "series",
            positionSeconds: 240,
            durationSeconds: 3000,
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let movie = WatchProgressEntry(
            id: "progress-movie",
            profileId: "profile-1",
            mediaId: "tt34611082",
            mediaType: "movie",
            positionSeconds: 60,
            durationSeconds: 5400,
            updatedAt: Date(timeIntervalSince1970: 150)
        )

        let entries = HomeRepository.latestEntriesForContinueWatching(
            [olderEpisode, newerEpisode, movie],
            limit: 10
        )

        XCTAssertEqual(entries.map(\.mediaId), ["tt9813792%3A1%3A2", "tt34611082"])
    }

    func testContinueWatchingItemKeepsOriginalLogo() {
        let item = ContinueWatchingItem(
            mediaId: "tt9813792:2:2",
            parentMediaId: "tt9813792",
            mediaType: "series",
            name: "FROM",
            logo: "https://image.example.com/from-logo.png"
        )

        XCTAssertEqual(item.logo, "https://image.example.com/from-logo.png")
    }

    func testDefaultAddonsIncludeTrailerAndDeepDiveCompanions() {
        XCTAssertTrue(MoonlitConfig.defaultAddons.contains {
            $0.contains("streailer")
        })
        XCTAssertTrue(MoonlitConfig.defaultAddons.contains {
            $0.contains("stremio-content-deepdive-addon-dc8f7b513289.herokuapp.com")
        })
    }


    func testStreamMatchGuardRejectsObviousWrongSeriesEpisode() {
        let stream = StreamItem(
            title: "FROM S04 · E02 1080p",
            description: "Cached source"
        )

        XCTAssertFalse(StreamMatchGuard.shouldKeep(stream, type: "series", id: "tt9813792:2:2"))
    }

    func testStreamMatchGuardKeepsNeutralCachedSeriesStream() {
        let stream = StreamItem(
            title: "RD+ 1080p WEB-DL",
            description: "Cached source"
        )

        XCTAssertTrue(StreamMatchGuard.shouldKeep(stream, type: "series", id: "tt9813792:2:2"))
    }

    func testStreamMatchGuardRejectsDifferentImdbId() {
        let stream = StreamItem(
            title: "Breaking Bad tt0903747 S02E02",
            description: "Wrong show"
        )

        XCTAssertFalse(StreamMatchGuard.shouldKeep(stream, type: "series", id: "tt9813792:2:2"))
    }

    func testStreamSourceSelectorDefaultsToBest1080p() {
        let streams = [
            StreamItem(title: "Movie 2160p HDR", url: "https://example.com/4k.mkv"),
            StreamItem(title: "Movie 1080p WEB-DL", url: "https://example.com/1080.mkv"),
            StreamItem(title: "Movie 1080p DTS", url: "https://example.com/1080-dts.mkv"),
        ]

        let selected = StreamSourceSelector.initialStream(from: streams, prefer4K: false)

        XCTAssertEqual(selected?.url, "https://example.com/1080.mkv")
    }

    func testStreamSourceSelectorUses4KWhenPreferred() {
        let streams = [
            StreamItem(title: "Movie 1080p WEB-DL", url: "https://example.com/1080.mkv"),
            StreamItem(title: "Movie 2160p HDR", url: "https://example.com/4k.mkv"),
        ]

        let selected = StreamSourceSelector.initialStream(from: streams, prefer4K: true)

        XCTAssertEqual(selected?.url, "https://example.com/4k.mkv")
    }

    func testStreamSourceSelectorPrioritizesBoltBeforeCachedAndBitrate() {
        let streams = [
            StreamItem(title: "Movie 2160p 90 Mbps", url: "https://example.com/high-bitrate.mkv"),
            StreamItem(title: "Movie 2160p cached", url: "https://example.com/cached.mkv"),
            StreamItem(title: "Movie 1080p ⚡", url: "https://example.com/bolt.mkv"),
        ]

        let selected = StreamSourceSelector.initialStream(from: streams, prefer4K: true)

        XCTAssertEqual(selected?.url, "https://example.com/bolt.mkv")
    }

    func testStreamSourceSelectorUsesHighestBitrateWhenNoBoltOrCached() {
        let streams = [
            StreamItem(title: "Movie 1080p 12 Mbps", url: "https://example.com/12mbps.mkv"),
            StreamItem(title: "Movie 1080p 42 Mbps", url: "https://example.com/42mbps.mkv"),
        ]

        let selected = StreamSourceSelector.initialStream(from: streams, prefer4K: false)

        XCTAssertEqual(selected?.url, "https://example.com/42mbps.mkv")
    }

    func testStreamSourceSelectorFinds4KUpgrade() {
        let current = StreamItem(title: "Movie 1080p WEB-DL", url: "https://example.com/1080.mkv")
        let streams = [
            current,
            StreamItem(title: "Movie 2160p HDR", url: "https://example.com/4k.mkv"),
        ]

        let selected = StreamSourceSelector.best4KStream(from: streams, excluding: current)

        XCTAssertEqual(selected?.url, "https://example.com/4k.mkv")
    }

    func testStreamSourceSelectorRetryUsesSameQualityFirst() {
        let current = StreamItem(title: "Movie 1080p WEB-DL", url: "https://example.com/1080-a.mkv")
        let streams = [
            StreamItem(title: "Movie 2160p HDR", url: "https://example.com/4k.mkv"),
            current,
            StreamItem(title: "Movie 1080p AAC", url: "https://example.com/1080-b.mkv"),
        ]

        let selected = StreamSourceSelector.nextStream(after: current, from: streams, prefer4K: false)

        XCTAssertEqual(selected?.url, "https://example.com/1080-b.mkv")
    }

    func testStreamSourceSelectorRetrySkipsCurrentSourceUrlWhenCurrentStreamIsUnknown() {
        let streams = [
            StreamItem(title: "Movie 1080p WEB-DL", url: "https://example.com/1080-a.mkv"),
            StreamItem(title: "Movie 1080p AAC", url: "https://example.com/1080-b.mkv"),
        ]

        let selected = StreamSourceSelector.nextStream(
            after: nil,
            currentSourceUrl: "https://example.com/1080-a.mkv",
            from: streams,
            prefer4K: false
        )

        XCTAssertEqual(selected?.url, "https://example.com/1080-b.mkv")
    }

    func testStreamSourceSelectorCountsOnlyPlayableRetryCandidates() {
        let streams = [
            StreamItem(title: "Trailer", ytId: "abc123"),
            StreamItem(title: "Movie 1080p", url: "https://example.com/1080.mkv"),
        ]

        XCTAssertFalse(StreamSourceSelector.hasMultiplePlaybackCandidates(in: streams))
    }

    func testStreamSourceSelectorDoesNotAutoPickYoutubeTrailer() {
        let streams = [
            StreamItem(
                title: "Trailer",
                ytId: "abc123",
                addonName: "Streailer",
                behaviorHints: StreamBehaviorHints(bingeGroup: "trailer")
            ),
            StreamItem(title: "FROM S04E01 1080p", url: "https://example.com/from-s4e1.mkv"),
        ]

        let selected = StreamSourceSelector.initialStream(from: streams, prefer4K: false)

        XCTAssertEqual(selected?.url, "https://example.com/from-s4e1.mkv")
    }

    func testStreamSourceSelectorExcludesTrailerFromPlaybackCandidates() {
        let trailer = StreamItem(
            title: "Official Trailer",
            ytId: "abc123",
            addonName: "Streailer",
            behaviorHints: StreamBehaviorHints(bingeGroup: "trailer")
        )

        XCTAssertFalse(StreamSourceSelector.isPlaybackCandidate(trailer))
    }

    @MainActor
    func testCatalogRowsArePreservedWhenCollectionReloadProducesNoRows() {
        let existingRows = [
            CatalogRow(
                id: "folder_existing",
                title: "Existing",
                items: [MetaPreview(id: "tt1", type: .movie, name: "Existing Movie")]
            )
        ]

        let resolved = CatalogRepository.resolvedRowsAfterReload(existingRows: existingRows, newRows: [])

        XCTAssertEqual(resolved.map(\.id), ["folder_existing"])
    }

    @MainActor
    func testAuthoritativeCollectionRefreshReplacesStaleCachedRows() {
        let existingRows = [
            CatalogRow(
                id: "collection_removed",
                title: "Removed",
                items: [MetaPreview(id: "tt1", type: .movie, name: "Removed Movie")]
            )
        ]
        let refreshedRows = [
            CatalogRow(
                id: "collection_current",
                title: "Current",
                items: [MetaPreview(id: "tt2", type: .movie, name: "Current Movie")]
            )
        ]

        let resolved = CatalogRepository.resolvedRowsAfterReload(
            existingRows: existingRows,
            newRows: refreshedRows,
            mode: .replaceCache
        )

        XCTAssertEqual(resolved.map(\.id), ["collection_current"])
    }

    @MainActor
    func testAuthoritativeCollectionRefreshCanRemoveAllCachedRows() {
        let existingRows = [
            CatalogRow(
                id: "collection_removed",
                title: "Removed",
                items: [MetaPreview(id: "tt1", type: .movie, name: "Removed Movie")]
            )
        ]

        let resolved = CatalogRepository.resolvedRowsAfterReload(
            existingRows: existingRows,
            newRows: [],
            mode: .replaceCache
        )

        XCTAssertTrue(resolved.isEmpty)
    }

    func testCollectionRefreshSkipsRebuildWhenSnapshotIsUnchanged() {
        let collections = [DBCollection(id: "featured", name: "Featured", sortOrder: 1)]
        let folders = [DBFolder(id: "latest", collectionId: "featured", name: "Latest", sortOrder: 1)]
        let catalogs = [DBFolderCatalog(id: "cat-latest", folderId: "latest", catalogId: "tmdb.popular", mediaType: "movie")]
        let sources = [DBFolderSource(id: "source-latest", folderId: "latest", provider: "tmdb", tmdbId: "123")]

        XCTAssertFalse(CollectionRepository.hasCollectionSnapshotChanged(
            currentCollections: collections,
            currentFolders: folders,
            currentFolderCatalogs: catalogs,
            currentFolderSources: sources,
            refreshedCollections: collections,
            refreshedFolders: folders,
            refreshedFolderCatalogs: catalogs,
            refreshedFolderSources: sources
        ))

        XCTAssertTrue(CollectionRepository.hasCollectionSnapshotChanged(
            currentCollections: collections,
            currentFolders: folders,
            currentFolderCatalogs: catalogs,
            currentFolderSources: sources,
            refreshedCollections: [DBCollection(id: "featured", name: "Featured Updated", sortOrder: 1)],
            refreshedFolders: folders,
            refreshedFolderCatalogs: catalogs,
            refreshedFolderSources: sources
        ))
    }

    func testMergeByNamePreservesBundleOnlyCollectionsAndLetsOverlayWin() {
        // Bundle: complete layout with IDs like the bundled JSON.
        let bundle = OrganizedCollections(
            collections: [
                DBCollection(id: "collection-trend-shows", name: "Trending Shows", sortOrder: 1),
                DBCollection(id: "collection-trend-movies", name: "Trending Movies", sortOrder: 2),
                DBCollection(id: "collection-asian", name: "Asian Dramas", sortOrder: 3),
            ],
            folders: [
                DBFolder(id: "f-shows", collectionId: "collection-trend-shows", name: "Trending Shows", sortOrder: 1),
                DBFolder(id: "f-movies", collectionId: "collection-trend-movies", name: "Trending Movies", sortOrder: 1),
                DBFolder(id: "f-asian", collectionId: "collection-asian", name: "K-Drama", sortOrder: 1),
            ],
            folderCatalogs: [
                DBFolderCatalog(id: "c-shows", folderId: "f-shows", catalogId: "mdblist.3882", mediaType: "series"),
                DBFolderCatalog(id: "c-movies-bundle", folderId: "f-movies", catalogId: "tmdb.trending_movie", mediaType: "movie"),
                DBFolderCatalog(id: "c-asian", folderId: "f-asian", catalogId: "mdblist.kdrama", mediaType: "series"),
            ],
            folderSources: []
        )
        // Overlay (Supabase): only "Trending Movies", different UUID + edited catalog.
        let overlay = OrganizedCollections(
            collections: [
                DBCollection(id: "uuid-trend-movies", name: "Trending Movies", sortOrder: 1),
            ],
            folders: [
                DBFolder(id: "uuid-f-movies", collectionId: "uuid-trend-movies", name: "Trending Movies", sortOrder: 1),
            ],
            folderCatalogs: [
                DBFolderCatalog(id: "uuid-c-movies", folderId: "uuid-f-movies", catalogId: "tmdb.trending_movie_edited", mediaType: "movie"),
            ],
            folderSources: []
        )

        let merged = CollectionRepository.mergeByName(base: bundle, overlay: overlay)

        // All three collections survive, in bundle order.
        XCTAssertEqual(merged.collections.map(\.name), ["Trending Shows", "Trending Movies", "Asian Dramas"])
        // Overlay won for the matching name (UUID id, edited catalog).
        let movies = merged.collections.first { $0.name == "Trending Movies" }
        XCTAssertEqual(movies?.id, "uuid-trend-movies")
        XCTAssertTrue(merged.folderCatalogs.contains { $0.catalogId == "tmdb.trending_movie_edited" })
        XCTAssertFalse(merged.folderCatalogs.contains { $0.catalogId == "tmdb.trending_movie" })
        // Bundle-only collections kept their catalogs.
        XCTAssertTrue(merged.folderCatalogs.contains { $0.catalogId == "mdblist.3882" })
        XCTAssertTrue(merged.folderCatalogs.contains { $0.catalogId == "mdblist.kdrama" })
    }

    func testMergeByNameKeepsRicherBundledCollectionWhenOverlayIsPartial() {
        // Bundled "Franchises" has 3 folders with cover art; the Supabase overlay only has 1.
        let bundle = OrganizedCollections(
            collections: [DBCollection(id: "collection-franchises", name: "Franchises", sortOrder: 1)],
            folders: [
                DBFolder(id: "b-sw", collectionId: "collection-franchises", name: "Star Wars", sortOrder: 1, coverImage: "sw.jpg"),
                DBFolder(id: "b-me", collectionId: "collection-franchises", name: "Middle Earth", sortOrder: 2, coverImage: "me.jpg"),
                DBFolder(id: "b-px", collectionId: "collection-franchises", name: "Pixar", sortOrder: 3, coverImage: "px.jpg"),
            ],
            folderCatalogs: [],
            folderSources: []
        )
        let overlay = OrganizedCollections(
            collections: [DBCollection(id: "uuid-franchises", name: "Franchises", sortOrder: 1)],
            folders: [DBFolder(id: "o-me", collectionId: "uuid-franchises", name: "Middle Earth", sortOrder: 1)],
            folderCatalogs: [],
            folderSources: []
        )

        let merged = CollectionRepository.mergeByName(base: bundle, overlay: overlay)

        // The richer bundled version is kept — all 3 folders + their cover art survive.
        let franchises = merged.collections.first { $0.name == "Franchises" }
        XCTAssertEqual(franchises?.id, "collection-franchises")
        let folderNames = merged.folders.filter { $0.collectionId == "collection-franchises" }.map(\.name)
        XCTAssertEqual(Set(folderNames), ["Star Wars", "Middle Earth", "Pixar"])
        XCTAssertTrue(merged.folders.contains { $0.name == "Star Wars" && $0.coverImage == "sw.jpg" })
    }

    func testSearchRelevanceRanksExactTitleFirst() {
        let q = "breaking bad"
        let exact = SearchRepository.relevanceScore(name: "Breaking Bad", query: q)
        let prefix = SearchRepository.relevanceScore(name: "Breaking Bad Franchise", query: q)
        let contains = SearchRepository.relevanceScore(name: "El Camino: A Breaking Bad Movie", query: q)
        let unrelated = SearchRepository.relevanceScore(name: "The Wire", query: q)
        XCTAssertGreaterThan(exact, prefix)
        XCTAssertGreaterThan(prefix, contains)
        XCTAssertGreaterThan(contains, unrelated)
        XCTAssertEqual(unrelated, 0)
    }

    func testSearchFiltersReleaseNameJunk() {
        XCTAssertTrue(SearchRepository.looksLikeReleaseName("Breaking.Bad.S01.Ger.En-g.EAC3D.DL.2160p.WEB.SD"))
        XCTAssertTrue(SearchRepository.looksLikeReleaseName("The.Matrix.1999.1080p.BluRay.x264"))
        XCTAssertTrue(SearchRepository.looksLikeReleaseName("Some.Dotted.Filename"))
        XCTAssertFalse(SearchRepository.looksLikeReleaseName("Breaking Bad"))
        XCTAssertFalse(SearchRepository.looksLikeReleaseName("El Camino: A Breaking Bad Movie"))
        XCTAssertFalse(SearchRepository.looksLikeReleaseName("Spider-Man: No Way Home"))
    }

    func testFolderLoadReadinessNormalizesIdsAndReportsMissingFolder() {
        let reason = CatalogRepository.folderLoadUnavailableReason(
            folderId: "missing",
            collections: [DBCollection(id: "featured", name: "Featured")],
            folders: [DBFolder(id: "present", collectionId: "featured", name: "Present")],
            folderCatalogs: [],
            folderSources: [],
            addons: [AddonManifest(id: "aio", name: "AIO", version: "1.0.0", transportUrl: "https://example.com")]
        )

        XCTAssertEqual(reason, .missingFolder)
    }

    func testFolderLoadReadinessReportsMissingSourcesForExistingFolder() {
        let reason = CatalogRepository.folderLoadUnavailableReason(
            folderId: "folder_present",
            collections: [DBCollection(id: "featured", name: "Featured")],
            folders: [DBFolder(id: "present", collectionId: "featured", name: "Present")],
            folderCatalogs: [],
            folderSources: [],
            addons: [AddonManifest(id: "aio", name: "AIO", version: "1.0.0", transportUrl: "https://example.com")]
        )

        XCTAssertEqual(reason, .missingSources)
    }

    func testFolderLoadReadinessReportsMissingAddonTransport() {
        let reason = CatalogRepository.folderLoadUnavailableReason(
            folderId: "present",
            collections: [DBCollection(id: "featured", name: "Featured")],
            folders: [DBFolder(id: "present", collectionId: "featured", name: "Present")],
            folderCatalogs: [DBFolderCatalog(id: "catalog-1", folderId: "present", catalogId: "popular", mediaType: "movie")],
            folderSources: [],
            addons: []
        )

        XCTAssertEqual(reason, .missingAddonTransport)
    }

    func testFolderLoadReadinessAcceptsFolderIdsWithOrWithoutPrefix() {
        let reason = CatalogRepository.folderLoadUnavailableReason(
            folderId: "folder_present",
            collections: [DBCollection(id: "featured", name: "Featured")],
            folders: [DBFolder(id: "present", collectionId: "featured", name: "Present")],
            folderCatalogs: [DBFolderCatalog(id: "catalog-1", folderId: "present", catalogId: "popular", mediaType: "movie")],
            folderSources: [],
            addons: [AddonManifest(id: "aio", name: "AIO", version: "1.0.0", transportUrl: "https://example.com")]
        )

        XCTAssertNil(reason)
    }

    func testCollectionDisplayPreferencesExpandFoldersIntoRows() {
        let collection = DBCollection(id: "decades", name: "Decades", sortOrder: 0)
        let folder1980s = DBFolder(id: "1980s", collectionId: "decades", name: "1980s", sortOrder: 0)
        let folder1990s = DBFolder(id: "1990s", collectionId: "decades", name: "1990s", sortOrder: 1)
        let folderRows = [
            CatalogRow(id: "folder_1980s", title: "1980s", items: [MetaPreview(id: "tt1", type: .movie, name: "Movie 1")]),
            CatalogRow(id: "folder_1990s", title: "1990s", items: [MetaPreview(id: "tt2", type: .movie, name: "Movie 2")])
        ]

        let grouped = CatalogRepository.displayRows(
            for: collection,
            folders: [folder1980s, folder1990s],
            folderRows: folderRows,
            preferences: CollectionDisplayPreferences(
                enabledCollectionIds: ["decades"],
                expandedCollectionIds: [],
                hiddenFolderIds: []
            )
        )
        let expanded = CatalogRepository.displayRows(
            for: collection,
            folders: [folder1980s, folder1990s],
            folderRows: folderRows,
            preferences: CollectionDisplayPreferences(
                enabledCollectionIds: ["decades"],
                expandedCollectionIds: ["decades"],
                hiddenFolderIds: []
            )
        )

        XCTAssertEqual(grouped.map(\.title), ["Decades"])
        XCTAssertEqual(grouped.first?.items.map(\.name), ["1980s", "1990s"])
        XCTAssertEqual(expanded.map(\.title), ["1980s", "1990s"])
        XCTAssertEqual(expanded.flatMap(\.items).map(\.name), ["Movie 1", "Movie 2"])
    }

    func testCollectionDisplayPreferencesCanDisableCollectionAndHideFolders() {
        let collection = DBCollection(id: "decades", name: "Decades", sortOrder: 0)
        let folder1980s = DBFolder(id: "1980s", collectionId: "decades", name: "1980s", sortOrder: 0)
        let folder1990s = DBFolder(id: "1990s", collectionId: "decades", name: "1990s", sortOrder: 1)
        let folderRows = [
            CatalogRow(id: "folder_1980s", title: "1980s", items: [MetaPreview(id: "tt1", type: .movie, name: "Movie 1")]),
            CatalogRow(id: "folder_1990s", title: "1990s", items: [MetaPreview(id: "tt2", type: .movie, name: "Movie 2")])
        ]

        let disabled = CatalogRepository.displayRows(
            for: collection,
            folders: [folder1980s, folder1990s],
            folderRows: folderRows,
            preferences: CollectionDisplayPreferences(
                enabledCollectionIds: [],
                expandedCollectionIds: ["decades"],
                hiddenFolderIds: []
            )
        )
        let hidden = CatalogRepository.displayRows(
            for: collection,
            folders: [folder1980s, folder1990s],
            folderRows: folderRows,
            preferences: CollectionDisplayPreferences(
                enabledCollectionIds: ["decades"],
                expandedCollectionIds: ["decades"],
                hiddenFolderIds: ["1990s"]
            )
        )

        XCTAssertTrue(disabled.isEmpty)
        XCTAssertEqual(hidden.map(\.title), ["1980s"])
    }

    func testSingleFolderCollectionDisplaysAsContentRow() {
        let collection = DBCollection(id: "popular", name: "Popular Movies", sortOrder: 0)
        let folder = DBFolder(id: "popular-folder", collectionId: "popular", name: "Popular Movies", sortOrder: 0)
        let contentRow = CatalogRow(
            id: "folder_popular-folder",
            title: "Popular Movies",
            items: [MetaPreview(id: "tt1", type: .movie, name: "Interstellar")]
        )

        let rows = CatalogRepository.displayRows(
            for: collection,
            folders: [folder],
            folderRows: [contentRow],
            preferences: CollectionDisplayPreferences(
                enabledCollectionIds: ["popular"],
                expandedCollectionIds: [],
                hiddenFolderIds: []
            )
        )

        XCTAssertEqual(rows.map(\.id), ["folder_popular-folder"])
        XCTAssertEqual(rows.first?.items.map(\.name), ["Interstellar"])
    }

    func testHomeCatalogLoadStrategyFallsBackToAddonCatalogsWhenCollectionsAreEmpty() {
        XCTAssertEqual(CatalogRepository.homeLoadStrategy(collections: []), .addonCatalogsOnly)

        let collection = DBCollection(id: "featured", name: "Featured", sortOrder: 0)
        XCTAssertEqual(
            CatalogRepository.homeLoadStrategy(collections: [collection]),
            .collectionsThenAddonSupplement
        )
    }

    func testLayoutOrganizerMapsToCollectionRepositoryModels() throws {
        let json = """
        [
          {
            "id": "collection-1",
            "title": "Popular Movies",
            "viewMode": "FOLLOW_LAYOUT",
            "showAllTab": true,
            "focusGlowEnabled": true,
            "pinToTop": true,
            "folders": [
              {
                "id": "folder-1",
                "title": "Popular 2010s Movies",
                "tileShape": "POSTER",
                "coverImageUrl": "https://images.example.com/poster.png",
                "focusGifUrl": "https://images.example.com/preview.gif",
                "focusGifEnabled": true,
                "heroBackdropUrl": "https://images.example.com/backdrop.jpg",
                "sources": [
                  { "provider": "addon", "type": "movie", "catalogId": "tmdb.top_movie", "genre": "None" },
                  { "provider": "tmdb", "type": "movie", "catalogId": "tmdb.discover.movie.abc", "genre": "Action" }
                ]
              }
            ]
          }
        ]
        """

        let layout = try CollectionOrganizerParser.parse(jsonData: Data(json.utf8))

        XCTAssertEqual(layout.collections.map(\.name), ["Popular Movies"])
        XCTAssertEqual(layout.collections.first?.focusGlowEnabled, false)
        XCTAssertEqual(layout.collections.first?.pinToTop, true)
        XCTAssertEqual(layout.folders.first?.tileShape, "poster")
        XCTAssertEqual(layout.folders.first?.coverImage, "https://images.example.com/poster.png")
        XCTAssertEqual(layout.folders.first?.focusGif, "https://images.example.com/preview.gif")
        XCTAssertEqual(layout.folderCatalogs.map(\.catalogId), ["tmdb.top_movie"])
        XCTAssertEqual(layout.folderSources.map(\.provider), ["tmdb"])
        XCTAssertEqual(layout.folderSources.first?.tmdbId, "abc")
        XCTAssertEqual(layout.folderSources.first?.tmdbSourceType, "discover")
    }

    func testLayoutOrganizerSynthesizesDiscoverFoldersFromFilters() throws {
        let json = """
        [
          {
            "id": "collection-discover",
            "title": "By Decade",
            "folders": [
              {
                "id": "folder-discover",
                "title": "2020s Movies",
                "sources": [
                  {
                    "title": "New Movies",
                    "provider": "tmdb",
                    "mediaType": "MOVIE",
                    "tmdbSourceType": "DISCOVER",
                    "filters": {
                      "withGenres": "28",
                      "voteCountGte": 10,
                      "withOriginalLanguage": "en",
                      "year": 2026
                    }
                  }
                ]
              }
            ]
          },
          {
            "id": "collection-fetchable",
            "title": "Decades",
            "folders": [
              {
                "id": "folder-fetchable",
                "title": "2020s",
                "sources": [
                  { "provider": "addon", "type": "movie", "catalogId": "mdblist.91304" }
                ]
              }
            ]
          }
        ]
        """

        let layout = try CollectionOrganizerParser.parse(jsonData: Data(json.utf8))

        XCTAssertEqual(layout.collections.map(\.id), ["collection-discover", "collection-fetchable"])
        XCTAssertEqual(layout.folders.map(\.id), ["folder-discover", "folder-fetchable"])
        XCTAssertEqual(layout.folderCatalogs.map(\.catalogId), ["tmdb.discover.movie.new-movies.069d5312", "mdblist.91304"])
        XCTAssertEqual(layout.folderCatalogs.first?.genre, "Action")
        XCTAssertEqual(layout.folderCatalogs.first?.extras?["vote_count.gte"], "10")
        XCTAssertEqual(layout.folderCatalogs.first?.extras?["with_original_language"], "en")
        XCTAssertEqual(layout.folderCatalogs.first?.extras?["year"], "2026")
        XCTAssertTrue(layout.folderSources.isEmpty)
    }

    func testCatalogQueryBuildURLUsesPathExtras() {
        let query = CatalogService.StremioCatalogQuery(
            type: "movie",
            id: "tmdb.popular",
            baseURL: "https://example.com/stremio",
            extras: ["genre": "Science Fiction"]
        )

        XCTAssertEqual(
            query.buildURL(),
            "https://example.com/stremio/catalog/movie/tmdb.popular/genre=Science%20Fiction.json"
        )
    }

    func testFolderPaginationAppendsNextPageAndAdvancesState() {
        let row = CatalogRow(
            id: "folder-2020s",
            title: "2020s Movies",
            items: [
                MetaPreview(id: "tt1000001", type: .movie, name: "First Page")
            ],
            page: 0,
            hasMore: true
        )
        let nextPage = [
            MetaPreview(id: "tt2000001", type: .movie, name: "Next Page")
        ]

        let updated = CatalogRepository.folderRow(row, appending: nextPage, pageSize: 50)

        XCTAssertEqual(updated.items.map(\.id), ["tt1000001", "tt2000001"])
        XCTAssertEqual(updated.page, 1)
        XCTAssertFalse(updated.hasMore)
    }

    func testMetaResponseDecodesAIOMetadataStringCreditsAndTrailerAliases() throws {
        let json = """
        {
          "meta": {
            "id": "tt35672862",
            "type": "movie",
            "name": "Hokum",
            "director": "Damian McCarthy",
            "writer": "Damian McCarthy",
            "trailers": [
              { "source": "qU_i5e48KzQ", "type": "Trailer", "name": "Final Trailer", "ytId": "qU_i5e48KzQ" }
            ]
          }
        }
        """

        let detail = try MetaService.decodeMetaResponse(json: json, type: "movie", id: "tt35672862")

        XCTAssertEqual(detail.name, "Hokum")
        XCTAssertEqual(detail.director?.map(\.name), ["Damian McCarthy"])
        XCTAssertEqual(detail.writer?.map(\.name), ["Damian McCarthy"])
        XCTAssertEqual(detail.trailers?.first?.id, "qU_i5e48KzQ")
        XCTAssertEqual(detail.trailers?.first?.title, "Final Trailer")
        XCTAssertEqual(detail.trailers?.first?.youtubeId, "qU_i5e48KzQ")
    }

    func testMetaResponseRejectsMissingMetaObjectInsteadOfUnknownTitle() {
        let json = """
        {
          "streams": []
        }
        """

        XCTAssertThrowsError(
            try MetaService.decodeMetaResponse(json: json, type: "series", id: "tt9813792")
        )
    }

    func testMetaResponseRejectsMetadataWithoutNameInsteadOfUnknownTitle() {
        let json = """
        {
          "meta": {
            "id": "tt9813792",
            "type": "series",
            "videos": [
              { "id": "tt9813792:1:1", "season": 1, "episode": 1 }
            ]
          }
        }
        """

        XCTAssertThrowsError(
            try MetaService.decodeMetaResponse(json: json, type: "series", id: "tt9813792")
        )
    }

    @MainActor
    func testStreamAutoplayPreferencesDefaultToManualAndAllAutomaticAddons() {
        let suiteName = "StreamAutoplayPreferenceStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = StreamAutoplayPreferenceStore(defaults: defaults)

        XCTAssertEqual(store.mode(profileId: "profile-1"), .manual)
        XCTAssertTrue(store.automaticAddonUrls(profileId: "profile-1").isEmpty)
    }

    @MainActor
    func testStreamAutoplayPreferencesPersistModeAndAutomaticAddonUrlsPerProfile() {
        let suiteName = "StreamAutoplayPreferenceStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = StreamAutoplayPreferenceStore(defaults: defaults)

        store.setMode(.automatic, profileId: "profile-1")
        store.setAutomaticAddonUrls(["https://a.test/manifest.json", "https://b.test/manifest.json"], profileId: "profile-1")

        let reloaded = StreamAutoplayPreferenceStore(defaults: defaults)
        XCTAssertEqual(reloaded.mode(profileId: "profile-1"), .automatic)
        XCTAssertEqual(reloaded.automaticAddonUrls(profileId: "profile-1"), [
            "https://a.test/manifest.json",
            "https://b.test/manifest.json"
        ])
        XCTAssertEqual(reloaded.mode(profileId: "profile-2"), .manual)
        XCTAssertTrue(reloaded.automaticAddonUrls(profileId: "profile-2").isEmpty)
    }

    @MainActor
    func testStreamAutoplayPreferencesPersistUnlimitedOrBoundedTimeoutPerProfile() {
        let suiteName = "StreamAutoplayPreferenceStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = StreamAutoplayPreferenceStore(defaults: defaults)

        XCTAssertNil(store.timeoutSeconds(profileId: "profile-1"))
        store.setTimeoutSeconds(10, profileId: "profile-1")
        XCTAssertEqual(store.timeoutSeconds(profileId: "profile-1"), 10)
        store.setTimeoutSeconds(nil, profileId: "profile-1")
        XCTAssertNil(store.timeoutSeconds(profileId: "profile-1"))
    }

    func testStreamAutoplayPreferencesFilterAutomaticAddonsOnlyWhenSelectionExists() {
        let addonA = AddonManifest(
            id: "addon-a",
            name: "Addon A",
            version: "1.0.0",
            resources: [AddonResource(name: "stream", types: ["movie"])],
            transportUrl: "https://a.test"
        )
        let addonB = AddonManifest(
            id: "addon-b",
            name: "Addon B",
            version: "1.0.0",
            resources: [AddonResource(name: "stream", types: ["movie"])],
            transportUrl: "https://b.test"
        )
        let managed = [
            ManagedAddon(manifest: addonA, manifestUrl: "https://a.test/manifest.json"),
            ManagedAddon(manifest: addonB, manifestUrl: "https://b.test/manifest.json")
        ]

        XCTAssertEqual(
            StreamAutoplayPreferenceStore.automaticAddons(from: managed, selectedUrls: []).map(\.id),
            ["addon-a", "addon-b"]
        )
        XCTAssertEqual(
            StreamAutoplayPreferenceStore.automaticAddons(
                from: managed,
                selectedUrls: ["https://b.test/manifest.json"]
            ).map(\.id),
            ["addon-b"]
        )
    }

    func testMetaResponseDecodesVideoAliasesIntoSeasons() throws {
        let json = """
        {
          "meta": {
            "id": "tt0108778",
            "type": "series",
            "name": "Friends",
            "videos": [
              { "id": "tt0108778:1:1", "name": "Pilot", "number": 1, "season": 1, "description": "First episode", "firstAired": "1994-09-22T00:00:00.000Z" }
            ]
          }
        }
        """

        let detail = try MetaService.decodeMetaResponse(json: json, type: "series", id: "tt0108778")

        XCTAssertEqual(detail.videos?.first?.title, "Pilot")
        XCTAssertEqual(detail.videos?.first?.episode, 1)
        XCTAssertEqual(detail.videos?.first?.overview, "First episode")
        XCTAssertEqual(detail.videos?.first?.released, "1994-09-22T00:00:00.000Z")
        XCTAssertEqual(detail.seasons?.first?.number, 1)
        XCTAssertEqual(detail.seasons?.first?.episodes?.first?.id, "tt0108778:1:1")
    }

    func testMetaResponseDecodesSeasonEpisodeArtworkAliases() throws {
        let json = """
        {
          "meta": {
            "id": "tt3581920",
            "type": "series",
            "name": "The Last of Us",
            "seasons": [
              {
                "id": "1",
                "number": 1,
                "name": "Season 1",
                "episodes": [
                  { "id": "tt3581920:1:1", "title": "When You're Lost in the Darkness", "season": 1, "episode": 1, "still": "/still-one.jpg" },
                  { "id": "tt3581920:1:2", "title": "Infected", "season": 1, "episode": 2, "img": "https://cdn.example.com/img-two.jpg" },
                  { "id": "tt3581920:1:3", "title": "Long, Long Time", "season": 1, "episode": 3, "image": "/image-three.jpg" }
                ]
              }
            ]
          }
        }
        """

        let detail = try MetaService.decodeMetaResponse(
            json: json,
            type: "series",
            id: "tt3581920",
            baseURL: "https://addon.example.com"
        )

        let thumbnails = detail.seasons?.first?.episodes?.map(\.thumbnail)
        XCTAssertEqual(thumbnails, [
            "https://addon.example.com/still-one.jpg",
            "https://cdn.example.com/img-two.jpg",
            "https://addon.example.com/image-three.jpg"
        ])
    }

    func testMetaResponseFallsBackToEpisodeStillWhenThumbnailIsEmpty() throws {
        let json = """
        {
          "meta": {
            "id": "tt9813792",
            "type": "series",
            "name": "FROM",
            "seasons": [
              {
                "id": "1",
                "number": 1,
                "episodes": [
                  {
                    "id": "tt9813792:1:1",
                    "title": "Long Day's Journey Into Night",
                    "season": 1,
                    "episode": 1,
                    "thumbnail": "",
                    "still": "https://artworks.thetvdb.com/banners/v4/episode/9041115/screencap/640x360.jpg"
                  }
                ]
              }
            ]
          }
        }
        """

        let detail = try MetaService.decodeMetaResponse(json: json, type: "series", id: "tt9813792")

        XCTAssertEqual(
            detail.seasons?.first?.episodes?.first?.thumbnail,
            "https://artworks.thetvdb.com/banners/v4/episode/9041115/screencap/640x360.jpg"
        )
    }

    func testMetaResponseNeverKeepsTopPostersEpisodeThumbnail() throws {
        let json = """
        {
          "meta": {
            "id": "tt9813792",
            "type": "series",
            "name": "FROM",
            "videos": [
              {
                "id": "tt9813792:1:1",
                "title": "Long Day's Journey Into Night",
                "season": 1,
                "episode": 1,
                "thumbnail": "https://api.top-posters.com/key/imdb/thumbnail/tt9813792/S1E1.jpg?fallback_url=https%3A%2F%2Fartworks.thetvdb.com%2Fbanners%2Fv4%2Fepisode%2F8808273%2Fscreencap%2F620b569ddb24c.jpg"
              },
              {
                "id": "tt9813792:1:2",
                "title": "The Way Things Are Now",
                "season": 1,
                "episode": 2,
                "thumbnail": "https://api.top-posters.com/key/imdb/thumbnail/tt9813792/S1E2.jpg"
              }
            ]
          }
        }
        """

        let detail = try MetaService.decodeMetaResponse(json: json, type: "series", id: "tt9813792")
        let episodes = detail.seasons?.first?.episodes

        XCTAssertEqual(
            episodes?.first?.thumbnail,
            "https://artworks.thetvdb.com/banners/v4/episode/8808273/screencap/620b569ddb24c.jpg"
        )
        XCTAssertNil(episodes?.dropFirst().first?.thumbnail)
    }

    func testMetaResponseDecodesDoubleEncodedTopPostersFallback() throws {
        let json = """
        {
          "meta": {
            "id": "tt9813792",
            "type": "series",
            "name": "FROM",
            "videos": [
              {
                "id": "tt9813792:1:2",
                "title": "The Way Things Are Now",
                "season": 1,
                "episode": 2,
                "thumbnail": "https://api.top-posters.com/key/imdb/thumbnail/tt9813792/S1E2.jpg?fallback_url=https%253A%252F%252Fartworks.thetvdb.com%252Fbanners%252Fv4%252Fepisode%252F8808282%252Fscreencap%252F620bc13566384.jpg"
              }
            ]
          }
        }
        """

        let detail = try MetaService.decodeMetaResponse(json: json, type: "series", id: "tt9813792")

        XCTAssertEqual(
            detail.seasons?.first?.episodes?.first?.thumbnail,
            "https://artworks.thetvdb.com/banners/v4/episode/8808282/screencap/620bc13566384.jpg"
        )
    }

    @MainActor
    func testMetadataIntegrationStorePersistsTrimmedAPIKeys() {
        let suiteName = "MetadataIntegrationStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = MetadataIntegrationStore(defaults: defaults)

        store.setTVDBAPIKey("  tvdb-key  ")
        store.setTMDBAPIKey("  tmdb-key  ")

        let reloaded = MetadataIntegrationStore(defaults: defaults)
        XCTAssertEqual(reloaded.tvdbAPIKey, "tvdb-key")
        XCTAssertEqual(reloaded.tmdbAPIKey, "tmdb-key")
    }

    func testEpisodeStillMergePrefersTVDBThenTMDBThenAddonImages() {
        let detail = MetaDetail(
            id: "tt9813792",
            type: .series,
            name: "FROM",
            seasons: [
                Season(
                    id: "1",
                    number: 1,
                    episodes: [
                        MetaVideo(id: "tt9813792:1:1", title: "TVDB overwrites addon", thumbnail: "https://addon.example.com/existing.jpg", season: 1, episode: 1),
                        MetaVideo(id: "tt9813792:1:2", title: "TVDB wins over TMDB", thumbnail: "https://addon.example.com/existing-2.jpg", season: 1, episode: 2),
                        MetaVideo(id: "tt9813792:1:3", title: "TMDB fallback", thumbnail: "https://addon.example.com/existing-3.jpg", season: 1, episode: 3),
                        MetaVideo(id: "tt9813792:1:4", title: "Addon fallback", thumbnail: "https://addon.example.com/existing-4.jpg", season: 1, episode: 4)
                    ]
                )
            ]
        )

        let merged = MetaRepository.mergeEpisodeStills(
            into: detail,
            tvdbStills: [
                EpisodeStillKey(season: 1, episode: 1): "https://artworks.thetvdb.com/s1.jpg",
                EpisodeStillKey(season: 1, episode: 2): "https://artworks.thetvdb.com/s2.jpg"
            ],
            tmdbStills: [
                EpisodeStillKey(season: 1, episode: 2): "https://image.tmdb.org/t/p/w400/s2.jpg",
                EpisodeStillKey(season: 1, episode: 3): "https://image.tmdb.org/t/p/w400/s3.jpg"
            ]
        )

        let thumbnails = merged.seasons?.first?.episodes?.map(\.thumbnail)
        XCTAssertEqual(thumbnails, [
            "https://artworks.thetvdb.com/s1.jpg",
            "https://artworks.thetvdb.com/s2.jpg",
            "https://image.tmdb.org/t/p/w400/s3.jpg",
            "https://addon.example.com/existing-4.jpg"
        ])
    }

    func testMetadataProviderConnectionStateLabels() {
        XCTAssertEqual(MetadataProviderConnectionState.missing.label, "Missing")
        XCTAssertEqual(MetadataProviderConnectionState.checking.label, "Checking...")
        XCTAssertEqual(MetadataProviderConnectionState.connected.label, "Connected")
        XCTAssertEqual(MetadataProviderConnectionState.failed("Invalid API key").label, "Invalid API key")
        XCTAssertTrue(MetadataProviderConnectionState.connected.isConnected)
        XCTAssertFalse(MetadataProviderConnectionState.failed("Invalid API key").isConnected)
    }

    func testPlayerControlVisibilityShowsOnInteractionAndHidesWhilePlaying() {
        var state = PlayerControlVisibilityState()

        XCTAssertTrue(state.controlsVisible)

        state.setPlayback(isPlaying: true)
        state.registerInteraction()
        XCTAssertTrue(state.controlsVisible)
        XCTAssertTrue(state.shouldScheduleAutoHide)

        state.hideAfterInactivityIfAllowed()
        XCTAssertFalse(state.controlsVisible)
    }

    func testPlayerControlVisibilityStaysVisibleWhilePaused() {
        var state = PlayerControlVisibilityState()

        state.setPlayback(isPlaying: false)
        state.registerInteraction()
        XCTAssertTrue(state.controlsVisible)
        XCTAssertFalse(state.shouldScheduleAutoHide)

        state.hideAfterInactivityIfAllowed()
        XCTAssertTrue(state.controlsVisible)
    }

    func testGroupedFolderArtworkDisablesFocusGifs() {
        let collection = DBCollection(id: "directors", name: "Directors", sortOrder: 0)
        let folder = DBFolder(
            id: "ridley-scott",
            collectionId: "directors",
            name: "Ridley Scott",
            sortOrder: 0,
            coverImage: "https://example.com/director.jpg",
            focusGif: "https://example.com/director.gif",
            tileShape: "landscape",
            focusGifEnabled: true
        )
        let folderRow = CatalogRow(
            id: "folder_ridley-scott",
            title: "Ridley Scott",
            items: [],
            tileShape: folder.tileShape,
            coverImage: folder.coverImage,
            focusGif: folder.focusGif,
            focusGifEnabled: folder.focusGifEnabled
        )

        let rows = CatalogRepository.displayRows(
            for: collection,
            folders: [folder, DBFolder(id: "other", collectionId: "directors", name: "Other", sortOrder: 1)],
            folderRows: [
                folderRow,
                CatalogRow(id: "folder_other", title: "Other", items: [], tileShape: "landscape")
            ],
            preferences: CollectionDisplayPreferences(
                enabledCollectionIds: ["directors"],
                expandedCollectionIds: [],
                hiddenFolderIds: []
            )
        )

        XCTAssertEqual(rows.first?.items.first?.poster, "https://example.com/director.jpg")
        XCTAssertEqual(rows.first?.items.first?.banner, "https://example.com/director.jpg")
        XCTAssertEqual(rows.first?.tileShape, "landscape")
    }

    func testStreamServiceDoesNotFetchSyntheticFolderIds() async throws {
        let streams = try await StreamService.shared.fetchStreams(
            type: "movie",
            id: "folder_folder-JRWZVYWG",
            baseURL: "https://example.invalid/stremio"
        )

        XCTAssertTrue(streams.isEmpty)
    }
}
