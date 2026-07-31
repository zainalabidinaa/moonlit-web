import XCTest
@testable import MoonlitCore

final class AudioFingerprintEngineTests: XCTestCase {
    func testMatcherFindsReferenceAfterLeadingRecap() throws {
        let intro = SignalFixture.intro(seconds: 24)
        let candidate = SignalFixture.speechLike(seconds: 37) + intro
            + SignalFixture.speechLike(seconds: 20)

        let match = try XCTUnwrap(AudioFingerprintEngine.match(
            reference: AudioFingerprintEngine.fingerprint(samples: intro),
            candidate: AudioFingerprintEngine.fingerprint(samples: candidate)
        ))

        XCTAssertEqual(match.offset, 37, accuracy: 0.75)
        XCTAssertGreaterThanOrEqual(match.confidence, 0.78)
        XCTAssertGreaterThanOrEqual(match.coverage, 0.65)
    }

    func testMatcherRejectsUnrelatedAudio() throws {
        let reference = try AudioFingerprintEngine.fingerprint(
            samples: SignalFixture.intro(seconds: 24)
        )
        let unrelated = try AudioFingerprintEngine.fingerprint(
            samples: SignalFixture.unrelated(seconds: 120)
        )

        XCTAssertNil(AudioFingerprintEngine.match(
            reference: reference,
            candidate: unrelated
        ))
    }

    func testMatcherIsInvariantToGainChanges() throws {
        let intro = SignalFixture.intro(seconds: 18)
        let candidate = SignalFixture.speechLike(seconds: 11)
            + intro.map { $0 * 0.27 }
            + SignalFixture.speechLike(seconds: 8)

        let match = try XCTUnwrap(AudioFingerprintEngine.match(
            reference: AudioFingerprintEngine.fingerprint(samples: intro),
            candidate: AudioFingerprintEngine.fingerprint(samples: candidate)
        ))

        XCTAssertEqual(match.offset, 11, accuracy: 0.75)
        XCTAssertGreaterThanOrEqual(match.confidence, 0.78)
    }

    func testMatcherHandlesNonHopAlignedOffsetAndEncodedLikeNoise() throws {
        let intro = SignalFixture.intro(seconds: 20)
        let noisyIntro = SignalFixture.addEncodedLikeNoise(to: intro)
        let leadingSeconds = 13.37
        let candidate = SignalFixture.speechLike(seconds: leadingSeconds) + noisyIntro

        let match = try XCTUnwrap(AudioFingerprintEngine.match(
            reference: AudioFingerprintEngine.fingerprint(samples: intro),
            candidate: AudioFingerprintEngine.fingerprint(samples: candidate)
        ))

        XCTAssertEqual(match.offset, leadingSeconds, accuracy: 0.75)
        XCTAssertGreaterThanOrEqual(match.confidence, 0.78)
        XCTAssertLessThanOrEqual(match.uncertainty, AudioFingerprintPolicy.maximumUncertainty)
    }

    func testFingerprintRejectsReferencesShorterThanFiveSeconds() {
        XCTAssertThrowsError(
            try AudioFingerprintEngine.fingerprint(
                samples: SignalFixture.intro(seconds: 4.99)
            )
        ) { error in
            guard case let AudioFingerprintError.insufficientAudio(minimumDuration, actualDuration) = error else {
                return XCTFail("Expected insufficientAudio, got \(error)")
            }
            XCTAssertEqual(minimumDuration, 5)
            XCTAssertEqual(actualDuration, 4.99, accuracy: 0.001)
        }
    }

    func testMatcherRejectsAmbiguousRepeatedMatches() throws {
        let intro = SignalFixture.intro(seconds: 18)
        let gap = SignalFixture.speechLike(seconds: 12)
        let candidate = gap + intro + gap + intro + gap

        XCTAssertNil(AudioFingerprintEngine.match(
            reference: try AudioFingerprintEngine.fingerprint(samples: intro),
            candidate: try AudioFingerprintEngine.fingerprint(samples: candidate)
        ))
    }

    func testFingerprintIgnoresCandidateAudioBeyondOpeningWindow() throws {
        let beyondOpeningWindow = SignalFixture.speechLike(
            seconds: AudioFingerprintPolicy.openingWindow + 1
        ) + SignalFixture.intro(seconds: 18)
        let candidate = try AudioFingerprintEngine.fingerprint(samples: beyondOpeningWindow)

        XCTAssertEqual(candidate.duration, AudioFingerprintPolicy.openingWindow, accuracy: 0.001)
        XCTAssertNil(AudioFingerprintEngine.match(
            reference: try AudioFingerprintEngine.fingerprint(
                samples: SignalFixture.intro(seconds: 18)
            ),
            candidate: candidate
        ))
    }

    func testFingerprintClampsNonFiniteSamplesDeterministically() throws {
        var damaged = SignalFixture.intro(seconds: 8)
        damaged[200] = .nan
        damaged[2_000] = .infinity
        damaged[8_000] = -.infinity

        let first = try AudioFingerprintEngine.fingerprint(samples: damaged)
        let second = try AudioFingerprintEngine.fingerprint(samples: damaged)

        XCTAssertEqual(first, second)
        XCTAssertFalse(first.landmarks.isEmpty)
    }

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

private enum SignalFixture {
    private static let sampleRate = AudioFingerprintPolicy.sampleRate

    static func intro(seconds: Double) -> [Float] {
        signal(seconds: seconds) { time, sample in
            let phrase = Int(time / 0.72)
            let phraseTime = time - Double(phrase) * 0.72
            let base = 165.0 + Double((phrase * 97) % 720)
            let sweep = 90.0 + Double((phrase * 53) % 410)
            let phase = 2 * Double.pi * (
                base * phraseTime + 0.5 * sweep * phraseTime * phraseTime
            )
            let pulse = exp(-18 * phraseTime)
            let accent: Float = sample % 5_513 < 180 ? 0.22 : 0
            let primary = Float(0.30 * sin(phase))
            let harmonic = Float(0.17 * sin(phase * 1.997 + Double(phrase) * 0.31))
            let transient = Float(pulse * 0.12 * sin(2 * Double.pi * 2_300 * time))
            let texture = accent * deterministicNoise(sample: sample, seed: 0xA341_316C)
            return primary + harmonic + transient + texture
        }
    }

    static func speechLike(seconds: Double) -> [Float] {
        signal(seconds: seconds) { time, sample in
            let syllable = Int(time / 0.19)
            let localTime = time - Double(syllable) * 0.19
            let fundamental = 105.0 + Double((syllable * 41) % 95)
            let envelope = sin(Double.pi * min(1, localTime / 0.19))
            let primary = 0.17 * envelope * sin(2 * Double.pi * fundamental * time)
            let harmonic = 0.09 * envelope * sin(2 * Double.pi * fundamental * 2.03 * time)
            let voiced = Float(primary + harmonic)
            let breath = 0.025 * deterministicNoise(sample: sample, seed: 0xC801_3EA4)
            return voiced + breath
        }
    }

    static func unrelated(seconds: Double) -> [Float] {
        signal(seconds: seconds) { time, sample in
            let block = Int(time / 0.43)
            let frequency = 1_350.0 + Double((block * 211) % 2_900)
            let tone = Float(0.21 * sin(2 * Double.pi * frequency * time))
            let noise = 0.08 * deterministicNoise(sample: sample, seed: 0xAD90_777D)
            return tone + noise
        }
    }

    static func addEncodedLikeNoise(to input: [Float]) -> [Float] {
        input.enumerated().map { index, value in
            let noise = deterministicNoise(sample: index, seed: 0x7E95_761E)
            let quantized = (value * 2_048).rounded() / 2_048
            return quantized + noise * 0.0015
        }
    }

    private static func signal(
        seconds: Double,
        sample: (_ time: Double, _ sample: Int) -> Float
    ) -> [Float] {
        let count = Int((seconds * Double(sampleRate)).rounded())
        return (0..<count).map { index in
            sample(Double(index) / Double(sampleRate), index)
        }
    }

    private static func deterministicNoise(sample: Int, seed: UInt32) -> Float {
        var value = UInt32(truncatingIfNeeded: sample) &+ seed
        value ^= value >> 16
        value &*= 0x7FEB_352D
        value ^= value >> 15
        value &*= 0x846C_A68B
        value ^= value >> 16
        return Float(Int32(bitPattern: value)) / Float(Int32.max)
    }
}
