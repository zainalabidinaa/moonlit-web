import CryptoKit
import Foundation

public struct AudioFingerprintLandmark: Codable, Hashable, Sendable {
    public let hash: UInt32
    public let frame: Int

    public init(hash: UInt32, frame: Int) {
        self.hash = hash
        self.frame = frame
    }
}

public struct AudioFingerprint: Codable, Equatable, Sendable {
    public static let algorithmVersion = 1

    public let sampleRate: Int
    public let hopSize: Int
    public let duration: Double
    public let landmarks: [AudioFingerprintLandmark]

    public init(sampleRate: Int, hopSize: Int, duration: Double, landmarks: [AudioFingerprintLandmark]) {
        self.sampleRate = sampleRate
        self.hopSize = hopSize
        self.duration = duration
        self.landmarks = landmarks
    }
}

public struct IntroFingerprintReferenceKey: Codable, Hashable, Sendable {
    public let imdbID: String
    public let season: Int
    public let audioLanguage: String
    public let algorithmVersion: Int

    public init(imdbID: String, season: Int, audioLanguage: String, algorithmVersion: Int) {
        self.imdbID = imdbID
        self.season = season
        self.audioLanguage = AudioFingerprintLanguage.normalize(audioLanguage)
        self.algorithmVersion = algorithmVersion
    }
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

    public init(
        key: IntroFingerprintReferenceKey,
        fingerprint: AudioFingerprint,
        referenceStart: Double,
        introDuration: Double,
        source: PlaybackSegmentSource,
        sourceConfidence: Double,
        createdAt: Date,
        lastValidatedAt: Date
    ) {
        self.key = key
        self.fingerprint = fingerprint
        self.referenceStart = referenceStart
        self.introDuration = introDuration
        self.source = source
        self.sourceConfidence = sourceConfidence
        self.createdAt = createdAt
        self.lastValidatedAt = lastValidatedAt
    }
}

public struct StreamFingerprintIdentity: Codable, Hashable, Sendable {
    public let rawValue: String

    private init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Produces an opaque, stable identity without retaining URL query values or headers.
    public static func make(
        sourceURL: String,
        streamIdentity: String,
        duration: Double,
        audioLanguage: String,
        audioTitle: String
    ) -> StreamFingerprintIdentity {
        let components = URLComponents(string: sourceURL)
        let sourceLocation = [
            components?.scheme?.lowercased() ?? "",
            components?.host?.lowercased() ?? "",
            components?.port.map(String.init) ?? "",
            components?.path ?? ""
        ]
        let input = (
            sourceLocation
            + [
                streamIdentity,
                String(Int(duration.rounded())),
                AudioFingerprintLanguage.normalize(audioLanguage),
                normalizeAudioTitle(audioTitle),
                String(AudioFingerprint.algorithmVersion)
            ]
        ).joined(separator: "|")
        let digest = SHA256.hash(data: Data(input.utf8))
        let rawValue = digest.map { String(format: "%02x", $0) }.joined()
        return StreamFingerprintIdentity(rawValue: rawValue)
    }

    private static func normalizeAudioTitle(_ title: String) -> String {
        title
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

public struct StreamFingerprintMatch: Codable, Equatable, Sendable {
    public let identity: StreamFingerprintIdentity
    public let referenceKey: IntroFingerprintReferenceKey
    public let start: Double
    public let end: Double
    public let confidence: Double
    public let uncertainty: Double
    public let createdAt: Date

    public init(
        identity: StreamFingerprintIdentity,
        referenceKey: IntroFingerprintReferenceKey,
        start: Double,
        end: Double,
        confidence: Double,
        uncertainty: Double,
        createdAt: Date
    ) {
        self.identity = identity
        self.referenceKey = referenceKey
        self.start = start
        self.end = end
        self.confidence = confidence
        self.uncertainty = uncertainty
        self.createdAt = createdAt
    }
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

private enum AudioFingerprintLanguage {
    private static let iso639Aliases = [
        "aar": "aa", "abk": "ab", "afr": "af", "amh": "am", "ara": "ar",
        "asm": "as", "aze": "az", "bel": "be", "bul": "bg", "ben": "bn",
        "bos": "bs", "cat": "ca", "ces": "cs", "cze": "cs", "cym": "cy",
        "wel": "cy", "dan": "da", "deu": "de", "ger": "de", "ell": "el",
        "gre": "el", "eng": "en", "est": "et", "eus": "eu", "baq": "eu",
        "fas": "fa", "per": "fa", "fin": "fi", "fil": "tl", "fra": "fr",
        "fre": "fr", "gle": "ga", "glg": "gl", "heb": "he", "iw": "he",
        "hin": "hi", "hrv": "hr", "hun": "hu", "hye": "hy", "arm": "hy",
        "ind": "id", "in": "id", "isl": "is", "ice": "is", "ita": "it",
        "jpn": "ja", "kat": "ka", "geo": "ka", "kaz": "kk", "khm": "km",
        "kor": "ko", "lao": "lo", "lit": "lt", "lav": "lv", "mkd": "mk",
        "mac": "mk", "mal": "ml", "mon": "mn", "mar": "mr", "msa": "ms",
        "may": "ms", "mya": "my", "bur": "my", "nep": "ne", "nld": "nl",
        "dut": "nl", "nor": "no", "ori": "or", "pan": "pa", "pol": "pl",
        "por": "pt", "ron": "ro", "rum": "ro", "rus": "ru", "sin": "si",
        "slk": "sk", "slo": "sk", "slv": "sl", "sqi": "sq", "alb": "sq",
        "srp": "sr", "swa": "sw", "swe": "sv", "tam": "ta", "tel": "te",
        "tha": "th", "tur": "tr", "ukr": "uk", "urd": "ur", "uzb": "uz",
        "vie": "vi", "zho": "zh", "chi": "zh"
    ]

    static func normalize(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-", maxSplits: 1)
            .first
            .map(String.init) ?? ""
        return iso639Aliases[normalized] ?? normalized
    }
}
