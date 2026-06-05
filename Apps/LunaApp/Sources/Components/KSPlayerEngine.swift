import SwiftUI
import LunaCore

#if canImport(KSPlayer)
import KSPlayer

@MainActor
public class KSPlayerEngine: ObservableObject {
    private var playerView: IOSVideoPlayerView?
    private var progressTimer: Timer?
    private var currentLaunch: PlayerLaunch?
    private var lastPlaybackSpeed: Float = 1.0

    @Published public var isPlaying = false
    @Published public var isLoading = true
    @Published public var isEnded = false
    @Published public var currentPosition: Double = 0
    @Published public var duration: Double = 0
    @Published public var bufferedPosition: Double = 0
    @Published public var playbackSpeed: Float = 1.0
    @Published public var availableSubtitles: [SubtitleItem] = []
    @Published public var selectedSubtitle: SubtitleItem?
    @Published public var availableAudioTracks: [String] = []
    @Published public var selectedAudioTrack: String?
    @Published public var isMuted = false

    public init() {
        KSOptions.secondPlayerType = KSMEPlayer.self
    }

    public var displayView: UIView? { playerView }

    public func launch(_ launch: PlayerLaunch) {
        cleanup()
        guard let sourceURL = URL(string: launch.sourceUrl) else { isLoading = false; return }
        currentLaunch = launch
        isLoading = true; isPlaying = false; isEnded = false
        let options = KSOptions()
        options.isAutoPlay = false
        if let headers = launch.sourceHeaders {
            for (key, value) in headers { options.appendHeader([key: value]) }
        }
        let view = IOSVideoPlayerView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.set(url: sourceURL, options: options)
        view.playTimeDidChange = { [weak self] current, total in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentPosition = current
                if total > 0, !total.isNaN, !total.isInfinite { self.duration = total }
                self.isLoading = false
            }
        }
        if let seekMs = launch.initialPositionMs, seekMs > 0 {
            view.playerLayer?.seek(time: seekMs / 1000, completion: nil)
        }
        playerView = view
        startProgressTimer()
    }

    public func play() { playerView?.playerLayer?.play(); playerView?.playerLayer?.player?.playbackRate = lastPlaybackSpeed; isPlaying = true; isEnded = false }
    public func pause() { playerView?.playerLayer?.pause(); isPlaying = false }
    public func togglePlayPause() { if isPlaying { pause() } else { play() } }
    public func seek(to seconds: Double) { playerView?.playerLayer?.seek(time: seconds) { [weak self] _ in Task { @MainActor [weak self] in self?.currentPosition = seconds } } }
    public func seekBy(_ seconds: Double) { seek(to: min(max(currentPosition + seconds, 0), duration)) }
    public func setPlaybackSpeed(_ speed: Float) { playbackSpeed = speed; lastPlaybackSpeed = speed; playerView?.playerLayer?.player?.playbackRate = speed }
    public func skipForward() { seekBy(30) }
    public func skipBack() { seekBy(-15) }
    public func skipForward15() { seekBy(15) }
    public func skipBack15() { seekBy(-15) }
    public func toggleMute() { isMuted.toggle(); playerView?.playerLayer?.player?.isMuted = isMuted }
    public func loadSubtitles(from subtitles: [SubtitleItem]) { availableSubtitles = subtitles; if selectedSubtitle == nil { selectedSubtitle = subtitles.first } }
    public func cycleSubtitle() {
        guard !availableSubtitles.isEmpty else { return }
        if let current = selectedSubtitle, let idx = availableSubtitles.firstIndex(where: { $0.id == current.id }) { selectedSubtitle = availableSubtitles[(idx + 1) % availableSubtitles.count] }
        else { selectedSubtitle = availableSubtitles.first }
    }
    public func setSubtitle(_ subtitle: SubtitleItem?) { selectedSubtitle = subtitle }
    public func stop() { cleanup() }

    private func cleanup() {
        progressTimer?.invalidate(); progressTimer = nil
        playerView?.playerLayer?.pause(); playerView?.removeFromSuperview()
        playerView = nil; currentLaunch = nil
        isPlaying = false; isLoading = true; isEnded = false
        currentPosition = 0; duration = 0; lastPlaybackSpeed = 1.0
    }

    private func startProgressTimer() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let launch = self.currentLaunch, let profile = ProfileManager.shared.currentProfile else { return }
                await WatchProgressRepository.shared.updateProgress(
                    profileId: profile.id, mediaId: launch.videoId, mediaType: launch.contentType.rawValue,
                    positionSeconds: self.currentPosition, durationSeconds: self.duration, completed: false,
                    name: launch.title, poster: launch.poster, parentMetaId: launch.parentMetaId,
                    season: launch.seasonNumber, episode: launch.episodeNumber)
            }
        }
    }
}
#else
// Stub: KSPlayer not available via SPM. Install via CocoaPods:
// pod 'KSPlayer', :git => 'https://github.com/kingslay/KSPlayer.git', :branch => 'main'
// pod 'FFmpegKit', :git => 'https://github.com/kingslay/FFmpegKit.git', :branch => 'main'
// pod 'Libass', :git => 'https://github.com/kingslay/FFmpegKit.git', :branch => 'main'
@MainActor
public class KSPlayerEngine: ObservableObject {
    @Published public var isPlaying = false
    @Published public var isLoading = true
    @Published public var isEnded = false
    @Published public var currentPosition: Double = 0
    @Published public var duration: Double = 0
    @Published public var bufferedPosition: Double = 0
    @Published public var playbackSpeed: Float = 1.0
    @Published public var availableSubtitles: [SubtitleItem] = []
    @Published public var selectedSubtitle: SubtitleItem?
    @Published public var availableAudioTracks: [String] = []
    @Published public var selectedAudioTrack: String?
    @Published public var isMuted = false

    public init() {}
    public var displayView: UIView? { nil }
    public func launch(_ launch: PlayerLaunch) {}
    public func play() {}
    public func pause() {}
    public func togglePlayPause() {}
    public func seek(to seconds: Double) {}
    public func seekBy(_ seconds: Double) {}
    public func setPlaybackSpeed(_ speed: Float) {}
    public func skipForward() {}
    public func skipBack() {}
    public func skipForward15() {}
    public func skipBack15() {}
    public func toggleMute() {}
    public func loadSubtitles(from subtitles: [SubtitleItem]) {}
    public func cycleSubtitle() {}
    public func setSubtitle(_ subtitle: SubtitleItem?) {}
    public func stop() {}
}
#endif
