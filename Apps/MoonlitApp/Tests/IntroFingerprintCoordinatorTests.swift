import Foundation
import MoonlitCore
import XCTest
@testable import MoonlitApp

final class IntroFingerprintCoordinatorTests: XCTestCase {
    func testCachedExactStreamMatchReturnsWithoutSampling() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest(streamIdentity: "release-cached")
        let identity = streamIdentity(for: request)
        let reference = try makeReference(for: request)
        try await fixture.store.save(reference: reference)
        try await fixture.store.save(match: StreamFingerprintMatch(
            identity: identity,
            referenceKey: reference.key,
            start: 42,
            end: 52,
            confidence: 0.91,
            uncertainty: 0.3,
            createdAt: Date(timeIntervalSince1970: 3_000)
        ))
        let sampler = FakeStreamAudioSampler(responses: [])
        let coordinator = IntroFingerprintCoordinator(
            store: fixture.store,
            sampler: sampler,
            runtimePolicy: MutableFingerprintRuntimePolicy(
                snapshot: .init(isLowPowerModeEnabled: true)
            )
        )

        let segment = await coordinator.resolve(
            request: request,
            existingSegments: nil
        )

        XCTAssertEqual(segment, PlaybackSegment(
            kind: .intro,
            start: 42,
            end: 52,
            confidence: 0.91,
            source: .audioFingerprint,
            match: .exact
        ))
        let recorded = await sampler.recordedRequests()
        XCTAssertEqual(recorded, [])
    }

    func testExistingReferenceAlignsOnlyTheSelectedStream() async throws {
        let fixture = try StoreFixture()
        let selectedURL = try XCTUnwrap(
            URL(string: "https://selected.example.test/episode.mkv?token=secret")
        )
        let request = makeRequest(
            sourceURL: selectedURL,
            streamIdentity: "selected-release"
        )
        let intro = FingerprintSignal.intro(seconds: 8)
        try await fixture.store.save(reference: try makeReference(
            for: request,
            samples: intro,
            referenceStart: 300
        ))
        let sampler = FakeStreamAudioSampler(responses: [
            FingerprintSignal.unrelated(seconds: 20),
            FingerprintSignal.speechLike(seconds: 7)
                + intro
                + FingerprintSignal.speechLike(seconds: 3)
        ])
        let coordinator = IntroFingerprintCoordinator(
            store: fixture.store,
            sampler: sampler,
            runtimePolicy: MutableFingerprintRuntimePolicy()
        )
        let existing = PlaybackSegments(
            recap: PlaybackSegment(
                kind: .recap,
                start: 0,
                end: 18,
                source: .embedded,
                match: .exact
            ),
            outro: PlaybackSegment(
                kind: .outro,
                start: 2_700,
                end: 2_760,
                source: .embedded,
                match: .exact
            )
        )

        let resolved = await coordinator.resolve(
            request: request,
            existingSegments: existing
        )
        let segment = try XCTUnwrap(resolved)

        XCTAssertEqual(segment.kind, .intro)
        XCTAssertEqual(segment.start, 7, accuracy: 0.75)
        XCTAssertEqual(segment.end, 15, accuracy: 0.75)
        XCTAssertEqual(segment.source, .audioFingerprint)
        XCTAssertEqual(segment.match, .exact)
        XCTAssertEqual(existing.recap?.start, 0)
        XCTAssertEqual(existing.outro?.start, 2_700)

        let recorded = await sampler.recordedRequests()
        XCTAssertEqual(recorded.map(\.sourceURL), [selectedURL, selectedURL])
        XCTAssertEqual(recorded.map(\.range), [180..<428, 0..<900])
        XCTAssertTrue(recorded.allSatisfy {
            $0.range.lowerBound >= 0 && $0.range.upperBound <= 900
        })
        XCTAssertTrue(recorded.allSatisfy {
            $0.headers == ["Authorization": "Bearer test-token"]
                && $0.audio == request.audio
        })
    }

    func testTrustedSegmentSeedsReferenceWithoutReplacingCurrentTiming() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest(streamIdentity: "trusted-seed")
        let intro = PlaybackSegment(
            kind: .intro,
            start: 40,
            end: 50,
            confidence: 0.93,
            source: .embedded,
            match: .exact
        )
        let existing = PlaybackSegments(
            recap: PlaybackSegment(
                kind: .recap,
                start: 0,
                end: 20,
                source: .embedded,
                match: .exact
            ),
            intro: intro,
            outro: PlaybackSegment(
                kind: .outro,
                start: 2_700,
                end: 2_760,
                source: .embedded,
                match: .exact
            )
        )
        let sampler = FakeStreamAudioSampler(responses: [
            FingerprintSignal.intro(seconds: 10)
        ])
        let coordinator = IntroFingerprintCoordinator(
            store: fixture.store,
            sampler: sampler,
            runtimePolicy: MutableFingerprintRuntimePolicy()
        )

        let resolved = await coordinator.resolve(
            request: request,
            existingSegments: existing
        )

        XCTAssertNil(resolved)
        XCTAssertEqual(existing.intro, intro)
        XCTAssertEqual(existing.recap?.end, 20)
        XCTAssertEqual(existing.outro?.start, 2_700)

        let storedReference = try await fixture.store.reference(
            for: referenceKey(for: request)
        )
        let saved = try XCTUnwrap(storedReference)
        XCTAssertEqual(saved.referenceStart, 40)
        XCTAssertEqual(saved.introDuration, 10)
        XCTAssertEqual(saved.source, .embedded)
        XCTAssertEqual(saved.sourceConfidence, 0.93)

        let recorded = await sampler.recordedRequests()
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.sourceURL, request.sourceURL)
        XCTAssertEqual(recorded.first?.range, 40..<50)
        XCTAssertTrue(recorded.allSatisfy {
            $0.range.lowerBound >= 0 && $0.range.upperBound <= 900
        })
    }

    func testAgnosticIntroDBSegmentDoesNotSeedReference() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest(streamIdentity: "agnostic")
        let sampler = FakeStreamAudioSampler(responses: [])
        let coordinator = IntroFingerprintCoordinator(
            store: fixture.store,
            sampler: sampler,
            runtimePolicy: MutableFingerprintRuntimePolicy()
        )
        let existing = PlaybackSegments(intro: PlaybackSegment(
            kind: .intro,
            start: 45,
            end: 55,
            confidence: 0.99,
            source: .introDB,
            match: .agnostic
        ))

        let segment = await coordinator.resolve(
            request: request,
            existingSegments: existing
        )

        XCTAssertNil(segment)
        let storedReference = try await fixture.store.reference(
            for: referenceKey(for: request)
        )
        let recorded = await sampler.recordedRequests()
        XCTAssertNil(storedReference)
        XCTAssertEqual(recorded, [])
    }

    func testLowConfidenceMatchProducesNoSegment() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest(streamIdentity: "unrelated-audio")
        try await fixture.store.save(reference: try makeReference(
            for: request,
            referenceStart: 240
        ))
        let sampler = FakeStreamAudioSampler(responses: [
            FingerprintSignal.unrelated(seconds: 20),
            FingerprintSignal.unrelated(seconds: 20)
        ])
        let coordinator = IntroFingerprintCoordinator(
            store: fixture.store,
            sampler: sampler,
            runtimePolicy: MutableFingerprintRuntimePolicy()
        )

        let segment = await coordinator.resolve(
            request: request,
            existingSegments: nil
        )

        XCTAssertNil(segment)
        let storedMatch = try await fixture.store.match(
            for: streamIdentity(for: request)
        )
        XCTAssertNil(storedMatch)
        let recorded = await sampler.recordedRequests()
        XCTAssertEqual(recorded.map(\.range), [120..<368, 0..<900])
        XCTAssertTrue(recorded.allSatisfy { $0.sourceURL == request.sourceURL })
        XCTAssertTrue(recorded.allSatisfy {
            $0.range.lowerBound >= 0 && $0.range.upperBound <= 900
        })
    }

    func testCancellationOnStreamChangeDropsLateResult() async throws {
        let fixture = try StoreFixture()
        let firstRequest = makeRequest(streamIdentity: "release-a")
        let secondRequest = makeRequest(streamIdentity: "release-b")
        let intro = FingerprintSignal.intro(seconds: 8)
        try await fixture.store.save(reference: try makeReference(
            for: firstRequest,
            samples: intro,
            referenceStart: 200
        ))
        let lateCandidate = FingerprintSignal.speechLike(seconds: 5)
            + intro
            + FingerprintSignal.speechLike(seconds: 3)
        let gate = LateSampleGate()
        let sampler = FakeStreamAudioSampler { _, index in
            if index == 0 {
                return await gate.samplesIgnoringCancellation()
            }
            return lateCandidate
        }
        let coordinator = IntroFingerprintCoordinator(
            store: fixture.store,
            sampler: sampler,
            runtimePolicy: MutableFingerprintRuntimePolicy()
        )

        let firstTask = Task {
            await coordinator.resolve(
                request: firstRequest,
                existingSegments: nil
            )
        }
        await gate.waitUntilStarted()
        let secondTask = Task {
            await coordinator.resolve(
                request: secondRequest,
                existingSegments: nil
            )
        }
        await gate.waitUntilCancelled()
        gate.release(with: lateCandidate)

        let first = await firstTask.value
        let secondResult = await secondTask.value
        let second = try XCTUnwrap(secondResult)
        XCTAssertNil(first)
        XCTAssertEqual(second.start, 85, accuracy: 0.75)
        XCTAssertEqual(second.end, 93, accuracy: 0.75)
        let firstStoredMatch = try await fixture.store.match(
            for: streamIdentity(for: firstRequest)
        )
        let secondStoredMatch = try await fixture.store.match(
            for: streamIdentity(for: secondRequest)
        )
        XCTAssertNil(firstStoredMatch)
        XCTAssertNotNil(secondStoredMatch)

        let snapshot = await sampler.snapshot()
        XCTAssertEqual(snapshot.maximumConcurrentRequests, 1)
        XCTAssertEqual(snapshot.requests.count, 2)
        XCTAssertTrue(snapshot.requests.allSatisfy {
            $0.sourceURL == firstRequest.sourceURL
                && $0.range == 80..<328
        })
    }

    func testRecapIsNeverFingerprintGenerated() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest(streamIdentity: "recap-only")
        let sampler = FakeStreamAudioSampler(responses: [])
        let coordinator = IntroFingerprintCoordinator(
            store: fixture.store,
            sampler: sampler,
            runtimePolicy: MutableFingerprintRuntimePolicy()
        )
        let existing = PlaybackSegments(recap: PlaybackSegment(
            kind: .recap,
            start: 0,
            end: 24,
            confidence: 1,
            source: .embedded,
            match: .exact
        ))

        let segment = await coordinator.resolve(
            request: request,
            existingSegments: existing
        )

        XCTAssertNil(segment)
        let storedReference = try await fixture.store.reference(
            for: referenceKey(for: request)
        )
        let recorded = await sampler.recordedRequests()
        XCTAssertNil(storedReference)
        XCTAssertEqual(recorded, [])
    }

    func testLowPowerModeSuppressesNewWork() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest(streamIdentity: "low-power")
        try await fixture.store.save(reference: try makeReference(for: request))
        let sampler = FakeStreamAudioSampler(responses: [
            FingerprintSignal.intro(seconds: 8)
        ])
        let coordinator = IntroFingerprintCoordinator(
            store: fixture.store,
            sampler: sampler,
            runtimePolicy: MutableFingerprintRuntimePolicy(
                snapshot: .init(isLowPowerModeEnabled: true)
            )
        )

        let segment = await coordinator.resolve(
            request: request,
            existingSegments: nil
        )
        let recorded = await sampler.recordedRequests()
        XCTAssertNil(segment)
        XCTAssertEqual(recorded, [])
    }

    func testSeriousAndCriticalThermalStatesSuppressNewWork() async throws {
        for thermalState in [
            FingerprintThermalState.serious,
            FingerprintThermalState.critical
        ] {
            let fixture = try StoreFixture()
            let request = makeRequest(
                streamIdentity: "thermal-\(thermalState)"
            )
            try await fixture.store.save(reference: try makeReference(for: request))
            let sampler = FakeStreamAudioSampler(responses: [
                FingerprintSignal.intro(seconds: 8)
            ])
            let coordinator = IntroFingerprintCoordinator(
                store: fixture.store,
                sampler: sampler,
                runtimePolicy: MutableFingerprintRuntimePolicy(
                    snapshot: .init(thermalState: thermalState)
                )
            )

            let segment = await coordinator.resolve(
                request: request,
                existingSegments: nil
            )
            let recorded = await sampler.recordedRequests()
            XCTAssertNil(segment)
            XCTAssertEqual(recorded, [])
        }
    }

    func testFallbackIsSkippedWhenRuntimePolicyChangesAfterBoundedSearch() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest(streamIdentity: "suppress-fallback")
        try await fixture.store.save(reference: try makeReference(
            for: request,
            referenceStart: 300
        ))
        let policy = MutableFingerprintRuntimePolicy()
        let sampler = FakeStreamAudioSampler { _, _ in
            policy.set(snapshot: .init(isLowPowerModeEnabled: true))
            return FingerprintSignal.unrelated(seconds: 20)
        }
        let coordinator = IntroFingerprintCoordinator(
            store: fixture.store,
            sampler: sampler,
            runtimePolicy: policy
        )

        let segment = await coordinator.resolve(
            request: request,
            existingSegments: nil
        )
        let recordedRanges = await sampler.recordedRequests().map(\.range)
        XCTAssertNil(segment)
        XCTAssertEqual(recordedRanges, [180..<428])
    }

    func testSustainedBufferingCancelsActiveAnalysis() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest(streamIdentity: "buffering")
        let intro = FingerprintSignal.intro(seconds: 8)
        try await fixture.store.save(reference: try makeReference(
            for: request,
            samples: intro
        ))
        let candidate = FingerprintSignal.speechLike(seconds: 5) + intro
        let gate = LateSampleGate()
        let sampler = FakeStreamAudioSampler { _, _ in
            await gate.samplesIgnoringCancellation()
        }
        let policy = MutableFingerprintRuntimePolicy()
        let coordinator = IntroFingerprintCoordinator(
            store: fixture.store,
            sampler: sampler,
            runtimePolicy: policy
        )

        let task = Task {
            await coordinator.resolve(
                request: request,
                existingSegments: nil
            )
        }
        await gate.waitUntilStarted()
        policy.set(snapshot: .init(isSustainedBuffering: true))
        await coordinator.runtimePolicyDidChange()
        await gate.waitUntilCancelled()
        gate.release(with: candidate)

        let segment = await task.value
        let storedMatch = try await fixture.store.match(
            for: streamIdentity(for: request)
        )
        let requestCount = await sampler.recordedRequests().count
        XCTAssertNil(segment)
        XCTAssertNil(storedMatch)
        XCTAssertEqual(requestCount, 1)
    }

    func testExplicitPlayerLifetimeCancellationDropsLateResult() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest(streamIdentity: "player-lifetime")
        let intro = FingerprintSignal.intro(seconds: 8)
        try await fixture.store.save(reference: try makeReference(
            for: request,
            samples: intro
        ))
        let gate = LateSampleGate()
        let sampler = FakeStreamAudioSampler { _, _ in
            await gate.samplesIgnoringCancellation()
        }
        let coordinator = IntroFingerprintCoordinator(
            store: fixture.store,
            sampler: sampler,
            runtimePolicy: MutableFingerprintRuntimePolicy()
        )

        let task = Task {
            await coordinator.resolve(
                request: request,
                existingSegments: nil
            )
        }
        await gate.waitUntilStarted()
        await coordinator.cancel()
        await gate.waitUntilCancelled()
        gate.release(with: FingerprintSignal.speechLike(seconds: 5) + intro)

        let segment = await task.value
        let storedMatch = try await fixture.store.match(
            for: streamIdentity(for: request)
        )
        XCTAssertNil(segment)
        XCTAssertNil(storedMatch)
    }

    func testDefaultStoreURLUsesLibraryCachesDirectory() throws {
        let cachesDirectory = try XCTUnwrap(
            FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first
        )

        let storeURL = IntroFingerprintCoordinator.defaultStoreURL

        XCTAssertEqual(storeURL.deletingLastPathComponent(), cachesDirectory)
        XCTAssertEqual(storeURL.lastPathComponent, "IntroFingerprints-v1.json")
    }
}

private extension IntroFingerprintCoordinatorTests {
    func makeRequest(
        sourceURL: URL = URL(
            string: "https://selected.example.test/episode.mkv?token=secret"
        )!,
        streamIdentity: String,
        imdbID: String = "tt0903747",
        audio: SelectedAudioDescriptor = .init(
            languageCode: "en",
            title: "Main"
        )
    ) -> IntroFingerprintRequest {
        IntroFingerprintRequest(
            segmentRequest: PlaybackSegmentRequest(
                imdbId: imdbID,
                season: 2,
                episode: 4,
                duration: 2_800,
                streamIdentity: streamIdentity
            ),
            sourceURL: sourceURL,
            sourceHeaders: ["Authorization": "Bearer test-token"],
            audio: audio
        )
    }

    func referenceKey(
        for request: IntroFingerprintRequest
    ) -> IntroFingerprintReferenceKey {
        IntroFingerprintReferenceKey(
            imdbID: request.segmentRequest.imdbId,
            season: request.segmentRequest.season,
            audioLanguage: request.audio.languageCode,
            algorithmVersion: AudioFingerprint.algorithmVersion
        )
    }

    func streamIdentity(
        for request: IntroFingerprintRequest
    ) -> StreamFingerprintIdentity {
        StreamFingerprintIdentity.make(
            sourceURL: request.sourceURL.absoluteString,
            streamIdentity: request.segmentRequest.streamIdentity,
            duration: request.segmentRequest.duration,
            audioLanguage: request.audio.languageCode,
            audioTitle: request.audio.title ?? ""
        )
    }

    func makeReference(
        for request: IntroFingerprintRequest,
        samples: [Float] = FingerprintSignal.intro(seconds: 8),
        referenceStart: Double = 200
    ) throws -> IntroFingerprintReference {
        IntroFingerprintReference(
            key: referenceKey(for: request),
            fingerprint: try AudioFingerprintEngine.fingerprint(samples: samples),
            referenceStart: referenceStart,
            introDuration: Double(samples.count)
                / Double(AudioFingerprintPolicy.sampleRate),
            source: .skipDB,
            sourceConfidence: 0.92,
            createdAt: Date(timeIntervalSince1970: 1_000),
            lastValidatedAt: Date(timeIntervalSince1970: 2_000)
        )
    }
}

private final class StoreFixture {
    let directoryURL: URL
    let store: IntroFingerprintStore

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        store = IntroFingerprintStore(
            fileURL: directoryURL.appendingPathComponent(
                "IntroFingerprints-v1.json"
            )
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private actor FakeStreamAudioSampler: StreamAudioSampling {
    struct RecordedRequest: Equatable, Sendable {
        let sourceURL: URL
        let headers: [String: String]
        let audio: SelectedAudioDescriptor
        let range: Range<Double>
    }

    struct Snapshot: Sendable {
        let requests: [RecordedRequest]
        let maximumConcurrentRequests: Int
    }

    typealias Handler = @Sendable (
        StreamAudioSampleRequest,
        Int
    ) async throws -> [Float]

    private let handler: Handler
    private var requests: [RecordedRequest] = []
    private var activeRequestCount = 0
    private var maximumConcurrentRequests = 0

    init(responses: [[Float]]) {
        handler = { _, index in
            guard responses.indices.contains(index) else {
                return FingerprintSignal.unrelated(seconds: 8)
            }
            return responses[index]
        }
    }

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func samples(for request: StreamAudioSampleRequest) async throws -> [Float] {
        let index = requests.count
        requests.append(RecordedRequest(
            sourceURL: request.sourceURL,
            headers: request.headers,
            audio: request.audio,
            range: request.range
        ))
        activeRequestCount += 1
        maximumConcurrentRequests = max(
            maximumConcurrentRequests,
            activeRequestCount
        )
        do {
            let result = try await handler(request, index)
            activeRequestCount -= 1
            return result
        } catch {
            activeRequestCount -= 1
            throw error
        }
    }

    func recordedRequests() -> [RecordedRequest] {
        requests
    }

    func snapshot() -> Snapshot {
        Snapshot(
            requests: requests,
            maximumConcurrentRequests: maximumConcurrentRequests
        )
    }
}

private final class MutableFingerprintRuntimePolicy:
    FingerprintRuntimePolicy,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedSnapshot: FingerprintRuntimeSnapshot

    init(snapshot: FingerprintRuntimeSnapshot = .init()) {
        storedSnapshot = snapshot
    }

    func snapshot() -> FingerprintRuntimeSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return storedSnapshot
    }

    func set(snapshot: FingerprintRuntimeSnapshot) {
        lock.lock()
        storedSnapshot = snapshot
        lock.unlock()
    }
}

private final class LateSampleGate: @unchecked Sendable {
    private let lock = NSLock()
    private var sampleContinuation: CheckedContinuation<[Float], Never>?
    private var started = false
    private var cancelled = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []

    func samplesIgnoringCancellation() async -> [Float] {
        signalStarted()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                sampleContinuation = continuation
                lock.unlock()
            }
        } onCancel: {
            signalCancelled()
        }
    }

    func waitUntilStarted() async {
        lock.lock()
        if started {
            lock.unlock()
            return
        }
        lock.unlock()
        await withCheckedContinuation { continuation in
            lock.lock()
            if started {
                lock.unlock()
                continuation.resume()
            } else {
                startedWaiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func waitUntilCancelled() async {
        lock.lock()
        if cancelled {
            lock.unlock()
            return
        }
        lock.unlock()
        await withCheckedContinuation { continuation in
            lock.lock()
            if cancelled {
                lock.unlock()
                continuation.resume()
            } else {
                cancellationWaiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func release(with samples: [Float]) {
        lock.lock()
        let continuation = sampleContinuation
        sampleContinuation = nil
        lock.unlock()
        continuation?.resume(returning: samples)
    }

    private func signalStarted() {
        lock.lock()
        started = true
        let waiters = startedWaiters
        startedWaiters.removeAll()
        lock.unlock()
        waiters.forEach { $0.resume() }
    }

    private func signalCancelled() {
        lock.lock()
        cancelled = true
        let waiters = cancellationWaiters
        cancellationWaiters.removeAll()
        lock.unlock()
        waiters.forEach { $0.resume() }
    }
}

private enum FingerprintSignal {
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
            let harmonic = Float(
                0.17 * sin(phase * 1.997 + Double(phrase) * 0.31)
            )
            let transient = Float(
                pulse * 0.12 * sin(2 * Double.pi * 2_300 * time)
            )
            return primary
                + harmonic
                + transient
                + accent * deterministicNoise(
                    sample: sample,
                    seed: 0xA341_316C
                )
        }
    }

    static func speechLike(seconds: Double) -> [Float] {
        signal(seconds: seconds) { time, sample in
            let syllable = Int(time / 0.19)
            let localTime = time - Double(syllable) * 0.19
            let fundamental = 105.0 + Double((syllable * 41) % 95)
            let envelope = sin(Double.pi * min(1, localTime / 0.19))
            let primary = 0.17
                * envelope
                * sin(2 * Double.pi * fundamental * time)
            let harmonic = 0.09
                * envelope
                * sin(2 * Double.pi * fundamental * 2.03 * time)
            return Float(primary + harmonic)
                + 0.025 * deterministicNoise(
                    sample: sample,
                    seed: 0xC801_3EA4
                )
        }
    }

    static func unrelated(seconds: Double) -> [Float] {
        signal(seconds: seconds) { time, sample in
            let block = Int(time / 0.43)
            let frequency = 1_350.0 + Double((block * 211) % 2_900)
            return Float(0.21 * sin(2 * Double.pi * frequency * time))
                + 0.08 * deterministicNoise(
                    sample: sample,
                    seed: 0xAD90_777D
                )
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

    private static func deterministicNoise(
        sample: Int,
        seed: UInt32
    ) -> Float {
        var value = UInt32(truncatingIfNeeded: sample) &+ seed
        value ^= value >> 16
        value &*= 0x7FEB_352D
        value ^= value >> 15
        value &*= 0x846C_A68B
        value ^= value >> 16
        return Float(Int32(bitPattern: value)) / Float(Int32.max)
    }
}
