import XCTest
@testable import MoonlitCore

/// Covers the hand-ported IPTV parsing logic (M3U line-scanner, Xtream URL
/// building, source-shape detection) against the tricky real-world cases the
/// the reference port has to handle: quoted attributes, sticky groups, per-channel
/// request headers, and decorative separator rows.
final class IPTVParsingTests: XCTestCase {

    // MARK: - M3U

    func testParsesStandardExtinfAttributes() {
        let m3u = """
        #EXTM3U
        #EXTINF:-1 tvg-id="bbc1.uk" tvg-logo="http://logos/bbc1.png" group-title="UK",BBC One HD
        http://example.com/bbc1.ts
        """
        let channels = M3UParser.parse(m3u, baseId: "src1")
        XCTAssertEqual(channels.count, 1)
        let ch = channels[0]
        XCTAssertEqual(ch.name, "BBC One HD")
        XCTAssertEqual(ch.tvgId, "bbc1.uk")
        XCTAssertEqual(ch.logo, "http://logos/bbc1.png")
        XCTAssertEqual(ch.group, "UK")
        XCTAssertEqual(ch.url, "http://example.com/bbc1.ts")
    }

    func testTitleWithCommaAfterQuotedAttributes() {
        // The display title itself contains a comma — the attr/title split must key
        // off the last closing quote, not the first comma.
        let m3u = """
        #EXTM3U
        #EXTINF:-1 tvg-id="x" group-title="News",CNN, International
        http://example.com/cnn.ts
        """
        let channels = M3UParser.parse(m3u, baseId: "src1")
        XCTAssertEqual(channels.first?.name, "CNN, International")
    }

    func testStickyGroupFromExtgrpAppliesToFollowingChannels() {
        let m3u = """
        #EXTM3U
        #EXTGRP:Sports
        #EXTINF:-1,ESPN
        http://example.com/espn.ts
        #EXTINF:-1,Fox Sports
        http://example.com/fox.ts
        """
        let channels = M3UParser.parse(m3u, baseId: "src1")
        XCTAssertEqual(channels.count, 2)
        XCTAssertEqual(channels[0].group, "Sports")
        XCTAssertEqual(channels[1].group, "Sports")
    }

    func testExtVlcOptBecomesRequestHeaders() {
        let m3u = """
        #EXTM3U
        #EXTINF:-1,Protected
        #EXTVLCOPT:http-user-agent=MyPlayer/1.0
        #EXTVLCOPT:http-referrer=http://ref.example
        http://example.com/protected.ts
        """
        let ch = M3UParser.parse(m3u, baseId: "src1").first
        XCTAssertEqual(ch?.headers?["User-Agent"], "MyPlayer/1.0")
        XCTAssertEqual(ch?.headers?["Referer"], "http://ref.example")
    }

    func testPipeDelimitedUrlParamsBecomeHeaders() {
        let m3u = """
        #EXTM3U
        #EXTINF:-1,Piped
        http://example.com/piped.ts|User-Agent=PipeAgent&Referer=http%3A%2F%2Fsite.example
        """
        let ch = M3UParser.parse(m3u, baseId: "src1").first
        // The URL is stripped of its pipe suffix; params become headers (percent-decoded).
        XCTAssertEqual(ch?.url, "http://example.com/piped.ts")
        XCTAssertEqual(ch?.headers?["User-Agent"], "PipeAgent")
        XCTAssertEqual(ch?.headers?["Referer"], "http://site.example")
    }

    func testDecorativeSeparatorRowsAreFiltered() {
        let m3u = """
        #EXTM3U
        #EXTINF:-1,▓▓▓▓▓▓▓▓▓▓
        http://example.com/sep.ts
        #EXTINF:-1,======
        http://example.com/sep2.ts
        #EXTINF:-1,Real Channel
        http://example.com/real.ts
        """
        let channels = M3UParser.parse(m3u, baseId: "src1")
        XCTAssertEqual(channels.map(\.name), ["Real Channel"])
    }

    func testChannelIdsAreUniqueWithinPlaylist() {
        let m3u = """
        #EXTM3U
        #EXTINF:-1,Same Name
        http://example.com/a.ts
        #EXTINF:-1,Same Name
        http://example.com/b.ts
        """
        let channels = M3UParser.parse(m3u, baseId: "src1")
        XCTAssertEqual(Set(channels.map(\.id)).count, 2)
    }

    func testCrlfLineEndingsAndBomAreHandled() {
        let m3u = "\u{FEFF}#EXTM3U\r\n#EXTINF:-1,Windows Channel\r\nhttp://example.com/win.ts\r\n"
        let channels = M3UParser.parse(m3u, baseId: "src1")
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels.first?.name, "Windows Channel")
    }

    func testDerivesEpgUrlsFromXtreamGetPhp() {
        let urls = M3UParser.deriveEpgUrls(from: "http://host:8080/get.php?username=u&password=p&type=m3u_plus")
        XCTAssertTrue(urls.contains { $0.hasPrefix("http://host:8080/xmltv.php") && $0.contains("username=u") })
    }

    // MARK: - Xtream

    func testXtreamCredsResolveFromServer() {
        let creds = XtreamClient.resolve(XtreamCredentials(server: "http://iptv.example:8080/", username: "u", password: "p"))
        XCTAssertEqual(creds?.base, "http://iptv.example:8080")
        XCTAssertEqual(creds?.username, "u")
    }

    func testXtreamRejectsNonHttpServer() {
        XCTAssertNil(XtreamClient.resolve(XtreamCredentials(server: "ftp://bad", username: "u", password: "p")))
        XCTAssertNil(XtreamClient.resolve(XtreamCredentials(server: "http://ok", username: "", password: "p")))
    }

    func testBuildsLiveStreamUrl() {
        let creds = XtreamClient.ResolvedCreds(base: "http://host:8080", username: "user", password: "pass")
        let url = XtreamClient.buildLiveStreamURL(creds, streamId: "12345", container: .ts)
        XCTAssertEqual(url, "http://host:8080/live/user/pass/12345.ts")
    }

    func testParsesXtreamUrlWithCredentials() {
        let creds = XtreamClient.parseUrl("http://host:8080/player_api.php?username=alice&password=secret")
        XCTAssertEqual(creds?.base, "http://host:8080")
        XCTAssertEqual(creds?.username, "alice")
        XCTAssertEqual(creds?.password, "secret")
    }

    // MARK: - Detection

    func testDetectsRawM3UAsNonMiddleware() {
        let source = IPTVPlaylistSource(name: "Raw", url: "http://host/playlist.m3u8", kind: .m3u)
        if case .m3u(_, let middleware) = IPTVSourceDetector.detect(source) {
            XCTAssertFalse(middleware)
        } else {
            XCTFail("Expected .m3u shape")
        }
    }

    func testDetectsMiddlewarePath() {
        let source = IPTVPlaylistSource(name: "Mid", url: "http://host/iptv/list", kind: .m3u)
        if case .m3u(_, let middleware) = IPTVSourceDetector.detect(source) {
            XCTAssertTrue(middleware)
        } else {
            XCTFail("Expected .m3u shape")
        }
    }

    func testDetectsXtreamFromCredentials() {
        let source = IPTVPlaylistSource(
            name: "XT", url: "", kind: .xtream,
            xtream: XtreamCredentials(server: "http://host:8080", username: "u", password: "p")
        )
        if case .xtream(let creds) = IPTVSourceDetector.detect(source) {
            XCTAssertEqual(creds.base, "http://host:8080")
        } else {
            XCTFail("Expected .xtream shape")
        }
    }

    func testChannelsGroupedInFirstSeenOrderWithUngroupedLast() {
        let channels = [
            IPTVChannel(id: "1", name: "A", group: "News", url: "http://x/1"),
            IPTVChannel(id: "2", name: "B", group: nil, url: "http://x/2"),
            IPTVChannel(id: "3", name: "C", group: "Sports", url: "http://x/3"),
            IPTVChannel(id: "4", name: "D", group: "News", url: "http://x/4"),
        ]
        let playlist = IPTVPlaylist(id: "p", name: "P", channels: channels, groups: ["News", "Sports"])
        let grouped = playlist.channelsByGroup
        XCTAssertEqual(grouped.map(\.group), ["News", "Sports", IPTVPlaylist.ungrouped])
        XCTAssertEqual(grouped[0].channels.map(\.id), ["1", "4"])
        XCTAssertEqual(grouped[2].channels.map(\.id), ["2"])
    }
}
