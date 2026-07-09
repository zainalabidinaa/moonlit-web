import XCTest
@testable import MoonlitCore

final class DownloadTests: XCTestCase {
    func testHLSNotDownloadable() {
        XCTAssertFalse(DownloadSupport.isDownloadable("https://x.com/master.m3u8"))
        XCTAssertFalse(DownloadSupport.isDownloadable("https://x.com/live.m3u8?token=1"))
    }
    func testDirectFilesDownloadable() {
        XCTAssertTrue(DownloadSupport.isDownloadable("https://x.com/movie.mkv"))
        XCTAssertTrue(DownloadSupport.isDownloadable("https://x.com/movie.mp4?e=9"))
    }
    func testProgressFraction() {
        var item = DownloadItem(id: "1", mediaId: "tt1", type: "movie", name: "M",
                                poster: nil, quality: "1080p",
                                remoteURL: "https://x/m.mp4", localFileName: "1.mp4",
                                totalBytes: 200, receivedBytes: 50, state: .downloading,
                                createdAt: Date())
        XCTAssertEqual(item.progress, 0.25, accuracy: 0.001)
        item.totalBytes = 0
        XCTAssertEqual(item.progress, 0)
    }
    func testCodableRoundTrip() throws {
        let item = DownloadItem(id: "1", mediaId: "tt1", type: "movie", name: "M",
                                poster: "p", quality: nil, remoteURL: "u",
                                localFileName: "1.mp4", totalBytes: 10, receivedBytes: 10,
                                state: .completed, createdAt: Date(timeIntervalSince1970: 0))
        let data = try JSONEncoder().encode(item)
        let back = try JSONDecoder().decode(DownloadItem.self, from: data)
        XCTAssertEqual(back, item)
    }
}
