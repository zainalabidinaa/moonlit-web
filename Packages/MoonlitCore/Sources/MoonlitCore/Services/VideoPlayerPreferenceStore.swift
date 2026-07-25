// Packages/MoonlitCore/Sources/MoonlitCore/Services/VideoPlayerPreferenceStore.swift
import Foundation

public enum VideoPlayerEngineOption: String, Codable, Sendable, CaseIterable {
    case auto      = "auto"
    case avPlayer  = "avplayer"
    case ksPlayer  = "ksplayer"

    public var displayName: String {
        switch self {
        case .auto:     return "Auto-Detect"
        case .avPlayer: return "AVPlayer"
        case .ksPlayer: return "KSPlayer"
        }
    }
}

public enum CacheMode: String, Codable, Sendable, CaseIterable {
    case memory = "memory"
    case disk   = "disk"
    case off    = "off"

    public var displayName: String {
        switch self {
        case .memory: return "Memory"
        case .disk:   return "Disk"
        case .off:    return "Off"
        }
    }
}

/// A selectable audio/subtitle language. `code` is an ISO 639-1 two-letter
/// code; `aliases` are the common ISO 639-2/text variants used to match
/// against stream filenames and mpv track languages (e.g. "en" → "eng").
public struct PlaybackLanguage: Identifiable, Sendable, Hashable {
    public let code: String
    public let name: String
    public let aliases: [String]

    public var id: String { code }

    public init(code: String, name: String, aliases: [String] = []) {
        self.code = code
        self.name = name
        self.aliases = aliases
    }

    /// All match tokens for this language: the code plus its aliases and name.
    public var matchTokens: [String] {
        ([code] + aliases + [name]).map { $0.lowercased() }
    }

    /// Common languages, ordered for a picker. Matches a neutral approach of a
    /// curated list with ISO 639-1 codes and 639-2 fallbacks.
    public static let all: [PlaybackLanguage] = [
        PlaybackLanguage(code: "en", name: "English", aliases: ["eng"]),
        PlaybackLanguage(code: "es", name: "Spanish", aliases: ["spa", "esp"]),
        PlaybackLanguage(code: "fr", name: "French", aliases: ["fre", "fra"]),
        PlaybackLanguage(code: "de", name: "German", aliases: ["ger", "deu"]),
        PlaybackLanguage(code: "it", name: "Italian", aliases: ["ita"]),
        PlaybackLanguage(code: "pt", name: "Portuguese", aliases: ["por"]),
        PlaybackLanguage(code: "ru", name: "Russian", aliases: ["rus"]),
        PlaybackLanguage(code: "ja", name: "Japanese", aliases: ["jpn", "jap"]),
        PlaybackLanguage(code: "ko", name: "Korean", aliases: ["kor"]),
        PlaybackLanguage(code: "zh", name: "Chinese", aliases: ["chi", "zho", "mandarin", "cantonese"]),
        PlaybackLanguage(code: "ar", name: "Arabic", aliases: ["ara"]),
        PlaybackLanguage(code: "hi", name: "Hindi", aliases: ["hin"]),
        PlaybackLanguage(code: "nl", name: "Dutch", aliases: ["dut", "nld"]),
        PlaybackLanguage(code: "sv", name: "Swedish", aliases: ["swe"]),
        PlaybackLanguage(code: "no", name: "Norwegian", aliases: ["nor"]),
        PlaybackLanguage(code: "da", name: "Danish", aliases: ["dan"]),
        PlaybackLanguage(code: "fi", name: "Finnish", aliases: ["fin"]),
        PlaybackLanguage(code: "pl", name: "Polish", aliases: ["pol"]),
        PlaybackLanguage(code: "tr", name: "Turkish", aliases: ["tur"]),
        PlaybackLanguage(code: "cs", name: "Czech", aliases: ["cze", "ces"]),
        PlaybackLanguage(code: "el", name: "Greek", aliases: ["gre", "ell"]),
        PlaybackLanguage(code: "he", name: "Hebrew", aliases: ["heb"]),
        PlaybackLanguage(code: "th", name: "Thai", aliases: ["tha"]),
        PlaybackLanguage(code: "vi", name: "Vietnamese", aliases: ["vie"]),
        PlaybackLanguage(code: "id", name: "Indonesian", aliases: ["ind"]),
        PlaybackLanguage(code: "uk", name: "Ukrainian", aliases: ["ukr"]),
    ]

    public static func named(_ code: String?) -> PlaybackLanguage? {
        guard let code, !code.isEmpty else { return nil }
        return all.first { $0.code == code }
    }
}

@MainActor
public final class VideoPlayerPreferenceStore: ObservableObject {
    public static let shared = VideoPlayerPreferenceStore()

    private let defaults: UserDefaults
    private let prefix = "moonlit.videoPlayer"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Skip Intro
    public var showSkipIntroButton: Bool {
        get { defaults.object(forKey: "\(prefix).showSkipIntroButton") as? Bool ?? true }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "\(prefix).showSkipIntroButton") }
    }

    public var autoSkipIntros: Bool {
        get { defaults.object(forKey: "\(prefix).autoSkipIntros") as? Bool ?? false }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "\(prefix).autoSkipIntros") }
    }

    public var useIntroDB: Bool {
        get { defaults.object(forKey: "\(prefix).useIntroDB") as? Bool ?? true }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "\(prefix).useIntroDB") }
    }

    /// Plan B: when no intro timestamps are available, show a fixed-duration skip button.
    public var fallbackSkipEnabled: Bool {
        get { defaults.object(forKey: "\(prefix).fallbackSkipEnabled") as? Bool ?? true }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "\(prefix).fallbackSkipEnabled") }
    }

    /// Seconds the Plan B skip button jumps forward.
    public var fallbackSkipSeconds: Int {
        get { defaults.object(forKey: "\(prefix).fallbackSkipSeconds") as? Int ?? 85 }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "\(prefix).fallbackSkipSeconds") }
    }

    public var showHighlightsOnTimeline: Bool {
        get { defaults.object(forKey: "\(prefix).showHighlights") as? Bool ?? true }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "\(prefix).showHighlights") }
    }

    // MARK: - Autoplay
    public var autoplayNextEpisode: Bool {
        get { defaults.object(forKey: "\(prefix).autoplayNext") as? Bool ?? false }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "\(prefix).autoplayNext") }
    }

    public var showNextEpisodeSecondsRemaining: Int {
        get { defaults.object(forKey: "\(prefix).nextEpisodeSeconds") as? Int ?? 30 }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "\(prefix).nextEpisodeSeconds") }
    }

    // MARK: - Players
    public var usePerTypePlayers: Bool {
        get { defaults.object(forKey: "\(prefix).usePerTypePlayers") as? Bool ?? false }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "\(prefix).usePerTypePlayers") }
    }

    public var moviePlayer: VideoPlayerEngineOption {
        get { VideoPlayerEngineOption(rawValue: defaults.string(forKey: "\(prefix).moviePlayer") ?? "") ?? .auto }
        set { objectWillChange.send(); defaults.set(newValue.rawValue, forKey: "\(prefix).moviePlayer") }
    }

    public var seriesPlayer: VideoPlayerEngineOption {
        get { VideoPlayerEngineOption(rawValue: defaults.string(forKey: "\(prefix).seriesPlayer") ?? "") ?? .auto }
        set { objectWillChange.send(); defaults.set(newValue.rawValue, forKey: "\(prefix).seriesPlayer") }
    }

    public var livePlayer: VideoPlayerEngineOption {
        get { VideoPlayerEngineOption(rawValue: defaults.string(forKey: "\(prefix).livePlayer") ?? "") ?? .auto }
        set { objectWillChange.send(); defaults.set(newValue.rawValue, forKey: "\(prefix).livePlayer") }
    }

    // MARK: - Cache
    public var cacheMode: CacheMode {
        get { CacheMode(rawValue: defaults.string(forKey: "\(prefix).cacheMode") ?? "") ?? .memory }
        set { objectWillChange.send(); defaults.set(newValue.rawValue, forKey: "\(prefix).cacheMode") }
    }

    // MARK: - Previews
    public var autoplayPreviews: Bool {
        get { defaults.object(forKey: "\(prefix).autoplayPreviews") as? Bool ?? true }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "\(prefix).autoplayPreviews") }
    }

    public var playPreviewSound: Bool {
        get { defaults.object(forKey: "\(prefix).playPreviewSound") as? Bool ?? false }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "\(prefix).playPreviewSound") }
    }

    // MARK: - Upscaling
    public var anime4KEnabled: Bool {
        get { defaults.object(forKey: "\(prefix).anime4KEnabled") as? Bool ?? false }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "\(prefix).anime4KEnabled") }
    }

    // MARK: - Compatibility
    public var showOnlyCompatibleFormats: Bool {
        get { defaults.object(forKey: "\(prefix).showOnlyCompatible") as? Bool ?? false }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "\(prefix).showOnlyCompatible") }
    }

    // MARK: - Preferred Languages
    /// Preferred audio language (ISO 639-1). `nil`/empty = system default.
    /// Streams whose filename advertises this language rank higher, and mpv
    /// auto-selects a matching embedded audio track on load.
    public var preferredAudioLanguage: String? {
        get {
            let value = defaults.string(forKey: "\(prefix).preferredAudioLanguage") ?? ""
            return value.isEmpty ? nil : value
        }
        set {
            objectWillChange.send()
            defaults.set(newValue ?? "", forKey: "\(prefix).preferredAudioLanguage")
        }
    }

    /// Preferred subtitle language (ISO 639-1). `nil`/empty = system default.
    /// mpv auto-selects a matching embedded subtitle track on load, and a
    /// matching already-loaded external subtitle is preselected. No scanning.
    public var preferredSubtitleLanguage: String? {
        get {
            let value = defaults.string(forKey: "\(prefix).preferredSubtitleLanguage") ?? ""
            return value.isEmpty ? nil : value
        }
        set {
            objectWillChange.send()
            defaults.set(newValue ?? "", forKey: "\(prefix).preferredSubtitleLanguage")
        }
    }
}
