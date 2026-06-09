// Packages/LunaCore/Sources/LunaCore/Services/VideoPlayerPreferenceStore.swift
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

@MainActor
public final class VideoPlayerPreferenceStore: ObservableObject {
    public static let shared = VideoPlayerPreferenceStore()

    private let defaults: UserDefaults
    private let prefix = "luna.videoPlayer"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Skip Intro
    public var showSkipIntroButton: Bool {
        get { defaults.object(forKey: "\(prefix).showSkipIntroButton") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "\(prefix).showSkipIntroButton") }
    }

    public var autoSkipIntros: Bool {
        get { defaults.object(forKey: "\(prefix).autoSkipIntros") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "\(prefix).autoSkipIntros") }
    }

    public var useIntroDB: Bool {
        get { defaults.object(forKey: "\(prefix).useIntroDB") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "\(prefix).useIntroDB") }
    }

    public var showHighlightsOnTimeline: Bool {
        get { defaults.object(forKey: "\(prefix).showHighlights") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "\(prefix).showHighlights") }
    }

    // MARK: - Autoplay
    public var autoplayNextEpisode: Bool {
        get { defaults.object(forKey: "\(prefix).autoplayNext") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "\(prefix).autoplayNext") }
    }

    public var showNextEpisodeSecondsRemaining: Int {
        get { defaults.object(forKey: "\(prefix).nextEpisodeSeconds") as? Int ?? 30 }
        set { defaults.set(newValue, forKey: "\(prefix).nextEpisodeSeconds") }
    }

    // MARK: - Players
    public var usePerTypePlayers: Bool {
        get { defaults.object(forKey: "\(prefix).usePerTypePlayers") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "\(prefix).usePerTypePlayers") }
    }

    public var moviePlayer: VideoPlayerEngineOption {
        get { VideoPlayerEngineOption(rawValue: defaults.string(forKey: "\(prefix).moviePlayer") ?? "") ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: "\(prefix).moviePlayer") }
    }

    public var seriesPlayer: VideoPlayerEngineOption {
        get { VideoPlayerEngineOption(rawValue: defaults.string(forKey: "\(prefix).seriesPlayer") ?? "") ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: "\(prefix).seriesPlayer") }
    }

    public var livePlayer: VideoPlayerEngineOption {
        get { VideoPlayerEngineOption(rawValue: defaults.string(forKey: "\(prefix).livePlayer") ?? "") ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: "\(prefix).livePlayer") }
    }

    // MARK: - Cache
    public var cacheMode: CacheMode {
        get { CacheMode(rawValue: defaults.string(forKey: "\(prefix).cacheMode") ?? "") ?? .memory }
        set { defaults.set(newValue.rawValue, forKey: "\(prefix).cacheMode") }
    }

    // MARK: - Previews
    public var autoplayPreviews: Bool {
        get { defaults.object(forKey: "\(prefix).autoplayPreviews") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "\(prefix).autoplayPreviews") }
    }

    public var playPreviewSound: Bool {
        get { defaults.object(forKey: "\(prefix).playPreviewSound") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "\(prefix).playPreviewSound") }
    }

    // MARK: - Compatibility
    public var showOnlyCompatibleFormats: Bool {
        get { defaults.object(forKey: "\(prefix).showOnlyCompatible") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "\(prefix).showOnlyCompatible") }
    }
}
