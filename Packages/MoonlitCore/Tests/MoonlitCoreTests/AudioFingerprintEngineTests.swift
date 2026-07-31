import XCTest
@testable import MoonlitCore

final class AudioFingerprintEngineTests: XCTestCase {
    func testReferenceKeyNormalizesLanguageAliases() {
        XCTAssertEqual(
            IntroFingerprintReferenceKey(
                imdbID: "tt0903747",
                season: 1,
                audioLanguage: "ENG-us",
                algorithmVersion: 1
            ).audioLanguage,
            "en"
        )
    }

    func testReferenceKeyNormalizesRepresentativeLanguageAliases() {
        let aliases = [
            ("spa-MX", "es"),
            ("swe-SE", "sv"),
            ("fre-FR", "fr"),
            ("ger-DE", "de"),
            ("zho-Hant", "zh")
        ]

        for (alias, expected) in aliases {
            XCTAssertEqual(
                IntroFingerprintReferenceKey(
                    imdbID: "tt0903747",
                    season: 1,
                    audioLanguage: alias,
                    algorithmVersion: 1
                ).audioLanguage,
                expected
            )
        }
    }

    func testReferenceKeyDecodingNormalizesLanguageAliases() throws {
        let data = Data(
            """
            {"imdbID":"tt0903747","season":1,"audioLanguage":"spa-MX","algorithmVersion":1}
            """.utf8
        )

        let decoded = try JSONDecoder().decode(IntroFingerprintReferenceKey.self, from: data)
        XCTAssertEqual(decoded.audioLanguage, "es")

        let roundTripped = try JSONDecoder().decode(
            IntroFingerprintReferenceKey.self,
            from: JSONEncoder().encode(decoded)
        )
        XCTAssertEqual(roundTripped.audioLanguage, "es")
        XCTAssertEqual(roundTripped, decoded)
    }

    func testStreamFingerprintIdentityDropsSecretsAndQueryValues() {
        let first = StreamFingerprintIdentity.make(
            sourceURL: "https://cdn.example/episode.mkv?token=secret-a",
            streamIdentity: "release-1",
            duration: 2_800.4,
            audioLanguage: "en",
            audioTitle: "Original"
        )
        let second = StreamFingerprintIdentity.make(
            sourceURL: "https://cdn.example/episode.mkv?token=secret-b",
            streamIdentity: "release-1",
            duration: 2_800.4,
            audioLanguage: "eng",
            audioTitle: "Original"
        )

        XCTAssertEqual(first, second)
        XCTAssertFalse(first.rawValue.contains("secret"))
    }
}
