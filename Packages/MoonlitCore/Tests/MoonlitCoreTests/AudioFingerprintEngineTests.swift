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
