import XCTest
@testable import MoonlitCore

/// Covers the on-disk behavior that caused the CatalogResponseCache to
/// balloon memory and disk writes: it used to re-encode and rewrite the
/// *entire* cache as one JSON file on every `set()`. These tests pin the
/// per-entry file layout and orphan cleanup that replaced it.
final class CatalogResponseCacheTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CatalogResponseCacheTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSetWritesOnlyOneSmallFilePerKey() {
        let cache = CatalogResponseCache(directory: tempDir)
        let payload = Data(repeating: 0x41, count: 1_000_000)

        cache.set(key: "catalog/movie/popular", data: payload)
        waitForSaveQueue(cache)

        let files = try? FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(files?.count, 1, "set() should write exactly one file for one key")
    }

    func testSetDoesNotRewriteUnrelatedEntries() {
        let cache = CatalogResponseCache(directory: tempDir)
        cache.set(key: "a", data: Data([1]))
        waitForSaveQueue(cache)

        let fileA = try! FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil).first!
        let mtimeBefore = try! FileManager.default.attributesOfItem(atPath: fileA.path)[.modificationDate] as! Date

        cache.set(key: "b", data: Data([2]))
        waitForSaveQueue(cache)

        let mtimeAfter = try! FileManager.default.attributesOfItem(atPath: fileA.path)[.modificationDate] as! Date
        XCTAssertEqual(mtimeBefore, mtimeAfter, "writing key b must not touch key a's file")
    }

    func testGetRoundTripsAcrossInstances() {
        let cache1 = CatalogResponseCache(directory: tempDir)
        cache1.set(key: "catalog/movie/popular", data: Data("hello".utf8))
        waitForSaveQueue(cache1)

        let cache2 = CatalogResponseCache(directory: tempDir)
        XCTAssertEqual(cache2.get(key: "catalog/movie/popular"), Data("hello".utf8))
    }

    func testOrphanedAtomicWriteTempFilesAreCleanedUpOnInit() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let orphan = tempDir.appendingPathComponent("deadbeef.json.sb-abc123-xyz789")
        try Data("stale".utf8).write(to: orphan)

        _ = CatalogResponseCache(directory: tempDir)

        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path),
                        "orphaned .sb- temp files from interrupted atomic writes must be swept on init")
    }

    func testExpiredEntryIsEvictedAndFileRemoved() {
        let cache = CatalogResponseCache(directory: tempDir)
        cache.set(key: "genre=action", data: Data([9]), now: Date(timeIntervalSinceNow: -7 * 3600))
        waitForSaveQueue(cache)

        XCTAssertNil(cache.get(key: "genre=action"))
    }

    private func waitForSaveQueue(_ cache: CatalogResponseCache) {
        let exp = expectation(description: "save queue drained")
        cache.drainSaveQueueForTesting { exp.fulfill() }
        wait(for: [exp], timeout: 2)
    }
}
