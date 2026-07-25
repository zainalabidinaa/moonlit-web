import XCTest
@testable import MoonlitCore

/// Covers the "media gone from Horror Vault" bug: resolving each collection
/// part's IMDB id used one unbounded request per movie, so opening a folder
/// with many franchise collections fired 200+ concurrent TMDB calls, got
/// rate-limited, and silently dropped every movie whose lookup failed.
/// Resolution must be bounded, order-preserving, and retry transient failures.
final class TMDBCollectionResolutionTests: XCTestCase {

    private func part(_ tmdbId: Int, title: String? = nil, releaseDate: String? = nil) -> CatalogRepository.CollectionPart {
        CatalogRepository.CollectionPart(tmdbId: tmdbId, title: title ?? "Movie \(tmdbId)", releaseDate: releaseDate)
    }

    func testResolvesAllPartsPreservingInputOrder() async {
        let parts = (1...20).map { part($0) }

        let items = await CatalogRepository.resolveCollectionParts(parts) { tmdbId in
            "tt\(tmdbId)"
        }

        XCTAssertEqual(items.map(\.id), (1...20).map { "tt\($0)" })
        XCTAssertEqual(items.first?.name, "Movie 1")
    }

    func testBuildsPreviewFieldsFromPart() async {
        let parts = [part(7, title: "Halloween", releaseDate: "1978-10-25")]

        let items = await CatalogRepository.resolveCollectionParts(parts) { _ in "tt0077651" }

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, "tt0077651")
        XCTAssertEqual(items[0].name, "Halloween")
        XCTAssertEqual(items[0].releaseInfo, "1978")
        XCTAssertEqual(items[0].rawReleaseDate, "1978-10-25")
        XCTAssertEqual(items[0].type, .movie)
    }

    func testConcurrencyIsBoundedByChunkSize() async {
        actor Tracker {
            var current = 0
            var maxSeen = 0
            func enter() {
                current += 1
                maxSeen = max(maxSeen, current)
            }
            func exit() { current -= 1 }
        }
        let tracker = Tracker()
        let parts = (1...30).map { part($0) }

        _ = await CatalogRepository.resolveCollectionParts(parts, chunkSize: 6) { tmdbId in
            await tracker.enter()
            try? await Task.sleep(nanoseconds: 10_000_000)
            await tracker.exit()
            return "tt\(tmdbId)"
        }

        let maxSeen = await tracker.maxSeen
        XCTAssertLessThanOrEqual(maxSeen, 6)
    }

    func testRetriesFailedResolutionOnceAndRecoversItem() async {
        actor CallLog {
            var calls: [Int: Int] = [:]
            func record(_ id: Int) -> Int {
                calls[id, default: 0] += 1
                return calls[id]!
            }
            func count(for id: Int) -> Int { calls[id] ?? 0 }
        }
        let log = CallLog()
        let parts = [part(1), part(2), part(3)]

        let items = await CatalogRepository.resolveCollectionParts(parts) { tmdbId in
            let attempt = await log.record(tmdbId)
            if tmdbId == 2 && attempt == 1 { return nil }
            return "tt\(tmdbId)"
        }

        XCTAssertEqual(items.map(\.id), ["tt1", "tt2", "tt3"])
        let retried = await log.count(for: 2)
        XCTAssertEqual(retried, 2)
        let untouched = await log.count(for: 1)
        XCTAssertEqual(untouched, 1)
    }

    func testDropsPartsThatStillFailAfterRetry() async {
        actor CallLog {
            var calls: [Int: Int] = [:]
            func record(_ id: Int) { calls[id, default: 0] += 1 }
            func count(for id: Int) -> Int { calls[id] ?? 0 }
        }
        let log = CallLog()
        let parts = [part(1), part(2), part(3)]

        let items = await CatalogRepository.resolveCollectionParts(parts) { tmdbId in
            await log.record(tmdbId)
            return tmdbId == 2 ? nil : "tt\(tmdbId)"
        }

        XCTAssertEqual(items.map(\.id), ["tt1", "tt3"])
        let attempts = await log.count(for: 2)
        XCTAssertEqual(attempts, 2)
    }

    func testDropsNonImdbIdentifiers() async {
        let parts = [part(1), part(2)]

        let items = await CatalogRepository.resolveCollectionParts(parts) { tmdbId in
            tmdbId == 1 ? "12345" : "tt2"
        }

        XCTAssertEqual(items.map(\.id), ["tt2"])
    }

    // MARK: - IMDB id cache poisoning

    func testCachesResolvedIdOn200() {
        XCTAssertEqual(TMDBDiscoverService.imdbCacheEntry(statusCode: 200, imdbId: "tt0077651"), "tt0077651")
    }

    func testCachesConfirmedMissAsEmptyStringOn200() {
        XCTAssertEqual(TMDBDiscoverService.imdbCacheEntry(statusCode: 200, imdbId: nil), "")
    }

    func testDoesNotCacheRateLimitedResponseAsMiss() {
        XCTAssertNil(TMDBDiscoverService.imdbCacheEntry(statusCode: 429, imdbId: nil))
        XCTAssertNil(TMDBDiscoverService.imdbCacheEntry(statusCode: 401, imdbId: nil))
    }
}
