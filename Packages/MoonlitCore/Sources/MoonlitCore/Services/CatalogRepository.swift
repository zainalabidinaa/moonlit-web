import Foundation

public enum HomeCatalogLoadStrategy: Equatable {
    case addonCatalogsOnly
    case collectionsThenAddonSupplement
}

public enum CatalogReloadMode: Equatable {
    case preserveCacheOnEmpty
    case replaceCache
}

public enum FolderLoadUnavailableReason: String, Equatable, Sendable {
    case missingFolder
    case missingSources
    case missingAddonTransport
    case emptyResponse
}

public enum FolderLoadResult: Equatable, Sendable {
    case alreadyLoaded
    case loaded
    case unavailable(FolderLoadUnavailableReason)
}

@MainActor
public class CatalogRepository: ObservableObject {
    public static let shared = CatalogRepository()

    @Published public var catalogRows: [CatalogRow] = []
    @Published public var collectionRows: [CatalogRow] = []
    @Published public var allFolderRows: [String: CatalogRow] = [:]
    @Published public var isLoading = false

    /// All MetaPreview items from both catalog and collection rows, for fallback lookups.
    public var allCatalogItems: [MetaPreview] {
        (catalogRows + collectionRows).flatMap(\.items)
    }

    private let catalogService = CatalogService.shared

    private nonisolated static let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MoonlitCatalogRows", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("rows.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: Self.cacheURL),
           let rows = try? JSONDecoder().decode([CatalogRow].self, from: data),
           !rows.isEmpty {
            catalogRows = rows
        }
    }

    private func saveToDisk() {
        let rows = catalogRows
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(rows) else { return }
            try? data.write(to: Self.cacheURL, options: .atomic)
        }
    }

    nonisolated public static func homeLoadStrategy(collections: [DBCollection]) -> HomeCatalogLoadStrategy {
        collections.isEmpty ? .addonCatalogsOnly : .collectionsThenAddonSupplement
    }

    nonisolated public static func resolvedRowsAfterReload(
        existingRows: [CatalogRow],
        newRows: [CatalogRow],
        mode: CatalogReloadMode = .preserveCacheOnEmpty
    ) -> [CatalogRow] {
        switch mode {
        case .preserveCacheOnEmpty:
            return newRows.isEmpty ? existingRows : newRows
        case .replaceCache:
            return newRows
        }
    }

    nonisolated public static func normalizedFolderId(_ folderId: String) -> String {
        folderId.hasPrefix("folder_") ? folderId : "folder_\(folderId)"
    }

    nonisolated public static func folderLoadUnavailableReason(
        folderId: String,
        collections: [DBCollection],
        folders: [DBFolder],
        folderCatalogs: [DBFolderCatalog],
        folderSources: [DBFolderSource],
        addons: [AddonManifest]
    ) -> FolderLoadUnavailableReason? {
        let normalizedId = normalizedFolderId(folderId)
        let visibleCollectionIds = Set(collections.map(\.id))
        guard let folder = folders.first(where: {
            normalizedFolderId($0.id) == normalizedId && visibleCollectionIds.contains($0.collectionId)
        }) else {
            return .missingFolder
        }

        let hasSources = folderCatalogs.contains { $0.folderId == folder.id }
            || folderSources.contains { $0.folderId == folder.id }
        guard hasSources else { return .missingSources }

        let hasTransport = addons.contains {
            ($0.transportUrl?.isEmpty == false)
        }
        return hasTransport ? nil : .missingAddonTransport
    }

    private nonisolated static let betterPostersPosterTemplate = "https://btttr.cc/poster-g/imdb/poster-default/{imdb_id}.jpg"

    private nonisolated static func shouldUseBetterPostersFallback(addonName: String?, addonId: String?, baseURL: String?) -> Bool {
        let marker = "\(addonName ?? "") \(addonId ?? "") \(baseURL ?? "")".lowercased()
        return !marker.contains("aiometadata") && !marker.contains("aio") && !marker.contains("btttr.cc")
    }

    private nonisolated static func betterPostersPosterURL(for item: MetaPreview) -> String? {
        let imdbId = item.id.split(separator: ":").first.map(String.init) ?? item.id
        guard imdbId.hasPrefix("tt") else { return nil }
        return betterPostersPosterTemplate.replacingOccurrences(of: "{imdb_id}", with: imdbId)
    }

    private nonisolated static func applyingBetterPostersFallback(to item: MetaPreview) -> MetaPreview {
        guard let poster = betterPostersPosterURL(for: item) else { return item }
        return MetaPreview(
            id: item.id,
            type: item.type,
            name: item.name,
            poster: poster,
            banner: item.banner,
            logo: item.logo,
            posterShape: item.posterShape,
            description: item.description,
            releaseInfo: item.releaseInfo,
            rawReleaseDate: item.rawReleaseDate,
            released: item.released,
            runtime: item.runtime,
            popularity: item.popularity,
            voteCount: item.voteCount,
            imdbRating: item.imdbRating,
            genres: item.genres,
            status: item.status,
            behaviorHints: item.behaviorHints,
            rankHint: item.rankHint,
            trailerStreams: item.trailerStreams
        )
    }

    private nonisolated static func applyingBetterPostersFallback(
        to items: [MetaPreview],
        addonName: String? = nil,
        addonId: String? = nil,
        baseURL: String? = nil
    ) -> [MetaPreview] {
        guard shouldUseBetterPostersFallback(addonName: addonName, addonId: addonId, baseURL: baseURL) else { return items }
        return items.map(applyingBetterPostersFallback(to:))
    }

    nonisolated public static func folderRow(
        _ row: CatalogRow,
        appending nextPageItems: [MetaPreview],
        pageSize: Int = 50
    ) -> CatalogRow {
        var updated = row
        var seenIds = Set(updated.items.map(\.id))
        let newItems = nextPageItems.filter { seenIds.insert($0.id).inserted }
        updated.items.append(contentsOf: newItems)
        updated.page += 1
        updated.hasMore = !newItems.isEmpty && nextPageItems.count >= pageSize
        return updated
    }

    /// Whether a folder's sources can serve additional pages. TMDB collection
    /// catalogs (tmdb.collection.*) return the whole franchise in one response
    /// and ignore `skip`, so a folder backed only by them has no further pages —
    /// paginating it would re-fetch and append the same items (the "Horror
    /// Vault duplicates" bug).
    nonisolated public static func sourcesSupportPagination(
        normalizedSources: [DBFolderCatalog],
        rawSources: [DBFolderSource]
    ) -> Bool {
        if !rawSources.isEmpty { return true }
        return normalizedSources.contains { !$0.catalogId.hasPrefix("tmdb.collection.") }
    }

    /// A content-less row built purely from folder/collection metadata (cover art,
    /// logos, hero backdrop). Used so a JSON-configured folder stays visible and
    /// tappable even when its catalog fetch returns nothing — real content fills in
    /// on retry/tap. Mirrors the skeleton rows used for multi-folder group tiles.
    nonisolated public static func skeletonRow(
        for folder: DBFolder,
        in collection: DBCollection,
        sourceCount: Int? = nil
    ) -> CatalogRow {
        CatalogRow(
            id: "folder_\(folder.id)",
            title: folder.name,
            items: [],
            addonName: "AIOMetadata",
            page: 0,
            hasMore: false,
            tileShape: folder.tileShape,
            coverImage: folder.coverImage,
            focusGif: folder.focusGif,
            focusGifEnabled: folder.focusGifEnabled,
            titleLogo: folder.titleLogo,
            heroBackdrop: folder.heroBackdrop,
            heroVideoURL: folder.heroVideoUrl,
            hideTitle: folder.hideTitle,
            focusGlowEnabled: collection.focusGlowEnabled,
            viewMode: collection.viewMode,
            showAllTab: collection.showAllTab,
            pinToTop: collection.pinToTop,
            backdropImage: collection.backdropImage,
            sourceCount: sourceCount
        )
    }

    /// Count + label kind for a folder group tile. Fully-loaded leaf folders show
    /// their real film/show count; unloaded franchise bundles (>1 source) fall back
    /// to a "N COLLECTIONS" badge so the tile isn't blank before its contents load.
    nonisolated public static func folderTileCount(for row: CatalogRow) -> (Int?, CountKind?) {
        if !row.items.isEmpty {
            let shows = row.items.filter { $0.type == .series || $0.type == .tv }.count
            let kind: CountKind = shows > row.items.count / 2 ? .shows : .films
            return (row.items.count, kind)
        }
        if let sources = row.sourceCount, sources > 1 {
            return (sources, .collections)
        }
        return (nil, nil)
    }

    nonisolated public static func displayRows(
        for collection: DBCollection,
        folders: [DBFolder],
        folderRows: [CatalogRow],
        preferences: CollectionDisplayPreferences,
        tab: CollectionTab = .home
    ) -> [CatalogRow] {
        guard preferences.enabledCollectionIds.contains(collection.id) else { return [] }
        guard collection.isVisible(in: tab) else { return [] }

        let visibleFolders = folders.filter { !preferences.hiddenFolderIds.contains($0.id) }
        let visibleRows = visibleFolders.compactMap { folder in
            folderRows.first { $0.id == "folder_\(folder.id)" || $0.title == folder.name }
        }
        guard !visibleRows.isEmpty else { return [] }

        if visibleRows.count == 1 || preferences.expandedCollectionIds.contains(collection.id) {
            return visibleRows
        }

        let folderTiles = zip(visibleFolders, visibleRows).map { folder, row in
            let first = row.items.first
            // Group tiles should stay static and readable; animated focus GIFs are
            // intentionally ignored for Home collection rows.
            // poster: primary cover; strip empty strings so fallbacks fire correctly.
            let poster = folder.coverImage?.nonEmpty
                ?? folder.heroBackdrop?.nonEmpty
                ?? folder.titleLogo?.nonEmpty
                ?? first?.poster
                ?? first?.banner
            // banner: coverImage first so landscape tiles (which read banner) get the
            // custom cover art; heroBackdrop is the fallback for 404s.
            let banner = folder.coverImage?.nonEmpty
                ?? folder.heroBackdrop?.nonEmpty
                ?? first?.banner
                ?? first?.poster
            let (count, kind) = Self.folderTileCount(for: row)
            return MetaPreview(
                id: "folder_\(folder.id)",
                type: first?.type ?? .movie,
                name: folder.name,
                poster: poster,
                banner: banner,
                logo: folder.titleLogo,
                posterShape: PosterShape(rawValue: folder.tileShape ?? "") ?? .landscape,
                // Clean backdrop art for  tiles that draw their own title.
                backdrop: folder.heroBackdrop?.nonEmpty,
                itemCount: count,
                countKind: kind,
                description: first?.description,
                focusGif: folder.focusGif,
                focusGifEnabled: folder.focusGifEnabled
            )
        }

        let groupTileShape = visibleFolders.first?.tileShape ?? visibleRows.first?.tileShape ?? "poster"

        return [CatalogRow(
            id: "collection_\(collection.id)",
            title: collection.name,
            items: folderTiles,
            addonName: "AIOMetadata",
            page: 0,
            hasMore: false,
            tileShape: groupTileShape,
            focusGlowEnabled: false,
            viewMode: collection.viewMode,
            showAllTab: collection.showAllTab,
            pinToTop: collection.pinToTop,
            backdropImage: collection.backdropImage
        )]
    }

    /// Portal-driven rows for a specific tab (Movies/Series/Home), assembled from the
    /// already-loaded folder rows. Collections are gated by their per-platform tab
    /// flags; within Movies/Series, content rows are narrowed to the matching media
    /// kind while folder/group tiles pass through untouched.
    public func rows(for tab: CollectionTab, collectionRepo: CollectionRepository) -> [CatalogRow] {
        let preferences = CollectionDisplayPreferenceStore.shared.preferences(for: collectionRepo.collections)
        var rows: [CatalogRow] = []
        for collection in collectionRepo.collections {
            let folders = collectionRepo.folders(for: collection)
            let folderRows = folders.compactMap { folder in
                allFolderRows["folder_\(folder.id)"]
                    ?? catalogRows.first { $0.id == "folder_\(folder.id)" }
            }
            rows.append(contentsOf: Self.displayRows(
                for: collection,
                folders: folders,
                folderRows: folderRows,
                preferences: preferences,
                tab: tab
            ))
        }
        guard tab != .home else { return rows }
        return rows.compactMap { row in
            guard !row.items.isEmpty else { return row }
            let items = row.items.filter { item in
                if item.id.hasPrefix("folder_") { return true }
                return tab == .movies ? item.isMovieKind : item.isShowKind
            }
            guard !items.isEmpty else { return nil }
            var narrowed = row
            narrowed.items = items
            return narrowed
        }
    }

    /// Fetches addon catalogs not already represented in catalogRows and appends them.
    /// Called after loadFromCollections so the user's addon catalogs always appear
    /// even if the Supabase collection IDs don't perfectly match the addon manifest.
    public func supplementWithAddonCatalogs(addons: [AddonManifest]) async {
        let existingAddonIds = Set(catalogRows.map { $0.addonName ?? "" })

        await withTaskGroup(of: CatalogRow?.self) { group in
            for addon in addons {
                // Skip addons whose rows are already fully represented
                guard !existingAddonIds.contains(addon.name) else { continue }
                guard let catalogs = addon.catalogs, let baseURL = addon.transportUrl else { continue }

                for catalog in catalogs {
                    let needsSearch = (catalog.extra ?? []).contains { $0.name == "search" && ($0.isRequired ?? false) }
                    if needsSearch { continue }

                    let rowId = "\(addon.id)_\(catalog.type)_\(catalog.id)"
                    guard !catalogRows.contains(where: { $0.id == rowId }) else { continue }

                    var extras: [String: String] = [:]
                    for e in catalog.extra ?? [] { if let first = e.options?.first { extras[e.name] = first } }

                    group.addTask {
                        do {
                            let query = CatalogService.StremioCatalogQuery(
                                type: catalog.type, id: catalog.id,
                                baseURL: baseURL, extras: extras
                            )
                            let fetchedItems = try await self.catalogService.fetchCatalog(query: query)
                            let items = Self.applyingBetterPostersFallback(
                                to: fetchedItems,
                                addonName: addon.name,
                                addonId: addon.id,
                                baseURL: baseURL
                            )
                            guard !items.isEmpty else { return nil }
                            let catalogTitle = catalog.name ?? catalog.id.capitalized
                            let filteredItems = Self.applyTitleBasedFilters(items, title: catalogTitle)
                            return CatalogRow(
                                id: rowId,
                                title: catalogTitle,
                                items: filteredItems,
                                addonName: addon.name,
                                addonId: addon.id,
                                page: 0,
                                hasMore: !items.isEmpty
                            )
                        } catch { return nil }
                    }
                }
            }
            for await row in group {
                if let row, !catalogRows.contains(where: { $0.id == row.id }) {
                    catalogRows.append(row)
                }
            }
        }
    }

    public func loadAllCatalogs(addons: [AddonManifest]) async {
        isLoading = true
        let existingRows = catalogRows

        // Score catalogs so Popular/Trending load first — hero appears fast,
        // then remaining rows fill in progressively behind it.
        struct ScoredCatalog {
            let addon: AddonManifest
            let catalog: AddonCatalog
            let baseURL: String
            let extras: [String: String]
            let score: Int
        }

        var scored: [ScoredCatalog] = []
        for addon in addons {
            guard let catalogs = addon.catalogs, let baseURL = addon.transportUrl else { continue }
            for catalog in catalogs {
                let needsSearch = (catalog.extra ?? []).contains { $0.name == "search" && ($0.isRequired ?? false) }
                if needsSearch { continue }
                var extras: [String: String] = [:]
                for e in catalog.extra ?? [] { if let first = e.options?.first { extras[e.name] = first } }
                let text = "\(catalog.name ?? "") \(catalog.id) \(catalog.type)".lowercased()
                var s = 0
                if text.contains("popular")  { s += 4 }
                if text.contains("trending") { s += 4 }
                if text.contains("featured") { s += 3 }
                if catalog.type == "movie" || catalog.type == "series" { s += 2 }
                scored.append(ScoredCatalog(addon: addon, catalog: catalog, baseURL: baseURL, extras: extras, score: s))
            }
        }
        scored.sort { $0.score > $1.score }

        // Load high-priority catalogs first (score ≥ 4) so the hero populates fast,
        // then load everything else progressively.
        let priority = scored.filter { $0.score >= 4 }
        let rest     = scored.filter { $0.score < 4 }
        var loadedRows: [CatalogRow] = []

        func fetch(_ items: [ScoredCatalog]) async {
            await withTaskGroup(of: CatalogRow?.self) { group in
                for sc in items {
                    group.addTask {
                        do {
                            let query = CatalogService.StremioCatalogQuery(
                                type: sc.catalog.type,
                                id: sc.catalog.id,
                                baseURL: sc.baseURL,
                                extras: sc.extras
                            )
                            let fetchedRows = try await self.catalogService.fetchCatalog(query: query)
                            let rows = Self.applyingBetterPostersFallback(
                                to: fetchedRows,
                                addonName: sc.addon.name,
                                addonId: sc.addon.id,
                                baseURL: sc.baseURL
                            )
                            guard !rows.isEmpty else { return nil }
                            let title = sc.catalog.name ?? sc.catalog.id.capitalized
                            let filtered = Self.applyTitleBasedFilters(rows, title: title)
                            return CatalogRow(
                                id: "\(sc.addon.id)_\(sc.catalog.type)_\(sc.catalog.id)",
                                title: title,
                                items: filtered,
                                addonName: sc.addon.name,
                                addonId: sc.addon.id,
                                page: 0,
                                hasMore: !rows.isEmpty
                            )
                        } catch { return nil }
                    }
                }
                for await row in group {
                    if let row, !loadedRows.contains(where: { $0.id == row.id }) {
                        loadedRows.append(row)
                        catalogRows = Self.resolvedRowsAfterReload(existingRows: existingRows, newRows: loadedRows)
                        isLoading = false
                    }
                }
            }
        }

        await fetch(priority)   // hero-worthy rows — appear first
        await fetch(rest)       // remaining rows fill in after
        if !loadedRows.isEmpty {
            allFolderRows = [:]
            saveToDisk()
        }
        isLoading = false
    }

    public func loadFromCollections(
        collectionRepo: CollectionRepository,
        addons: [AddonManifest],
        mode: CatalogReloadMode = .preserveCacheOnEmpty
    ) async {
        isLoading = true
        let existingRows = catalogRows
        let existingCollectionRows = collectionRows
        let existingFolderRows = allFolderRows
        defer { isLoading = false }

        guard let fallbackURL = addons.first(where: {
            $0.transportUrl?.contains("aiometadata") == true || $0.id.contains("aio")
        })?.transportUrl ?? addons.first?.transportUrl else { return }

        let preferences = CollectionDisplayPreferenceStore.shared.preferences(for: collectionRepo.collections)

        // Build work items for folders that need content fetched (single-folder collections
        // or explicitly expanded multi-folder collections). Multi-folder group collections
        // get skeleton rows built from their folder metadata — their cover images come from
        // the JSON (coverImageUrl/titleLogo/heroBackdrop), so we don't need HTTP fetches
        // on startup. Content loads on demand when the user taps into a group folder.
        struct FolderWork {
            let collectionIdx: Int
            let folderIdx: Int
            let collection: DBCollection
            let folder: DBFolder
            let normalizedSources: [DBFolderCatalog]
            let rawSources: [DBFolderSource]
        }
        struct FolderResult {
            let collectionIdx: Int
            let folderIdx: Int
            let row: CatalogRow
        }

        var workItems: [FolderWork] = []
        var skeletonResults: [FolderResult] = []

        for (ci, collection) in collectionRepo.collections.enumerated() {
            let folders = collectionRepo.folders(for: collection)
            // A collection shows as GROUP TILES when it has >1 folder and isn't expanded.
            // Group tiles only need folder metadata (cover art already in JSON), not content.
            let willShowAsGroup = folders.count > 1
                && !preferences.expandedCollectionIds.contains(collection.id)

            for (fi, folder) in folders.enumerated() {
                if willShowAsGroup {
                    // Skeleton row — cover image from folder metadata, no HTTP fetch needed.
                    // Content is loaded on-demand when the user opens this folder.
                    // Carry the source count so a franchise bundle can show "N COLLECTIONS".
                    let sourceCount = collectionRepo.catalogs(for: folder).count
                        + collectionRepo.sources(for: folder).count
                    skeletonResults.append(FolderResult(
                        collectionIdx: ci,
                        folderIdx: fi,
                        row: Self.skeletonRow(for: folder, in: collection, sourceCount: sourceCount)
                    ))
                } else {
                    let norm = collectionRepo.catalogs(for: folder)
                    let raw  = collectionRepo.sources(for: folder)
                    guard !norm.isEmpty || !raw.isEmpty else { continue }
                    workItems.append(FolderWork(
                        collectionIdx: ci, folderIdx: fi,
                        collection: collection, folder: folder,
                        normalizedSources: norm, rawSources: raw
                    ))
                }
            }
        }

        // Fetch only the single-folder (row-display) folders concurrently.
        var fetchedRows: [FolderResult] = skeletonResults
        await withTaskGroup(of: FolderResult?.self) { group in
            for work in workItems {
                group.addTask {
                    // Merge sources in submission order (deterministic) rather than
                    // completion order, so the rail doesn't reshuffle between loads.
                    var buckets: [Int: [MetaPreview]] = [:]
                    await withTaskGroup(of: (Int, [MetaPreview]).self) { inner in
                        var sourceIndex = 0
                        for source in work.normalizedSources {
                            let sourceURL = addons.first(where: {
                                $0.catalogs?.contains(where: { $0.id == source.catalogId }) == true
                            })?.transportUrl ?? fallbackURL
                            let idx = sourceIndex; sourceIndex += 1
                            inner.addTask { (idx, await self.fetchNormalizedSource(source, baseURL: sourceURL)) }
                        }
                        for source in work.rawSources {
                            let idx = sourceIndex; sourceIndex += 1
                            inner.addTask { (idx, await self.fetchRawSource(source, baseURL: fallbackURL)) }
                        }
                        for await (idx, result) in inner { buckets[idx] = result }
                    }
                    let items = Self.applyTitleBasedFilters(
                        Self.deduplicated(buckets.keys.sorted().flatMap { buckets[$0] ?? [] }),
                        title: work.folder.name
                    )
                    guard !items.isEmpty else { return nil }
                    return FolderResult(
                        collectionIdx: work.collectionIdx,
                        folderIdx: work.folderIdx,
                        row: CatalogRow(
                            id: "folder_\(work.folder.id)",
                            title: work.folder.name,
                            items: items,
                            addonName: "AIOMetadata",
                            page: 0,
                            hasMore: Self.sourcesSupportPagination(
                                normalizedSources: work.normalizedSources,
                                rawSources: work.rawSources
                            ),
                            tileShape: work.folder.tileShape,
                            coverImage: work.folder.coverImage,
                            focusGif: work.folder.focusGif,
                            focusGifEnabled: work.folder.focusGifEnabled,
                            titleLogo: work.folder.titleLogo,
                            heroBackdrop: work.folder.heroBackdrop,
                            heroVideoURL: work.folder.heroVideoUrl,
                            hideTitle: work.folder.hideTitle,
                            focusGlowEnabled: work.collection.focusGlowEnabled,
                            viewMode: work.collection.viewMode,
                            showAllTab: work.collection.showAllTab,
                            pinToTop: work.collection.pinToTop,
                            backdropImage: work.collection.backdropImage,
                            sourceCount: work.normalizedSources.count + work.rawSources.count
                        )
                    )
                }
            }
            for await result in group {
                if let r = result { fetchedRows.append(r) }
            }
        }

        // Reassemble in original collection/folder order.
        // For folders whose fetch returned nothing, fall back to the previously-cached row
        // so a transient empty response doesn't delete a row from the home screen.
        var newFolderRows: [String: CatalogRow] = [:]
        var rows: [CatalogRow] = []
        for (ci, collection) in collectionRepo.collections.enumerated() {
            let folders = collectionRepo.folders(for: collection)
            let collectionFolderRows: [CatalogRow] = folders.enumerated().compactMap { fi, folder in
                if let fetched = fetchedRows.first(where: { $0.collectionIdx == ci && $0.folderIdx == fi }) {
                    return fetched.row
                }
                // Fetch failed for this folder — recover from any cached source.
                // existingFolderRows is empty at session start (not persisted to disk),
                // so also check existingRows (catalogRows, loaded from disk at init).
                // If nothing is cached either, fall back to a metadata-only skeleton so a
                // JSON-configured collection never silently vanishes from the home screen.
                let folderId = "folder_\(folder.id)"
                let sourceCount = collectionRepo.catalogs(for: folder).count
                    + collectionRepo.sources(for: folder).count
                return existingFolderRows[folderId]
                    ?? existingCollectionRows.first(where: { $0.id == folderId })
                    ?? existingRows.first(where: { $0.id == folderId })
                    ?? Self.skeletonRow(for: folder, in: collection, sourceCount: sourceCount)
            }
            for row in collectionFolderRows { newFolderRows[row.id] = row }
            rows.append(contentsOf: Self.displayRows(
                for: collection,
                folders: folders,
                folderRows: collectionFolderRows,
                preferences: preferences
            ))
        }

        var merged = existingFolderRows
        for (key, row) in newFolderRows {
            if let existing = merged[key], !existing.items.isEmpty {
                continue
            }
            merged[key] = row
        }
        self.allFolderRows = merged
        self.collectionRows = Self.resolvedRowsAfterReload(
            existingRows: existingCollectionRows,
            newRows: rows,
            mode: mode
        )
        self.catalogRows = Self.resolvedRowsAfterReload(
            existingRows: existingRows,
            newRows: rows,
            mode: mode
        )
        if !rows.isEmpty || mode == .replaceCache { saveToDisk() }
    }

    /// Fetches content of the same type and genre from the best available addon,
    /// excluding the item with `excludingId`. Used for "More Like This" rows.
    /// Prioritises Cinemeta (most complete catalogue), then falls back to other
    /// genre-capable addons until we have at least 10 results.
    public func fetchRelated(
        type: String,
        genre: String,
        excludingId: String,
        addons: [AddonManifest]
    ) async -> [MetaPreview] {
        // Sort: Cinemeta first, then any other addon with genre support
        let sorted = addons.sorted { a, _ in
            a.transportUrl?.contains("cinemeta") == true
        }

        var collected: [MetaPreview] = []

        for addon in sorted {
            guard collected.count < 10,
                  let catalogs = addon.catalogs,
                  let baseURL = addon.transportUrl else { continue }
            for catalog in catalogs {
                guard catalog.type == type else { continue }
                let supportsGenre = (catalog.extra ?? []).contains { $0.name == "genre" }
                guard supportsGenre else { continue }
                let query = CatalogService.StremioCatalogQuery(
                    type: type,
                    id: catalog.id,
                    baseURL: baseURL,
                    extras: ["genre": genre]
                )
                if let fetchedResults = try? await catalogService.fetchCatalog(query: query) {
                    let results = Self.applyingBetterPostersFallback(
                        to: fetchedResults,
                        addonName: addon.name,
                        addonId: addon.id,
                        baseURL: baseURL
                    )
                    let fresh = results.filter { item in
                        item.id != excludingId && !collected.contains(where: { $0.id == item.id })
                    }
                    collected.append(contentsOf: fresh)
                }
                break // one catalog per addon is enough
            }
        }
        return collected
    }

    private func fetchNormalizedSource(
        _ source: DBFolderCatalog,
        baseURL: String,
        skip: Int = 0
    ) async -> [MetaPreview] {
        // TMDB collection (e.g. "Die Hard Collection") — fetch directly from TMDB API
        // since AIO Metadata doesn't serve individual collection catalogs correctly.
        if source.catalogId.hasPrefix("tmdb.collection."),
           let collectionId = Int(source.catalogId.dropFirst("tmdb.collection.".count)) {
            return await fetchTMDBCollectionItems(collectionId: collectionId)
        }
        do {
            // Start with any stored extras (e.g. DISCOVER year/language filters),
            // then layer genre on top, then skip.
            var extras = source.extras ?? [:]
            if let genre = source.genre, genre.lowercased() != "none", !genre.isEmpty {
                extras["genre"] = genre
            }
            if source.mediaType == "all" {
                var movieExtras = extras
                var seriesExtras = extras
                if skip > 0 {
                    movieExtras["skip"] = String(skip)
                    seriesExtras["skip"] = String(skip)
                }
                let movieQuery = CatalogService.StremioCatalogQuery(
                    type: "movie", id: source.catalogId, baseURL: baseURL, extras: movieExtras
                )
                let seriesQuery = CatalogService.StremioCatalogQuery(
                    type: "series", id: source.catalogId, baseURL: baseURL, extras: seriesExtras
                )
                async let movieResult = catalogService.fetchCatalog(query: movieQuery)
                async let seriesResult = catalogService.fetchCatalog(query: seriesQuery)
                let movieItems = (try? await movieResult).map { Self.applyingBetterPostersFallback(to: $0, baseURL: baseURL) } ?? []
                let seriesItems = (try? await seriesResult).map { Self.applyingBetterPostersFallback(to: $0, baseURL: baseURL) } ?? []
                return movieItems + seriesItems
            }
            if skip > 0 { extras["skip"] = String(skip) }
            let query = CatalogService.StremioCatalogQuery(
                type: source.mediaType,
                id: source.catalogId,
                baseURL: baseURL,
                extras: extras
            )
            let items = try await catalogService.fetchCatalog(query: query)
            return Self.applyingBetterPostersFallback(to: items, baseURL: baseURL)
        } catch {
            return []
        }
    }

    private func fetchRawSource(
        _ source: DBFolderSource,
        baseURL: String,
        skip: Int = 0
    ) async -> [MetaPreview] {
        do {
            guard var query = resolveRawQuery(from: source, baseURL: baseURL) else {
                return []
            }
            if skip > 0 {
                var extras = query.extras
                extras["skip"] = String(skip)
                query = CatalogService.StremioCatalogQuery(
                    type: query.type,
                    id: query.id,
                    baseURL: query.baseURL,
                    extras: extras
                )
            }
            let items = try await catalogService.fetchCatalog(query: query)
            return Self.applyingBetterPostersFallback(to: items, baseURL: baseURL)
        } catch {
            return []
        }
    }

    private func resolveRawQuery(
        from source: DBFolderSource,
        baseURL: String
    ) -> CatalogService.StremioCatalogQuery? {
        let mediaType = source.mediaType ?? "movie"
        let extras: [String: String] = [:]

        switch source.provider.lowercased() {
        case "trakt":
            guard let tmdbId = source.tmdbId else { return nil }
            return CatalogService.StremioCatalogQuery(
                type: mediaType,
                id: "trakt.list.\(tmdbId)",
                baseURL: baseURL,
                extras: extras
            )
        case "tmdb":
            if source.tmdbSourceType?.uppercased() == "COLLECTION" {
                return nil
            }
            guard let tmdbId = source.tmdbId else { return nil }
            let catalogId = source.tmdbSourceType?.lowercased() == "discover"
                ? "tmdb.discover.\(mediaType).\(tmdbId)"
                : "tmdb.\(tmdbId)"
            return CatalogService.StremioCatalogQuery(
                type: mediaType,
                id: catalogId,
                baseURL: baseURL,
                extras: extras
            )
        case "mdblist":
            guard let tmdbId = source.tmdbId else { return nil }
            return CatalogService.StremioCatalogQuery(
                type: mediaType,
                id: "mdblist.\(tmdbId)",
                baseURL: baseURL,
                extras: extras
            )
        case "tvdb":
            guard let tmdbId = source.tmdbId else { return nil }
            return CatalogService.StremioCatalogQuery(
                type: mediaType,
                id: "tvdb.discover.\(mediaType).\(tmdbId)",
                baseURL: baseURL,
                extras: extras
            )
        case "streaming":
            guard let tmdbId = source.tmdbId else { return nil }
            return CatalogService.StremioCatalogQuery(
                type: mediaType,
                id: "streaming.\(tmdbId)",
                baseURL: baseURL,
                extras: extras
            )
        default:
            return nil
        }
    }

    /// Loads items for a skeleton folder row on demand (called when the user opens a group folder).
    /// Updates `allFolderRows` so FolderScreen can refresh once items are ready.
    @discardableResult
    public func loadFolderItems(
        folderId: String,
        collectionRepo: CollectionRepository,
        addons: [AddonManifest]
    ) async -> FolderLoadResult {
        let normalizedFolderId = Self.normalizedFolderId(folderId)

        // Already loaded — nothing to do.
        if let existing = allFolderRows[normalizedFolderId], !existing.items.isEmpty {
            return .alreadyLoaded
        }

        if let reason = Self.folderLoadUnavailableReason(
            folderId: normalizedFolderId,
            collections: collectionRepo.collections,
            folders: collectionRepo.folders,
            folderCatalogs: collectionRepo.folderCatalogs,
            folderSources: collectionRepo.folderSources,
            addons: addons
        ) {
            return .unavailable(reason)
        }

        guard let fallbackURL = addons.first(where: {
            $0.transportUrl?.contains("aiometadata") == true || $0.id.contains("aio")
        })?.transportUrl ?? addons.first?.transportUrl else {
            return .unavailable(.missingAddonTransport)
        }

        // Find the folder in any collection.
        var targetFolder: DBFolder?
        for collection in collectionRepo.collections {
            if let f = collectionRepo.folders(for: collection).first(where: { Self.normalizedFolderId($0.id) == normalizedFolderId }) {
                targetFolder = f
                break
            }
        }
        guard let folder = targetFolder else { return .unavailable(.missingFolder) }

        let normalizedSources = collectionRepo.catalogs(for: folder)
        let rawSources = collectionRepo.sources(for: folder)
        guard !normalizedSources.isEmpty || !rawSources.isEmpty else { return .unavailable(.missingSources) }

        let fetchedItems = await fetchFolderItems(
            normalizedSources: normalizedSources,
            rawSources: rawSources,
            fallbackURL: fallbackURL,
            addons: addons,
            skip: 0,
            sortByReleaseDate: folder.name.localizedCaseInsensitiveContains("coming soon")
        )
        let items = Self.applyTitleBasedFilters(fetchedItems, title: folder.name)

        guard !items.isEmpty else { return .unavailable(.emptyResponse) }

        let hasMore = !items.isEmpty && Self.sourcesSupportPagination(
            normalizedSources: normalizedSources,
            rawSources: rawSources
        )

        // Patch the stored row with the fetched items.
        if var row = allFolderRows[normalizedFolderId] {
            row.items = items
            row.page = 0
            row.hasMore = hasMore
            allFolderRows[normalizedFolderId] = row
        } else {
            allFolderRows[normalizedFolderId] = CatalogRow(
                id: normalizedFolderId,
                title: folder.name,
                items: items,
                addonName: "AIOMetadata",
                page: 0,
                hasMore: hasMore,
                tileShape: folder.tileShape,
                coverImage: folder.coverImage,
                focusGif: folder.focusGif,
                focusGifEnabled: folder.focusGifEnabled,
                titleLogo: folder.titleLogo,
                heroBackdrop: folder.heroBackdrop,
                heroVideoURL: folder.heroVideoUrl,
                hideTitle: folder.hideTitle
            )
        }

        // Also update in catalogRows so the home-screen group tile cover reflects live data.
        if let idx = catalogRows.firstIndex(where: { $0.id == normalizedFolderId }) {
            catalogRows[idx].items = items
            catalogRows[idx].page = 0
            catalogRows[idx].hasMore = hasMore
        }
        return .loaded
    }

    public func loadMoreFolderItems(
        folderId: String,
        collectionRepo: CollectionRepository,
        addons: [AddonManifest]
    ) async {
        let normalizedFolderId = Self.normalizedFolderId(folderId)
        guard let row = allFolderRows[normalizedFolderId], row.hasMore else { return }

        guard let fallbackURL = addons.first(where: {
            $0.transportUrl?.contains("aiometadata") == true || $0.id.contains("aio")
        })?.transportUrl ?? addons.first?.transportUrl else { return }

        var targetFolder: DBFolder?
        for collection in collectionRepo.collections {
            if let folder = collectionRepo.folders(for: collection).first(where: { Self.normalizedFolderId($0.id) == normalizedFolderId }) {
                targetFolder = folder
                break
            }
        }
        guard let folder = targetFolder else { return }

        let normalizedSources = collectionRepo.catalogs(for: folder)
        let rawSources = collectionRepo.sources(for: folder)
        guard !normalizedSources.isEmpty || !rawSources.isEmpty else { return }

        // Rows cached before pagination support was source-aware may carry a
        // stale hasMore=true for non-paginatable (tmdb.collection-only) folders.
        guard Self.sourcesSupportPagination(normalizedSources: normalizedSources, rawSources: rawSources) else {
            allFolderRows[normalizedFolderId]?.hasMore = false
            if let idx = catalogRows.firstIndex(where: { $0.id == normalizedFolderId }) {
                catalogRows[idx].hasMore = false
            }
            return
        }

        let skip = (row.page + 1) * 50
        let fetchedItems = await fetchFolderItems(
            normalizedSources: normalizedSources,
            rawSources: rawSources,
            fallbackURL: fallbackURL,
            addons: addons,
            skip: skip
        )
        let items = Self.applyTitleBasedFilters(fetchedItems, title: folder.name)

        guard !items.isEmpty else {
            allFolderRows[normalizedFolderId]?.hasMore = false
            if let idx = catalogRows.firstIndex(where: { $0.id == normalizedFolderId }) {
                catalogRows[idx].hasMore = false
            }
            return
        }

        let updated = Self.folderRow(row, appending: items)
        allFolderRows[normalizedFolderId] = updated
        if let idx = catalogRows.firstIndex(where: { $0.id == normalizedFolderId }) {
            catalogRows[idx] = updated
        }
    }

    /// Loads a genre hub: `GenreCatalog` sections (folder tiles, no fetch), the
    /// bundled addon-catalog browse rails (New / Popular / Top …), and — when a
    /// TMDB key is configured and `mediaKind` narrows the genre to Movies or
    /// Shows —  curated TMDB discover rails (Trending, Top Rated,
    /// New, Hidden Gems, companion media-kind) layered on top. The addon rails
    /// are the fallback for users without a TMDB key.
    // MARK: Genre hub cache
    //
    // Without this, every visit to a genre refetches a dozen rails. Whether a hub
    // felt instant was down to whatever URLSession happened to still hold — which
    // is why the same build showed Adventure instantly and Comedy after six
    // seconds. Memory-only by design; see the spec's non-goals.
    private var genreHubCache: [String: (content: GenreCatalog.HubContent, at: Date)] = [:]
    private static let genreHubTTL: TimeInterval = 6 * 3600

    private static func genreHubKey(genre: String, mediaKind: MediaType?) -> String {
        "\(GenreCatalog.normalize(genre))|\(mediaKind?.rawValue ?? "any")"
    }

    /// Previously loaded hub content for this genre, if still within TTL.
    /// Callers paint this immediately and refresh behind it.
    public func cachedGenreHub(genre: String, mediaKind: MediaType? = nil) -> GenreCatalog.HubContent? {
        let key = Self.genreHubKey(genre: genre, mediaKind: mediaKind)
        guard let hit = genreHubCache[key],
              Date().timeIntervalSince(hit.at) < Self.genreHubTTL else { return nil }
        return hit.content
    }

    public func loadGenreHub(
        genre: String,
        collectionRepo: CollectionRepository,
        addons: [AddonManifest],
        mediaKind: MediaType? = nil
    ) async -> GenreCatalog.HubContent {
        await loadGenreHubProgressive(
            genre: genre,
            collectionRepo: collectionRepo,
            addons: addons,
            mediaKind: mediaKind,
            onPartial: { _ in }
        )
    }

    /// As `loadGenreHub`, but reports rails as they resolve instead of only at the
    /// end. The TMDB discover rails land well before the addon catalog fan-out, so
    /// the screen can paint something instead of holding a spinner until the
    /// slowest rail returns.
    public func loadGenreHubProgressive(
        genre: String,
        collectionRepo: CollectionRepository,
        addons: [AddonManifest],
        mediaKind: MediaType? = nil,
        onPartial: @MainActor ([GenreCatalog.LoadedBrowseRail]) -> Void
    ) async -> GenreCatalog.HubContent {
        let org = collectionRepo.organized
        let key = GenreCatalog.normalize(genre)
        let sections = GenreCatalog.sections(for: genre, in: org)
        let rails = GenreCatalog.browseRails(for: genre, in: org)

        async let discoverRails: [GenreCatalog.LoadedBrowseRail] = {
            guard let mediaKind else { return [] }
            return await TMDBDiscoverService.shared.discoverRails(genreName: genre, mediaKind: mediaKind)
        }()

        async let creativeRails: [GenreCatalog.LoadedBrowseRail] = {
            guard let mediaKind else { return [] }
            return await TMDBDiscoverService.shared.discoverCreativeRails(genreName: genre, mediaKind: mediaKind)
        }()

        // Publish the TMDB rails the moment they resolve — they are a single fast
        // request each, while the addon fan-out below is a dozen. Waiting for both
        // is what left the screen blank behind a spinner.
        let tmdbRails = await discoverRails + creativeRails
        if !tmdbRails.isEmpty {
            onPartial(tmdbRails)
        }

        let fallbackURL = addons.first(where: {
            $0.transportUrl?.contains("aiometadata") == true || $0.id.contains("aio")
        })?.transportUrl ?? addons.first?.transportUrl

        var loaded: [GenreCatalog.LoadedBrowseRail] = []
        if let fallbackURL {
            // Fire every rail's request at once instead of awaiting them one at a
            // time — with a dozen rails on a genre page, serial fetches were the
            // dominant cause of slow hub loads. Indices keep the result order
            // matching `rails` since task-group completion order is unspecified.
            let indexed = await withTaskGroup(of: (Int, GenreCatalog.LoadedBrowseRail?).self) { group in
                for (index, rail) in rails.enumerated() {
                    group.addTask {
                        let items = await self.fetchFolderItems(
                            normalizedSources: rail.catalogs,
                            rawSources: rail.sources,
                            fallbackURL: fallbackURL,
                            addons: addons,
                            skip: 0
                        )
                        let deduped = Self.deduplicated(items)
                        guard !deduped.isEmpty else { return (index, nil) }
                        return (index, GenreCatalog.LoadedBrowseRail(id: rail.id, title: rail.title, items: deduped))
                    }
                }
                var collected: [(Int, GenreCatalog.LoadedBrowseRail?)] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }
            loaded = indexed.sorted { $0.0 < $1.0 }.compactMap { $0.1 }
        }

        var collectionRails: [GenreCatalog.LoadedBrowseRail] = []
        if let fallbackURL {
            collectionRails = await fetchCollectionRails(genre: genre, key: key, org: org, fallbackURL: fallbackURL, addons: addons, mediaKind: mediaKind)
        }

        let content = GenreCatalog.HubContent(
            sections: sections,
            browse: tmdbRails + loaded,
            collectionRails: collectionRails
        )
        if !content.browse.isEmpty || !content.collectionRails.isEmpty {
            genreHubCache[Self.genreHubKey(genre: genre, mediaKind: mediaKind)] = (content, Date())
        }
        onPartial(content.browse)
        return content
    }

    /// Editorial rows for the top-level Movies and Series tabs. Unlike a genre
    /// hub, these deliberately stay broad: cinema history, decades, and a small
    /// set of category spotlights. Genre identity lists remain in their genre hub.
    public func loadMediaEditorialRails(
        mediaKind: MediaType,
        collectionRepo: CollectionRepository,
        addons: [AddonManifest]
    ) async -> [GenreCatalog.LoadedBrowseRail] {
        guard let fallbackURL = addons.first(where: {
            $0.transportUrl?.contains("aiometadata") == true || $0.id.contains("aio")
        })?.transportUrl ?? addons.first?.transportUrl else { return [] }

        let org = collectionRepo.organized
        let categoryNames: Set<String> = mediaKind == .movie
            ? ["action", "animation", "comedy", "drama", "fantasy & sci-fi", "horror", "mystery", "romance", "thriller", "western"]
            : ["action", "animation", "comedy", "drama", "fantasy & sci-fi", "horror", "romance", "thriller"]
        let categoryCollectionIds = Set(org.collections
            .filter { GenreCatalog.normalize($0.name) == "categories" }
            .map(\.id))
        let folders = org.folders.filter { folder in
            if categoryCollectionIds.contains(folder.collectionId) {
                return categoryNames.contains(GenreCatalog.normalize(folder.name))
            }
            return false
        }

        var railInputs: [(id: String, title: String, catalogs: [DBFolderCatalog])] = folders.map { folder in
            (folder.id, "\(folder.name) Spotlight", org.folderCatalogs.filter { $0.folderId == folder.id })
        }

        if mediaKind == .movie {
            func source(_ id: String, _ title: String, _ catalogId: String) -> (id: String, title: String, catalogs: [DBFolderCatalog]) {
                (id, title, [DBFolderCatalog(id: "editorial-\(id)", folderId: "editorial-\(id)", catalogId: catalogId, mediaType: "movie")])
            }
            railInputs.insert(contentsOf: [
                source("all-time-greats", "All-Time Greats", "tmdb.discover.movie.top-all-time-movies.39f5a0c4"),
                source("1001-greatest", "1001 Greatest Movies of All Time", "trakt.list.1282987"),
                source("70s-auteurs", "70s Auteurs", "tmdb.discover.movie.most-popular-of-the-decade-1970s.a5d4aa4a"),
                source("80s-classics", "80s Classics", "mdblist.91301"),
                source("essential-90s", "Essential 90s", "mdblist.91300"),
                source("defining-2010s", "Defining the 2010s", "mdblist.91303"),
                source("2020s-now", "2020s Now", "mdblist.91304"),
            ], at: 0)
        }

        let results = await withTaskGroup(of: (Int, GenreCatalog.LoadedBrowseRail?).self) { group in
            for (index, input) in railInputs.enumerated() where !input.catalogs.isEmpty {
                group.addTask {
                    let items = await self.fetchFolderItems(
                        normalizedSources: input.catalogs,
                        rawSources: [],
                        fallbackURL: fallbackURL,
                        addons: addons,
                        skip: 0
                    ).filter { mediaKind == .movie ? $0.isMovieKind : $0.isShowKind }
                    guard !items.isEmpty else { return (index, nil) }
                    return (index, GenreCatalog.LoadedBrowseRail(
                        id: "editorial-\(mediaKind.rawValue)-\(input.id)",
                        title: input.title,
                        items: Self.deduplicated(items),
                        subtitle: input.id.contains("70s") || input.id.contains("80s") || input.id.contains("90s") || input.id.contains("2010") || input.id.contains("2020") ? "CINEMA HISTORY" : "EDITORIAL"
                    ))
                }
            }
            var collected: [(Int, GenreCatalog.LoadedBrowseRail?)] = []
            for await result in group { collected.append(result) }
            return collected
        }
        return results.sorted { $0.0 < $1.0 }.compactMap(\.1)
    }

    /// Returns franchise-collection content rails for a genre so they can be
    /// shown as media rows (not folder tiles) in browse views. Looks at "Film
    /// Collections" for movies and "Series Universes" for series.
    public func loadCollectionRails(
        genre: String?,
        collectionRepo: CollectionRepository,
        addons: [AddonManifest],
        mediaKind: MediaType? = nil
    ) async -> [GenreCatalog.LoadedBrowseRail] {
        guard let fallbackURL = addons.first(where: {
            $0.transportUrl?.contains("aiometadata") == true || $0.id.contains("aio")
        })?.transportUrl ?? addons.first?.transportUrl else { return [] }
        let org = collectionRepo.organized
        let key = genre.map(GenreCatalog.normalize)
        return await fetchCollectionRails(genre: genre, key: key, org: org,
                                           fallbackURL: fallbackURL, addons: addons,
                                           mediaKind: mediaKind)
    }
    private func fetchCollectionRails(
        genre: String?, key: String?, org: OrganizedCollections,
        fallbackURL: String, addons: [AddonManifest],
        mediaKind: MediaType?
    ) async -> [GenreCatalog.LoadedBrowseRail] {
        let collectionNames: [String]
        let rowSubtitle: String
        switch mediaKind {
        case .series:
            collectionNames = ["series universes"]
            rowSubtitle = "FRANCHISE"
        case .movie, .channel, .tv:
            collectionNames = ["film collections"]
            rowSubtitle = "COLLECTION"
        case nil:
            collectionNames = ["film collections", "series universes"]
            rowSubtitle = "COLLECTION"
        }

        var rails: [GenreCatalog.LoadedBrowseRail] = []
        for cname in collectionNames {
            guard let collection = org.collections.first(where: {
                GenreCatalog.normalize($0.name) == cname
            }) else { continue }

            let folders = org.folders
                .filter { $0.collectionId == collection.id }
                .sorted { $0.sortOrder < $1.sortOrder }

            let isSeriesCollection = cname == "series universes"

            let bundleFolders: [DBFolder] = folders.filter { folder in
                if isSeriesCollection {
                    if let key {
                        return GenreCatalog.normalize(folder.genre ?? "") == key
                    }
                    return true
                }
                let n = GenreCatalog.normalize(folder.name)
                let words = n.split(separator: " ")
                if let key {
                    return words.first.map(String.init) == key
                }
                let first = words.first.map(String.init) ?? ""
                return !["collection", "collections", "franchise", "franchises", "universe", "universes"].contains(first)
            }

            guard !bundleFolders.isEmpty else { continue }

            // Film Collections: expand genre bundles to standalone franchise folders
            // via shared TMDB collection IDs. Series Universes: each folder is a
            // standalone franchise — no expansion needed.
            let targetFolders: [DBFolder] = {
                guard !isSeriesCollection else { return bundleFolders }
                let bundleIds = Set(bundleFolders.map(\.id))
                let memberCatalogIds = Set(
                    org.folderCatalogs
                        .filter { bundleIds.contains($0.folderId) && $0.catalogId.hasPrefix("tmdb.collection.") }
                        .map(\.catalogId)
                )
                if memberCatalogIds.isEmpty { return bundleFolders }
                let standalone = folders.filter { folder in
                    guard !bundleIds.contains(folder.id) else { return false }
                    return org.folderCatalogs.contains {
                        $0.folderId == folder.id && memberCatalogIds.contains($0.catalogId)
                    }
                }
                return standalone.isEmpty ? bundleFolders : standalone
            }()

            for folder in targetFolders {
                let catalogs = org.folderCatalogs.filter { $0.folderId == folder.id }
                let sources = org.folderSources.filter { $0.folderId == folder.id }
                guard !catalogs.isEmpty || !sources.isEmpty else { continue }

                let items = await fetchFolderItems(
                    normalizedSources: catalogs,
                    rawSources: sources,
                    fallbackURL: fallbackURL,
                    addons: addons,
                    skip: 0
                )
                let deduped = Self.deduplicated(items)
                if !deduped.isEmpty {
                    rails.append(GenreCatalog.LoadedBrowseRail(
                        id: "collection-\(folder.id)",
                        title: friendlyCollectionTitle(folder.name, genre: genre),
                        items: deduped,
                        subtitle: rowSubtitle
                    ))
                }
            }
        }
        return rails
    }

    private func friendlyCollectionTitle(_ name: String, genre: String?) -> String {
        var skip: Set<String> = [
            "collection", "collections", "franchise", "franchises",
            "universe", "universes",
        ]
        if let genre { skip.insert(GenreCatalog.normalize(genre)) }
        let words = GenreCatalog.normalize(name)
            .split(separator: " ")
            .filter { !skip.contains(String($0)) }
        guard !words.isEmpty else { return name }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// Resolves award-winner title ids → bundled award-body asset name, by fetching the
    /// Awards collection's winner lists. Bounded to a couple of sources per body to keep
    /// the background pass cheap.
    public func fetchAwardWinners(
        collectionRepo: CollectionRepository,
        addons: [AddonManifest]
    ) async -> [String: String] {
        guard let fallbackURL = addons.first(where: {
            $0.transportUrl?.contains("aiometadata") == true || $0.id.contains("aio")
        })?.transportUrl ?? addons.first?.transportUrl else { return [:] }

        var result: [String: String] = [:]
        for collection in collectionRepo.collections
        where GenreCatalog.normalize(collection.name) == "awards" {
            for folder in collectionRepo.folders(for: collection) {
                guard let asset = AwardIndex.assetName(forBody: folder.name) else { continue }
                let catalogs = Array(collectionRepo.catalogs(for: folder).prefix(2))
                let sources = Array(collectionRepo.sources(for: folder).prefix(2))
                guard !catalogs.isEmpty || !sources.isEmpty else { continue }
                let items = await fetchFolderItems(
                    normalizedSources: catalogs,
                    rawSources: sources,
                    fallbackURL: fallbackURL,
                    addons: addons,
                    skip: 0
                )
                for item in items where result[item.id] == nil {
                    result[item.id] = asset
                }
            }
        }
        return result
    }

    private func fetchFolderItems(
        normalizedSources: [DBFolderCatalog],
        rawSources: [DBFolderSource],
        fallbackURL: String,
        addons: [AddonManifest],
        skip: Int,
        sortByReleaseDate: Bool = false
    ) async -> [MetaPreview] {
        // Merge sources in submission order (deterministic) rather than completion
        // order, so the folder grid doesn't reshuffle between loads.
        var buckets: [Int: [MetaPreview]] = [:]
        await withTaskGroup(of: (Int, [MetaPreview]).self) { group in
            var sourceIndex = 0
            for source in normalizedSources {
                let sourceURL = addons.first(where: {
                    $0.catalogs?.contains(where: { $0.id == source.catalogId }) == true
                })?.transportUrl ?? fallbackURL
                let idx = sourceIndex; sourceIndex += 1
                group.addTask { (idx, await self.fetchNormalizedSource(source, baseURL: sourceURL, skip: skip)) }
            }
            for source in rawSources {
                let idx = sourceIndex; sourceIndex += 1
                group.addTask { (idx, await self.fetchRawSource(source, baseURL: fallbackURL, skip: skip)) }
            }
            for await (idx, result) in group { buckets[idx] = result }
        }
        let merged = Self.deduplicated(buckets.keys.sorted().flatMap { buckets[$0] ?? [] })
        return sortByReleaseDate ? Self.sortedByReleaseDateAscending(merged) : merged
    }

    /// Stable dedup by id, preserving first-seen order.
    /// When two items share the same id, the one with a non-empty release date wins,
    /// so that undated mdblist entries don't replace properly-dated trakt entries on
    /// the "Coming Soon" rails.
    nonisolated static func deduplicated(_ items: [MetaPreview]) -> [MetaPreview] {
        var result: [MetaPreview] = []
        for item in items {
            if let idx = result.firstIndex(where: { $0.id == item.id }) {
                let existingHasDate = !(result[idx].rawReleaseDate ?? "").isEmpty
                let newHasDate = !(item.rawReleaseDate ?? "").isEmpty
                if newHasDate && !existingHasDate {
                    result[idx] = item
                }
            } else {
                result.append(item)
            }
        }
        return result
    }

    /// Soonest release first; undated items last; ties keep source/merge order
    /// (e.g. mdblist before trakt). Used for the "Coming Soon" rails.
    nonisolated static func sortedByReleaseDateAscending(_ items: [MetaPreview]) -> [MetaPreview] {
        items.enumerated().sorted { lhs, rhs in
            let a = lhs.element.rawReleaseDate ?? ""
            let b = rhs.element.rawReleaseDate ?? ""
            if a.isEmpty != b.isEmpty { return !a.isEmpty }   // undated last
            if a != b { return a < b }                        // soonest first
            return lhs.offset < rhs.offset                    // tiebreak: source order
        }.map(\.element)
    }

    nonisolated static func filteredByMinimumVoteCount(_ items: [MetaPreview], min: Int) -> [MetaPreview] {
        items.filter { ($0.voteCount ?? 0) >= min }
    }

    /// Below this, a "trending" title is almost always a single-review or
    /// single-mention spike rather than genuine broad interest.
    private nonisolated static let trendingMinVoteCount = 20

    /// TMDB TV genres for daily-broadcast formats (news, talk, reality) — these
    /// rack up huge vote/episode counts just by airing every weekday, which lets
    /// them crowd out actual series in a "trending"/"popular" rail even though
    /// they're not the kind of show someone is browsing a streaming catalog for.
    private nonisolated static let nonScriptedGenres: Set<String> = ["News", "Talk", "Reality"]

    private nonisolated static func applyTitleBasedFilters(_ items: [MetaPreview], title: String) -> [MetaPreview] {
        var result = items
        if title.localizedCaseInsensitiveContains("coming soon") {
            result = sortedByReleaseDateAscending(result)
        }
        if title.localizedCaseInsensitiveContains("top rated") {
            result = result.sorted {
                let a = Double(($0.imdbRating ?? "").replacingOccurrences(of: "/10", with: "")) ?? 0
                let b = Double(($1.imdbRating ?? "").replacingOccurrences(of: "/10", with: "")) ?? 0
                return a > b
            }
        }
        if title.localizedCaseInsensitiveContains("trending") {
            // Only drop items where we actually know the vote count is low —
            // missing voteCount (some sources don't populate it) is left alone
            // rather than treated as a strike against the item.
            result = result.filter { ($0.voteCount ?? trendingMinVoteCount) >= trendingMinVoteCount }
            result = result.filter { item in
                !(item.genres ?? []).contains { nonScriptedGenres.contains($0) }
            }
        }
        return result
    }

    public func loadMore(rowId: String, addons: [AddonManifest]) async {
        guard let index = catalogRows.firstIndex(where: { $0.id == rowId }),
              catalogRows[index].hasMore else { return }

        let row = catalogRows[index]
        let nextPage = row.page + 1

        guard let addonId = row.addonId,
              let addon = addons.first(where: { $0.id == addonId }),
              let baseURL = addon.transportUrl else { return }

        let components = rowId.split(separator: "_").map(String.init)
        guard components.count >= 3 else { return }
        let catalogType = components[components.count - 2]
        let catalogId = components[components.count - 1]

        guard let catalog = addon.catalogs?.first(where: {
            $0.type == catalogType && $0.id == catalogId
        }) ?? addon.catalogs?.first(where: { $0.id == catalogId }) else { return }

        do {
            let query = CatalogService.StremioCatalogQuery(
                type: catalog.type,
                id: catalog.id,
                baseURL: baseURL,
                extras: ["skip": String(nextPage * 50)]
            )
            let fetchedItems = try await catalogService.fetchCatalog(query: query)
            let items = Self.applyingBetterPostersFallback(
                to: fetchedItems,
                addonName: addon.name,
                addonId: addon.id,
                baseURL: baseURL
            )
            if !items.isEmpty {
                catalogRows[index].items.append(contentsOf: items)
                catalogRows[index].page = nextPage
                catalogRows[index].hasMore = !items.isEmpty
            } else {
                catalogRows[index].hasMore = false
            }
        } catch {
            catalogRows[index].hasMore = false
        }
    }

    // MARK: - TMDB Collection Direct Fetch

    private func fetchTMDBCollectionItems(collectionId: Int) async -> [MetaPreview] {
        guard let apiKey = MetadataIntegrationStore.shared.effectiveTMDBAPIKey, !apiKey.isEmpty else { return [] }
        let tmdbBase = "https://api.themoviedb.org/3"
        guard let url = URL(string: "\(tmdbBase)/collection/\(collectionId)?api_key=\(apiKey)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(TMDBCollectionResponse.self, from: data) else { return [] }

        let parts = response.parts.map {
            CollectionPart(tmdbId: $0.id, title: $0.title ?? $0.originalTitle ?? "", releaseDate: $0.releaseDate)
        }
        let items = await Self.resolveCollectionParts(parts) { tmdbId in
            await TMDBDiscoverService.shared.resolveImdbId(tmdbId: tmdbId, kind: "movie", apiKey: apiKey)
        }
        TMDBDiscoverService.shared.persistCache()
        return items.sorted { ($0.rawReleaseDate ?? "") < ($1.rawReleaseDate ?? "") }
    }

    struct CollectionPart: Sendable {
        let tmdbId: Int
        let title: String
        let releaseDate: String?
    }

    /// Resolves collection parts to IMDB-keyed previews with bounded
    /// concurrency, preserving input order. Unbounded resolution (one in-flight
    /// request per movie across 27 concurrent franchise fetches) tripped TMDB
    /// rate limits and silently dropped whatever failed, so folders came up
    /// missing titles. Transient failures get one retry pass; parts with no
    /// usable IMDB id after that are dropped (nothing in the app can act on them).
    nonisolated static func resolveCollectionParts(
        _ parts: [CollectionPart],
        chunkSize: Int = 6,
        resolver: @escaping @Sendable (Int) async -> String?
    ) async -> [MetaPreview] {
        func resolvePass(_ pending: [(Int, CollectionPart)]) async -> (resolved: [Int: MetaPreview], failed: [(Int, CollectionPart)]) {
            var resolved: [Int: MetaPreview] = [:]
            var failed: [(Int, CollectionPart)] = []
            var index = 0
            while index < pending.count {
                let chunk = pending[index..<min(index + chunkSize, pending.count)]
                await withTaskGroup(of: (Int, CollectionPart, MetaPreview?).self) { group in
                    for (position, part) in chunk {
                        group.addTask {
                            guard let imdbId = await resolver(part.tmdbId), imdbId.hasPrefix("tt") else {
                                return (position, part, nil)
                            }
                            return (position, part, MetaPreview(
                                id: imdbId,
                                type: .movie,
                                name: part.title,
                                poster: PosterService.posterURL(forImdbId: imdbId),
                                releaseInfo: part.releaseDate.flatMap { String($0.prefix(4)) },
                                rawReleaseDate: part.releaseDate
                            ))
                        }
                    }
                    for await (position, part, preview) in group {
                        if let preview {
                            resolved[position] = preview
                        } else {
                            failed.append((position, part))
                        }
                    }
                }
                index += chunkSize
            }
            return (resolved, failed)
        }

        let indexed = Array(parts.enumerated().map { ($0.offset, $0.element) })
        let firstPass = await resolvePass(indexed)
        var resolved = firstPass.resolved
        if !firstPass.failed.isEmpty {
            let retryPass = await resolvePass(firstPass.failed.sorted { $0.0 < $1.0 })
            resolved.merge(retryPass.resolved) { current, _ in current }
        }
        return resolved.keys.sorted().compactMap { resolved[$0] }
    }
}

private struct TMDBCollectionResponse: Decodable {
    let parts: [TMDBCollectionPart]
}

private struct TMDBCollectionPart: Decodable {
    let id: Int
    let title: String?
    let originalTitle: String?
    let releaseDate: String?
    enum CodingKeys: String, CodingKey {
        case id, title
        case originalTitle = "original_title"
        case releaseDate = "release_date"
    }
}

private extension String {
    /// Returns the string itself when non-empty, or nil — so `??` fallback chains
    /// skip over empty-string placeholders (e.g. `"coverImageUrl": ""`).
    var nonEmpty: String? { isEmpty ? nil : self }
}
