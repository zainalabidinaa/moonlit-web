import XCTest
@testable import MoonlitCore

/// Covers the catch-up / timeshift URL builder (adapted from a reference
/// implementation): type detection and URL construction for flussonic, Xtream timeshift, and generic
/// `catchup-source` templates.
final class CatchupTests: XCTestCase {

    // A fixed program window so timestamps are deterministic.
    // 2026-07-15 12:00:00 UTC → 13:00:00 UTC.
    private let startMs: Double = 1_784_116_800_000
    private var endMs: Double { startMs + 3_600_000 }
    private var nowMs: Double { endMs + 600_000 } // 10 min after it ended

    private func channel(type: String? = nil, source: String? = nil, url: String) -> IPTVChannel {
        IPTVChannel(id: "c", name: "Test", url: url, catchupType: type, catchupSource: source)
    }

    // MARK: - Detection

    func testDetectsFlussonic() {
        XCTAssertEqual(IPTVCatchup.detectType(channel(type: "flussonic", url: "http://h/live/s.ts")), .flussonic)
        XCTAssertEqual(IPTVCatchup.detectType(channel(type: "fs", url: "http://h/live/s.ts")), .flussonic)
    }

    func testDetectsXtreamByTypeAndByUrlShape() {
        XCTAssertEqual(IPTVCatchup.detectType(channel(type: "xtream", url: "http://h/x")), .xtream)
        // No explicit type, but the URL is an Xtream live URL.
        XCTAssertEqual(IPTVCatchup.detectType(channel(url: "http://host:8080/live/user/pass/123.ts")), .xtream)
    }

    func testCatchupSourceImpliesDefault() {
        XCTAssertEqual(IPTVCatchup.detectType(channel(source: "?utc=${start}", url: "http://h/s")), .default)
    }

    func testNoCatchupReturnsNil() {
        XCTAssertNil(IPTVCatchup.detectType(channel(url: "http://h/plain/stream")))
    }

    // MARK: - Flussonic

    func testFlussonicUrlFromTsFile() {
        let ch = channel(type: "flussonic", url: "http://host/ch1/index.ts?token=abc")
        let url = IPTVCatchup.buildURL(for: ch, startMs: startMs, endMs: endMs, nowMs: nowMs)
        // start = 1784116800 sec, duration = 3600 sec
        XCTAssertEqual(url, "http://host/ch1/index-1784116800-3600.ts?token=abc")
    }

    func testFlussonicFallbackWhenNoFileStem() {
        let ch = channel(type: "flussonic", url: "http://host/ch1/")
        let url = IPTVCatchup.buildURL(for: ch, startMs: startMs, endMs: endMs, nowMs: nowMs)
        XCTAssertEqual(url, "http://host/ch1/archive-1784116800-3600.ts")
    }

    // MARK: - Xtream timeshift

    func testXtreamTimeshiftUrl() {
        let ch = channel(type: "xtream", url: "http://host:8080/live/user/pass/456.ts")
        let url = IPTVCatchup.buildURL(for: ch, startMs: startMs, endMs: endMs, nowMs: nowMs)
        // mins = 60, stamp = 2026-07-15:12-00
        XCTAssertEqual(url, "http://host:8080/timeshift/user/pass/60/2026-07-15:12-00/456.ts")
    }

    // MARK: - Generic templates

    func testAbsoluteTemplateSubstitution() {
        let ch = channel(source: "http://cdn/replay?start=${start}&end=${utcend}&dur=${duration-minutes}", url: "http://h/s")
        let url = IPTVCatchup.buildURL(for: ch, startMs: startMs, endMs: endMs, nowMs: nowMs)
        XCTAssertEqual(url, "http://cdn/replay?start=1784116800&end=1784120400&dur=60")
    }

    func testDateFormatTokenSubstitution() {
        let ch = channel(source: "http://cdn/${start:Y-m-d/H-M-S}.m3u8", url: "http://h/s")
        let url = IPTVCatchup.buildURL(for: ch, startMs: startMs, endMs: endMs, nowMs: nowMs)
        XCTAssertEqual(url, "http://cdn/2026-07-15/12-00-00.m3u8")
    }

    func testRelativeTemplateAppendedToStreamUrl() {
        let ch = channel(source: "?utc={utc}&lutc={lutc}", url: "http://host/stream.ts")
        let url = IPTVCatchup.buildURL(for: ch, startMs: startMs, endMs: endMs, nowMs: nowMs)
        XCTAssertEqual(url, "http://host/stream.ts?utc=1784116800&lutc=\(Int(nowMs / 1000))")
    }

    func testDefaultFallbackAppendsUtcParams() {
        // catchup type "default" with no source → append ?utc=&lutc=.
        let ch = channel(type: "default", url: "http://host/stream.ts")
        let url = IPTVCatchup.buildURL(for: ch, startMs: startMs, endMs: endMs, nowMs: nowMs)
        XCTAssertEqual(url, "http://host/stream.ts?utc=1784116800&lutc=\(Int(nowMs / 1000))")
    }

    func testNoCatchupReturnsNilUrl() {
        let ch = channel(url: "http://host/plain")
        XCTAssertNil(IPTVCatchup.buildURL(for: ch, startMs: startMs, endMs: endMs, nowMs: nowMs))
    }
}
