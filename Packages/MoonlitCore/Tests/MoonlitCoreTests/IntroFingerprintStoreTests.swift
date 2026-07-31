import Foundation
import XCTest
@testable import MoonlitCore

final class IntroFingerprintStoreTests: XCTestCase {
    func testReferenceAndMatchRoundTripAcrossStoreInstances() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let reference = makeReference(index: 1)
        let match = makeMatch(index: 1, referenceKey: reference.key)

        let writer = IntroFingerprintStore(fileURL: fixture.fileURL)
        try await writer.save(reference: reference)
        try await writer.save(match: match)

        let reader = IntroFingerprintStore(fileURL: fixture.fileURL)
        let restoredReference = try await reader.reference(for: reference.key)
        let restoredMatch = try await reader.match(for: match.identity)

        XCTAssertEqual(restoredReference, reference)
        XCTAssertEqual(restoredMatch, match)
    }

    func testReferencesFromAnotherAlgorithmVersionAreInvalidated() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let stale = makeReference(
            index: 1,
            algorithmVersion: AudioFingerprint.algorithmVersion + 1
        )

        let writer = IntroFingerprintStore(fileURL: fixture.fileURL)
        try await writer.save(reference: stale)

        let reader = IntroFingerprintStore(fileURL: fixture.fileURL)
        let restored = try await reader.reference(for: stale.key)

        XCTAssertNil(restored)
    }

    func testMatchesFromAnotherAlgorithmVersionAreInvalidated() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let staleKey = makeKey(
            index: 1,
            algorithmVersion: AudioFingerprint.algorithmVersion + 1
        )
        let stale = makeMatch(index: 1, referenceKey: staleKey)

        let writer = IntroFingerprintStore(fileURL: fixture.fileURL)
        try await writer.save(match: stale)

        let reader = IntroFingerprintStore(fileURL: fixture.fileURL)
        let restored = try await reader.match(for: stale.identity)

        XCTAssertNil(restored)
    }

    func testReferenceLookupIsIsolatedByNormalizedAudioLanguage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let english = makeReference(index: 1, language: "eng")
        let french = makeReference(index: 1, language: "fr")
        let store = IntroFingerprintStore(fileURL: fixture.fileURL)

        try await store.save(reference: english)
        try await store.save(reference: french)

        let restoredEnglish = try await store.reference(
            for: makeKey(index: 1, language: "en")
        )
        let restoredFrench = try await store.reference(
            for: makeKey(index: 1, language: "fra")
        )
        let german = try await store.reference(for: makeKey(index: 1, language: "de"))

        XCTAssertEqual(restoredEnglish, english)
        XCTAssertEqual(restoredFrench, french)
        XCTAssertNil(german)
    }

    func testReferenceLRUEvictsLeastRecentlyAccessedAtDefaultLimitOf50() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = IntroFingerprintStore(fileURL: fixture.fileURL)

        for index in 0..<50 {
            try await store.save(reference: makeReference(index: index))
        }
        let retainedKey = makeKey(index: 0)
        let firstAccess = try await store.reference(for: retainedKey)
        XCTAssertNotNil(firstAccess)

        let reopened = IntroFingerprintStore(fileURL: fixture.fileURL)
        try await reopened.save(reference: makeReference(index: 50))

        let retained = try await reopened.reference(for: retainedKey)
        let evicted = try await reopened.reference(for: makeKey(index: 1))
        let newest = try await reopened.reference(for: makeKey(index: 50))
        XCTAssertNotNil(retained)
        XCTAssertNil(evicted)
        XCTAssertNotNil(newest)
    }

    func testMatchLRUEvictsLeastRecentlyAccessedAtDefaultLimitOf200() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = IntroFingerprintStore(fileURL: fixture.fileURL)
        let referenceKey = makeKey(index: 0)

        for index in 0..<200 {
            try await store.save(match: makeMatch(index: index, referenceKey: referenceKey))
        }
        let retainedIdentity = makeIdentity(index: 0)
        let firstAccess = try await store.match(for: retainedIdentity)
        XCTAssertNotNil(firstAccess)

        let reopened = IntroFingerprintStore(fileURL: fixture.fileURL)
        try await reopened.save(match: makeMatch(index: 200, referenceKey: referenceKey))

        let retained = try await reopened.match(for: retainedIdentity)
        let evicted = try await reopened.match(for: makeIdentity(index: 1))
        let newest = try await reopened.match(for: makeIdentity(index: 200))
        XCTAssertNotNil(retained)
        XCTAssertNil(evicted)
        XCTAssertNotNil(newest)
    }

    func testCorruptedFileIsQuarantinedWithoutTouchingSiblingFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let unrelatedURL = fixture.directoryURL.appendingPathComponent("unrelated.json")
        try Data("keep me".utf8).write(to: unrelatedURL)
        let corruptedData = Data("{not-json".utf8)
        try corruptedData.write(to: fixture.fileURL)
        let store = IntroFingerprintStore(fileURL: fixture.fileURL)

        let restored = try await store.reference(for: makeKey(index: 0))

        let quarantineURL = fixture.fileURL.appendingPathExtension("corrupt")
        XCTAssertNil(restored)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
        XCTAssertEqual(try Data(contentsOf: quarantineURL), corruptedData)
        XCTAssertEqual(try Data(contentsOf: unrelatedURL), Data("keep me".utf8))
    }

    func testReplacingExistingEnvelopeLeavesOnlyTheCacheFile() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = makeReference(index: 1)
        let second = makeReference(index: 2)
        let store = IntroFingerprintStore(fileURL: fixture.fileURL)

        try await store.save(reference: first)
        try await store.save(reference: second)

        let siblingNames = try FileManager.default.contentsOfDirectory(
            atPath: fixture.directoryURL.path
        )
        XCTAssertEqual(siblingNames, [fixture.fileURL.lastPathComponent])
        let reader = IntroFingerprintStore(fileURL: fixture.fileURL)
        let restoredFirst = try await reader.reference(for: first.key)
        let restoredSecond = try await reader.reference(for: second.key)
        XCTAssertEqual(restoredFirst, first)
        XCTAssertEqual(restoredSecond, second)
    }

    func testPersistedEnvelopeDoesNotContainSourceURLSecrets() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let reference = makeReference(index: 1)
        let match = makeMatch(index: 1, referenceKey: reference.key)
        let store = IntroFingerprintStore(fileURL: fixture.fileURL)

        try await store.save(reference: reference)
        try await store.save(match: match)

        let persisted = String(decoding: try Data(contentsOf: fixture.fileURL), as: UTF8.self)
        XCTAssertFalse(persisted.contains("secret-token"))
        XCTAssertFalse(persisted.contains("https://"))
        XCTAssertFalse(persisted.contains("Authorization"))
    }

    func testRemoveReferencePersistsAcrossStoreInstances() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let reference = makeReference(index: 1)
        let store = IntroFingerprintStore(fileURL: fixture.fileURL)
        try await store.save(reference: reference)

        try await store.removeReference(for: reference.key)

        let reader = IntroFingerprintStore(fileURL: fixture.fileURL)
        let restored = try await reader.reference(for: reference.key)
        XCTAssertNil(restored)
    }

    func testReplacingReferenceInvalidatesMatchesUsingItsKey() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = makeReference(index: 1)
        let replacement = makeReference(index: 1, referenceStart: 72)
        let match = makeMatch(index: 1, referenceKey: original.key)
        let store = IntroFingerprintStore(fileURL: fixture.fileURL)
        try await store.save(reference: original)
        try await store.save(match: match)

        try await store.save(reference: replacement)

        let sameActorMatch = try await store.match(for: match.identity)
        let reopened = IntroFingerprintStore(fileURL: fixture.fileURL)
        let reopenedMatch = try await reopened.match(for: match.identity)
        XCTAssertNil(sameActorMatch)
        XCTAssertNil(reopenedMatch)
    }

    func testRemovingReferenceInvalidatesMatchesUsingItsKey() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let reference = makeReference(index: 1)
        let match = makeMatch(index: 1, referenceKey: reference.key)
        let store = IntroFingerprintStore(fileURL: fixture.fileURL)
        try await store.save(reference: reference)
        try await store.save(match: match)

        try await store.removeReference(for: reference.key)

        let sameActorMatch = try await store.match(for: match.identity)
        let reopened = IntroFingerprintStore(fileURL: fixture.fileURL)
        let reopenedMatch = try await reopened.match(for: match.identity)
        XCTAssertNil(sameActorMatch)
        XCTAssertNil(reopenedMatch)
    }

    func testEvictingReferenceInvalidatesMatchesUsingItsKey() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let evicted = makeReference(index: 1)
        let retained = makeReference(index: 2)
        let match = makeMatch(index: 1, referenceKey: evicted.key)
        let store = IntroFingerprintStore(
            fileURL: fixture.fileURL,
            referenceLimit: 1
        )
        try await store.save(reference: evicted)
        try await store.save(match: match)

        try await store.save(reference: retained)

        let sameActorMatch = try await store.match(for: match.identity)
        let reopened = IntroFingerprintStore(fileURL: fixture.fileURL)
        let reopenedMatch = try await reopened.match(for: match.identity)
        XCTAssertNil(sameActorMatch)
        XCTAssertNil(reopenedMatch)
    }

    func testFailedSaveDoesNotPublishUnpersistedState() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let fileIO = FaultInjectingFileIO()
        let original = makeReference(index: 1)
        let rejected = makeReference(index: 2)
        let store = IntroFingerprintStore(fileURL: fixture.fileURL, fileIO: fileIO)
        try await store.save(reference: original)

        fileIO.failWrites = true
        do {
            try await store.save(reference: rejected)
            XCTFail("Expected the injected persistence failure")
        } catch {}
        fileIO.failWrites = false

        let sameActorOriginal = try await store.reference(for: original.key)
        let sameActorRejected = try await store.reference(for: rejected.key)
        let reopened = IntroFingerprintStore(fileURL: fixture.fileURL)
        let reopenedOriginal = try await reopened.reference(for: original.key)
        let reopenedRejected = try await reopened.reference(for: rejected.key)
        XCTAssertEqual(sameActorOriginal, original)
        XCTAssertNil(sameActorRejected)
        XCTAssertEqual(reopenedOriginal, original)
        XCTAssertNil(reopenedRejected)
    }

    func testFailedRemovalDoesNotPublishUnpersistedState() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let fileIO = FaultInjectingFileIO()
        let reference = makeReference(index: 1)
        let store = IntroFingerprintStore(fileURL: fixture.fileURL, fileIO: fileIO)
        try await store.save(reference: reference)

        fileIO.failWrites = true
        do {
            try await store.removeReference(for: reference.key)
            XCTFail("Expected the injected persistence failure")
        } catch {}
        fileIO.failWrites = false

        let sameActor = try await store.reference(for: reference.key)
        let reopened = IntroFingerprintStore(fileURL: fixture.fileURL)
        let persisted = try await reopened.reference(for: reference.key)
        XCTAssertEqual(sameActor, reference)
        XCTAssertEqual(persisted, reference)
    }

    func testFailedReadAccessDoesNotPublishAnLRUUpdate() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let fileIO = FaultInjectingFileIO()
        let first = makeReference(index: 1)
        let second = makeReference(index: 2)
        let third = makeReference(index: 3)
        let store = IntroFingerprintStore(
            fileURL: fixture.fileURL,
            referenceLimit: 2,
            fileIO: fileIO
        )
        try await store.save(reference: first)
        try await store.save(reference: second)

        fileIO.failWrites = true
        do {
            _ = try await store.reference(for: first.key)
            XCTFail("Expected the injected persistence failure")
        } catch {}
        fileIO.failWrites = false

        try await store.save(reference: third)

        let sameActorFirst = try await store.reference(for: first.key)
        let sameActorSecond = try await store.reference(for: second.key)
        let reopened = IntroFingerprintStore(fileURL: fixture.fileURL)
        let reopenedFirst = try await reopened.reference(for: first.key)
        let reopenedSecond = try await reopened.reference(for: second.key)
        XCTAssertNil(sameActorFirst)
        XCTAssertEqual(sameActorSecond, second)
        XCTAssertNil(reopenedFirst)
        XCTAssertEqual(reopenedSecond, second)
    }

    func testTransientReadFailureRetriesBeforeSaving() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = makeReference(index: 1)
        let addedAfterRetry = makeReference(index: 2)
        let writer = IntroFingerprintStore(fileURL: fixture.fileURL)
        try await writer.save(reference: original)
        let fileIO = FaultInjectingFileIO()
        fileIO.readFailuresRemaining = 1
        let store = IntroFingerprintStore(fileURL: fixture.fileURL, fileIO: fileIO)

        do {
            _ = try await store.reference(for: original.key)
            XCTFail("Expected the injected transient read failure")
        } catch {}

        try await store.save(reference: addedAfterRetry)

        let sameActorOriginal = try await store.reference(for: original.key)
        let reopened = IntroFingerprintStore(fileURL: fixture.fileURL)
        let reopenedOriginal = try await reopened.reference(for: original.key)
        let reopenedAdded = try await reopened.reference(for: addedAfterRetry.key)
        XCTAssertEqual(sameActorOriginal, original)
        XCTAssertEqual(reopenedOriginal, original)
        XCTAssertEqual(reopenedAdded, addedAfterRetry)
    }
}

private extension IntroFingerprintStoreTests {
    struct Fixture {
        let directoryURL: URL
        let fileURL: URL

        init() throws {
            directoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            fileURL = directoryURL.appendingPathComponent("IntroFingerprints-v1.json")
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    func makeKey(
        index: Int,
        language: String = "en",
        algorithmVersion: Int = AudioFingerprint.algorithmVersion
    ) -> IntroFingerprintReferenceKey {
        IntroFingerprintReferenceKey(
            imdbID: "tt\(String(format: "%07d", index))",
            season: index + 1,
            audioLanguage: language,
            algorithmVersion: algorithmVersion
        )
    }

    func makeReference(
        index: Int,
        language: String = "en",
        algorithmVersion: Int = AudioFingerprint.algorithmVersion,
        referenceStart: Double = 61
    ) -> IntroFingerprintReference {
        IntroFingerprintReference(
            key: makeKey(
                index: index,
                language: language,
                algorithmVersion: algorithmVersion
            ),
            fingerprint: AudioFingerprint(
                sampleRate: AudioFingerprintPolicy.sampleRate,
                hopSize: 512,
                duration: 30,
                landmarks: [.init(hash: UInt32(index), frame: index)]
            ),
            referenceStart: referenceStart,
            introDuration: 30,
            source: .skipDB,
            sourceConfidence: 0.9,
            createdAt: Date(timeIntervalSince1970: 1_000),
            lastValidatedAt: Date(timeIntervalSince1970: 2_000)
        )
    }

    func makeIdentity(index: Int) -> StreamFingerprintIdentity {
        StreamFingerprintIdentity.make(
            sourceURL: "https://cdn.example.test/video-\(index).mkv?token=secret-token",
            streamIdentity: "stream-\(index)",
            duration: 2_800,
            audioLanguage: "en",
            audioTitle: "Main"
        )
    }

    func makeMatch(
        index: Int,
        referenceKey: IntroFingerprintReferenceKey
    ) -> StreamFingerprintMatch {
        StreamFingerprintMatch(
            identity: makeIdentity(index: index),
            referenceKey: referenceKey,
            start: 61,
            end: 91,
            confidence: 0.9,
            uncertainty: 0.4,
            createdAt: Date(timeIntervalSince1970: 3_000)
        )
    }
}

private enum InjectedFileIOError: Error {
    case read
    case write
}

private final class FaultInjectingFileIO: IntroFingerprintStoreFileIO, @unchecked Sendable {
    private let lock = NSLock()
    private var storedFailWrites = false
    private var storedReadFailuresRemaining = 0

    var failWrites: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedFailWrites
        }
        set {
            lock.lock()
            storedFailWrites = newValue
            lock.unlock()
        }
    }

    var readFailuresRemaining: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedReadFailuresRemaining
        }
        set {
            lock.lock()
            storedReadFailuresRemaining = newValue
            lock.unlock()
        }
    }

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func read(from url: URL) throws -> Data {
        lock.lock()
        if storedReadFailuresRemaining > 0 {
            storedReadFailuresRemaining -= 1
            lock.unlock()
            throw InjectedFileIOError.read
        }
        lock.unlock()
        return try Data(contentsOf: url)
    }

    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    func write(_ data: Data, to url: URL) throws {
        if failWrites {
            throw InjectedFileIOError.write
        }
        try data.write(to: url)
    }

    func replaceItem(at originalURL: URL, with replacementURL: URL) throws {
        _ = try FileManager.default.replaceItemAt(
            originalURL,
            withItemAt: replacementURL
        )
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }

    func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
