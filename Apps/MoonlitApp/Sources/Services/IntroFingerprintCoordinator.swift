import Foundation
import MoonlitCore
import OSLog

struct IntroFingerprintRequest: Sendable {
    let segmentRequest: PlaybackSegmentRequest
    let sourceURL: URL
    let sourceHeaders: [String: String]
    let audio: SelectedAudioDescriptor
}

enum FingerprintThermalState: Sendable {
    case nominal
    case fair
    case serious
    case critical
}

struct FingerprintRuntimeSnapshot: Sendable {
    let isLowPowerModeEnabled: Bool
    let thermalState: FingerprintThermalState
    let isSustainedBuffering: Bool

    init(
        isLowPowerModeEnabled: Bool = false,
        thermalState: FingerprintThermalState = .nominal,
        isSustainedBuffering: Bool = false
    ) {
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.thermalState = thermalState
        self.isSustainedBuffering = isSustainedBuffering
    }

    var permitsNewWork: Bool {
        guard !isLowPowerModeEnabled, !isSustainedBuffering else {
            return false
        }
        switch thermalState {
        case .nominal, .fair:
            return true
        case .serious, .critical:
            return false
        }
    }
}

protocol FingerprintRuntimePolicy: Sendable {
    func snapshot() -> FingerprintRuntimeSnapshot
}

private struct SystemFingerprintRuntimePolicy: FingerprintRuntimePolicy {
    func snapshot() -> FingerprintRuntimeSnapshot {
        FingerprintRuntimeSnapshot(
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: Self.thermalState(
                from: ProcessInfo.processInfo.thermalState
            )
        )
    }

    private static func thermalState(
        from state: ProcessInfo.ThermalState
    ) -> FingerprintThermalState {
        switch state {
        case .nominal:
            return .nominal
        case .fair:
            return .fair
        case .serious:
            return .serious
        case .critical:
            return .critical
        @unknown default:
            return .critical
        }
    }
}

actor IntroFingerprintCoordinator {
    static let defaultStoreURL: URL = {
        guard let cachesDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            preconditionFailure("The user caches directory is unavailable")
        }
        return cachesDirectory.appendingPathComponent(
            "IntroFingerprints-v1.json"
        )
    }()

    private struct RequestKey: Equatable {
        let sourceURL: URL
        let sourceHeaders: [String: String]
        let streamIdentity: String
        let imdbID: String
        let season: Int
        let episode: Int
        let duration: Double
        let audio: SelectedAudioDescriptor
        let seedIntro: PlaybackSegment?
    }

    private struct ActiveResolution {
        let key: RequestKey
        let token: UInt64
        let task: Task<PlaybackSegment?, Never>
    }

    private enum CoordinatorFailure: Error {
        case timedOut
    }

    private static let logger = Logger(
        subsystem: "app.trymoonlit",
        category: "IntroFingerprint"
    )

    private let store: IntroFingerprintStore
    private let sampler: any StreamAudioSampling
    private let runtimePolicy: any FingerprintRuntimePolicy
    private var activeResolution: ActiveResolution?
    private var cancellationToken: UInt64 = 0

    init() {
        store = IntroFingerprintStore(fileURL: Self.defaultStoreURL)
        sampler = FFmpegStreamAudioSampler()
        runtimePolicy = SystemFingerprintRuntimePolicy()
    }

    init(
        store: IntroFingerprintStore,
        sampler: any StreamAudioSampling,
        runtimePolicy: any FingerprintRuntimePolicy
    ) {
        self.store = store
        self.sampler = sampler
        self.runtimePolicy = runtimePolicy
    }

    func resolve(
        request: IntroFingerprintRequest,
        existingSegments: PlaybackSegments?
    ) async -> PlaybackSegment? {
        let key = RequestKey(
            sourceURL: request.sourceURL,
            sourceHeaders: request.sourceHeaders,
            streamIdentity: request.segmentRequest.streamIdentity,
            imdbID: request.segmentRequest.imdbId,
            season: request.segmentRequest.season,
            episode: request.segmentRequest.episode,
            duration: request.segmentRequest.duration,
            audio: request.audio,
            seedIntro: existingSegments?.intro
        )

        if let activeResolution,
           activeResolution.key == key,
           activeResolution.token == cancellationToken {
            let result = await activeResolution.task.value
            return finish(
                result: result,
                task: activeResolution.task,
                token: activeResolution.token
            )
        }

        cancellationToken &+= 1
        let token = cancellationToken

        if let previous = activeResolution {
            previous.task.cancel()
            _ = await previous.task.value
            guard cancellationToken == token else {
                return nil
            }
            if self.activeResolution?.token == previous.token {
                self.activeResolution = nil
            }
        }

        guard cancellationToken == token else {
            return nil
        }

        let store = store
        let sampler = sampler
        let runtimePolicy = runtimePolicy
        let task = Task(priority: .utility) {
            do {
                return try await Self.performResolution(
                    request: request,
                    existingSegments: existingSegments,
                    store: store,
                    sampler: sampler,
                    runtimePolicy: runtimePolicy
                )
            } catch is CancellationError {
                return nil
            } catch CoordinatorFailure.timedOut {
                Self.logExpectedFailure("timeout")
                return nil
            } catch is StreamAudioSampleError {
                Self.logExpectedFailure("stream decoding")
                return nil
            } catch is URLError {
                Self.logExpectedFailure("network")
                return nil
            } catch let error as NSError
                where error.domain == NSCocoaErrorDomain
                    || error.domain == NSPOSIXErrorDomain {
                Self.logExpectedFailure("cache I/O")
                return nil
            } catch let error as AudioFingerprintError {
                assertionFailure(
                    "Audio fingerprint model invariant failed: \(error)"
                )
                return nil
            } catch {
                assertionFailure(
                    "Unexpected fingerprint failure type: "
                        + String(reflecting: type(of: error))
                )
                return nil
            }
        }
        activeResolution = ActiveResolution(
            key: key,
            token: token,
            task: task
        )

        let result = await task.value
        return finish(result: result, task: task, token: token)
    }

    func cancel() {
        cancellationToken &+= 1
        activeResolution?.task.cancel()
    }

    func runtimePolicyDidChange() {
        guard !runtimePolicy.snapshot().permitsNewWork else {
            return
        }
        cancel()
    }

    private func finish(
        result: PlaybackSegment?,
        task: Task<PlaybackSegment?, Never>,
        token: UInt64
    ) -> PlaybackSegment? {
        if activeResolution?.token == token {
            activeResolution = nil
        }
        guard cancellationToken == token, !task.isCancelled else {
            return nil
        }
        return result
    }
}

private extension IntroFingerprintCoordinator {
    static func performResolution(
        request: IntroFingerprintRequest,
        existingSegments: PlaybackSegments?,
        store: IntroFingerprintStore,
        sampler: any StreamAudioSampling,
        runtimePolicy: any FingerprintRuntimePolicy
    ) async throws -> PlaybackSegment? {
        let identity = streamIdentity(for: request)
        let referenceKey = referenceKey(for: request)

        if let cached = try await store.match(for: identity) {
            return playbackSegment(
                from: cached,
                expectedReferenceKey: referenceKey,
                mediaDuration: request.segmentRequest.duration
            )
        }

        try Task.checkCancellation()
        guard runtimePolicy.snapshot().permitsNewWork else {
            return nil
        }

        return try await withLiveAnalysisTimeout {
            if let reference = try await store.reference(for: referenceKey) {
                return try await alignExistingReference(
                    reference,
                    request: request,
                    identity: identity,
                    store: store,
                    sampler: sampler,
                    runtimePolicy: runtimePolicy
                )
            }

            if let intro = existingSegments?.intro,
               intro.canSeedAudioFingerprintReference {
                try await seedReference(
                    from: intro,
                    request: request,
                    key: referenceKey,
                    store: store,
                    sampler: sampler
                )
            }
            return nil
        }
    }

    static func alignExistingReference(
        _ reference: IntroFingerprintReference,
        request: IntroFingerprintRequest,
        identity: StreamFingerprintIdentity,
        store: IntroFingerprintStore,
        sampler: any StreamAudioSampling,
        runtimePolicy: any FingerprintRuntimePolicy
    ) async throws -> PlaybackSegment? {
        let boundedRange = boundedSearchRange(for: reference)
        if let segment = try await match(
            reference: reference,
            searchRange: boundedRange,
            request: request,
            identity: identity,
            store: store,
            sampler: sampler
        ) {
            return segment
        }

        try Task.checkCancellation()
        guard runtimePolicy.snapshot().permitsNewWork else {
            return nil
        }

        let fallbackRange = 0..<AudioFingerprintPolicy.openingWindow
        guard boundedRange != fallbackRange else {
            return nil
        }
        return try await match(
            reference: reference,
            searchRange: fallbackRange,
            request: request,
            identity: identity,
            store: store,
            sampler: sampler
        )
    }

    static func match(
        reference: IntroFingerprintReference,
        searchRange: Range<Double>,
        request: IntroFingerprintRequest,
        identity: StreamFingerprintIdentity,
        store: IntroFingerprintStore,
        sampler: any StreamAudioSampling
    ) async throws -> PlaybackSegment? {
        let sampleRequest = try StreamAudioSampleRequest.validated(
            sourceURL: request.sourceURL,
            headers: request.sourceHeaders,
            audio: request.audio,
            range: searchRange
        )
        let samples = try await sampler.samples(for: sampleRequest)
        try Task.checkCancellation()
        let candidate = try AudioFingerprintEngine.fingerprint(samples: samples)
        guard let fingerprintMatch = AudioFingerprintEngine.match(
            reference: reference.fingerprint,
            candidate: candidate
        ) else {
            return nil
        }
        try Task.checkCancellation()

        let start = searchRange.lowerBound + fingerprintMatch.offset
        let end = start + reference.introDuration
        guard let segment = validatedFingerprintSegment(
            start: start,
            end: end,
            confidence: fingerprintMatch.confidence,
            uncertainty: fingerprintMatch.uncertainty,
            mediaDuration: request.segmentRequest.duration
        ) else {
            return nil
        }

        try await store.save(match: StreamFingerprintMatch(
            identity: identity,
            referenceKey: reference.key,
            start: segment.start,
            end: segment.end,
            confidence: segment.confidence,
            uncertainty: fingerprintMatch.uncertainty,
            createdAt: Date()
        ))
        try Task.checkCancellation()
        return segment
    }

    static func seedReference(
        from intro: PlaybackSegment,
        request: IntroFingerprintRequest,
        key: IntroFingerprintReferenceKey,
        store: IntroFingerprintStore,
        sampler: any StreamAudioSampling
    ) async throws {
        guard intro.start.isFinite,
              intro.end.isFinite,
              intro.start >= 0,
              intro.end <= AudioFingerprintPolicy.openingWindow,
              intro.end <= request.segmentRequest.duration else {
            return
        }

        let sampleRequest = try StreamAudioSampleRequest.validated(
            sourceURL: request.sourceURL,
            headers: request.sourceHeaders,
            audio: request.audio,
            range: intro.start..<intro.end
        )
        let samples = try await sampler.samples(for: sampleRequest)
        try Task.checkCancellation()
        let fingerprint = try AudioFingerprintEngine.fingerprint(samples: samples)
        let now = Date()
        try await store.save(reference: IntroFingerprintReference(
            key: key,
            fingerprint: fingerprint,
            referenceStart: intro.start,
            introDuration: intro.end - intro.start,
            source: intro.source,
            sourceConfidence: intro.confidence,
            createdAt: now,
            lastValidatedAt: now
        ))
        try Task.checkCancellation()
    }

    static func boundedSearchRange(
        for reference: IntroFingerprintReference
    ) -> Range<Double> {
        let lowerBound = max(0, reference.referenceStart - 120)
        let upperBound = min(
            AudioFingerprintPolicy.openingWindow,
            reference.referenceStart + reference.introDuration + 120
        )
        guard lowerBound.isFinite,
              upperBound.isFinite,
              upperBound > lowerBound else {
            preconditionFailure("Stored fingerprint reference range is invalid")
        }
        return lowerBound..<upperBound
    }

    static func playbackSegment(
        from cached: StreamFingerprintMatch,
        expectedReferenceKey: IntroFingerprintReferenceKey,
        mediaDuration: Double
    ) -> PlaybackSegment? {
        guard cached.referenceKey == expectedReferenceKey else {
            return nil
        }
        return validatedFingerprintSegment(
            start: cached.start,
            end: cached.end,
            confidence: cached.confidence,
            uncertainty: cached.uncertainty,
            mediaDuration: mediaDuration
        )
    }

    static func validatedFingerprintSegment(
        start: Double,
        end: Double,
        confidence: Double,
        uncertainty: Double,
        mediaDuration: Double
    ) -> PlaybackSegment? {
        let duration = end - start
        guard start.isFinite,
              end.isFinite,
              confidence.isFinite,
              uncertainty.isFinite,
              mediaDuration.isFinite,
              start >= 0,
              end <= mediaDuration,
              end <= AudioFingerprintPolicy.openingWindow,
              duration >= AudioFingerprintPolicy.minimumIntroDuration,
              duration <= AudioFingerprintPolicy.maximumIntroDuration,
              confidence >= AudioFingerprintPolicy.minimumConfidence,
              uncertainty >= 0,
              uncertainty <= AudioFingerprintPolicy.maximumUncertainty else {
            return nil
        }
        return PlaybackSegment(
            kind: .intro,
            start: start,
            end: end,
            confidence: confidence,
            source: .audioFingerprint,
            match: .exact
        )
    }

    static func referenceKey(
        for request: IntroFingerprintRequest
    ) -> IntroFingerprintReferenceKey {
        IntroFingerprintReferenceKey(
            imdbID: request.segmentRequest.imdbId,
            season: request.segmentRequest.season,
            audioLanguage: request.audio.languageCode,
            algorithmVersion: AudioFingerprint.algorithmVersion
        )
    }

    static func streamIdentity(
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

    static func withLiveAnalysisTimeout<T: Sendable>(
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: AudioFingerprintPolicy.timeout)
                throw CoordinatorFailure.timedOut
            }

            guard let result = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return result
        }
    }

    static func logExpectedFailure(_ category: String) {
        logger.notice(
            "Fingerprint analysis produced no segment (\(category, privacy: .public))"
        )
    }
}
