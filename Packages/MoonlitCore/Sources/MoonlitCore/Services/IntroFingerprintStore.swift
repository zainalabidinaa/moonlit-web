import Foundation

protocol IntroFingerprintStoreFileIO: Sendable {
    func fileExists(at url: URL) -> Bool
    func read(from url: URL) throws -> Data
    func createDirectory(at url: URL) throws
    func write(_ data: Data, to url: URL) throws
    func replaceItem(at originalURL: URL, with replacementURL: URL) throws
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws
    func removeItem(at url: URL) throws
}

private struct LocalIntroFingerprintStoreFileIO: IntroFingerprintStoreFileIO {
    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func read(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    func write(_ data: Data, to url: URL) throws {
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

public actor IntroFingerprintStore {
    private static let schemaVersion = 1

    private struct ReferenceRecord: Codable, Sendable {
        let reference: IntroFingerprintReference
        var lastAccessSequence: UInt64
    }

    private struct MatchRecord: Codable, Sendable {
        let match: StreamFingerprintMatch
        var lastAccessSequence: UInt64
    }

    private struct Envelope: Codable, Sendable {
        let schemaVersion: Int
        let accessSequence: UInt64
        let references: [ReferenceRecord]
        let matches: [MatchRecord]
    }

    private struct State: Sendable {
        var accessSequence: UInt64 = 0
        var references: [IntroFingerprintReferenceKey: ReferenceRecord] = [:]
        var matches: [StreamFingerprintIdentity: MatchRecord] = [:]
    }

    private enum StoreError: Error {
        case unsupportedSchemaVersion(Int)
    }

    private let fileURL: URL
    private let referenceLimit: Int
    private let matchLimit: Int
    private let fileIO: any IntroFingerprintStoreFileIO
    private var didLoad = false
    private var state = State()

    public init(fileURL: URL, referenceLimit: Int = 50, matchLimit: Int = 200) {
        self.fileURL = fileURL
        self.referenceLimit = max(0, referenceLimit)
        self.matchLimit = max(0, matchLimit)
        fileIO = LocalIntroFingerprintStoreFileIO()
    }

    init(
        fileURL: URL,
        referenceLimit: Int = 50,
        matchLimit: Int = 200,
        fileIO: any IntroFingerprintStoreFileIO
    ) {
        self.fileURL = fileURL
        self.referenceLimit = max(0, referenceLimit)
        self.matchLimit = max(0, matchLimit)
        self.fileIO = fileIO
    }

    public func reference(
        for key: IntroFingerprintReferenceKey
    ) async throws -> IntroFingerprintReference? {
        try loadIfNeeded()
        guard key.algorithmVersion == AudioFingerprint.algorithmVersion,
              var record = state.references[key] else {
            return nil
        }

        var candidate = state
        record.lastAccessSequence = nextAccessSequence(in: &candidate)
        candidate.references[key] = record
        try persist(candidate)
        state = candidate
        return record.reference
    }

    public func match(
        for identity: StreamFingerprintIdentity
    ) async throws -> StreamFingerprintMatch? {
        try loadIfNeeded()
        guard var record = state.matches[identity] else { return nil }
        guard record.match.referenceKey.algorithmVersion == AudioFingerprint.algorithmVersion else {
            var candidate = state
            candidate.matches.removeValue(forKey: identity)
            try persist(candidate)
            state = candidate
            return nil
        }

        var candidate = state
        record.lastAccessSequence = nextAccessSequence(in: &candidate)
        candidate.matches[identity] = record
        try persist(candidate)
        state = candidate
        return record.match
    }

    public func save(reference: IntroFingerprintReference) async throws {
        try loadIfNeeded()
        var candidate = state
        candidate.matches = candidate.matches.filter {
            $0.value.match.referenceKey != reference.key
        }
        guard reference.key.algorithmVersion == AudioFingerprint.algorithmVersion else {
            candidate.references.removeValue(forKey: reference.key)
            try persist(candidate)
            state = candidate
            return
        }

        candidate.references[reference.key] = ReferenceRecord(
            reference: reference,
            lastAccessSequence: nextAccessSequence(in: &candidate)
        )
        evictReferencesIfNeeded(in: &candidate)
        try persist(candidate)
        state = candidate
    }

    public func save(match: StreamFingerprintMatch) async throws {
        try loadIfNeeded()
        var candidate = state
        guard match.referenceKey.algorithmVersion == AudioFingerprint.algorithmVersion else {
            candidate.matches.removeValue(forKey: match.identity)
            try persist(candidate)
            state = candidate
            return
        }

        candidate.matches[match.identity] = MatchRecord(
            match: match,
            lastAccessSequence: nextAccessSequence(in: &candidate)
        )
        evictMatchesIfNeeded(in: &candidate)
        try persist(candidate)
        state = candidate
    }

    public func removeReference(for key: IntroFingerprintReferenceKey) async throws {
        try loadIfNeeded()
        var candidate = state
        candidate.references.removeValue(forKey: key)
        candidate.matches = candidate.matches.filter {
            $0.value.match.referenceKey != key
        }
        try persist(candidate)
        state = candidate
    }

    private func loadIfNeeded() throws {
        guard !didLoad else { return }

        guard fileIO.fileExists(at: fileURL) else {
            didLoad = true
            return
        }
        let data = try fileIO.read(from: fileURL)

        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.schemaVersion == Self.schemaVersion else {
                throw StoreError.unsupportedSchemaVersion(envelope.schemaVersion)
            }
        } catch {
            try quarantineCorruptedFile()
            state = State()
            didLoad = true
            return
        }

        var candidate = State()
        candidate.accessSequence = envelope.accessSequence
        candidate.references = Dictionary(
            envelope.references
                .filter {
                    $0.reference.key.algorithmVersion == AudioFingerprint.algorithmVersion
                }
                .map { ($0.reference.key, $0) },
            uniquingKeysWith: { first, second in
                first.lastAccessSequence >= second.lastAccessSequence ? first : second
            }
        )
        candidate.matches = Dictionary(
            envelope.matches
                .filter {
                    $0.match.referenceKey.algorithmVersion == AudioFingerprint.algorithmVersion
                }
                .map { ($0.match.identity, $0) },
            uniquingKeysWith: { first, second in
                first.lastAccessSequence >= second.lastAccessSequence ? first : second
            }
        )
        candidate.accessSequence = max(
            candidate.accessSequence,
            candidate.references.values.map(\.lastAccessSequence).max() ?? 0,
            candidate.matches.values.map(\.lastAccessSequence).max() ?? 0
        )
        evictReferencesIfNeeded(in: &candidate)
        evictMatchesIfNeeded(in: &candidate)
        if candidate.references.count != envelope.references.count
            || candidate.matches.count != envelope.matches.count {
            try persist(candidate)
        }
        state = candidate
        didLoad = true
    }

    private func nextAccessSequence(in candidate: inout State) -> UInt64 {
        candidate.accessSequence &+= 1
        return candidate.accessSequence
    }

    private func evictReferencesIfNeeded(in candidate: inout State) {
        while candidate.references.count > referenceLimit,
              let key = candidate.references.min(by: {
                  $0.value.lastAccessSequence < $1.value.lastAccessSequence
              })?.key {
            candidate.references.removeValue(forKey: key)
            candidate.matches = candidate.matches.filter {
                $0.value.match.referenceKey != key
            }
        }
    }

    private func evictMatchesIfNeeded(in candidate: inout State) {
        while candidate.matches.count > matchLimit,
              let identity = candidate.matches.min(by: {
                  $0.value.lastAccessSequence < $1.value.lastAccessSequence
              })?.key {
            candidate.matches.removeValue(forKey: identity)
        }
    }

    private func persist(_ candidate: State) throws {
        let envelope = Envelope(
            schemaVersion: Self.schemaVersion,
            accessSequence: candidate.accessSequence,
            references: candidate.references.values.sorted {
                $0.lastAccessSequence < $1.lastAccessSequence
            },
            matches: candidate.matches.values.sorted {
                $0.lastAccessSequence < $1.lastAccessSequence
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)

        let directoryURL = fileURL.deletingLastPathComponent()
        try fileIO.createDirectory(at: directoryURL)
        let temporaryURL = directoryURL.appendingPathComponent(
            ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp"
        )

        do {
            try fileIO.write(data, to: temporaryURL)
            if fileIO.fileExists(at: fileURL) {
                try fileIO.replaceItem(
                    at: fileURL,
                    with: temporaryURL
                )
            } else {
                try fileIO.moveItem(at: temporaryURL, to: fileURL)
            }
        } catch {
            try? fileIO.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func quarantineCorruptedFile() throws {
        guard fileIO.fileExists(at: fileURL) else { return }
        let quarantineURL = fileURL.appendingPathExtension("corrupt")
        if fileIO.fileExists(at: quarantineURL) {
            try fileIO.removeItem(at: quarantineURL)
        }
        try fileIO.moveItem(at: fileURL, to: quarantineURL)
    }
}
