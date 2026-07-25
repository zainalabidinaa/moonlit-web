import Foundation

/// Aggregates the many genre-related collections (a `Genres` browse collection,
/// `<Genre> Collections` franchise bundles inside `Film Collections`, and themed
/// collections like `Horror Franchises` / `International Horror`) into a single,
/// sectioned "genre hub" — driven entirely by collection naming so authoring a new
/// `Horror Decades` collection automatically appears under Horror.
///
/// This is pure logic over an `OrganizedCollections` snapshot so it stays unit-testable
/// and off the `@MainActor`.
public enum GenreCatalog {

    public struct Genre: Sendable, Identifiable, Hashable {
        public let id: String      // normalized key, e.g. "sci-fi"
        public let name: String    // display name, e.g. "Sci-Fi"
    }

    /// A row of folder tiles inside a genre hub (e.g. "Franchises" → [Halloween, Scream]).
    public struct Section: Sendable, Identifiable {
        public let id: String
        public let title: String
        public let folders: [DBFolder]
    }

    /// A merged browse rail (e.g. "New" = New Movies + New Series for this genre).
    public struct BrowseRail: Sendable, Identifiable {
        public let id: String
        public let title: String
        public let catalogs: [DBFolderCatalog]
        public let sources: [DBFolderSource]
    }

    /// A browse rail with its items resolved, ready to render.
    public struct LoadedBrowseRail: Sendable, Identifiable, Codable {
        public let id: String
        public let title: String
        public let items: [MetaPreview]
        public let subtitle: String?

        public init(id: String, title: String, items: [MetaPreview], subtitle: String? = nil) {
            self.id = id
            self.title = title
            self.items = items
            self.subtitle = subtitle
        }
    }

    /// Everything a genre hub renders: sectioned folder tiles + loaded browse rails.
    public struct HubContent: Sendable {
        public let sections: [Section]
        public let browse: [LoadedBrowseRail]
        public let collectionRails: [LoadedBrowseRail]

        public init(sections: [Section], browse: [LoadedBrowseRail], collectionRails: [LoadedBrowseRail] = []) {
            self.sections = sections
            self.browse = browse
            self.collectionRails = collectionRails
        }
    }

    /// Genres we always want to offer, even when the profile has no browse folder for them
    /// (Crime, for instance, has franchise collections but no `Genres` row).
    public static let canonicalGenres = [
        "Action", "Adventure", "Animation", "Comedy", "Crime", "Documentary",
        "Drama", "Family", "Fantasy", "Horror", "Mystery", "Romance",
        "Sci-Fi", "Thriller", "War", "Western"
    ]

    // MARK: - Genre list

    public static func genres(in org: OrganizedCollections) -> [Genre] {
        // Genre names come from every "Genres" browse collection's folders.
        var names = org.collections
            .filter { normalize($0.name) == "genres" }
            .flatMap { folders(of: $0, in: org) }
            .map(\.name)
        if names.isEmpty { names = canonicalGenres }
        // Crime is wanted even when it lacks a browse row.
        if !names.contains(where: { normalize($0) == "crime" }) {
            names.append("Crime")
        }
        var seen = Set<String>()
        return names.compactMap { name in
            let key = normalize(name)
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return Genre(id: key, name: name)
        }
    }

    // MARK: - Sections

    public static func sections(for genre: String, in org: OrganizedCollections) -> [Section] {
        let key = normalize(genre)
        var sections: [Section] = []

        // 1) Themed top-level collections whose name contains the genre as a
        //    standalone word — not a substring — so "Action" doesn't bleed
        //    into collections named "Reaction Films" or mixed-genre collections.
        for collection in org.collections.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let cname = normalize(collection.name)
            guard cname != "genres", cname != "film collections" else { continue }
            guard genreIsStandaloneWord(in: cname, key: key) else { continue }
            let folders = folders(of: collection, in: org)
            guard !folders.isEmpty else { continue }
            sections.append(Section(
                id: "section-\(key)-\(cname)",
                title: friendlyLabel(collection.name, genre: genre),
                folders: folders
            ))
        }

        // 2) Film-collection franchise content is now fetched directly in
        //    CatalogRepository.loadGenreHub as media rows instead of folder tiles.

        return sections.sorted { sectionOrder($0.title) < sectionOrder($1.title) }
    }

    /// Checks whether `key` appears as a standalone word in `name`.
    /// e.g. key="horror" matches "horror collections" but not "action horror collections"
    /// or "reaction films".
    private static func genreIsStandaloneWord(in name: String, key: String) -> Bool {
        let words = name.split(separator: " ")
        return words.contains(where: { $0 == key })
    }

    // MARK: - Browse rails

    public static func browseRails(for genre: String, in org: OrganizedCollections) -> [BrowseRail] {
        let key = normalize(genre)
        // Browse catalogs live in the "Genres" collection(s); the parser turns each
        // "New Movies"/"Popular Series"/… source into a discover catalog whose id encodes
        // the category (e.g. "tmdb.discover.movie.new-movies.<hash>").
        let genreCollectionIds = Set(
            org.collections.filter { normalize($0.name) == "genres" }.map(\.id)
        )
        let categoryCollectionIds = Set(
            org.collections.filter { normalize($0.name) == "categories" }.map(\.id)
        )
        let folderIds = Set(
            org.folders
                .filter {
                    (genreCollectionIds.contains($0.collectionId) || categoryCollectionIds.contains($0.collectionId))
                        && normalize($0.name) == key
                }
                .map(\.id)
        )
        guard !folderIds.isEmpty else { return [] }

        let catalogs = org.folderCatalogs.filter { folderIds.contains($0.folderId) }

        // Merge the movie + series catalog of each category into one rail, in canonical order.
        var order: [String] = []
        var buckets: [String: [DBFolderCatalog]] = [:]
        var leftover: [DBFolderCatalog] = []
        for catalog in catalogs {
            guard let category = browseCategory(forCatalogId: catalog.catalogId) else {
                leftover.append(catalog)
                continue
            }
            if buckets[category] == nil { order.append(category) }
            buckets[category, default: []].append(catalog)
        }

        var rails = order
            .sorted { browseOrder($0) < browseOrder($1) }
            .map { category in
                BrowseRail(
                    id: "browse-\(key)-\(normalize(category))",
                    title: category,
                    catalogs: buckets[category] ?? [],
                    sources: []
                )
            }

        // A curated source is editorial content in its own right. Combining every
        // remaining source into one anonymous "Browse" row loses that editorial
        // intent (for example Attenborough, BFI 100 Best Thrillers, or Jackie Chan).
        // Keep each source as an individually titled rail, in organizer order.
        for catalog in leftover {
            rails.append(BrowseRail(
                id: "browse-\(key)-\(catalog.id)",
                title: curatedTitle(for: catalog.catalogId),
                catalogs: [catalog],
                sources: []
            ))
        }
        return rails
    }

    // MARK: - Helpers

    /// Browse-rail category from a synthesized discover catalog id, e.g.
    /// "tmdb.discover.movie.new-movies.069d5312" → "New". Returns nil for genre/decade/anime
    /// discover catalogs so only New / Popular / Top rails surface.
    private static func browseCategory(forCatalogId id: String) -> String? {
        let parts = id.split(separator: ".")
        guard parts.count >= 4, parts[0] == "tmdb", parts[1] == "discover",
              parts[2] == "movie" || parts[2] == "series" else { return nil }
        var slug = String(parts[3])
        for suffix in ["-movies", "-series", "-shows"] {
            if slug.hasSuffix(suffix) { slug = String(slug.dropLast(suffix.count)); break }
        }
        switch slug {
        case "new": return "New"
        case "popular": return "Popular"
        case "top-all-time": return "Top of all time"
        case "top-of-the-year": return "Top of the year"
        default: return nil
        }
    }

    /// Display names for imported AIOMetadata catalogs whose layout source omits
    /// a title. New organizer sources keep their own title upstream; this fallback
    /// prevents the existing library of list IDs from becoming anonymous rails.
    private static func curatedTitle(for catalogId: String) -> String {
        let titles: [String: String] = [
            "mdblist.128037": "New Action Releases",
            "mdblist.2407": "Top Action Movies",
            "trakt.list.11255166": "Action Movies (2000–2020)",
            "trakt.list.825738": "Action Comedy",
            "trakt.list.4973644": "100 Best Action Movies",
            "trakt.list.22847039": "IMDb’s Top Animation Movies",
            "trakt.list.24484523": "IMDb’s Popular Family Animation",
            "mdblist.121922": "Popular Animation Movies",
            "mdblist.121921": "Popular Animation Series",
            "trakt.list.1522155": "Pixar Animation Studios",
            "trakt.list.1580797": "DreamWorks Animation",
            "trakt.list.23334961": "Sony Pictures Animation",
            "trakt.list.3899489": "Hidden Animation Gems",
            "trakt.list.837518": "Warner Bros. Animation",
            "trakt.list.5707382": "100 Anime to Watch Before You Die",
            "trakt.list.23438792": "100 Best Anime Movies of All Time",
            "trakt.list.5040627": "Time Out 100 Best Comedy Movies",
            "trakt.list.9659389": "Best of British Comedy TV Shows",
            "mdblist.2195": "Top Comedy Movies",
            "mdblist.3122": "Comedy Series",
            "mdblist.128040": "New Releases in Comedy",
            "trakt.list.22097600": "Top 100 TV Comedy Shows",
            "trakt.list.10235726": "Rotten Tomatoes’ 100 Best Documentaries",
            "trakt.list.801580": "Documentary Blog’s Top 50 of the Decade",
            "trakt.list.33762909": "Professor Brian Cox",
            "trakt.list.1799417": "True Crime Documentaries",
            "trakt.list.6652940": "History Documentaries",
            "trakt.list.25298201": "BBC Wildlife & Nature Documentaries",
            "trakt.list.2565470": "Hacking & Programming Documentaries",
            "trakt.list.23020633": "Space Documentaries",
            "trakt.list.19556363": "War Documentaries",
            "trakt.list.6652017": "Attenborough Documentaries",
            "trakt.list.26957348": "IMDb: Popular Nature Documentaries",
            "trakt.list.23440324": "BBC Earth — Life on Our Planet",
            "mdblist.84487": "Top Nature Shows",
            "trakt.list.3813071": "Astronomy and Cosmology",
            "trakt.list.21840363": "Martial Arts: Top 250",
            "trakt.list.6674425": "Hollywood Martial Arts",
            "trakt.list.4467615": "Bruce Lee",
            "trakt.list.11632332": "Jackie Chan",
            "trakt.list.4974101": "100 Best Musicals",
            "trakt.list.2619099": "Popular Musicals",
            "trakt.list.22803128": "BFI 100 Best Thrillers",
            "trakt.list.22096238": "Top 200 Psychological Thrillers",
            "trakt.list.19594387": "Murder Mystery Movies",
            "trakt.list.5221223": "Mystery: 1,000 Titles",
            "trakt.list.797798": "100 Greatest Sci‑Fi Movies",
            "trakt.list.4433767": "Best War Movies Ever Made",
            "trakt.list.21899611": "Spaghetti Westerns",
            "trakt.list.22847467": "IMDb’s Top Western Movies",
            "trakt.list.20701912": "Rotten Tomatoes’ Top 100 Romance Movies",
            "trakt.list.21033097": "Mega Erotic",
            "trakt.list.4203408": "Rotten Tomatoes: Best Horror Movies",
            "trakt.list.21193458": "Popular Horror",
            "mdblist.2410": "Top Horror Movies",
            "mdblist.128045": "New Horror Releases",
            "mdblist.3124": "Horror Series",
            "trakt.list.2067889": "Best Slasher Flicks",
            "trakt.list.22535146": "Hidden Horror Gems",
            "trakt.list.10563394": "Classic Horror",
            "trakt.list.23423498": "Comedy Horror",
            "trakt.list.1076151": "British Crime & Drama",
            "trakt.list.21715794": "Courtroom Dramas",
            "trakt.list.22957181": "Period Drama Movies",
            "trakt.list.20580022": "Rotten Tomatoes: Top Kids & Family Movies",
        ]
        return titles[catalogId] ?? "Curated Collection"
    }

    private static func folders(of collection: DBCollection, in org: OrganizedCollections) -> [DBFolder] {
        org.folders
            .filter { $0.collectionId == collection.id }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private static func friendlyLabel(_ collectionName: String, genre: String) -> String {
        let rest = normalize(collectionName)
            .replacingOccurrences(of: normalize(genre), with: " ")
            .replacingOccurrences(of: "&", with: " and ")
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        switch rest {
        case "genre", "genres": return "Sub-genres"
        case "franchise", "franchises": return "Franchises"
        case "decade", "decades": return "Decades"
        case "mood and vibe", "mood vibe", "vibe": return "Mood & Vibe"
        case "": return "Collections"
        default: return titleCased(rest)
        }
    }

    private static func sectionOrder(_ title: String) -> Int {
        ["Sub-genres", "Collections", "Franchises", "International", "Mood & Vibe", "Decades"]
            .firstIndex(of: title) ?? 50
    }

    private static func browseOrder(_ title: String) -> Int {
        ["New", "Popular", "Top of all time", "Top of the year"]
            .firstIndex(of: title) ?? 50
    }

    private static func titleCased(_ s: String) -> String {
        s.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Lowercased, format-mark-stripped, whitespace-collapsed key for matching.
    public static func normalize(_ s: String) -> String {
        let cleaned = s
            .replacingOccurrences(of: "\u{200E}", with: "")
            .replacingOccurrences(of: "\u{200F}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .lowercased()
        return cleaned
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

public extension GenreCatalog.Section {
    /// Folder tiles for this section, as a row `MediaCard`/`ContentCard` can render.
    /// Tapping a tile opens the existing folder view, which fetches on demand.
    func asRow() -> CatalogRow {
        func present(_ s: String?) -> String? { (s?.isEmpty == false) ? s : nil }
        let tiles = folders.map { folder -> MetaPreview in
            let cover = present(folder.coverImage) ?? present(folder.heroBackdrop) ?? present(folder.titleLogo)
            return MetaPreview(
                id: "folder_\(folder.id)",
                type: .movie,
                name: folder.name,
                poster: cover,
                banner: present(folder.coverImage) ?? present(folder.heroBackdrop),
                logo: folder.titleLogo,
                posterShape: PosterShape(rawValue: folder.tileShape ?? "") ?? .landscape,
                backdrop: present(folder.heroBackdrop)
            )
        }
        return CatalogRow(
            id: "section_\(id)",
            title: title,
            items: tiles,
            tileShape: folders.first?.tileShape ?? "landscape"
        )
    }
}

public extension CollectionRepository {
    /// A snapshot of the current layout for genre aggregation.
    var organized: OrganizedCollections {
        OrganizedCollections(
            collections: collections,
            folders: folders,
            folderCatalogs: folderCatalogs,
            folderSources: folderSources
        )
    }

    /// If a home folder-tile row id maps to a folder in the named "Genres" browse
    /// collection, returns the genre name so the tile can open the genre hub.
    func genreName(forFolderRowId rowId: String) -> String? {
        let fid = rowId.hasPrefix("folder_") ? String(rowId.dropFirst("folder_".count)) : rowId
        guard let folder = folders.first(where: { $0.id == fid }),
              let collection = collections.first(where: { $0.id == folder.collectionId }),
              GenreCatalog.normalize(collection.name) == "genres"
        else { return nil }
        return folder.name
    }

    /// If a folder tile belongs to the named "Streaming Services" collection,
    /// returns the service name so apps can open a branded service page instead
    /// of the generic folder grid.
    func streamingServiceName(forFolderRowId rowId: String) -> String? {
        let fid = rowId.hasPrefix("folder_") ? String(rowId.dropFirst("folder_".count)) : rowId
        guard let folder = folders.first(where: { $0.id == fid }),
              let collection = collections.first(where: { $0.id == folder.collectionId }),
              GenreCatalog.normalize(collection.name) == "streaming services"
        else { return nil }
        return folder.name
    }

}
