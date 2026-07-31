import Foundation

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

    private enum StoreError: Error {
        case unsupportedSchemaVersion(Int)
    }

    private let fileURL: URL
    private let referenceLimit: Int
    private let matchLimit: Int
    private var didLoad = false
    private var accessSequence: UInt64 = 0
    private var references: [IntroFingerprintReferenceKey: ReferenceRecord] = [:]
    private var matches: [StreamFingerprintIdentity: MatchRecord] = [:]

    public init(fileURL: URL, referenceLimit: Int = 50, matchLimit: Int = 200) {
        self.fileURL = fileURL
        self.referenceLimit = max(0, referenceLimit)
        self.matchLimit = max(0, matchLimit)
    }

    public func reference(
        for key: IntroFingerprintReferenceKey
    ) async throws -> IntroFingerprintReference? {
        try loadIfNeeded()
        guard key.algorithmVersion == AudioFingerprint.algorithmVersion,
              var record = references[key] else {
            return nil
        }

        record.lastAccessSequence = nextAccessSequence()
        references[key] = record
        try persist()
        return record.reference
    }

    public func match(
        for identity: StreamFingerprintIdentity
    ) async throws -> StreamFingerprintMatch? {
        try loadIfNeeded()
        guard var record = matches[identity] else { return nil }
        guard record.match.referenceKey.algorithmVersion == AudioFingerprint.algorithmVersion else {
            matches.removeValue(forKey: identity)
            try persist()
            return nil
        }

        record.lastAccessSequence = nextAccessSequence()
        matches[identity] = record
        try persist()
        return record.match
    }

    public func save(reference: IntroFingerprintReference) async throws {
        try loadIfNeeded()
        guard reference.key.algorithmVersion == AudioFingerprint.algorithmVersion else {
            references.removeValue(forKey: reference.key)
            try persist()
            return
        }

        references[reference.key] = ReferenceRecord(
            reference: reference,
            lastAccessSequence: nextAccessSequence()
        )
        evictReferencesIfNeeded()
        try persist()
    }

    public func save(match: StreamFingerprintMatch) async throws {
        try loadIfNeeded()
        guard match.referenceKey.algorithmVersion == AudioFingerprint.algorithmVersion else {
            matches.removeValue(forKey: match.identity)
            try persist()
            return
        }

        matches[match.identity] = MatchRecord(
            match: match,
            lastAccessSequence: nextAccessSequence()
        )
        evictMatchesIfNeeded()
        try persist()
    }

    public func removeReference(for key: IntroFingerprintReferenceKey) async throws {
        try loadIfNeeded()
        references.removeValue(forKey: key)
        try persist()
    }

    private func loadIfNeeded() throws {
        guard !didLoad else { return }
        didLoad = true

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let data = try Data(contentsOf: fileURL)

        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.schemaVersion == Self.schemaVersion else {
                throw StoreError.unsupportedSchemaVersion(envelope.schemaVersion)
            }
        } catch {
            references.removeAll()
            matches.removeAll()
            accessSequence = 0
            try quarantineCorruptedFile()
            return
        }

        accessSequence = envelope.accessSequence
        references = Dictionary(
            envelope.references
                .filter {
                    $0.reference.key.algorithmVersion == AudioFingerprint.algorithmVersion
                }
                .map { ($0.reference.key, $0) },
            uniquingKeysWith: { first, second in
                first.lastAccessSequence >= second.lastAccessSequence ? first : second
            }
        )
        matches = Dictionary(
            envelope.matches
                .filter {
                    $0.match.referenceKey.algorithmVersion == AudioFingerprint.algorithmVersion
                }
                .map { ($0.match.identity, $0) },
            uniquingKeysWith: { first, second in
                first.lastAccessSequence >= second.lastAccessSequence ? first : second
            }
        )
        accessSequence = max(
            accessSequence,
            references.values.map(\.lastAccessSequence).max() ?? 0,
            matches.values.map(\.lastAccessSequence).max() ?? 0
        )
        evictReferencesIfNeeded()
        evictMatchesIfNeeded()
        if references.count != envelope.references.count
            || matches.count != envelope.matches.count {
            try persist()
        }
    }

    private func nextAccessSequence() -> UInt64 {
        accessSequence &+= 1
        return accessSequence
    }

    private func evictReferencesIfNeeded() {
        while references.count > referenceLimit,
              let key = references.min(by: {
                  $0.value.lastAccessSequence < $1.value.lastAccessSequence
              })?.key {
            references.removeValue(forKey: key)
        }
    }

    private func evictMatchesIfNeeded() {
        while matches.count > matchLimit,
              let identity = matches.min(by: {
                  $0.value.lastAccessSequence < $1.value.lastAccessSequence
              })?.key {
            matches.removeValue(forKey: identity)
        }
    }

    private func persist() throws {
        let envelope = Envelope(
            schemaVersion: Self.schemaVersion,
            accessSequence: accessSequence,
            references: references.values.sorted {
                $0.lastAccessSequence < $1.lastAccessSequence
            },
            matches: matches.values.sorted {
                $0.lastAccessSequence < $1.lastAccessSequence
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)

        let fileManager = FileManager.default
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let temporaryURL = directoryURL.appendingPathComponent(
            ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp"
        )

        do {
            try data.write(to: temporaryURL)
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(
                    fileURL,
                    withItemAt: temporaryURL
                )
            } else {
                try fileManager.moveItem(at: temporaryURL, to: fileURL)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func quarantineCorruptedFile() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        let quarantineURL = fileURL.appendingPathExtension("corrupt")
        if fileManager.fileExists(atPath: quarantineURL.path) {
            try fileManager.removeItem(at: quarantineURL)
        }
        try fileManager.moveItem(at: fileURL, to: quarantineURL)
    }
}
