import Foundation

@MainActor
public class WatchProgressRepository: ObservableObject {
    public static let shared = WatchProgressRepository()

    @Published public var progressEntries: [WatchProgressEntry] = []
    @Published public var watchedItems: [WatchedItem] = []

    private let syncService = SyncService.shared

    private init() {}

    public func loadAll(profileId: String) async {
        do {
            progressEntries = try await syncService.pullWatchProgress(profileId: profileId)
            watchedItems = try await syncService.pullWatchedItems(profileId: profileId)
        } catch {
            progressEntries = []
            watchedItems = []
        }
    }

    public func updateProgress(
        profileId: String,
        mediaId: String,
        mediaType: String,
        positionSeconds: Double,
        durationSeconds: Double,
        completed: Bool = false,
        name: String? = nil,
        poster: String? = nil,
        parentMetaId: String? = nil,
        season: Int? = nil,
        episode: Int? = nil
    ) async {
        let existing = progressEntries.first(where: { $0.mediaId == mediaId })
        let existingId = existing?.id ?? UUID().uuidString

        let entry = WatchProgressEntry(
            id: existingId,
            profileId: profileId,
            mediaId: mediaId,
            mediaType: mediaType,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds,
            completed: completed,
            updatedAt: Date(),
            name: name ?? existing?.name,
            poster: poster ?? existing?.poster,
            parentMetaId: parentMetaId ?? existing?.parentMetaId,
            season: season ?? existing?.season,
            episode: episode ?? existing?.episode
        )

        if let idx = progressEntries.firstIndex(where: { $0.mediaId == mediaId }) {
            progressEntries[idx] = entry
        } else {
            progressEntries.append(entry)
        }

        do {
            try await syncService.pushWatchProgress(entry: entry)
        } catch {
            NSLog("[Moonlit][Sync] pushWatchProgress FAILED for %@: %@",
                  mediaId, String(describing: error))
        }
    }

    public func getProgress(mediaId: String) -> WatchProgressEntry? {
        progressEntries
            .filter { $0.matchesMedia(id: mediaId) && !$0.completed }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    public func getEpisodeProgress(parentMediaId: String, season: Int?, episode: Int?) -> WatchProgressEntry? {
        progressEntries
            .filter {
                $0.matchesMedia(id: parentMediaId)
                && $0.inferredSeason == season
                && $0.inferredEpisode == episode
                && !$0.completed
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    public func markWatched(
        profileId: String,
        mediaId: String,
        mediaType: String,
        name: String? = nil,
        poster: String? = nil,
        season: Int? = nil,
        episode: Int? = nil
    ) async {
        watchedItems.removeAll { existing in
            existing.mediaId == mediaId
            && existing.season == season
            && existing.episode == episode
        }
        let item = WatchedItem(
            id: UUID().uuidString,
            profileId: profileId,
            mediaId: mediaId,
            mediaType: mediaType,
            name: name,
            poster: poster,
            season: season,
            episode: episode,
            markedAt: Date()
        )
        watchedItems.append(item)
        do {
            try await syncService.pushWatchedItem(item: item)
        } catch {
            NSLog("[Moonlit][Sync] pushWatchedItem FAILED for %@ S%d E%d: %@",
                  mediaId, season ?? -1, episode ?? -1, String(describing: error))
        }
    }

    /// Marks every episode of a season as watched in one batch — used by the
    /// season menu's "Mark Season N as Watched" action. Skips episodes already
    /// marked, appends all new entries in a single `@Published` mutation so the
    /// UI updates instantly, then pushes each to sync sequentially.
    public func markSeasonWatched(
        profileId: String,
        seriesId: String,
        mediaType: String,
        season: Int,
        episodes: [(mediaId: String, episode: Int?)],
        name: String? = nil,
        poster: String? = nil
    ) async {
        let newItems: [WatchedItem] = episodes
            .filter { !isEpisodeWatched(parentMediaId: seriesId, season: season, episode: $0.episode) }
            .map { ep in
                WatchedItem(
                    id: UUID().uuidString,
                    profileId: profileId,
                    mediaId: ep.mediaId,
                    mediaType: mediaType,
                    name: name,
                    poster: poster,
                    season: season,
                    episode: ep.episode,
                    markedAt: Date()
                )
            }
        guard !newItems.isEmpty else { return }
        watchedItems.append(contentsOf: newItems)
        for item in newItems {
            do {
                try await syncService.pushWatchedItem(item: item)
            } catch {
                NSLog("[Moonlit][Sync] pushWatchedItem (season batch) FAILED for %@ S%d E%d: %@",
                      item.mediaId, item.season ?? -1, item.episode ?? -1, String(describing: error))
            }
        }
    }

    public func markUnwatched(mediaId: String) async {
        let decodedId = mediaId.removingPercentEncoding ?? mediaId
        guard let item = watchedItems.first(where: {
            let decodedWatchedId = $0.mediaId.removingPercentEncoding ?? $0.mediaId
            return decodedWatchedId == decodedId
        }) else { return }
        try? await SupabaseClient.shared.delete(
            from: "watched_items",
            where: ["id": item.id]
        )
        watchedItems.removeAll {
            let decodedWatchedId = $0.mediaId.removingPercentEncoding ?? $0.mediaId
            return decodedWatchedId == decodedId
        }
    }

    public func isWatched(mediaId: String) -> Bool {
        watchedItems.contains(where: {
            let decodedId = mediaId.removingPercentEncoding ?? mediaId
            let decodedWatchedId = $0.mediaId.removingPercentEncoding ?? $0.mediaId
            return decodedWatchedId == decodedId
        })
    }

    public func isEpisodeWatched(parentMediaId: String, season: Int?, episode: Int?) -> Bool {
        watchedItems.contains {
            let decodedWatchedId = $0.mediaId.removingPercentEncoding ?? $0.mediaId
            let parent = decodedWatchedId.split(separator: ":").first.map(String.init) ?? decodedWatchedId
            let idParts = decodedWatchedId.split(separator: ":")
            let inferredSeason = $0.season ?? idParts.dropFirst().first.flatMap { Int($0) }
            let inferredEpisode = $0.episode ?? idParts.dropFirst(2).first.flatMap { Int($0) }
            return parent == parentMediaId && inferredSeason == season && inferredEpisode == episode
        }
    }

    public var watchedMediaIds: Set<String> {
        Set(watchedItems.map { $0.mediaId })
    }
}
