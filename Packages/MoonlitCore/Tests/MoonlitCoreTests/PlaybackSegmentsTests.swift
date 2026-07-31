import XCTest
@testable import MoonlitCore

final class PlaybackSegmentsTests: XCTestCase {
    func testLegacyIntroTimestampMapsTheIntroSegment() throws {
        let segments = PlaybackSegments(
            recap: PlaybackSegment(
                kind: .recap, start: 0, end: 42,
                source: .embedded, match: .exact
            ),
            intro: PlaybackSegment(
                kind: .intro, start: 61, end: 91,
                source: .skipDB, match: .exact
            )
        )

        let timestamp = try XCTUnwrap(IntroTimestamp(segments: segments))

        XCTAssertEqual(timestamp.introStart, 61)
        XCTAssertEqual(timestamp.introEnd, 91)
        XCTAssertEqual(timestamp.highlights, [])
    }

    func testOnlyExactTrustedIntroCanSeedReference() {
        XCTAssertTrue(PlaybackSegment(
            kind: .intro, start: 61, end: 91, confidence: 0.9,
            source: .skipDB, match: .exact
        ).canSeedAudioFingerprintReference)
        XCTAssertFalse(PlaybackSegment(
            kind: .intro, start: 61, end: 91, confidence: 1,
            source: .introDB, match: .agnostic
        ).canSeedAudioFingerprintReference)
        XCTAssertFalse(PlaybackSegment(
            kind: .recap, start: 0, end: 42, confidence: 1,
            source: .embedded, match: .exact
        ).canSeedAudioFingerprintReference)
    }

    func testReferenceSeedEligibilityEnforcesEveryTrustBoundary() {
        let trustedSources: [PlaybackSegmentSource] = [
            .embedded, .skipDB, .theIntroDB, .localCorrection
        ]
        for source in trustedSources {
            XCTAssertTrue(PlaybackSegment(
                kind: .intro, start: 0, end: 5, confidence: 0.8,
                source: source, match: .exact
            ).canSeedAudioFingerprintReference)
        }

        XCTAssertFalse(PlaybackSegment(
            kind: .intro, start: 0, end: 30, confidence: 0.79,
            source: .skipDB, match: .exact
        ).canSeedAudioFingerprintReference)
        XCTAssertFalse(PlaybackSegment(
            kind: .intro, start: -0.1, end: 30, confidence: 1,
            source: .skipDB, match: .exact
        ).canSeedAudioFingerprintReference)
        XCTAssertFalse(PlaybackSegment(
            kind: .intro, start: 0, end: 4.9, confidence: 1,
            source: .skipDB, match: .exact
        ).canSeedAudioFingerprintReference)
        XCTAssertFalse(PlaybackSegment(
            kind: .intro, start: 0, end: 240.1, confidence: 1,
            source: .skipDB, match: .exact
        ).canSeedAudioFingerprintReference)
        XCTAssertFalse(PlaybackSegment(
            kind: .intro, start: 0, end: 30, confidence: 1,
            source: .audioFingerprint, match: .exact
        ).canSeedAudioFingerprintReference)
        XCTAssertFalse(PlaybackSegment(
            kind: .intro, start: 0, end: 30, confidence: 1,
            source: .embedded, match: .shifted
        ).canSeedAudioFingerprintReference)
    }

    func testAudioFingerprintSourceRanksBelowEmbeddedAndAboveRemoteProviders() {
        let fingerprint = PlaybackSegments(intro: PlaybackSegment(
            kind: .intro, start: 61, end: 91, confidence: 0.8,
            source: .audioFingerprint, match: .exact
        ))
        let embedded = PlaybackSegments(intro: PlaybackSegment(
            kind: .intro, start: 42, end: 91, confidence: 0.8,
            source: .embedded, match: .exact
        ))
        let remote = PlaybackSegments(intro: PlaybackSegment(
            kind: .intro, start: 100, end: 130, confidence: 1,
            source: .skipDB, match: .exact
        ))

        XCTAssertEqual(
            PlaybackSegments.preferred(from: [remote, fingerprint])?.intro?.source,
            .audioFingerprint
        )
        XCTAssertEqual(
            PlaybackSegments.preferred(from: [fingerprint, embedded])?.intro?.source,
            .embedded
        )
    }

    func testSegmentsDecodeRecapAndIntroWindows() throws {
        let data = Data("""
        {
          "imdb_id": "tt0455275",
          "season": 1,
          "episode": 15,
          "intro": {
            "start_sec": 299,
            "end_sec": 330,
            "start_ms": 299000,
            "end_ms": 330000,
            "confidence": 0.88,
            "submission_count": 3
          },
          "recap": {
            "start_sec": 0,
            "end_sec": 52,
            "start_ms": 0,
            "end_ms": 52000,
            "confidence": 0.92,
            "submission_count": 4
          },
          "outro": null
        }
        """.utf8)

        let segments = try PlaybackSegments.decode(data: data)

        XCTAssertEqual(segments.recap?.end, 52)
        XCTAssertEqual(segments.intro?.start, 299)
        XCTAssertTrue(segments.action(at: 12)?.kind == .recap)
        XCTAssertTrue(segments.action(at: 310)?.kind == .intro)
        XCTAssertNil(segments.action(at: 400))
    }

    func testLowConfidenceSegmentDoesNotOfferSkipAction() {
        let segments = PlaybackSegments(recap: .init(kind: .recap, start: 0, end: 30, confidence: 0.4))
        XCTAssertNil(segments.action(at: 10))
    }

    func testOutroNeverAppearsAsAnIntroOrRecapAction() {
        let segments = PlaybackSegments(
            outro: .init(kind: .outro, start: 2_579, end: 2_648, confidence: 1)
        )

        XCTAssertNil(segments.action(at: 2_600))
    }

    func testSkipDBRejectsSegmentsForAnOutOfRangeCut() throws {
        let data = Data("""
        {
          "segments": {
            "intro": {
              "start_ms": 229500,
              "end_ms": 246500,
              "match": "out-of-range",
              "adjusted": false,
              "offset_ms": -680000,
              "confidence": 0.9
            },
            "recap": null,
            "outro": null,
            "preview": null
          }
        }
        """.utf8)

        let segments = try PlaybackSegments.decodeSkipDB(data: data)

        XCTAssertNil(segments)
        XCTAssertTrue(try PlaybackSegments.skipDBIndicatesCutMismatch(data: data))
    }

    func testSkipDBKeepsExactDurationMatchProvenance() throws {
        let data = Data("""
        {
          "segments": {
            "intro": {
              "start_ms": 61000,
              "end_ms": 91000,
              "match": "exact",
              "adjusted": false,
              "offset_ms": 0,
              "confidence": 0.93
            },
            "recap": null,
            "outro": null,
            "preview": null
          }
        }
        """.utf8)

        let segments = try XCTUnwrap(PlaybackSegments.decodeSkipDB(data: data))

        XCTAssertEqual(segments.intro?.source, .skipDB)
        XCTAssertEqual(segments.intro?.match, .exact)
        XCTAssertEqual(segments.intro?.end, 91)
    }

    func testIntroDBFallbackRequiresCommunityAgreement() throws {
        let data = Data("""
        {
          "intro": {
            "start_ms": 1000,
            "end_ms": 50000,
            "confidence": 1,
            "submission_count": 1
          },
          "recap": {
            "start_ms": 0,
            "end_ms": 45000,
            "confidence": 0.9,
            "submission_count": 3
          },
          "outro": null
        }
        """.utf8)

        let segments = try PlaybackSegments.decodeIntroDB(data: data)

        XCTAssertNil(segments.intro)
        XCTAssertEqual(segments.recap?.source, .introDB)
        XCTAssertEqual(segments.recap?.match, .agnostic)
    }

    func testTheIntroDBRequiresAMatchingPositiveDurationVersion() throws {
        let data = Data("""
        {
          "tmdb_id": 1396,
          "type": "tv",
          "season": 1,
          "episode": 1,
          "intro": [{ "start_ms": 228892, "end_ms": 245607 }],
          "recap": [],
          "credits": [{ "start_ms": 3431000, "end_ms": null }]
        }
        """.utf8)

        XCTAssertNil(try PlaybackSegments.decodeTheIntroDB(
            data: data,
            requestedDuration: 3_480,
            availableDurations: [0]
        ))

        let matched = try XCTUnwrap(PlaybackSegments.decodeTheIntroDB(
            data: data,
            requestedDuration: 3_480,
            availableDurations: [3_479.5]
        ))
        XCTAssertEqual(matched.intro?.source, .theIntroDB)
        XCTAssertEqual(matched.intro?.match, .exact)
        XCTAssertEqual(matched.outro?.end, 3_480)
    }

    func testResolverPrefersExactCutOverEpisodeOnlyFallback() {
        let fallback = PlaybackSegments(
            intro: .init(
                kind: .intro,
                start: 10,
                end: 50,
                confidence: 1,
                source: .introDB,
                match: .agnostic
            )
        )
        let exact = PlaybackSegments(
            intro: .init(
                kind: .intro,
                start: 70,
                end: 100,
                confidence: 0.8,
                source: .skipDB,
                match: .exact
            )
        )

        let resolved = PlaybackSegments.preferred(from: [fallback, exact])

        XCTAssertEqual(resolved?.intro?.start, 70)
    }

    func testSegmentCacheSeparatesDifferentDurationsAndStreams() {
        let first = PlaybackSegmentRequest(
            imdbId: "tt0903747",
            season: 1,
            episode: 1,
            duration: 2_820,
            streamIdentity: "provider-a:release-one"
        )
        let otherDuration = PlaybackSegmentRequest(
            imdbId: "tt0903747",
            season: 1,
            episode: 1,
            duration: 3_500,
            streamIdentity: "provider-a:release-one"
        )
        let otherStream = PlaybackSegmentRequest(
            imdbId: "tt0903747",
            season: 1,
            episode: 1,
            duration: 2_820,
            streamIdentity: "provider-b:release-two"
        )

        XCTAssertNotEqual(first.cacheKey, otherDuration.cacheKey)
        XCTAssertNotEqual(first.cacheKey, otherStream.cacheKey)
    }

    func testEmbeddedNamedChaptersBecomeExactSegments() {
        let chapters = [
            PlaybackChapter(title: "Previously On", start: 0),
            PlaybackChapter(title: "Opening Credits", start: 42),
            PlaybackChapter(title: "Episode", start: 91),
            PlaybackChapter(title: "End Credits", start: 2_700)
        ]

        let segments = PlaybackSegments.fromChapters(chapters, duration: 2_820)

        XCTAssertEqual(segments?.recap?.end, 42)
        XCTAssertEqual(segments?.intro?.start, 42)
        XCTAssertEqual(segments?.intro?.end, 91)
        XCTAssertEqual(segments?.outro?.end, 2_820)
        XCTAssertEqual(segments?.intro?.source, .embedded)
        XCTAssertEqual(segments?.intro?.match, .exact)
    }

    func testStreamIdentityIgnoresSignedQueryButSeparatesFiles() {
        let first = PlaybackStreamIdentity.make(
            providerName: "Example",
            sourceURL: "https://cdn.example/show/episode-a.mkv?token=secret-one",
            sourceSize: 123,
            streamTitle: "1080p"
        )
        let refreshedToken = PlaybackStreamIdentity.make(
            providerName: "Example",
            sourceURL: "https://cdn.example/show/episode-a.mkv?token=secret-two",
            sourceSize: 123,
            streamTitle: "1080p"
        )
        let otherFile = PlaybackStreamIdentity.make(
            providerName: "Example",
            sourceURL: "https://cdn.example/show/episode-b.mkv?token=secret-one",
            sourceSize: 123,
            streamTitle: "1080p"
        )

        XCTAssertEqual(first, refreshedToken)
        XCTAssertNotEqual(first, otherFile)
        XCTAssertFalse(first.contains("secret"))
    }
}
