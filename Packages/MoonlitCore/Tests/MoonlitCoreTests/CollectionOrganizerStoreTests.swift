import XCTest
@testable import MoonlitCore

/// Covers the broken home-organizer refresh: the edge function requires
/// Supabase auth headers (a bare GET gets HTTP 401, which deletes the cache
/// and silently reverts the app to fallback layouts), and a cached remote
/// layout must be merged onto the bundle rather than replace it, so a partial
/// cache can never drop bundle-only collections for 24 hours.
final class CollectionOrganizerStoreTests: XCTestCase {

    private func layoutJSON(collectionTitle: String, folderTitle: String) -> String {
        """
        [
          {
            "id": "col-\(collectionTitle)",
            "title": "\(collectionTitle)",
            "folders": [
              {
                "id": "folder-\(folderTitle)",
                "title": "\(folderTitle)",
                "sources": [
                  { "provider": "addon", "type": "movie", "catalogId": "mdblist.91304" }
                ]
              }
            ]
          }
        ]
        """
    }

    func testRemoteRequestCarriesSupabaseAuthHeaders() throws {
        let url = try XCTUnwrap(URL(string: "https://example.supabase.co/functions/v1/home-organizer"))

        let request = CollectionOrganizerStore.remoteRequest(url: url, apiKey: "anon-key-123")

        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "anon-key-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer anon-key-123")
    }

    func testCachedLayoutMergesOntoBundlePreservingBundleOnlyCollections() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("organizer-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cacheURL = dir.appendingPathComponent("home-organizer.json")

        let cachedJSON = layoutJSON(collectionTitle: "Horror Vault", folderTitle: "Horror Vault")
        try Data(cachedJSON.utf8).write(to: cacheURL)

        let bundledJSON = layoutJSON(collectionTitle: "Trending Shows", folderTitle: "Trending")
        let store = CollectionOrganizerStore(cacheURL: cacheURL, session: .shared)

        let layout = try store.cachedOrBundledLayout(bundledData: Data(bundledJSON.utf8))

        XCTAssertEqual(
            Set(layout.collections.map(\.name)),
            ["Trending Shows", "Horror Vault"],
            "A cached remote layout must merge onto the bundle, not replace it"
        )
    }
}
