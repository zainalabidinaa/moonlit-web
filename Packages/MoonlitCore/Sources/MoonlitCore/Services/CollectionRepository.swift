import Foundation

private struct CollectionSnapshot: Codable, Sendable {
    var collections: [DBCollection]
    var folders: [DBFolder]
    var folderCatalogs: [DBFolderCatalog]
    var folderSources: [DBFolderSource]
}

@MainActor
public class CollectionRepository: ObservableObject {
    public static let shared = CollectionRepository()

    @Published public var collections: [DBCollection] = []
    @Published public var folders: [DBFolder] = []
    @Published public var folderCatalogs: [DBFolderCatalog] = []
    @Published public var folderSources: [DBFolderSource] = []
    @Published public var isLoading = false

    private let client = SupabaseClient.shared

    private static let cacheURL: URL = {
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MoonlitCollections", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("snapshot.json")
    }()

    private init() {}

    public func loadOrganizer(
        bundledData: Data,
        remoteURL: URL? = nil,
        store: CollectionOrganizerStore = .shared
    ) async {
        isLoading = true
        defer { isLoading = false }

        var bundled: OrganizedCollections?
        do {
            let layout = try store.cachedOrBundledLayout(bundledData: bundledData)
            bundled = layout
            apply(layout)
        } catch {
            collections = []
            folders = []
            folderCatalogs = []
            folderSources = []
        }

        if let refreshed = await store.refresh(remoteURL: remoteURL) {
            // Merge remote on top of the complete bundled layout so a partial remote
            // can't drop bundle-only collections. Falls back to remote if no bundle.
            apply(bundled.map { Self.mergeByName(base: $0, overlay: refreshed) } ?? refreshed)
        }
    }

    public func apply(_ organized: OrganizedCollections) {
        collections = organized.collections
        folders = organized.folders
        folderCatalogs = organized.folderCatalogs
        folderSources = organized.folderSources
    }

    /// Merges a remote layout (`overlay`, e.g. the Supabase edge function) on top of a
    /// complete local layout (`base`, the bundled JSON). Collections are joined by
    /// **name** because bundled IDs (`collection-…`) and Supabase IDs (UUIDs) never match.
    ///
    /// - On a name match, the overlay collection (and its folders/catalogs/sources) WINS,
    ///   so portal edits take effect.
    /// - Base-only collections are preserved, so a partially-populated remote layout can't
    ///   silently drop collections that only exist in the bundle (e.g. Trending Shows,
    ///   Asian Dramas).
    /// - Overlay-only collections are appended after the base order.
    nonisolated public static func mergeByName(
        base: OrganizedCollections,
        overlay: OrganizedCollections
    ) -> OrganizedCollections {
        OrganizedCollections.merged(base: base, overlay: overlay)
    }

    public func load() {
        Task { await refreshForCatalogRows() }
    }

    @discardableResult
    public func refreshForCatalogRows() async -> Bool {
        isLoading = true
        defer { isLoading = false }

        _ = await applyDiskCacheIfNeeded()
        return await refreshFromSupabase()
    }

    @discardableResult
    public func forceRefresh() async -> Bool {
        isLoading = true
        defer { isLoading = false }

        return await refreshFromSupabase()
    }

    private func applyDiskCacheIfNeeded() async -> Bool {
        guard collections.isEmpty, folders.isEmpty, folderCatalogs.isEmpty, folderSources.isEmpty else {
            return false
        }

        guard let snapshot = await Self.readCachedSnapshot(from: Self.cacheURL) else { return false }
        apply(snapshot)
        return true
    }

    private func refreshFromSupabase() async -> Bool {
        isLoading = true
        defer { isLoading = false }

        do {
            async let c: [DBCollection] = client.select(from: "collections", order: "sort_order.asc")
            async let f: [DBFolder] = client.select(from: "folders", order: "sort_order.asc")
            async let fc: [DBFolderCatalog] = client.select(from: "folder_catalogs")
            async let fs: [DBFolderSource] = client.select(from: "folder_sources", order: "sort_order.asc")
            let (newCollections, newFolders, newCatalogs, newSources) = try await (c, f, fc, fs)
            let refreshed = CollectionSnapshot(
                collections: newCollections,
                folders: newFolders,
                folderCatalogs: newCatalogs,
                folderSources: newSources
            )
            let currentCollections = collections
            let currentFolders = folders
            let currentFolderCatalogs = folderCatalogs
            let currentFolderSources = folderSources
            // If Supabase returns empty collections but we currently have data,
            // treat it as a transient failure (e.g. RLS auth issue returning [] instead
            // of an error). Don't wipe a working collection cache with an empty result.
            if refreshed.collections.isEmpty && !currentCollections.isEmpty {
                return false
            }

            let changed = await Task.detached(priority: .utility) {
                Self.hasCollectionSnapshotChanged(
                    currentCollections: currentCollections,
                    currentFolders: currentFolders,
                    currentFolderCatalogs: currentFolderCatalogs,
                    currentFolderSources: currentFolderSources,
                    refreshedCollections: refreshed.collections,
                    refreshedFolders: refreshed.folders,
                    refreshedFolderCatalogs: refreshed.folderCatalogs,
                    refreshedFolderSources: refreshed.folderSources
                )
            }.value
            guard changed else { return false }

            apply(refreshed)
            Self.writeCachedSnapshot(refreshed, to: Self.cacheURL)
            return true
        } catch {
            // keep existing data on error
            return false
        }
    }

    private func apply(_ snapshot: CollectionSnapshot) {
        collections = snapshot.collections
        folders = snapshot.folders
        folderCatalogs = snapshot.folderCatalogs
        folderSources = snapshot.folderSources
    }

    public nonisolated static func hasCollectionSnapshotChanged(
        currentCollections: [DBCollection],
        currentFolders: [DBFolder],
        currentFolderCatalogs: [DBFolderCatalog],
        currentFolderSources: [DBFolderSource],
        refreshedCollections: [DBCollection],
        refreshedFolders: [DBFolder],
        refreshedFolderCatalogs: [DBFolderCatalog],
        refreshedFolderSources: [DBFolderSource]
    ) -> Bool {
        let current = CollectionSnapshot(
            collections: currentCollections,
            folders: currentFolders,
            folderCatalogs: currentFolderCatalogs,
            folderSources: currentFolderSources
        )
        let refreshed = CollectionSnapshot(
            collections: refreshedCollections,
            folders: refreshedFolders,
            folderCatalogs: refreshedFolderCatalogs,
            folderSources: refreshedFolderSources
        )
        return snapshotFingerprint(current) != snapshotFingerprint(refreshed)
    }

    private nonisolated static func readCachedSnapshot(from url: URL) async -> CollectionSnapshot? {
        await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(CollectionSnapshot.self, from: data)
        }.value
    }

    private nonisolated static func writeCachedSnapshot(_ snapshot: CollectionSnapshot, to url: URL) {
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private nonisolated static func snapshotFingerprint(_ snapshot: CollectionSnapshot) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(snapshot)
    }

    public func folders(for collection: DBCollection) -> [DBFolder] {
        folders
            .filter { $0.collectionId == collection.id }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    public func catalogs(for folder: DBFolder) -> [DBFolderCatalog] {
        folderCatalogs.filter { $0.folderId == folder.id }
    }

    public func sources(for folder: DBFolder) -> [DBFolderSource] {
        folderSources
            .filter { $0.folderId == folder.id }
            .sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
    }
}
