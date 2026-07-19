import Foundation

public actor SyncService {
    public static let shared = SyncService()
    private let client = SupabaseClient.shared

    public func pushProfiles(profiles: [MoonlitProfile]) async throws {
        for profile in profiles {
            try await client.upsert(
                into: "profiles",
                onConflict: "id",
                value: profile
            )
        }
    }

    public func pullProfiles(userId: String) async throws -> [MoonlitProfile] {
        let profiles: [MoonlitProfile] = try await client.select(
            from: "profiles",
            where: ["user_id": userId],
            order: "profile_index.asc"
        )
        return profiles
    }

    public func pushAddons(profileId: String, addonUrls: [String]) async throws {
        struct AddonRow: Codable {
            let profile_id: String
            let addon_url: String
            let enabled: Bool
            let sort_order: Int
        }

        try await client.delete(from: "installed_addons", where: ["profile_id": profileId])

        for (index, url) in addonUrls.enumerated() {
            let row = AddonRow(
                profile_id: profileId,
                addon_url: url,
                enabled: true,
                sort_order: index
            )
            _ = try await client.insert(into: "installed_addons", value: row) as [AddonRow]
        }
    }

    public func pullAddons(profileId: String) async throws -> [String] {
        struct AddonRow: Codable {
            let addon_url: String
            let enabled: Bool
        }
        let rows: [AddonRow] = try await client.select(
            from: "installed_addons",
            where: ["profile_id": profileId],
            order: "sort_order.asc"
        )
        return rows.filter { $0.enabled }.map { $0.addon_url }
    }

    public func pushWatchProgress(entry: WatchProgressEntry) async throws {
        struct ProgressRow: Codable {
            let id: String
            let profile_id: String
            let media_id: String
            let media_type: String
            let position_seconds: Double
            let duration_seconds: Double
            let completed: Bool
            let updated_at: String
            let name: String?
            let poster: String?
            let parent_meta_id: String?
            let season: Int?
            let episode: Int?
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"

        let row = ProgressRow(
            id: entry.id,
            profile_id: entry.profileId,
            media_id: entry.mediaId,
            media_type: entry.mediaType,
            position_seconds: entry.positionSeconds,
            duration_seconds: entry.durationSeconds,
            completed: entry.completed,
            updated_at: dateFormatter.string(from: entry.updatedAt),
            name: entry.name,
            poster: entry.poster,
            parent_meta_id: entry.parentMetaId,
            season: entry.season,
            episode: entry.episode
        )
        do {
            try await client.upsert(into: "watch_progress", onConflict: "profile_id,media_id", value: row)
        } catch {
            struct LegacyProgressRow: Codable {
                let id: String
                let profile_id: String
                let media_id: String
                let media_type: String
                let position_seconds: Double
                let duration_seconds: Double
                let completed: Bool
                let updated_at: String
                let parent_meta_id: String?
                let season: Int?
                let episode: Int?
            }

            let legacyRow = LegacyProgressRow(
                id: row.id,
                profile_id: row.profile_id,
                media_id: row.media_id,
                media_type: row.media_type,
                position_seconds: row.position_seconds,
                duration_seconds: row.duration_seconds,
                completed: row.completed,
                updated_at: row.updated_at,
                parent_meta_id: row.parent_meta_id,
                season: row.season,
                episode: row.episode
            )
            try await client.upsert(into: "watch_progress", onConflict: "profile_id,media_id", value: legacyRow)
        }
    }

    public func pullWatchProgress(profileId: String) async throws -> [WatchProgressEntry] {
        struct ProgressRow: Codable {
            let id: String
            let profile_id: String
            let media_id: String
            let media_type: String
            let position_seconds: Double
            let duration_seconds: Double
            let completed: Bool
            let updated_at: String
            let name: String?
            let poster: String?
            let parent_meta_id: String?
            let season: Int?
            let episode: Int?
        }
        let rows: [ProgressRow] = try await client.select(
            from: "watch_progress",
            where: ["profile_id": profileId]
        )
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"

        return rows.map { row in
            WatchProgressEntry(
                id: row.id,
                profileId: row.profile_id,
                mediaId: row.media_id,
                mediaType: row.media_type,
                positionSeconds: row.position_seconds,
                durationSeconds: row.duration_seconds,
                completed: row.completed,
                updatedAt: dateFormatter.date(from: row.updated_at) ?? Date(),
                name: row.name,
                poster: row.poster,
                parentMetaId: row.parent_meta_id,
                season: row.season,
                episode: row.episode
            )
        }
    }

    public func deleteWatchProgress(id: String) async throws {
        try await client.delete(from: "watch_progress", where: ["id": id])
    }

    public func pushWatchedItem(item: WatchedItem) async throws {
        struct WatchedRow: Codable {
            let id: String
            let profile_id: String
            let media_id: String
            let media_type: String
            let name: String?
            let season: Int?
            let episode: Int?
            let marked_at: String
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"

        let row = WatchedRow(
            id: item.id,
            profile_id: item.profileId,
            media_id: item.mediaId,
            media_type: item.mediaType,
            name: item.name,
            season: item.season,
            episode: item.episode,
            marked_at: dateFormatter.string(from: item.markedAt)
        )
        _ = try await client.insert(into: "watched_items", value: row) as [WatchedRow]
    }

    public func pullWatchedItems(profileId: String) async throws -> [WatchedItem] {
        struct WatchedRow: Codable {
            let id: String
            let profile_id: String
            let media_id: String
            let media_type: String
            let name: String?
            let season: Int?
            let episode: Int?
            let marked_at: String
        }
        let rows: [WatchedRow] = try await client.select(
            from: "watched_items",
            where: ["profile_id": profileId],
            order: "marked_at.desc"
        )
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"

        return rows.map { row in
            WatchedItem(
                id: row.id,
                profileId: row.profile_id,
                mediaId: row.media_id,
                mediaType: row.media_type,
                name: row.name,
                season: row.season,
                episode: row.episode,
                markedAt: dateFormatter.date(from: row.marked_at) ?? Date()
            )
        }
    }

    public func pushLibraryItem(item: LibraryItem) async throws {
        struct LibraryRow: Codable {
            let id: String
            let profile_id: String
            let media_id: String
            let media_type: String
            let name: String?
            let poster: String?
            let saved_at: String
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"

        let row = LibraryRow(
            id: item.id,
            profile_id: item.profileId,
            media_id: item.mediaId,
            media_type: item.mediaType,
            name: item.name,
            poster: item.poster,
            saved_at: dateFormatter.string(from: item.savedAt)
        )
        try await client.upsert(into: "library_items", onConflict: "profile_id,media_id", value: row)
    }

    public func pullLibraryItems(profileId: String) async throws -> [LibraryItem] {
        struct LibraryRow: Codable {
            let id: String
            let profile_id: String
            let media_id: String
            let media_type: String
            let name: String?
            let poster: String?
            let saved_at: String
        }
        let rows: [LibraryRow] = try await client.select(
            from: "library_items",
            where: ["profile_id": profileId],
            order: "saved_at.desc"
        )
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"

        return rows.map { row in
            LibraryItem(
                id: row.id,
                profileId: row.profile_id,
                mediaId: row.media_id,
                mediaType: row.media_type,
                name: row.name,
                poster: row.poster,
                savedAt: dateFormatter.date(from: row.saved_at) ?? Date()
            )
        }
    }

    public func deleteLibraryItem(profileId: String, mediaId: String) async throws {
        try await client.delete(
            from: "library_items",
            where: ["profile_id": profileId, "media_id": mediaId]
        )
    }

    // MARK: - Liked items

    public func pushLikedItem(item: LikedItem) async throws {
        struct LikedRow: Codable {
            let id: String
            let profile_id: String
            let media_id: String
            let media_type: String
            let name: String?
            let poster: String?
            let tmdb_id: Int?
            let liked_at: String
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"

        let row = LikedRow(
            id: item.id,
            profile_id: item.profileId,
            media_id: item.mediaId,
            media_type: item.mediaType,
            name: item.name,
            poster: item.poster,
            tmdb_id: item.tmdbId,
            liked_at: dateFormatter.string(from: item.likedAt)
        )
        try await client.upsert(into: "liked_items", onConflict: "profile_id,media_id", value: row)
    }

    public func pullLikedItems(profileId: String) async throws -> [LikedItem] {
        struct LikedRow: Codable {
            let id: String
            let profile_id: String
            let media_id: String
            let media_type: String
            let name: String?
            let poster: String?
            let tmdb_id: Int?
            let liked_at: String
        }
        let rows: [LikedRow] = try await client.select(
            from: "liked_items",
            where: ["profile_id": profileId],
            order: "liked_at.desc"
        )
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"

        return rows.map { row in
            LikedItem(
                mediaId: row.media_id,
                mediaType: row.media_type,
                name: row.name ?? "",
                poster: row.poster,
                tmdbId: row.tmdb_id,
                profileId: row.profile_id,
                id: row.id,
                likedAt: dateFormatter.date(from: row.liked_at) ?? Date()
            )
        }
    }

    public func deleteLikedItem(profileId: String, mediaId: String) async throws {
        try await client.delete(
            from: "liked_items",
            where: ["profile_id": profileId, "media_id": mediaId]
        )
    }

    public struct SystemAddonInfo: Sendable {
        public let name: String?
        public let url: String
    }

    public func pullSystemAddonInfo() async throws -> SystemAddonInfo? {
        struct SystemAddonRow: Codable {
            let manifest_url: String
            let name: String?
        }
        let rows: [SystemAddonRow] = try await client.select(
            from: "system_addon",
            order: "updated_at.desc"
        )
        guard let row = rows.first else { return nil }
        return SystemAddonInfo(name: row.name, url: row.manifest_url)
    }

    public func pullSystemAddon() async throws -> String? {
        try await pullSystemAddonInfo()?.url
    }

    /// Addon URLs curated by the admin (their own installed addons), shared to all
    /// authenticated users via the get_shared_addons() SECURITY DEFINER function.
    /// Callers MUST stream-guard these (metadata/catalog/subtitle only) — see
    /// AddonRepository. The backend must never deliver a stream source to users.
    public func pullSharedAddons() async throws -> [String] {
        struct SharedAddonRow: Codable {
            let addon_url: String
        }
        let rows: [SharedAddonRow] = try await client.rpc(function: "get_shared_addons")
        return rows.map { $0.addon_url }
    }
}
