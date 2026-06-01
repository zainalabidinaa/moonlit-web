import Foundation
import SwiftUI
import AVKit

@MainActor
public class PlayerEngine: ObservableObject {
    public static let shared = PlayerEngine()

    @Published public var player: AVPlayer?
    @Published public var isPlaying = false
    @Published public var isLoading = true
    @Published public var isEnded = false
    @Published public var currentPosition: Double = 0
    @Published public var duration: Double = 0
    @Published public var bufferedPosition: Double = 0
    @Published public var playbackSpeed: Float = 1.0
    @Published public var currentLaunch: PlayerLaunch?
    @Published public var availableSubtitles: [SubtitleItem] = []
    @Published public var selectedSubtitle: SubtitleItem?
    @Published public var availableAudioTracks: [String] = []
    @Published public var selectedAudioTrack: String?
    @Published public var isMuted = false

    private var timeObserver: Any?
    private var progressTimer: Timer?

    private init() {}

    public func launch(_ launch: PlayerLaunch) {
        cleanup()

        self.currentLaunch = launch
        self.isLoading = true
        self.isPlaying = false
        self.isEnded = false

        let asset: AVURLAsset
        if let headers = launch.sourceHeaders, !headers.isEmpty {
            let options = ["AVURLAssetHTTPHeaderFieldsKey": headers]
            asset = AVURLAsset(url: URL(string: launch.sourceUrl)!, options: options)
        } else {
            asset = AVURLAsset(url: URL(string: launch.sourceUrl)!)
        }

        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)

        if let seekMs = launch.initialPositionMs, seekMs > 0 {
            let seekTime = CMTime(seconds: seekMs / 1000, preferredTimescale: 600)
            playerItem.seek(to: seekTime, completionHandler: nil)
        }

        self.player = player

        if let subs = launch.subtitles, !subs.isEmpty {
            self.availableSubtitles = subs
            self.selectedSubtitle = subs.first
        }

        addTimeObserver()
        startProgressTimer()
        setupNotifications(playerItem: playerItem)
    }

    public func play() {
        player?.play()
        isPlaying = true
        isEnded = false
    }

    public func pause() {
        player?.pause()
        isPlaying = false
    }

    public func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    public func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentPosition = seconds
    }

    public func seekBy(_ seconds: Double) {
        let newPosition = min(max(currentPosition + seconds, 0), duration)
        seek(to: newPosition)
    }

    public func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        player?.rate = speed
    }

    public func skipForward() {
        seekBy(30)
    }

    public func skipBack() {
        seekBy(-15)
    }

    public func skipForward15() {
        seekBy(15)
    }

    public func skipBack15() {
        seekBy(-15)
    }

    public func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }

    public func loadSubtitles(from subtitles: [SubtitleItem]) {
        availableSubtitles = subtitles
        if selectedSubtitle == nil {
            selectedSubtitle = subtitles.first
        }
    }

    public func cycleSubtitle() {
        guard !availableSubtitles.isEmpty else { return }
        if let current = selectedSubtitle,
           let idx = availableSubtitles.firstIndex(where: { $0.id == current.id }) {
            let next = (idx + 1) % availableSubtitles.count
            selectedSubtitle = availableSubtitles[next]
        } else {
            selectedSubtitle = availableSubtitles.first
        }
    }

    public func setSubtitle(_ subtitle: SubtitleItem?) {
        selectedSubtitle = subtitle
    }

    public func stop() {
        cleanup()
    }

    private func cleanup() {
        progressTimer?.invalidate()
        progressTimer = nil
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        timeObserver = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        currentLaunch = nil
        isPlaying = false
        isLoading = true
        isEnded = false
        currentPosition = 0
        duration = 0
    }

    private func addTimeObserver() {
        guard let player = player else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentPosition = time.seconds
            self?.isLoading = false

            if let duration = player.currentItem?.duration.seconds,
               duration > 0, !duration.isNaN, !duration.isInfinite {
                self?.duration = duration
            }

            if let loadedRange = player.currentItem?.loadedTimeRanges.first as? CMTimeRange {
                self?.bufferedPosition = loadedRange.end.seconds
            }
        }
    }

    private func startProgressTimer() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.saveProgress()
            }
        }
    }

    private func setupNotifications(playerItem: AVPlayerItem) {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.isEnded = true
                self.isPlaying = false
            }
            Task {
                await self.saveProgress(completed: true)
            }
        }
    }

    private func saveProgress(completed: Bool = false) async {
        guard let launch = currentLaunch,
              let profile = ProfileManager.shared.currentProfile else { return }

        await WatchProgressRepository.shared.updateProgress(
            profileId: profile.id,
            mediaId: launch.videoId,
            mediaType: launch.contentType.rawValue,
            positionSeconds: currentPosition,
            durationSeconds: duration,
            completed: completed
        )
    }

    public func addExternalSubtitle(_ subtitle: SubtitleItem) {
        selectedSubtitle = subtitle
    }
}
