# Per-Stream Audio Fingerprinting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect the recurring intro at its exact position in the selected stream by matching locally generated audio fingerprints, without delaying playback or scanning a whole season.

**Architecture:** MoonlitCore owns the fingerprint data model, spectral landmark generator, matcher, reference eligibility, and cache policy. The iOS app owns an FFmpeg-backed audio-only sampler and an actor coordinator that seeds references from trustworthy existing segments or aligns a cached season reference against the active stream. `PlayerScreen` starts and cancels the coordinator alongside its existing segment lookup; the current timestamp resolver remains the safe fallback.

**Tech Stack:** Swift 6, Foundation, CryptoKit, Accelerate/vDSP, structured concurrency, MoonlitCore, MPVKit's bundled FFmpeg 8.x modules (`Libavformat`, `Libavcodec`, `Libswresample`, `Libavutil`), XCTest, Xcode 26.

## Global Constraints

- Scope is the iPhone/iPad MPV player; native tvOS and macOS players are unchanged.
- Analyze only the selected stream and at most its opening 15 minutes.
- Playback starts immediately and always has priority over analysis.
- Target a result within 10 seconds on a seekable direct stream; cancel analysis after 30 seconds.
- Initial implementation is local-only: no raw audio or fingerprint upload.
- Raw or decoded audio is never persisted.
- Signed URL query values, cookies, authorization headers, and addon credentials are never persisted or logged.
- Intro matching is supported; fingerprint-based recap and outro detection are excluded.
- A match below the calibrated confidence threshold never creates a skip action.
- Existing embedded chapters and remote segment providers remain functional when fingerprinting is unavailable.
- No cloud device is used; after local verification, build and install on physical device `00008150-001534C10CA0C01C`.

---

## File Structure

### Create

- `Packages/MoonlitCore/Sources/MoonlitCore/Services/AudioFingerprintModels.swift` — Codable fingerprint, reference, stream match, key, and failure models.
- `Packages/MoonlitCore/Sources/MoonlitCore/Services/AudioFingerprintEngine.swift` — deterministic spectral-landmark generation and offset-voting matcher.
- `Packages/MoonlitCore/Sources/MoonlitCore/Services/IntroFingerprintStore.swift` — actor-backed bounded cache with atomic file replacement.
- `Packages/MoonlitCore/Tests/MoonlitCoreTests/AudioFingerprintEngineTests.swift` — signal fixtures, matching, rejection, and boundary tests.
- `Packages/MoonlitCore/Tests/MoonlitCoreTests/IntroFingerprintStoreTests.swift` — persistence, invalidation, sanitization, and LRU tests.
- `Apps/MoonlitApp/Sources/Services/StreamAudioSampler.swift` — sampler protocol, request/result types, and FFmpeg implementation.
- `Apps/MoonlitApp/Sources/Services/IntroFingerprintCoordinator.swift` — per-player orchestration, timeout, cancellation, seeding, and matching.
- `Apps/MoonlitApp/Tests/StreamAudioSamplerTests.swift` — request/header sanitization, limits, cancellation, and local fixture decoding.
- `Apps/MoonlitApp/Tests/IntroFingerprintCoordinatorTests.swift` — deterministic fake-sampler orchestration tests.
- `Apps/MoonlitApp/Tests/Fixtures/fingerprint-reference.wav` — short synthetic PCM/WAV fixture generated from test-owned tones, not copyrighted media.

### Modify

- `Packages/MoonlitCore/Sources/MoonlitCore/Services/IntroTimestampService.swift` — add `.audioFingerprint` provenance and exact-match ranking.
- `Packages/MoonlitCore/Tests/MoonlitCoreTests/PlaybackSegmentsTests.swift` — verify fingerprint provenance and resolver preference.
- `Apps/MoonlitApp/Sources/Components/MPVPlayerEngine.swift` — expose the selected audio descriptor required by sampling.
- `Apps/MoonlitApp/Sources/Screens/PlayerScreen.swift` — start/cancel fingerprint work and merge only verified intro results.
- `Apps/MoonlitApp/Tests/SubtitleCueIndexTests.swift` — cover selected-audio descriptor updates.

---

### Task 1: Fingerprint Domain Models and Safe Identity

**Files:**
- Create: `Packages/MoonlitCore/Sources/MoonlitCore/Services/AudioFingerprintModels.swift`
- Test: `Packages/MoonlitCore/Tests/MoonlitCoreTests/AudioFingerprintEngineTests.swift`

**Interfaces:**
- Produces: `AudioFingerprintLandmark`, `AudioFingerprint`, `IntroFingerprintReferenceKey`, `IntroFingerprintReference`, `StreamFingerprintIdentity`, `StreamFingerprintMatch`, and `AudioFingerprintPolicy`.
- Consumes: Existing `PlaybackStreamIdentity` conventions for opaque identities.

- [ ] **Step 1: Write failing model and identity tests**

```swift
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
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
swift test --package-path ../../Packages/MoonlitCore \
  --filter AudioFingerprintEngineTests
```

Expected: FAIL because the fingerprint types do not exist.

- [ ] **Step 3: Implement the value types and fixed policy**

Use these public shapes:

```swift
public struct AudioFingerprintLandmark: Codable, Hashable, Sendable {
    public let hash: UInt32
    public let frame: Int
}

public struct AudioFingerprint: Codable, Equatable, Sendable {
    public static let algorithmVersion = 1
    public let sampleRate: Int
    public let hopSize: Int
    public let duration: Double
    public let landmarks: [AudioFingerprintLandmark]
}

public struct IntroFingerprintReferenceKey: Codable, Hashable, Sendable {
    public let imdbID: String
    public let season: Int
    public let audioLanguage: String
    public let algorithmVersion: Int
}

public struct IntroFingerprintReference: Codable, Equatable, Sendable {
    public let key: IntroFingerprintReferenceKey
    public let fingerprint: AudioFingerprint
    public let referenceStart: Double
    public let introDuration: Double
    public let source: PlaybackSegmentSource
    public let sourceConfidence: Double
    public let createdAt: Date
    public let lastValidatedAt: Date
}

public struct StreamFingerprintIdentity: Codable, Hashable, Sendable {
    public let rawValue: String
}

public struct StreamFingerprintMatch: Codable, Equatable, Sendable {
    public let identity: StreamFingerprintIdentity
    public let referenceKey: IntroFingerprintReferenceKey
    public let start: Double
    public let end: Double
    public let confidence: Double
    public let uncertainty: Double
    public let createdAt: Date
}

public enum AudioFingerprintPolicy {
    public static let sampleRate = 11_025
    public static let openingWindow: Double = 900
    public static let timeout: Duration = .seconds(30)
    public static let minimumIntroDuration: Double = 5
    public static let maximumIntroDuration: Double = 240
    public static let minimumCoverage = 0.65
    public static let minimumConfidence = 0.78
    public static let maximumUncertainty: Double = 1.5
}
```

Normalize ISO-639 aliases before constructing keys. Build the stream identity from scheme, host, port, path, existing opaque stream identity, rounded measured duration, normalized language, normalized audio title, and algorithm version. Hash with SHA-256 and store only the hexadecimal digest; never include URL queries or headers.

- [ ] **Step 4: Run focused tests**

Run:

```bash
swift test --package-path ../../Packages/MoonlitCore \
  --filter AudioFingerprintEngineTests
```

Expected: PASS for model, normalization, and identity tests.

- [ ] **Step 5: Commit the domain boundary**

```bash
git add \
  Packages/MoonlitCore/Sources/MoonlitCore/Services/AudioFingerprintModels.swift \
  Packages/MoonlitCore/Tests/MoonlitCoreTests/AudioFingerprintEngineTests.swift
git commit -m "feat: add audio fingerprint domain models"
```

---

### Task 2: Spectral Landmark Generator and Matcher

**Files:**
- Create: `Packages/MoonlitCore/Sources/MoonlitCore/Services/AudioFingerprintEngine.swift`
- Modify: `Packages/MoonlitCore/Tests/MoonlitCoreTests/AudioFingerprintEngineTests.swift`

**Interfaces:**
- Consumes: `[Float]` mono PCM normalized to `AudioFingerprintPolicy.sampleRate`.
- Produces:

```swift
public enum AudioFingerprintEngine {
    public static func fingerprint(
        samples: [Float],
        sampleRate: Int = AudioFingerprintPolicy.sampleRate
    ) throws -> AudioFingerprint

    public static func match(
        reference: AudioFingerprint,
        candidate: AudioFingerprint
    ) -> AudioFingerprintMatch?
}

public struct AudioFingerprintMatch: Equatable, Sendable {
    public let offset: Double
    public let confidence: Double
    public let coverage: Double
    public let uncertainty: Double
}
```

- [ ] **Step 1: Add failing deterministic signal tests**

Create test-owned signals from sine sweeps, pulses, and deterministic noise:

```swift
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
```

Also test gain changes, mild time offsets, encoded-like noise, references shorter than five seconds, ambiguous repeated matches, and candidate windows beyond 900 seconds.

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
swift test --package-path ../../Packages/MoonlitCore \
  --filter AudioFingerprintEngineTests
```

Expected: FAIL because `AudioFingerprintEngine` is undefined.

- [ ] **Step 3: Implement deterministic landmark extraction**

Use Accelerate/vDSP with:

- 4,096-sample Hann window
- 1,024-sample hop
- real FFT
- 24 logarithmic bands from 80 Hz through 5 kHz
- local peaks above the rolling median energy
- at most three peaks per frame
- landmark pairs separated by 1–5 seconds

Pack each pair into a stable `UInt32`:

```swift
let hash =
    UInt32(anchorBand & 0x1F) << 27 |
    UInt32(targetBand & 0x1F) << 22 |
    UInt32(deltaFrame & 0x3FF) << 12 |
    UInt32(energyRelation & 0x0FFF)
```

The implementation must clamp non-finite input samples, normalize RMS without changing timing, and return a typed error for insufficient audio.

- [ ] **Step 4: Implement offset-voting alignment**

Index candidate landmarks by hash. For every matching reference/candidate landmark pair, vote for:

```swift
let offsetFrames = candidateLandmark.frame - referenceLandmark.frame
```

Cluster votes within one hop, evaluate the three strongest clusters, deduplicate matched reference landmarks, and calculate:

```swift
coverage = Double(uniqueReferenceMatches) / Double(reference.landmarks.count)
confidence = coverage * peakDominance * temporalConsistency
uncertainty = Double(clusterFrameSpread * candidate.hopSize)
    / Double(candidate.sampleRate)
```

Return `nil` unless policy thresholds pass. Return offset in seconds from the winning cluster.

- [ ] **Step 5: Run all core fingerprint tests**

Run:

```bash
swift test --package-path ../../Packages/MoonlitCore \
  --filter AudioFingerprintEngineTests
```

Expected: PASS with deterministic offsets on repeated runs.

- [ ] **Step 6: Commit the pure matching engine**

```bash
git add \
  Packages/MoonlitCore/Sources/MoonlitCore/Services/AudioFingerprintEngine.swift \
  Packages/MoonlitCore/Tests/MoonlitCoreTests/AudioFingerprintEngineTests.swift
git commit -m "feat: match intro audio fingerprints"
```

---

### Task 3: Reference Eligibility, Provenance, and Persistent Store

**Files:**
- Create: `Packages/MoonlitCore/Sources/MoonlitCore/Services/IntroFingerprintStore.swift`
- Create: `Packages/MoonlitCore/Tests/MoonlitCoreTests/IntroFingerprintStoreTests.swift`
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Services/IntroTimestampService.swift`
- Modify: `Packages/MoonlitCore/Tests/MoonlitCoreTests/PlaybackSegmentsTests.swift`

**Interfaces:**
- Consumes: `IntroFingerprintReference`, `StreamFingerprintMatch`, and `PlaybackSegment`.
- Produces:

```swift
public actor IntroFingerprintStore {
    public init(fileURL: URL, referenceLimit: Int = 50, matchLimit: Int = 200)
    public func reference(for key: IntroFingerprintReferenceKey)
        async throws -> IntroFingerprintReference?
    public func match(for identity: StreamFingerprintIdentity)
        async throws -> StreamFingerprintMatch?
    public func save(reference: IntroFingerprintReference) async throws
    public func save(match: StreamFingerprintMatch) async throws
    public func removeReference(for key: IntroFingerprintReferenceKey) async throws
}

public extension PlaybackSegment {
    var canSeedAudioFingerprintReference: Bool { get }
}
```

- [ ] **Step 1: Write failing store and eligibility tests**

```swift
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
```

Add async tests for round-trip persistence, algorithm-version invalidation, language isolation, LRU eviction at 50/200 records, corrupted-file recovery, and atomic replacement.

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
swift test --package-path ../../Packages/MoonlitCore \
  --filter IntroFingerprintStoreTests
```

Expected: FAIL because the store and eligibility API do not exist.

- [ ] **Step 3: Add fingerprint provenance and eligibility**

Add `.audioFingerprint` to `PlaybackSegmentSource`. Rank it as an exact, locally derived source below `.embedded` but above remote providers. Seed eligibility is:

```swift
kind == .intro
    && match == .exact
    && confidence >= 0.8
    && start >= 0
    && (5...240).contains(end - start)
    && [.embedded, .skipDB, .theIntroDB, .localCorrection].contains(source)
```

- [ ] **Step 4: Implement the bounded actor store**

Store one versioned Codable envelope in `Library/Caches/IntroFingerprints-v1.json`. Write to a sibling temporary file and replace atomically. Update `lastValidatedAt`/access metadata on reads. If decoding fails, quarantine only that cache file with a `.corrupt` suffix and begin empty.

Never persist source URLs, headers, or raw samples.

- [ ] **Step 5: Run focused and regression tests**

Run:

```bash
swift test --package-path ../../Packages/MoonlitCore \
  --filter IntroFingerprintStoreTests
swift test --package-path ../../Packages/MoonlitCore \
  --filter PlaybackSegmentsTests
```

Expected: PASS.

- [ ] **Step 6: Commit persistence and provenance**

```bash
git add \
  Packages/MoonlitCore/Sources/MoonlitCore/Services/IntroFingerprintStore.swift \
  Packages/MoonlitCore/Sources/MoonlitCore/Services/IntroTimestampService.swift \
  Packages/MoonlitCore/Tests/MoonlitCoreTests/IntroFingerprintStoreTests.swift \
  Packages/MoonlitCore/Tests/MoonlitCoreTests/PlaybackSegmentsTests.swift
git commit -m "feat: cache trusted intro fingerprints"
```

---

### Task 4: Audio-Only FFmpeg Sampler

**Files:**
- Create: `Apps/MoonlitApp/Sources/Services/StreamAudioSampler.swift`
- Create: `Apps/MoonlitApp/Tests/StreamAudioSamplerTests.swift`
- Create: `Apps/MoonlitApp/Tests/Fixtures/fingerprint-reference.wav`

**Interfaces:**
- Consumes: active stream URL, request headers, selected audio descriptor, and a bounded time range.
- Produces:

```swift
struct SelectedAudioDescriptor: Equatable, Sendable {
    let languageCode: String
    let title: String?
}

struct StreamAudioSampleRequest: Sendable {
    let sourceURL: URL
    let headers: [String: String]
    let audio: SelectedAudioDescriptor
    let range: Range<Double>
}

protocol StreamAudioSampling: Sendable {
    func samples(for request: StreamAudioSampleRequest) async throws -> [Float]
}
```

- [ ] **Step 1: Add failing request-policy and fixture tests**

```swift
func testRequestRejectsRangesOutsideOpeningWindow() {
    XCTAssertThrowsError(try StreamAudioSampleRequest.validated(
        sourceURL: fixtureURL,
        headers: [:],
        audio: .init(languageCode: "en", title: nil),
        range: 0..<901
    ))
}

func testSamplerDecodesFixtureAsMono11025Hz() async throws {
    let samples = try await FFmpegStreamAudioSampler().samples(
        for: .validated(
            sourceURL: fixtureURL,
            headers: [:],
            audio: .init(languageCode: "en", title: nil),
            range: 0..<5
        )
    )
    XCTAssertLessThanOrEqual(abs(samples.count - 55_125), 2_048)
    XCTAssertTrue(samples.allSatisfy(\.isFinite))
}
```

Generate the WAV fixture once from deterministic test tones and commit only the fixture, not a script output containing third-party media.

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test \
  -project MoonlitApp.xcodeproj \
  -scheme MoonlitApp \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' \
  -only-testing:MoonlitAppTests/StreamAudioSamplerTests
```

Expected: FAIL because the sampler types do not exist.

- [ ] **Step 3: Implement request validation and safe header forwarding**

Accept only `http`, `https`, and local test-file URLs. Clamp ranges to `0..<900`, reject empty ranges, and forward headers to FFmpeg in memory through an `AVDictionary`. Never print header values. Diagnostic output may include only the URL host, range, audio language, elapsed time, and typed failure reason.

- [ ] **Step 4: Implement FFmpeg audio-only decoding**

Import the modules already bundled by MPVKit:

```swift
import Libavformat
import Libavcodec
import Libswresample
import Libavutil
```

The decode sequence is:

1. `avformat_open_input`
2. `avformat_find_stream_info`
3. select the best audio stream matching normalized language/title, falling back to default audio
4. `avcodec_parameters_to_context` and `avcodec_open2`
5. seek to the requested start with `avformat_seek_file`
6. decode audio packets only
7. use `swr_alloc_set_opts2`/`swr_convert` to mono Float32 at 11,025 Hz
8. stop at the requested end or opening-window limit
9. release every packet, frame, codec, resampler, dictionary, and format context in `defer`

Use an FFmpeg interrupt callback backed by a lock-protected cancellation token so closing the player or exceeding 30 seconds interrupts blocked network reads. Keep decoded samples in bounded memory and never create a PCM file.

- [ ] **Step 5: Prove cancellation and resource cleanup**

Add a test URL protocol/local delayed source whose read blocks until cancellation. Assert the task throws `CancellationError` within one second and the sampler reports zero active decode contexts afterward.

- [ ] **Step 6: Run sampler tests and compile the device architecture**

Run:

```bash
xcodebuild test \
  -project MoonlitApp.xcodeproj \
  -scheme MoonlitApp \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' \
  -only-testing:MoonlitAppTests/StreamAudioSamplerTests

xcodebuild build \
  -project MoonlitApp.xcodeproj \
  -scheme MoonlitApp \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: tests PASS and arm64 device build succeeds with the bundled FFmpeg modules.

- [ ] **Step 7: Commit the isolated sampler**

```bash
git add \
  Apps/MoonlitApp/Sources/Services/StreamAudioSampler.swift \
  Apps/MoonlitApp/Tests/StreamAudioSamplerTests.swift \
  Apps/MoonlitApp/Tests/Fixtures/fingerprint-reference.wav
git commit -m "feat: sample stream audio for intro matching"
```

---

### Task 5: Per-Stream Fingerprint Coordinator

**Files:**
- Create: `Apps/MoonlitApp/Sources/Services/IntroFingerprintCoordinator.swift`
- Create: `Apps/MoonlitApp/Tests/IntroFingerprintCoordinatorTests.swift`

**Interfaces:**
- Consumes: `PlaybackSegmentRequest`, selected URL/headers/audio, existing resolved segments, `StreamAudioSampling`, `IntroFingerprintStore`.
- Produces:

```swift
actor IntroFingerprintCoordinator {
    func resolve(
        request: IntroFingerprintRequest,
        existingSegments: PlaybackSegments?
    ) async -> PlaybackSegment?
    func cancel()
}

struct IntroFingerprintRequest: Sendable {
    let segmentRequest: PlaybackSegmentRequest
    let sourceURL: URL
    let sourceHeaders: [String: String]
    let audio: SelectedAudioDescriptor
}
```

- [ ] **Step 1: Write failing orchestration tests with a fake sampler**

Cover:

```swift
func testCachedExactStreamMatchReturnsWithoutSampling() async
func testExistingReferenceAlignsOnlyTheSelectedStream() async
func testTrustedSegmentSeedsReferenceWithoutReplacingCurrentTiming() async
func testAgnosticIntroDBSegmentDoesNotSeedReference() async
func testLowConfidenceMatchProducesNoSegment() async
func testCancellationOnStreamChangeDropsLateResult() async
func testRecapIsNeverFingerprintGenerated() async
```

The fake sampler records every URL and range. Assert one selected URL only, no range outside `0..<900`, and a seed range exactly equal to the verified intro. For a cached reference, first assert a bounded search around `referenceStart`; when that fails, assert a single `0..<900` fallback scan.

- [ ] **Step 2: Run coordinator tests and verify failure**

Run:

```bash
xcodebuild test \
  -project MoonlitApp.xcodeproj \
  -scheme MoonlitApp \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' \
  -only-testing:MoonlitAppTests/IntroFingerprintCoordinatorTests
```

Expected: FAIL because the coordinator is undefined.

- [ ] **Step 3: Implement cached-match and live-alignment paths**

The algorithm is:

```swift
if let cached = try await store.match(for: streamIdentity) {
    return cached.playbackSegment
}

if let reference = try await store.reference(for: referenceKey) {
    for searchRange in searchRanges(for: reference) {
        let samples = try await sampler.samples(
            candidateRequest(range: searchRange)
        )
        let candidate = try AudioFingerprintEngine.fingerprint(samples: samples)
        if let match = AudioFingerprintEngine.match(
            reference: reference.fingerprint,
            candidate: candidate
        ) {
            return try await validatePersistAndReturn(
                match.offsetBy(searchRange.lowerBound),
                reference,
                streamIdentity
            )
        }
    }
    return nil
}

if let intro = existingSegments?.intro,
   intro.canSeedAudioFingerprintReference {
    let samples = try await sampler.samples(seedRangeRequest(for: intro))
    let fingerprint = try AudioFingerprintEngine.fingerprint(samples: samples)
    try await store.save(reference: reference(from: fingerprint, intro: intro))
}
return nil
```

Wrap live sampling in a 30-second throwing task group timeout. Treat expected network, decoding, low-confidence, thermal, and cancellation failures as a nil result plus sanitized diagnostics.

`searchRanges(for:)` first searches from 120 seconds before `referenceStart` through 120 seconds after the reference end, clamped to `0..<900`. Only if that bounded search fails and runtime policy still permits work does it request one continuous `0..<900` fallback. This is the sparse-first path required by the design while retaining coverage for unusually shifted cuts.

- [ ] **Step 4: Add power, buffering, and lifecycle suppression**

Inject a lightweight `FingerprintRuntimePolicy` so tests can assert:

- low-power mode suppresses new work
- serious/critical thermal state suppresses new work
- sustained MPV buffering cancels active analysis
- only one active task exists

Cancellation tokens must change when URL, stream identity, audio descriptor, or player lifetime changes.

- [ ] **Step 5: Run coordinator tests**

Run:

```bash
xcodebuild test \
  -project MoonlitApp.xcodeproj \
  -scheme MoonlitApp \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' \
  -only-testing:MoonlitAppTests/IntroFingerprintCoordinatorTests
```

Expected: PASS.

- [ ] **Step 6: Commit orchestration**

```bash
git add \
  Apps/MoonlitApp/Sources/Services/IntroFingerprintCoordinator.swift \
  Apps/MoonlitApp/Tests/IntroFingerprintCoordinatorTests.swift
git commit -m "feat: coordinate per-stream intro matching"
```

---

### Task 6: Player Audio Descriptor and Segment Integration

**Files:**
- Modify: `Apps/MoonlitApp/Sources/Components/MPVPlayerEngine.swift`
- Modify: `Apps/MoonlitApp/Sources/Screens/PlayerScreen.swift`
- Modify: `Apps/MoonlitApp/Tests/SubtitleCueIndexTests.swift`
- Modify: `Apps/MoonlitApp/Tests/IntroFingerprintCoordinatorTests.swift`

**Interfaces:**
- Consumes: coordinator API from Task 5.
- Produces: `MPVPlayerEngine.selectedAudioDescriptor` and fingerprint-enhanced `PlaybackSegmentsViewModel`.

- [ ] **Step 1: Write failing selected-audio and merge tests**

```swift
func testSelectingAudioUpdatesFingerprintDescriptor() {
    let engine = MPVPlayerEngine()
    engine.replaceAudioTracksForTesting([
        .init(id: 1, languageCode: "en", title: "Original", isSelected: true),
        .init(id: 2, languageCode: "ja", title: "Original", isSelected: false)
    ])
    engine.selectAudioTrack(id: 2)
    XCTAssertEqual(engine.selectedAudioDescriptor?.languageCode, "ja")
}

func testEmbeddedIntroWinsOverFingerprintIntro()
func testFingerprintIntroReplacesAgnosticRemoteIntro()
func testFingerprintIntroDoesNotRemoveExistingRecap()
```

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```bash
xcodebuild test \
  -project MoonlitApp.xcodeproj \
  -scheme MoonlitApp \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' \
  -only-testing:MoonlitAppTests/MPVPlayerSeekTests \
  -only-testing:MoonlitAppTests/IntroFingerprintCoordinatorTests
```

Expected: FAIL because the descriptor and merge behavior are absent.

- [ ] **Step 3: Publish the exact selected audio descriptor**

In `MPVPlayerEngine`, update track enumeration and selection to publish:

```swift
@Published public private(set)
var selectedAudioDescriptor: SelectedAudioDescriptor?
```

Set it from the selected MPV audio-track ID, normalized language metadata, and title. Reset it during `cleanup()`. Do not infer selection from display labels.

- [ ] **Step 4: Integrate the coordinator into the segment task**

Extend `PlaybackSegmentsViewModel.load` to:

1. resolve existing segments immediately;
2. publish them;
3. invoke the coordinator only when the request has a valid series episode and selected audio descriptor;
4. merge a verified fingerprint intro without deleting existing recap/outro;
5. reject late results using the existing `activeLoadToken`.

Use this priority:

```swift
embedded intro
    ?? fingerprint intro
    ?? existing remote intro
```

Do not move or resize the skip-action layout.

- [ ] **Step 5: Wire cancellation to every player lifecycle edge**

Cancel and clear fingerprint work on:

- `activeLaunch.sourceUrl` change
- selected audio descriptor change
- sustained `paused-for-cache`
- player dismissal
- MPV error
- stream-switch retry
- `PlaybackSegmentsViewModel.clear()`

- [ ] **Step 6: Run focused player tests**

Run:

```bash
xcodebuild test \
  -project MoonlitApp.xcodeproj \
  -scheme MoonlitApp \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' \
  -only-testing:MoonlitAppTests/MPVPlayerSeekTests \
  -only-testing:MoonlitAppTests/IntroFingerprintCoordinatorTests
```

Expected: PASS.

- [ ] **Step 7: Commit player integration**

```bash
git add \
  Apps/MoonlitApp/Sources/Components/MPVPlayerEngine.swift \
  Apps/MoonlitApp/Sources/Screens/PlayerScreen.swift \
  Apps/MoonlitApp/Tests/SubtitleCueIndexTests.swift \
  Apps/MoonlitApp/Tests/IntroFingerprintCoordinatorTests.swift
git commit -m "feat: adapt skip intro to selected stream"
```

---

### Task 7: Full Verification, Performance Diagnostics, and Physical Installation

**Files:**
- Modify only if verification exposes a defect in the files listed in Tasks 1–6.

**Interfaces:**
- Consumes: completed implementation.
- Produces: test evidence, device build, installed application, and sanitized runtime timing evidence.

- [ ] **Step 1: Run all MoonlitCore tests**

Run:

```bash
swift test --package-path ../../Packages/MoonlitCore
```

Expected: all tests PASS.

- [ ] **Step 2: Run all iOS app tests**

Run:

```bash
xcodebuild test \
  -project MoonlitApp.xcodeproj \
  -scheme MoonlitApp \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1'
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Build the signed app for the connected iPhone**

Run:

```bash
xcodebuild build \
  -project MoonlitApp.xcodeproj \
  -scheme MoonlitApp \
  -configuration Debug \
  -destination 'platform=iOS,id=00008150-001534C10CA0C01C' \
  -derivedDataPath build/DerivedData-iPhone17 \
  -allowProvisioningUpdates
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Install and launch on the physical iPhone**

Run:

```bash
xcrun devicectl device install app \
  --device 00008150-001534C10CA0C01C \
  build/DerivedData-iPhone17/Build/Products/Debug-iphoneos/MoonlitApp.app

xcrun devicectl device process launch \
  --device 00008150-001534C10CA0C01C \
  app.trymoonlit
```

Expected: installation and launch both succeed. Do not use Revyl or any cloud device.

- [ ] **Step 5: Verify user-visible and runtime behavior**

On the physical phone, verify:

- playback begins before fingerprint completion;
- analysis samples only the active source;
- an existing season reference relocates the intro in a shifted-cut fixture/stream;
- low-confidence or unavailable matching leaves current provider timing intact;
- video does not stutter while analysis runs;
- Skip Intro does not move other controls;
- changing source or audio track cancels the previous task;
- closing the player cancels work and restores portrait;
- replaying the same stream uses the cached match;
- diagnostics contain host and timing only, never URL queries or header values.

Capture sanitized elapsed-time, CPU, memory, and thermal observations for at least one direct stream and one HLS/debrid stream. The feature passes only if the direct-stream target is normally within 10 seconds and all analysis stops at 30 seconds.

- [ ] **Step 6: Review the final diff for scope and secrets**

Run:

```bash
git diff --check
git diff --name-only HEAD~6..HEAD
rg -n \"Authorization|Bearer |token=|Cookie:\" \
  Apps/MoonlitApp/Sources/Services \
  Packages/MoonlitCore/Sources/MoonlitCore/Services
```

Expected: no whitespace errors, only planned files plus justified fixes, and no credentials or logged secret values.

- [ ] **Step 7: Commit any verification-only fixes**

If verification required fixes, stage only the affected fingerprint files and commit:

```bash
git commit -m "fix: harden stream fingerprint analysis"
```

If no fixes were required, do not create an empty commit.
