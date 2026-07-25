import Foundation
import MoonlitCore

/// Finds the previous/next episode relative to a launch's current
/// season/episode, and resolves a fresh `PlayerLaunch` for one of them —
/// mirrors the reference `useEpisodeNavigation`, which reloads a new source rather
/// than seeking within the current one.
enum EpisodeNavigator {
    static func adjacentEpisodes(for launch: PlayerLaunch, addons: [AddonManifest]) async -> (prev: MetaVideo?, next: MetaVideo?) {
        guard launch.contentType == .series,
              let metaId = launch.parentMetaId,
              let season = launch.seasonNumber,
              let episode = launch.episodeNumber else {
            return (nil, nil)
        }

        guard let detail = await MetaRepository.shared.fetchDetail(
            type: launch.parentMetaType ?? launch.contentType.rawValue,
            id: metaId,
            addons: addons
        ), let seasons = detail.seasons else {
            return (nil, nil)
        }

        let sorted = seasons.sorted { $0.number < $1.number }
        guard let seasonIndex = sorted.firstIndex(where: { $0.number == season }) else {
            return (nil, nil)
        }
        let episodes = (sorted[seasonIndex].episodes ?? []).sorted { ($0.episode ?? 0) < ($1.episode ?? 0) }
        guard let episodeIndex = episodes.firstIndex(where: { $0.episode == episode }) else {
            return (nil, nil)
        }

        var prev: MetaVideo?
        if episodeIndex > 0 {
            prev = episodes[episodeIndex - 1]
        } else if seasonIndex > 0 {
            let prevSeasonEpisodes = (sorted[seasonIndex - 1].episodes ?? []).sorted { ($0.episode ?? 0) < ($1.episode ?? 0) }
            prev = prevSeasonEpisodes.last
        }

        var next: MetaVideo?
        if episodeIndex + 1 < episodes.count {
            next = episodes[episodeIndex + 1]
        } else if seasonIndex + 1 < sorted.count {
            let nextSeasonEpisodes = (sorted[seasonIndex + 1].episodes ?? []).sorted { ($0.episode ?? 0) < ($1.episode ?? 0) }
            next = nextSeasonEpisodes.first
        }

        return (prev, next)
    }

    /// Resolves a playable stream for `episode` and builds a new launch to hand to `engine.launch(...)`.
    static func buildLaunch(for episode: MetaVideo, base: PlayerLaunch, addons: [AddonManifest]) async -> PlayerLaunch? {
        let type = base.parentMetaType ?? base.contentType.rawValue
        await StreamRepository.shared.fetchStreams(type: type, id: episode.id, addons: addons, title: episode.title)
        let prefer4K = await MainActor.run {
            ProfileManager.shared.currentProfile.map {
                PlaybackQualityPreferenceStore.shared.prefers4K(profileId: $0.id)
            } ?? false
        }
        let preferredAudioLanguage = await MainActor.run {
            VideoPlayerPreferenceStore.shared.preferredAudioLanguage
        }
        let streams = await StreamRepository.shared.streams
        guard let stream = StreamSourceSelector.candidatesForAutoPlay(from: streams, prefer4K: prefer4K, preferredAudioLanguage: preferredAudioLanguage).first else {
            return nil
        }
        return PlayerLaunch(
            title: base.title,
            sourceUrl: stream.url ?? "",
            sourceHeaders: stream.behaviorHints?.proxyHeaders?.request,
            sourceContentType: nil,
            logo: base.logo,
            poster: base.poster,
            episodeThumbnail: episode.thumbnail,
            background: base.background,
            seasonNumber: episode.season,
            episodeNumber: episode.episode,
            streamTitle: stream.title,
            providerName: stream.name,
            contentType: base.contentType,
            videoId: episode.id,
            parentMetaId: base.parentMetaId,
            parentMetaType: base.parentMetaType,
            subtitles: stream.subtitles
        )
    }
}
