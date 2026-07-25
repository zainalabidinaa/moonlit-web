import XCTest
@testable import MoonlitCore

/// Covers the hand-ported EPG logic: XMLTV block parsing + entity/CDATA decoding,
/// timestamp/timezone conversion, binary-search now/next, and channel→EPG resolution
/// (direct tvg-id, normalized-name fallback, manual override).
final class EPGParsingTests: XCTestCase {

    private let sampleXMLTV = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv>
      <channel id="bbc1.uk"><display-name>BBC One HD</display-name><icon src="http://logo/bbc1.png"/></channel>
      <programme start="20260715120000 +0000" stop="20260715130000 +0000" channel="bbc1.uk">
        <title>News &amp; Weather</title>
        <desc><![CDATA[The latest headlines]]></desc>
        <category>News</category>
      </programme>
      <programme start="20260715130000 +0000" stop="20260715140000 +0000" channel="bbc1.uk">
        <title>Afternoon Drama</title>
      </programme>
    </tv>
    """

    // MARK: - Parsing

    func testParsesChannelsAndProgrammes() {
        let result = XMLTVParser.parse(sampleXMLTV)
        XCTAssertEqual(result.programs.count, 2)
        XCTAssertEqual(result.channelMeta["bbc1.uk"]?.displayName, "BBC One HD")
        XCTAssertEqual(result.channelMeta["bbc1.uk"]?.icon, "http://logo/bbc1.png")

        let first = result.programs[0]
        XCTAssertEqual(first.channelTvgId, "bbc1.uk")
        XCTAssertEqual(first.title, "News & Weather", "entities should be decoded")
        XCTAssertEqual(first.description, "The latest headlines", "CDATA should be unwrapped")
        XCTAssertEqual(first.category, "News")
    }

    func testProgrammeWithoutTitleGetsUntitledFallbackAndNilDesc() {
        let result = XMLTVParser.parse(sampleXMLTV)
        XCTAssertEqual(result.programs[1].title, "Afternoon Drama")
        XCTAssertNil(result.programs[1].description)
    }

    func testNumericEntitiesDecoded() {
        let xml = """
        <tv><programme start="20260101000000 +0000" stop="20260101010000 +0000" channel="c">
        <title>Caf&#233; &#x2764; Show</title></programme></tv>
        """
        let program = XMLTVParser.parse(xml).programs.first
        XCTAssertEqual(program?.title, "Café ❤ Show")
    }

    // MARK: - Timestamps

    func testXmltvTimeUTC() {
        let ms = XMLTVParser.parseXmltvTime("20260715120000 +0000")
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 15; comps.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(ms, cal.date(from: comps)!.timeIntervalSince1970 * 1000, accuracy: 1)
    }

    func testXmltvTimeAppliesTimezoneOffset() {
        // +0100 is one hour ahead of UTC, so the UTC instant is one hour earlier.
        let utc = XMLTVParser.parseXmltvTime("20260715120000 +0000")
        let plusOne = XMLTVParser.parseXmltvTime("20260715120000 +0100")
        XCTAssertEqual(utc - plusOne, 3_600_000, accuracy: 1)
    }

    func testMalformedTimeReturnsNaN() {
        XCTAssertTrue(XMLTVParser.parseXmltvTime("not-a-time").isNaN)
        XCTAssertTrue(XMLTVParser.parseXmltvTime("2026").isNaN)
    }

    // MARK: - findCurrent

    private func programs(_ startHours: [Double]) -> [EPGProgram] {
        startHours.map { h in
            EPGProgram(channelTvgId: "c", title: "P\(h)", startMs: h * 3_600_000, endMs: (h + 1) * 3_600_000)
        }
    }

    func testFindCurrentReturnsCurrentAndNext() {
        let arr = programs([10, 11, 12])
        let result = EPGIndex.findCurrent(arr, nowMs: 11.5 * 3_600_000)
        XCTAssertEqual(result.current?.title, "P11.0")
        XCTAssertEqual(result.next?.title, "P12.0")
    }

    func testFindCurrentBeforeAllReturnsNextOnly() {
        let result = EPGIndex.findCurrent(programs([10, 11]), nowMs: 9 * 3_600_000)
        XCTAssertNil(result.current)
        XCTAssertEqual(result.next?.title, "P10.0")
    }

    func testFindCurrentAfterAllReturnsNothing() {
        let result = EPGIndex.findCurrent(programs([10, 11]), nowMs: 20 * 3_600_000)
        XCTAssertNil(result.current)
        XCTAssertNil(result.next)
    }

    // MARK: - Resolution

    func testResolvesByDirectTvgId() {
        let index = EPGIndex(from: XMLTVParser.parse(sampleXMLTV))
        let channel = IPTVChannel(id: "ch1", tvgId: "bbc1.uk", name: "BBC 1", url: "http://x")
        XCTAssertEqual(index.programs(for: channel)?.count, 2)
    }

    func testResolvesByNameFallbackWhenNoTvgId() {
        let index = EPGIndex(from: XMLTVParser.parse(sampleXMLTV))
        // No tvg-id, but the name normalizes to the same key as display-name "BBC One HD".
        let channel = IPTVChannel(id: "ch2", tvgId: nil, name: "bbc one hd", url: "http://x")
        XCTAssertEqual(index.programs(for: channel)?.count, 2)
    }

    func testManualOverrideForcesTvgId() {
        let index = EPGIndex(from: XMLTVParser.parse(sampleXMLTV))
        let channel = IPTVChannel(id: "ch3", tvgId: "wrong.id", name: "Mystery", url: "http://x")
        XCTAssertNil(index.programs(for: channel))
        XCTAssertEqual(index.programs(for: channel, overrides: ["ch3": "bbc1.uk"])?.count, 2)
    }

    func testSortsProgramsAscendingRegardlessOfInputOrder() {
        let out = EPGProgram(channelTvgId: "c", title: "late", startMs: 5_000, endMs: 6_000)
        let early = EPGProgram(channelTvgId: "c", title: "early", startMs: 1_000, endMs: 2_000)
        let index = EPGIndex(programs: [out, early], channelMeta: [:])
        XCTAssertEqual(index.byChannel["c"]?.map(\.title), ["early", "late"])
    }
}
