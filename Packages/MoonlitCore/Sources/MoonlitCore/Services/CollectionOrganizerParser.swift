import Foundation

public struct OrganizedCollections: Sendable {
    public let collections: [DBCollection]
    public let folders: [DBFolder]
    public let folderCatalogs: [DBFolderCatalog]
    public let folderSources: [DBFolderSource]

    public init(
        collections: [DBCollection],
        folders: [DBFolder],
        folderCatalogs: [DBFolderCatalog],
        folderSources: [DBFolderSource]
    ) {
        self.collections = collections
        self.folders = folders
        self.folderCatalogs = folderCatalogs
        self.folderSources = folderSources
    }

    /// Merges a partial `overlay` layout (e.g. the cached/remote Supabase layout) on top of
    /// a complete `base` layout (the bundled JSON). Collections are joined by **name**
    /// because bundled IDs (`collection-…`) and Supabase IDs (UUIDs) never match.
    ///
    /// - On a name match, the overlay collection (and its subtree) WINS, so edits apply.
    /// - Base-only collections are preserved, so a partial overlay can't drop collections
    ///   that only exist in the bundle (Trending Shows, Asian Dramas, …).
    /// - Overlay-only collections are appended after the base order.
    public static func merged(
        base: OrganizedCollections,
        overlay: OrganizedCollections
    ) -> OrganizedCollections {
        func subtree(
            of collectionId: String,
            in org: OrganizedCollections
        ) -> ([DBFolder], [DBFolderCatalog], [DBFolderSource]) {
            let folders = org.folders.filter { $0.collectionId == collectionId }
            let folderIds = Set(folders.map(\.id))
            let catalogs = org.folderCatalogs.filter { folderIds.contains($0.folderId) }
            let sources = org.folderSources.filter { folderIds.contains($0.folderId) }
            return (folders, catalogs, sources)
        }

        var overlayByName: [String: DBCollection] = [:]
        for c in overlay.collections where overlayByName[c.name] == nil { overlayByName[c.name] = c }

        var collections: [DBCollection] = []
        var folders: [DBFolder] = []
        var folderCatalogs: [DBFolderCatalog] = []
        var folderSources: [DBFolderSource] = []
        var usedOverlayNames = Set<String>()

        func append(_ collection: DBCollection, from org: OrganizedCollections) {
            let (f, c, s) = subtree(of: collection.id, in: org)
            collections.append(collection)
            folders.append(contentsOf: f)
            folderCatalogs.append(contentsOf: c)
            folderSources.append(contentsOf: s)
        }

        for baseCollection in base.collections {
            if let overlayCollection = overlayByName[baseCollection.name] {
                usedOverlayNames.insert(baseCollection.name)
                // Score = folderCount × 1000 + total source/catalog entries.
                // Overlay wins on equal score so portal edits still apply once the DB
                // is fully populated; but an overlay with the same folder count but
                // fewer sources (stale Supabase export) loses to the richer bundle.
                let baseFolders    = base.folders.filter { $0.collectionId == baseCollection.id }
                let overlayFolders = overlay.folders.filter { $0.collectionId == overlayCollection.id }
                let baseFolderIds    = Set(baseFolders.map(\.id))
                let overlayFolderIds = Set(overlayFolders.map(\.id))
                let baseSources    = base.folderCatalogs.filter { baseFolderIds.contains($0.folderId) }.count
                                   + base.folderSources.filter { baseFolderIds.contains($0.folderId) }.count
                let overlaySources = overlay.folderCatalogs.filter { overlayFolderIds.contains($0.folderId) }.count
                                   + overlay.folderSources.filter { overlayFolderIds.contains($0.folderId) }.count
                let baseScore    = baseFolders.count * 1000 + baseSources
                let overlayScore = overlayFolders.count * 1000 + overlaySources
                if overlayScore >= baseScore {
                    append(overlayCollection, from: overlay)
                } else {
                    append(baseCollection, from: base)
                }
            } else {
                append(baseCollection, from: base)
            }
        }
        for overlayCollection in overlay.collections
        where !usedOverlayNames.contains(overlayCollection.name) {
            usedOverlayNames.insert(overlayCollection.name)
            append(overlayCollection, from: overlay)
        }

        return OrganizedCollections(
            collections: collections,
            folders: folders,
            folderCatalogs: folderCatalogs,
            folderSources: folderSources
        )
    }
}

public enum CollectionOrganizerParser {
    public static func parse(jsonData: Data) throws -> OrganizedCollections {
        if let nuvio = try? JSONDecoder().decode([NuvioCollection].self, from: jsonData) {
            return mapNuvio(nuvio)
        }
        let best = try JSONDecoder().decode(BESTPack.self, from: jsonData)
        return mapBEST(best)
    }

    private static func mapNuvio(_ input: [NuvioCollection]) -> OrganizedCollections {
        var collections: [DBCollection] = []
        var folders: [DBFolder] = []
        var folderCatalogs: [DBFolderCatalog] = []
        var folderSources: [DBFolderSource] = []
        var seenCollectionIds = Set<String>()
        var seenFolderIds = Set<String>()
        var sortOrder = 0

        for collection in input {
            guard !seenCollectionIds.contains(collection.id) else { continue }
            seenCollectionIds.insert(collection.id)

            var mappedFolders: [DBFolder] = []
            var mappedFolderCatalogs: [DBFolderCatalog] = []
            var mappedFolderSources: [DBFolderSource] = []

            for (folderIndex, folder) in collection.folders.enumerated() {
                guard !seenFolderIds.contains(folder.id) else { continue }

                var folderCatalogsForFolder: [DBFolderCatalog] = []
                var folderSourcesForFolder: [DBFolderSource] = []
                var seenCatalogIdsForFolder = Set<String>()
                for (sourceIndex, source) in folder.sources.enumerated() {
                    appendSource(
                        source,
                        folderId: folder.id,
                        index: sourceIndex,
                        seenCatalogIds: &seenCatalogIdsForFolder,
                        folderCatalogs: &folderCatalogsForFolder,
                        folderSources: &folderSourcesForFolder
                    )
                }

                guard !folderCatalogsForFolder.isEmpty || !folderSourcesForFolder.isEmpty else { continue }
                seenFolderIds.insert(folder.id)

                mappedFolders.append(DBFolder(
                    id: folder.id,
                    collectionId: collection.id,
                    name: folder.title,
                    sortOrder: folderIndex,
                    coverImage: folder.coverImageUrl,
                    focusGif: folder.focusGifUrl,
                    titleLogo: folder.titleLogoUrl,
                    heroBackdrop: folder.heroBackdropUrl,
                    heroVideoUrl: folder.heroVideoUrl,
                    hideTitle: folder.hideTitle,
                    tileShape: normalizeShape(folder.tileShape),
                    focusGifEnabled: folder.focusGifEnabled
                ))

                mappedFolderCatalogs.append(contentsOf: folderCatalogsForFolder)
                mappedFolderSources.append(contentsOf: folderSourcesForFolder)
            }

            guard !mappedFolders.isEmpty else { continue }

            collections.append(DBCollection(
                id: collection.id,
                name: collection.title,
                sortOrder: sortOrder,
                backdropImage: collection.backdropImageUrl,
                viewMode: collection.viewMode,
                showAllTab: collection.showAllTab,
                focusGlowEnabled: false,
                pinToTop: collection.pinToTop
            ))
            sortOrder += 1
            folders.append(contentsOf: mappedFolders)
            folderCatalogs.append(contentsOf: mappedFolderCatalogs)
            folderSources.append(contentsOf: mappedFolderSources)
        }

        return OrganizedCollections(
            collections: collections,
            folders: folders,
            folderCatalogs: folderCatalogs,
            folderSources: folderSources
        )
    }

    private static func mapBEST(_ input: BESTPack) -> OrganizedCollections {
        let collections = input.collections.map {
            DBCollection(
                id: $0.sourceKey,
                name: $0.name,
                sortOrder: $0.sortOrder,
                backdropImage: $0.backdropImage,
                viewMode: $0.viewMode,
                showAllTab: $0.showAllTab,
                focusGlowEnabled: false,
                pinToTop: $0.pinToTop
            )
        }
        let folders = input.folders.map {
            DBFolder(
                id: $0.sourceKey,
                collectionId: $0.collectionSourceKey,
                name: $0.name,
                sortOrder: $0.sortOrder,
                coverImage: $0.coverImage,
                focusGif: $0.focusGif,
                titleLogo: $0.titleLogo,
                heroBackdrop: $0.heroBackdrop,
                heroVideoUrl: $0.heroVideoUrl,
                hideTitle: $0.hideTitle,
                tileShape: normalizeShape($0.tileShape),
                focusGifEnabled: $0.focusGifEnabled
            )
        }
        let folderCatalogs = input.folderCatalogs.map {
            DBFolderCatalog(
                id: "\($0.folderSourceKey)-\($0.catalogId)-\($0.mediaType)",
                folderId: $0.folderSourceKey,
                catalogId: $0.catalogId,
                mediaType: $0.mediaType,
                genre: normalizeGenre($0.genre)
            )
        }

        return OrganizedCollections(
            collections: collections,
            folders: folders,
            folderCatalogs: folderCatalogs,
            folderSources: []
        )
    }

    private static func appendSource(
        _ source: NuvioSource,
        folderId: String,
        index: Int,
        seenCatalogIds: inout Set<String>,
        folderCatalogs: inout [DBFolderCatalog],
        folderSources: inout [DBFolderSource]
    ) {
        // Resolve catalogId: explicit OR synthesized from non-standard fields.
        // traktListId → "trakt.list.ID"
        // tmdb COLLECTION → "tmdb.ID" (AIOMetadata collection lookup)
        // tmdb DISCOVER + releaseDateGte → "tmdb.discover.<type>.decades.<decade>s"
        //   e.g. releaseDateGte "2020-01-01" → tmdb.discover.movie.decades.2020s
        let effectiveCatalogId: String
        let normalizedMediaType = normalizeMediaType(source.type ?? source.mediaType)
        let isDiscoverSource = source.tmdbSourceType?.uppercased() == "DISCOVER"
        let tmdbInt = source.tmdbId.flatMap(Int.init)
        let hasConcreteTMDBId = (tmdbInt ?? 0) > 0

        if let cid = source.catalogId {
            effectiveCatalogId = cid
        } else if let tid = source.traktListId {
            effectiveCatalogId = "trakt.list.\(tid)"
        } else if let mid = source.tmdbId, source.tmdbSourceType?.uppercased() == "COLLECTION" {
            effectiveCatalogId = "tmdb.collection.\(mid)"
        } else if isDiscoverSource, !hasConcreteTMDBId,
                  let discoverId = discoverCatalogId(for: source, mediaType: normalizedMediaType) {
            effectiveCatalogId = discoverId
        } else if isDiscoverSource,
                  let dateGte = source.filters?.releaseDateGte,
                  let year = Int(dateGte.prefix(4)) {
            // Multiple DISCOVER sources within one folder often share the same decade.
            // Synthesise one catalog entry per (folder, decade, mediaType) — duplicates skipped below.
            let decade = (year / 10) * 10
            effectiveCatalogId = "tmdb.discover.\(normalizedMediaType).decades.\(decade)s"
        } else {
            return
        }

        // Deduplicate within the same folder so multiple DISCOVER sources that resolve to
        // the same decade catalog don't create redundant rows.
        let dedupeKey = "\(folderId):\(effectiveCatalogId)"
        guard seenCatalogIds.insert(dedupeKey).inserted else { return }

        let mediaType = normalizedMediaType
        let provider = source.provider?.lowercased()
        // Non-standard sources synthesize an addon-compatible catalogId, so treat as addon.
        let isAddon = provider == nil || provider == "addon" || source.traktListId != nil || source.tmdbId != nil || (isDiscoverSource && !hasConcreteTMDBId)

        if isAddon {
            // Build extras from DISCOVER filters so year-range queries work correctly.
            var catalogExtras: [String: String]? = nil
            if let f = source.filters {
                var ex: [String: String] = [:]
                if let v = f.releaseDateGte { ex["primary_release_date.gte"] = v }
                if let v = f.releaseDateLte { ex["primary_release_date.lte"] = v }
                if let v = f.voteCountGte, v > 0 { ex["vote_count.gte"] = String(v) }
                if let v = f.voteAverageGte, v > 0 { ex["vote_average.gte"] = trimNumber(v) }
                if let v = f.withOriginalLanguage { ex["with_original_language"] = v }
                if let v = f.year, v > 0 { ex["year"] = String(v) }
                if let v = source.sortBy { ex["sort_by"] = v }
                if !ex.isEmpty { catalogExtras = ex }
            }
            let genre = normalizeGenre(source.genre) ?? genreName(for: source.filters?.withGenres, mediaType: mediaType)
            folderCatalogs.append(DBFolderCatalog(
                id: "\(folderId)-\(effectiveCatalogId)-\(mediaType)-\(index)",
                folderId: folderId,
                catalogId: effectiveCatalogId,
                mediaType: mediaType,
                genre: genre,
                extras: catalogExtras
            ))
            return
        }

        let resolved = resolveRawSource(provider: provider ?? "", catalogId: effectiveCatalogId, mediaType: source.type)
        folderSources.append(DBFolderSource(
            id: "\(folderId)-\(effectiveCatalogId)-\(index)",
            folderId: folderId,
            provider: resolved.provider,
            title: nil,
            tmdbId: resolved.tmdbId,
            mediaType: mediaType,
            tmdbSourceType: resolved.tmdbSourceType,
            sortBy: source.sortBy,
            sortOrder: index
        ))
    }

    private static func discoverCatalogId(for source: NuvioSource, mediaType: String) -> String? {
        let title = (source.title ?? "").lowercased()
        switch (mediaType, title) {
        case ("movie", "new movies"): return "tmdb.discover.movie.new-movies.069d5312"
        case ("movie", "popular movies"): return "tmdb.discover.movie.popular-movies.29727d26"
        case ("movie", "top all time movies"): return "tmdb.discover.movie.top-all-time-movies.39f5a0c4"
        case ("movie", "top of the year movies"): return "tmdb.discover.movie.top-of-the-year-movies.870b3ada"
        case ("movie", "anime movies"): return "tmdb.discover.movie.anime-movies.8caaddea"
        case ("movie", "top anime movies"): return "tmdb.discover.movie.top-anime-movies.ef410dcc"
        case ("movie", "upcoming anime movies"): return "tmdb.discover.movie.upcoming-anime-movies.e57db259"
        case ("series", "new series"): return "tmdb.discover.series.new-series.76fc7ade"
        case ("series", "popular series"): return "tmdb.discover.series.popular-series.20af3ad9"
        case ("series", "top all time series"): return "tmdb.discover.series.top-all-time-series.53046f30"
        case ("series", "top of the year series"): return "tmdb.discover.series.top-of-the-year-series.f0fd20b7"
        case ("series", "anime series"): return "tmdb.discover.series.anime-series.193e8308"
        case ("series", "top anime series"): return "tmdb.discover.series.top-anime-series.63ff4f07"
        case ("series", "upcoming anime series"): return "tmdb.discover.series.upcoming-anime-series.e71e22cf"
        default:
            return nil
        }
    }

    private static func genreName(for tmdbGenreId: String?, mediaType: String) -> String? {
        guard let tmdbGenreId else { return nil }
        let firstGenreId = tmdbGenreId
            .split(separator: ",")
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? tmdbGenreId
        if mediaType == "series" {
            return [
                "10759": "Action & Adventure",
                "16": "Animation",
                "35": "Comedy",
                "80": "Crime",
                "99": "Documentary",
                "18": "Drama",
                "10751": "Family",
                "10762": "Kids",
                "9648": "Mystery",
                "10763": "News",
                "10764": "Reality",
                "10765": "Sci-Fi & Fantasy",
                "10766": "Soap",
                "10767": "Talk",
                "10768": "War & Politics",
                "37": "Western"
            ][firstGenreId]
        }
        return [
            "28": "Action",
            "12": "Adventure",
            "16": "Animation",
            "35": "Comedy",
            "80": "Crime",
            "99": "Documentary",
            "18": "Drama",
            "10751": "Family",
            "14": "Fantasy",
            "36": "History",
            "27": "Horror",
            "10402": "Music",
            "9648": "Mystery",
            "10749": "Romance",
            "878": "Science Fiction",
            "10770": "TV Movie",
            "53": "Thriller",
            "10752": "War",
            "37": "Western"
        ][firstGenreId]
    }

    private static func trimNumber(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    private static func normalizeMediaType(_ value: String?) -> String {
        switch value?.uppercased() {
        case "TV", "SERIES": return "series"
        case "MOVIE": return "movie"
        default: return value?.lowercased() ?? "movie"
        }
    }

    private static func resolveRawSource(provider: String, catalogId: String, mediaType: String?) -> (provider: String, tmdbId: String?, tmdbSourceType: String?) {
        if catalogId.hasPrefix("tmdb.discover.") {
            let parts = catalogId.split(separator: ".").map(String.init)
            return ("tmdb", parts.last, "discover")
        }
        if catalogId.hasPrefix("tmdb.") {
            return ("tmdb", String(catalogId.dropFirst("tmdb.".count)), nil)
        }
        if catalogId.hasPrefix("trakt.list.") {
            return ("trakt", String(catalogId.dropFirst("trakt.list.".count)), nil)
        }
        if catalogId.hasPrefix("mdblist.") {
            return ("mdblist", String(catalogId.dropFirst("mdblist.".count)), nil)
        }
        if catalogId.hasPrefix("tvdb.discover.") {
            return ("tvdb", catalogId.split(separator: ".").last.map(String.init), "discover")
        }
        return (provider, catalogId, nil)
    }

    private static func normalizeShape(_ value: String?) -> String? {
        switch value?.lowercased() {
        case "poster": "poster"
        case "landscape": "landscape"
        case "square": "square"
        default: nil
        }
    }

    private static func normalizeGenre(_ value: String?) -> String? {
        guard let value, value.lowercased() != "none" else { return nil }
        return value
    }
}

private struct NuvioCollection: Decodable {
    let id: String
    let title: String
    let folders: [NuvioFolder]
    let pinToTop: Bool?
    let viewMode: String?
    let showAllTab: Bool?
    let backdropImageUrl: String?
    let focusGlowEnabled: Bool?
}

private struct NuvioFolder: Decodable {
    let id: String
    let title: String
    let sources: [NuvioSource]
    let hideTitle: Bool?
    let tileShape: String?
    let focusGifUrl: String?
    let heroVideoUrl: String?
    let titleLogoUrl: String?
    let coverImageUrl: String?
    let focusGifEnabled: Bool?
    let heroBackdropUrl: String?
}

private struct NuvioSource: Decodable {
    let title: String?
    let type: String?
    let genre: String?
    let provider: String?
    let catalogId: String?
    let mediaType: String?
    let traktListId: Int?
    let tmdbId: String?           // non-standard tmdb format (may be Int or String)
    let tmdbSourceType: String?
    let sortBy: String?
    let filters: NuvioDiscoverFilters?

    enum CodingKeys: String, CodingKey {
        case title, type, genre, provider, catalogId, mediaType
        case traktListId, tmdbId, tmdbSourceType, sortBy, filters
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        genre = try c.decodeIfPresent(String.self, forKey: .genre)
        provider = try c.decodeIfPresent(String.self, forKey: .provider)
        catalogId = try c.decodeIfPresent(String.self, forKey: .catalogId)
        mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType)
        traktListId = try c.decodeIfPresent(Int.self, forKey: .traktListId)
        if let intVal = try? c.decode(Int.self, forKey: .tmdbId) {
            tmdbId = "\(intVal)"
        } else {
            tmdbId = try c.decodeIfPresent(String.self, forKey: .tmdbId)
        }
        tmdbSourceType = try c.decodeIfPresent(String.self, forKey: .tmdbSourceType)
        sortBy = try c.decodeIfPresent(String.self, forKey: .sortBy)
        filters = try c.decodeIfPresent(NuvioDiscoverFilters.self, forKey: .filters)
    }
}

private struct NuvioDiscoverFilters: Decodable {
    let releaseDateGte: String?
    let releaseDateLte: String?
    let voteCountGte: Int?
    let voteAverageGte: Double?
    let withGenres: String?
    let withKeywords: String?
    let withOriginalLanguage: String?
    let year: Int?
}

private struct BESTPack: Decodable {
    let collections: [BESTCollection]
    let folders: [BESTFolder]
    let folderCatalogs: [BESTFolderCatalog]

    enum CodingKeys: String, CodingKey {
        case collections, folders
        case folderCatalogs = "folder_catalogs"
    }
}

private struct BESTCollection: Decodable {
    let sourceKey: String
    let sortOrder: Int
    let name: String
    let viewMode: String?
    let showAllTab: Bool?
    let focusGlowEnabled: Bool?
    let pinToTop: Bool?
    let backdropImage: String?

    enum CodingKeys: String, CodingKey {
        case name
        case sourceKey = "source_key"
        case sortOrder = "sort_order"
        case viewMode = "view_mode"
        case showAllTab = "show_all_tab"
        case focusGlowEnabled = "focus_glow_enabled"
        case pinToTop = "pin_to_top"
        case backdropImage = "backdrop_image"
    }
}

private struct BESTFolder: Decodable {
    let sourceKey: String
    let collectionSourceKey: String
    let sortOrder: Int
    let name: String
    let coverImage: String?
    let focusGif: String?
    let titleLogo: String?
    let heroBackdrop: String?
    let heroVideoUrl: String?
    let hideTitle: Bool?
    let tileShape: String?
    let focusGifEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case sourceKey = "source_key"
        case collectionSourceKey = "collection_source_key"
        case sortOrder = "sort_order"
        case coverImage = "cover_image"
        case focusGif = "focus_gif"
        case titleLogo = "title_logo"
        case heroBackdrop = "hero_backdrop"
        case heroVideoUrl = "hero_video_url"
        case hideTitle = "hide_title"
        case tileShape = "tile_shape"
        case focusGifEnabled = "focus_gif_enabled"
    }
}

private struct BESTFolderCatalog: Decodable {
    let folderSourceKey: String
    let catalogId: String
    let mediaType: String
    let genre: String?

    enum CodingKeys: String, CodingKey {
        case genre
        case folderSourceKey = "folder_source_key"
        case catalogId = "catalog_id"
        case mediaType = "media_type"
    }
}
