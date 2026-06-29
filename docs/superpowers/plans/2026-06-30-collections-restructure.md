# Collections Restructure + Sub-Folder Support + Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add sub-folder nesting to the collection data model, restructure horror and genre Collections into their genre folders, fix the Supabase refresh to expire stale caches, and make folder tiles fill their frames.

**Architecture:** Add `parentFolderId: String?` to `DBFolder` for sub-folder nesting. Sub-folders keep their root `collectionId` so existing resolution code works unchanged. Lookup methods (`folders(for:)`, `folders(of:in:)`) filter `parentFolderId == nil` to return only root folders. `GenreCatalog.sections(for:)` reads sub-folders from the genre folder and cross-references Film Collections for matching standalone franchise folders. Parse changes recurse into `NuvioFolder.folders`. JSON is restructured to nest collections inside genre folders.

**Tech Stack:** Swift 6.2, SwiftUI, Codable, os_log

**Files changed:** ~14 files across 3 modules (MoonlitCore package, iOS app, Mac app)

---

### Task 1: Add `parentFolderId` to `DBFolder` model

**Files:**
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Models/CollectionModels.swift:48-107`

- [ ] **Step 1.1: Add property**

After line 51 (`public let collectionId: String`):
```swift
    public let parentFolderId: String?
```

- [ ] **Step 1.2: Add CodingKey**

In CodingKeys enum (line 65), after `case collectionId = "collection_id"`:
```swift
        case parentFolderId = "parent_folder_id"
```

- [ ] **Step 1.3: Update init signature**

In init (line 78), after `collectionId: String = ""`:
```swift
        parentFolderId: String? = nil,
```

- [ ] **Step 1.4: Update init body**

In self assignments (line 94), after `self.collectionId = collectionId`:
```swift
        self.parentFolderId = parentFolderId
```

- [ ] **Step 1.5: Build MoonlitCore to verify compilation**

```bash
swift build --package-path Packages/MoonlitCore
```

Expected: build succeeds (existing code uses default `nil`).

- [ ] **Step 1.6: Commit**

```bash
git add Packages/MoonlitCore/Sources/MoonlitCore/Models/CollectionModels.swift
git commit -m "feat: add parentFolderId to DBFolder for sub-folder support"
```

---

### Task 2: Add sub-folder lookup to `CollectionRepository`

**Files:**
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Services/CollectionRepository.swift:212-216`

- [ ] **Step 2.1: Update `folders(for:)` to filter root folders only**

Change line 214 from:
```swift
            .filter { $0.collectionId == collection.id }
```
To:
```swift
            .filter { $0.collectionId == collection.id && $0.parentFolderId == nil }
```

- [ ] **Step 2.2: Add `subFolders(for:)` method**

After `folders(for:)` (line 216):
```swift
    public func subFolders(for parentFolder: DBFolder) -> [DBFolder] {
        folders
            .filter { $0.parentFolderId == parentFolder.id }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
```

- [ ] **Step 2.3: Build**

```bash
swift build --package-path Packages/MoonlitCore
```

Expected: build succeeds.

- [ ] **Step 2.4: Commit**

```bash
git add Packages/MoonlitCore/Sources/MoonlitCore/Services/CollectionRepository.swift
git commit -m "feat: add subFolders lookup, scope folders(for:) to root-only"
```

---

### Task 3: Add `folders` field to `NuvioFolder` and recursive parse

**Files:**
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Services/CollectionOrganizerParser.swift:458-470` (NuvioFolder)
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Services/CollectionOrganizerParser.swift:120-191` (mapNuvio)
- Create/Modify: `Packages/MoonlitCore/Tests/MoonlitCoreTests/` (add sub-folder parse test)

- [ ] **Step 3.1: Add `folders` field to `NuvioFolder`**

At line 461, after `let sources: [NuvioSource]`:
```swift
    let folders: [NuvioFolder]?
```

- [ ] **Step 3.2: Add `processNuvioFolder` recursive helper**

Add before `mapBEST` method (around line 192):

```swift
    private static func processNuvioFolder(
        _ folder: NuvioFolder,
        collectionId: String,
        parentFolderId: String?,
        folderIndex: Int,
        seenFolderIds: inout Set<String>,
        mappedFolders: inout [DBFolder],
        mappedFolderCatalogs: inout [DBFolderCatalog],
        mappedFolderSources: inout [DBFolderSource]
    ) {
        guard !seenFolderIds.contains(folder.id) else { return }

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

        // Allow folders with sub-folders even if they have no sources
        let hasSubFolders = folder.folders?.isEmpty == false
        guard !folderCatalogsForFolder.isEmpty || !folderSourcesForFolder.isEmpty || hasSubFolders else { return }
        seenFolderIds.insert(folder.id)

        mappedFolders.append(DBFolder(
            id: folder.id,
            collectionId: collectionId,
            name: folder.title,
            sortOrder: folderIndex,
            coverImage: folder.coverImageUrl,
            focusGif: folder.focusGifUrl,
            titleLogo: folder.titleLogoUrl,
            heroBackdrop: folder.heroBackdropUrl,
            heroVideoUrl: folder.heroVideoUrl,
            hideTitle: folder.hideTitle,
            tileShape: normalizeShape(folder.tileShape),
            focusGifEnabled: folder.focusGifEnabled,
            parentFolderId: parentFolderId
        ))

        mappedFolderCatalogs.append(contentsOf: folderCatalogsForFolder)
        mappedFolderSources.append(contentsOf: folderSourcesForFolder)

        // Recursively process sub-sub-folders
        if let subFolders = folder.folders {
            for (subIndex, subFolder) in subFolders.enumerated() {
                processNuvioFolder(
                    subFolder,
                    collectionId: collectionId,
                    parentFolderId: folder.id,
                    folderIndex: subIndex,
                    seenFolderIds: &seenFolderIds,
                    mappedFolders: &mappedFolders,
                    mappedFolderCatalogs: &mappedFolderCatalogs,
                    mappedFolderSources: &mappedFolderSources
                )
            }
        }
    }
```

- [ ] **Step 3.3: Simplify the collection loop in `mapNuvio`**

Replace lines 128-165 with a single call per root folder:

```swift
            for (folderIndex, folder) in collection.folders.enumerated() {
                processNuvioFolder(
                    folder,
                    collectionId: collection.id,
                    parentFolderId: nil,
                    folderIndex: folderIndex,
                    seenFolderIds: &seenFolderIds,
                    mappedFolders: &mappedFolders,
                    mappedFolderCatalogs: &mappedFolderCatalogs,
                    mappedFolderSources: &mappedFolderSources
                )
            }
```

- [ ] **Step 3.4: Add unit test for sub-folder parsing**

In `Packages/MoonlitCore/Tests/MoonlitCoreTests/` create or append:

```swift
func testParseSubFolders() throws {
    let json = """
    [
        {
            "id": "c-genres",
            "title": "Genres",
            "folders": [
                {
                    "id": "f-horror",
                    "title": "Horror",
                    "sources": [
                        {"type": "movie", "genre": "Horror", "addonId": "aio", "provider": "addon", "catalogId": "tmdb.discover.movie.horror.abc"}
                    ],
                    "folders": [
                        {
                            "id": "sf-franchises",
                            "title": "Horror Franchises",
                            "sources": [],
                            "folders": [
                                {
                                    "id": "sf-halloween",
                                    "title": "Halloween",
                                    "sources": [{"type": "movie", "genre": "Horror", "provider": "tmdb", "tmdbId": 820, "tmdbSourceType": "COLLECTION"}]
                                }
                            ]
                        }
                    ]
                }
            ]
        }
    ]
    """.data(using: .utf8)!

    let result = try CollectionOrganizerParser.parse(jsonData: json)

    XCTAssertEqual(result.collections.count, 1)
    XCTAssertEqual(result.collections[0].name, "Genres")
    XCTAssertEqual(result.folders.count, 3)

    let horrorFolder = result.folders.first { $0.id == "f-horror" }!
    XCTAssertNil(horrorFolder.parentFolderId)
    XCTAssertEqual(horrorFolder.collectionId, "c-genres")

    let franchisesFolder = result.folders.first { $0.id == "sf-franchises" }!
    XCTAssertEqual(franchisesFolder.parentFolderId, "f-horror")
    XCTAssertEqual(franchisesFolder.collectionId, "c-genres")

    let halloweenFolder = result.folders.first { $0.id == "sf-halloween" }!
    XCTAssertEqual(halloweenFolder.parentFolderId, "sf-franchises")
}
```

- [ ] **Step 3.5: Run tests**

```bash
swift test --package-path Packages/MoonlitCore --filter CollectionOrganizerParserTests
```

Expected: new test passes.

- [ ] **Step 3.6: Commit**

```bash
git add Packages/MoonlitCore/Sources/MoonlitCore/Services/CollectionOrganizerParser.swift
git add Packages/MoonlitCore/Tests/MoonlitCoreTests/
git commit -m "feat: add sub-folder parsing to CollectionOrganizerParser"
```

---

### Task 4: Update `GenreCatalog` folder lookups to filter root-only

**Files:**
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Services/GenreCatalog.swift:228-232`
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Services/GenreCatalog.swift:159-162`

- [ ] **Step 4.1: Add `parentFolderId == nil` to `folders(of:in:)`**

Line 231:
```swift
            .filter { $0.collectionId == collection.id && $0.parentFolderId == nil }
```

- [ ] **Step 4.2: Add `parentFolderId == nil` to `browseRails()` filter**

Line 161:
```swift
                .filter { genreCollectionIds.contains($0.collectionId) && $0.parentFolderId == nil && normalize($0.name) == key }
```

- [ ] **Step 4.3: Run existing GenreCatalog tests**

```bash
swift test --package-path Packages/MoonlitCore --filter GenreCatalogTests
```

Expected: all pass.

- [ ] **Step 4.4: Commit**

```bash
git add Packages/MoonlitCore/Sources/MoonlitCore/Services/GenreCatalog.swift
git commit -m "fix: scope GenreCatalog folder lookups to root folders only"
```

---

### Task 5: Rewrite `GenreCatalog.sections(for:)` — sub-folders + Film Collections cross-ref

**Files:**
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Services/GenreCatalog.swift:88-147`
- Modify: `Packages/MoonlitCore/Tests/MoonlitCoreTests/GenreCatalogTests.swift`

- [ ] **Step 5.1: Replace `sections(for:in:)` with sub-folder + cross-ref implementation**

Replace lines 88-113 with:

```swift
    public static func sections(for genre: String, in org: OrganizedCollections) -> [Section] {
        let key = normalize(genre)
        var sections: [Section] = []

        // Find the genre folder inside "Genres" collection
        let genreCollections = org.collections.filter { normalize($0.name) == "genres" }
        let genreFolders = genreCollections.flatMap { folders(of: $0, in: org) }
        guard let genreFolder = genreFolders.first(where: { normalize($0.name) == key }) else { return [] }

        // Each sub-folder of the genre folder becomes a section
        let subFolders = org.folders
            .filter { $0.parentFolderId == genreFolder.id }
            .sorted { $0.sortOrder < $1.sortOrder }

        // Collect all catalog IDs from the genre's sub-folder tree (for cross-referencing Film Collections)
        var allSubtreeIds = subFolders.map(\.id)
        for sf in subFolders {
            allSubtreeIds.append(contentsOf: org.folders.filter { $0.parentFolderId == sf.id }.map(\.id))
        }
        let matchedCatalogIds = Set(
            org.folderCatalogs
                .filter { allSubtreeIds.contains($0.folderId) && $0.catalogId.hasPrefix("tmdb.collection.") }
                .map(\.catalogId)
        )

        for subFolder in subFolders {
            let nestedFolders = org.folders
                .filter { $0.parentFolderId == subFolder.id }
                .sorted { $0.sortOrder < $1.sortOrder }
            let displayFolders = nestedFolders.isEmpty ? [subFolder] : nestedFolders
            sections.append(Section(
                id: "section-\(key)-\(normalize(subFolder.name))",
                title: friendlyLabel(subFolder.name, genre: genre),
                folders: displayFolders
            ))
        }

        // Cross-reference: standalone franchise folders from "Film Collections" that
        // match the genre's catalog IDs but aren't already in the sub-folder tree.
        if !matchedCatalogIds.isEmpty,
           let film = org.collections.first(where: { normalize($0.name) == "film collections" }) {
            let filmFolders = folders(of: film, in: org)
            let standalone = filmFolders.filter { folder in
                !allSubtreeIds.contains(folder.id) &&
                org.folderCatalogs.contains { $0.folderId == folder.id && matchedCatalogIds.contains($0.catalogId) }
            }
            if !standalone.isEmpty {
                if let collectionsIdx = sections.firstIndex(where: { normalize($0.title).contains("collection") }) {
                    var merged = sections[collectionsIdx].folders
                    merged.append(contentsOf: standalone)
                    sections[collectionsIdx] = Section(
                        id: sections[collectionsIdx].id,
                        title: sections[collectionsIdx].title,
                        folders: merged
                    )
                } else {
                    sections.append(Section(
                        id: "section-\(key)-collections",
                        title: "Collections",
                        folders: standalone
                    ))
                }
            }
        }

        return sections.sorted { sectionOrder($0.title) < sectionOrder($1.title) }
    }
```

- [ ] **Step 5.2: Remove now-unused `franchiseCollectionsSection` method**

Delete lines 115-147 entirely — sub-folders + cross-ref replace it.

- [ ] **Step 5.3: Update GenreCatalogTests for sub-folder + cross-ref behavior**

Replace existing sections tests in `GenreCatalogTests.swift` with:

```swift
func testSectionsUsesSubFoldersOfGenreFolder() throws {
    let org = OrganizedCollections(
        collections: [
            DBCollection(id: "c-genres", name: "Genres", sortOrder: 0),
        ],
        folders: [
            DBFolder(id: "f-horror", collectionId: "c-genres", name: "Horror", sortOrder: 0, parentFolderId: nil),
            DBFolder(id: "sf-franchises", collectionId: "c-genres", name: "Horror Franchises", sortOrder: 0, parentFolderId: "f-horror"),
            DBFolder(id: "sf-halloween", collectionId: "c-genres", name: "Halloween", sortOrder: 0, parentFolderId: "sf-franchises"),
            DBFolder(id: "sf-scream", collectionId: "c-genres", name: "Scream", sortOrder: 1, parentFolderId: "sf-franchises"),
        ],
        folderCatalogs: [
            DBFolderCatalog(id: "cat-1", folderId: "sf-halloween", catalogId: "tmdb.collection.820", mediaType: "movie"),
            DBFolderCatalog(id: "cat-2", folderId: "sf-scream", catalogId: "tmdb.collection.4232", mediaType: "movie"),
        ],
        folderSources: []
    )

    let sections = GenreCatalog.sections(for: "Horror", in: org)
    XCTAssertEqual(sections.count, 1)

    let franchisesSection = sections.first!
    XCTAssertTrue(franchisesSection.title.contains("Franchises"))
    XCTAssertEqual(franchisesSection.folders.count, 2)
    XCTAssertEqual(franchisesSection.folders[0].name, "Halloween")
    XCTAssertEqual(franchisesSection.folders[1].name, "Scream")
}

func testSectionsCrossReferencesFilmCollections() throws {
    let org = OrganizedCollections(
        collections: [
            DBCollection(id: "c-genres", name: "Genres", sortOrder: 0),
            DBCollection(id: "c-film", name: "Film Collections", sortOrder: 1),
        ],
        folders: [
            DBFolder(id: "f-horror", collectionId: "c-genres", name: "Horror", sortOrder: 0, parentFolderId: nil),
            DBFolder(id: "sf-franchises", collectionId: "c-genres", name: "Horror Franchises", sortOrder: 0, parentFolderId: "f-horror"),
            DBFolder(id: "sf-halloween", collectionId: "c-genres", name: "Halloween", sortOrder: 0, parentFolderId: "sf-franchises"),
            // Standalone franchise in Film Collections matching same catalog ID
            DBFolder(id: "f-fc-diehard", collectionId: "c-film", name: "Die Hard", sortOrder: 0, parentFolderId: nil),
        ],
        folderCatalogs: [
            DBFolderCatalog(id: "cat-1", folderId: "sf-halloween", catalogId: "tmdb.collection.820", mediaType: "movie"),
            // Die Hard also uses tmdb.collection.820 — should NOT be cross-referenced since Halloween already covers it
            DBFolderCatalog(id: "cat-2", folderId: "f-fc-diehard", catalogId: "tmdb.collection.1570", mediaType: "movie"),
        ],
        folderSources: []
    )

    let sections = GenreCatalog.sections(for: "Horror", in: org)
    XCTAssertEqual(sections.count, 1) // Only Franchises, no duplicate Die Hard
}

func testSectionsReturnsEmptyForMissingGenre() {
    let org = OrganizedCollections(collections: [], folders: [], folderCatalogs: [], folderSources: [])
    let sections = GenreCatalog.sections(for: "Nonexistent", in: org)
    XCTAssertTrue(sections.isEmpty)
}
```

- [ ] **Step 5.4: Run GenreCatalog tests**

```bash
swift test --package-path Packages/MoonlitCore --filter GenreCatalogTests
```

Expected: updated tests pass.

- [ ] **Step 5.5: Commit**

```bash
git add Packages/MoonlitCore/Sources/MoonlitCore/Services/GenreCatalog.swift
git add Packages/MoonlitCore/Tests/MoonlitCoreTests/GenreCatalogTests.swift
git commit -m "feat: rewrite GenreCatalog.sections to use sub-folders with Film Collections cross-ref"
```

---

### Task 6: Handle sub-folders as group tiles in `CatalogRepository.loadFromCollections()`

**Files:**
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Services/CatalogRepository.swift:475-505`

- [ ] **Step 6.1: Add sub-folder handling**

In the folder iteration loop at lines 475-505, before the existing `if willShowAsGroup { ... } else { ... }` block (line 483), insert:

```swift
                // Folders with sub-folders always render as group tiles from sub-folder metadata.
                let subFolders = collectionRepo.subFolders(for: folder)
                if !subFolders.isEmpty {
                    let tiles = subFolders.map { sf -> MetaPreview in
                        let childSubs = collectionRepo.subFolders(for: sf)
                        let count = childSubs.isEmpty
                            ? collectionRepo.catalogs(for: sf).count + collectionRepo.sources(for: sf).count
                            : childSubs.count
                        let kind: MetaPreview.CountKind = childSubs.isEmpty
                            ? .films
                            : .collections
                        return MetaPreview(
                            id: "folder_\(sf.id)",
                            type: .movie,
                            name: sf.name,
                            poster: sf.coverImage?.nonEmpty ?? sf.heroBackdrop?.nonEmpty,
                            banner: sf.heroBackdrop?.nonEmpty ?? sf.coverImage?.nonEmpty,
                            logo: sf.titleLogo,
                            posterShape: PosterShape(rawValue: sf.tileShape ?? "") ?? .landscape,
                            itemCount: count,
                            countKind: kind
                        )
                    }
                    let subRow = CatalogRow(
                        id: "folder_\(folder.id)",
                        title: folder.name,
                        items: tiles,
                        addonName: "AIOMetadata",
                        page: 0,
                        hasMore: false,
                        tileShape: subFolders.first?.tileShape ?? "landscape",
                        coverImage: folder.coverImage,
                        focusGif: folder.focusGif,
                        focusGifEnabled: folder.focusGifEnabled,
                        titleLogo: folder.titleLogo,
                        heroBackdrop: folder.heroBackdrop,
                        heroVideoURL: folder.heroVideoUrl,
                        hideTitle: folder.hideTitle,
                        focusGlowEnabled: collection.focusGlowEnabled,
                        sourceCount: subFolders.count
                    )
                    skeletonResults.append(FolderResult(
                        collectionIdx: ci,
                        folderIdx: fi,
                        row: subRow
                    ))
                    continue
                }
```

- [ ] **Step 6.2: Build**

```bash
swift build --package-path Packages/MoonlitCore
```

Expected: build succeeds.

- [ ] **Step 6.3: Commit**

```bash
git add Packages/MoonlitCore/Sources/MoonlitCore/Services/CatalogRepository.swift
git commit -m "feat: handle sub-folders as group tiles in loadFromCollections"
```

---

### Task 7: Restructure `home-organizer.json` (iOS)

**Files:**
- Modify: `Apps/MoonlitApp/Resources/home-organizer.json`

- [ ] **Step 7.1: Create transformation script at `/tmp/restructure_collections.py`**

```python
#!/usr/bin/env python3
import json, sys, uuid

with open(sys.argv[1]) as f:
    data = json.load(f)

GENRE_COLLECTION_NAMES = {
    "action": "Action Collections",
    "comedy": "Comedy Collections",
    "crime": "Crime Collections",
    "drama": "Drama Collections",
    "family": "Family & Animation Collections",
    "fantasy": "Fantasy Collections",
    "horror": "Horror Collections",
    "mystery": "Mystery Collections",
    "sci-fi": "Sci-Fi Collections",
    "thriller": "Thriller Collections",
    "war": "War Collections",
}

HORROR_THEME_NAMES = [
    "Horror genre",
    "Horror Decades",
    "Horror Franchises",
    "International Horror",
    "Horror Mood & Vibe",
]

# Find collections
film_collections = next((c for c in data if c["title"] == "Film Collections"), None)
genres = next((c for c in data if "Genres" in c.get("title", "")), None)

if not genres:
    print("ERROR: Genres collection not found")
    sys.exit(1)

# Build lookup of genre folders inside Genres
genre_folders = {}
for f in genres.get("folders", []):
    name_norm = f["title"].lower().strip()
    genre_folders[name_norm] = f

# Extract genre Collections folders from Film Collections and nest them
if film_collections:
    new_film_folders = []
    for f in film_collections.get("folders", []):
        name_norm = f["title"].lower().strip()
        matched_genre = None
        for genre_key, collection_name in GENRE_COLLECTION_NAMES.items():
            if name_norm == collection_name.lower():
                matched_genre = genre_key
                break
        if matched_genre and matched_genre in genre_folders:
            f["id"] = f"gc-{matched_genre}-collections-{uuid.uuid4().hex[:8]}"
            genre_folders[matched_genre].setdefault("folders", []).append(f)
        else:
            new_film_folders.append(f)
    film_collections["folders"] = new_film_folders

# Move horror theme collections into Horror genre folder
horror_folder = genre_folders.get("horror")
if horror_folder:
    horror_folder.setdefault("folders", [])
    new_data = []
    for c in data:
        if c["title"] in HORROR_THEME_NAMES:
            c["id"] = f"ht-{c['title'].lower().replace(' ', '-')}-{uuid.uuid4().hex[:8]}"
            horror_folder["folders"].append(c)
        else:
            new_data.append(c)
    data = new_data

with open(sys.argv[2], 'w') as f:
    json.dump(data, f, indent=2)
```

- [ ] **Step 7.2: Run transformation on iOS JSON**

```bash
python3 /tmp/restructure_collections.py \
  Apps/MoonlitApp/Resources/home-organizer.json \
  Apps/MoonlitApp/Resources/home-organizer.json.tmp \
  && mv Apps/MoonlitApp/Resources/home-organizer.json.tmp \
        Apps/MoonlitApp/Resources/home-organizer.json
```

- [ ] **Step 7.3: Verify JSON structure**

```bash
python3 -c "
import json
with open('Apps/MoonlitApp/Resources/home-organizer.json') as f:
    d = json.load(f)
print(f'Top-level collections: {len(d)}')
horror_names = ['Horror genre', 'Horror Decades', 'Horror Franchises', 'International Horror', 'Horror Mood & Vibe']
for c in d:
    if c['title'] in horror_names:
        print(f'ERROR: {c[\"title\"]} still at top level')
for c in d:
    if 'Genres' in c.get('title',''):
        for f in c['folders']:
            if f['title'].lower() == 'horror':
                subs = f.get('folders', [])
                print(f'Horror sub-folders ({len(subs)}): {[s[\"title\"] for s in subs]}')
            if f['title'].lower() == 'action':
                subs = f.get('folders', [])
                print(f'Action sub-folders ({len(subs)}): {[s[\"title\"] for s in subs]}')
"
```

Expected: horror themes not at top level. Horror shows 5 sub-folders. Action shows "Action Collections".

- [ ] **Step 7.4: Commit**

```bash
git add Apps/MoonlitApp/Resources/home-organizer.json
git commit -m "feat: nest horror and genre collections into genre folders (iOS)"
```

---

### Task 8: Restructure `home-organizer.json` (Mac)

**Files:**
- Modify: `Apps/MoonlitMac/Resources/home-organizer.json`

- [ ] **Step 8.1: Check parity**

```bash
diff Apps/MoonlitApp/Resources/home-organizer.json Apps/MoonlitMac/Resources/home-organizer.json
```

- [ ] **Step 8.2: Sync Mac JSON**

If identical (no diff output):
```bash
cp Apps/MoonlitApp/Resources/home-organizer.json Apps/MoonlitMac/Resources/home-organizer.json
```

If different, run the same script:
```bash
python3 /tmp/restructure_collections.py \
  Apps/MoonlitMac/Resources/home-organizer.json \
  Apps/MoonlitMac/Resources/home-organizer.json.tmp \
  && mv Apps/MoonlitMac/Resources/home-organizer.json.tmp \
        Apps/MoonlitMac/Resources/home-organizer.json
```

- [ ] **Step 8.3: Commit**

```bash
git add Apps/MoonlitMac/Resources/home-organizer.json
git commit -m "feat: nest horror and genre collections into genre folders (Mac)"
```

---

### Task 9: Supabase refresh fix — TTL + error logging + cache deletion

**Files:**
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Services/CollectionOrganizerStore.swift`
- Modify: `Apps/MoonlitApp/Sources/Screens/HomeScreen.swift:514-525`
- Modify: `Apps/MoonlitMac/Sources/Screens/MacHomeView.swift:306-326`

- [ ] **Step 9.1: Update `CollectionOrganizerStore.swift`**

Full replacement:

```swift
import Foundation
import OSLog

private let logger = Logger(subsystem: "ai.moonlit.MoonlitCore", category: "CollectionOrganizer")

public final class CollectionOrganizerStore: @unchecked Sendable {
    public static let shared = CollectionOrganizerStore()

    private let cacheURL: URL
    private let session: URLSession
    private let cacheTTL: TimeInterval = 86400 // 24 hours

    public convenience init() {
        let cacheDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MoonlitHomeLayout", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        self.init(
            cacheURL: cacheDir.appendingPathComponent("home-organizer.json"),
            session: .shared
        )
    }

    init(cacheURL: URL, session: URLSession) {
        self.cacheURL = cacheURL
        self.session = session
    }

    public func cachedOrBundledLayout(bundledData: Data) throws -> OrganizedCollections {
        if let cachedData = try? Data(contentsOf: cacheURL),
           let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
           let modDate = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modDate) < cacheTTL,
           let cached = try? CollectionOrganizerParser.parse(jsonData: cachedData),
           !cached.collections.isEmpty {
            return cached
        }
        return try CollectionOrganizerParser.parse(jsonData: bundledData)
    }

    public func refresh(remoteURL: URL?) async -> OrganizedCollections? {
        guard let remoteURL else { return nil }
        do {
            let (data, response) = try await session.data(from: remoteURL)
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("home-organizer fetch: not an HTTP response")
                return nil
            }
            guard httpResponse.statusCode == 200 else {
                logger.error("home-organizer fetch: HTTP \(httpResponse.statusCode)")
                try? FileManager.default.removeItem(at: cacheURL)
                return nil
            }
            let parsed = try CollectionOrganizerParser.parse(jsonData: data)
            try? data.write(to: cacheURL, options: .atomic)
            logger.info("home-organizer refreshed successfully (\(parsed.collections.count) collections)")
            return parsed
        } catch {
            logger.error("home-organizer fetch failed: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: cacheURL)
            return nil
        }
    }
}
```

Key changes:
- `import OSLog` + `private let logger`
- `cacheTTL` = 86400 (24h)
- `cachedOrBundledLayout` checks modification date against TTL
- Error + success logging via `Logger`
- Delete cache file on failure (non-200 status, network error)

- [ ] **Step 9.2: Add logging to iOS `loadGlobalOrganizer()`**

In `HomeScreen.swift`, around line 516-518, add a log on failure:

```swift
        Task {
            guard let refreshed = await CollectionOrganizerStore.shared.refresh(
                remoteURL: MoonlitConfig.homeOrganizerRemoteURL.flatMap(URL.init)
            ) else {
                Logger(subsystem: "ai.moonlit", category: "HomeScreen")
                    .warning("home-organizer background refresh failed")
                return
            }
```

- [ ] **Step 9.3: Add same logging to Mac `loadGlobalOrganizer()`**

In `MacHomeView.swift`, same addition in the `Task` block.

- [ ] **Step 9.4: Build**

```bash
swift build --package-path Packages/MoonlitCore
```

- [ ] **Step 9.5: Commit**

```bash
git add Packages/MoonlitCore/Sources/MoonlitCore/Services/CollectionOrganizerStore.swift
git add Apps/MoonlitApp/Sources/Screens/HomeScreen.swift
git add Apps/MoonlitMac/Sources/Screens/MacHomeView.swift
git commit -m "fix: add 24h TTL to organizer cache, log errors, delete cache on failure"
```

---

### Task 10: Fix images to fill tiles

**Files:**
- Modify: `Apps/MoonlitApp/Sources/Components/ContentCard.swift:20-63`

- [ ] **Step 10.1: Remove dark background, use `.fill` for all images**

In `body`, lines 22-63:

1. Remove lines 23-25 (the `RoundedRectangle` background)
2. Change line 32 from `.scaleAspectFit` to `.scaleAspectFill` for GIFs
3. Change line 42 from `.aspectRatio(contentMode: usesFittedArtwork ? .fit : .fill)` to `.aspectRatio(contentMode: .fill)`

Updated body:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottom) {
                let displayURL = primaryFailed ? fallbackImageURL : primaryImageURL
                if let url = displayURL {
                    if url.pathExtension.lowercased() == "gif" {
                        AnimatedRemoteImage(url: url, contentMode: .scaleAspectFill)
                            .frame(width: cardWidth, height: cardHeight)
                            .scaleEffect(groupArtworkScale)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        CachedAsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: cardWidth, height: cardHeight)
                                    .scaleEffect(groupArtworkScale)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            case .failure:
                                placeholderView.onAppear {
                                    if !primaryFailed { primaryFailed = true }
                                }
                            case .empty:
                                MoonlitTheme.surfaceElevated
                            @unknown default:
                                placeholderView
                            }
                        }
                    }
                } else {
                    placeholderView
                }
            }
            // ... rest of body unchanged
```

- [ ] **Step 10.2: Commit**

```bash
git add Apps/MoonlitApp/Sources/Components/ContentCard.swift
git commit -m "fix: fill folder tiles completely, remove dark background gap"
```

---

### Task 11: Run full test suite

- [ ] **Step 11.1: Run all MoonlitCore tests**

```bash
swift test --package-path Packages/MoonlitCore
```

Expected: all tests pass. Fix any failures related to existing tests that directly filter `OrganizedCollections.folders` by `collectionId` without `parentFolderId == nil`.

- [ ] **Step 11.2: Fix legacy test filters if needed**

Any test that does `result.folders.filter { $0.collectionId == "..." }` on parsed data will now include sub-folders. Update to `result.folders.filter { $0.collectionId == "..." && $0.parentFolderId == nil }` or use `CollectionRepository.folders(for:)`.

- [ ] **Step 11.3: Commit**

```bash
git add Packages/MoonlitCore/Tests/
git commit -m "test: fix legacy tests for parentFolderId filtering"
```

---

### Task 12: iOS + Mac build verification

- [ ] **Step 12.1: Build iOS app**

```bash
xcodebuild -project Apps/MoonlitApp/MoonlitApp.xcodeproj -scheme MoonlitApp -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 12.2: Build Mac app**

```bash
xcodebuild -project Apps/MoonlitMac/MoonlitMac.xcodeproj -scheme MoonlitMac -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED.

---

### Task 13: Supabase DB migration + edge function update

**Files:**
- Create: `supabase/migrations/013_add_parent_folder_id.sql`
- Modify: `moonlit-portal/supabase/functions/home-organizer/index.ts`

- [ ] **Step 13.1: Create DB migration**

```sql
ALTER TABLE folders ADD COLUMN IF NOT EXISTS parent_folder_id UUID REFERENCES folders(id);
CREATE INDEX IF NOT EXISTS idx_folders_parent_folder_id ON folders(parent_folder_id);
```

- [ ] **Step 13.2: Update edge function for recursive sub-folders**

Modify `index.ts` to:
1. Fetch sub-folders via `parent_folder_id IN (...map of folderIds)`
2. Fetch catalogs/sources for sub-folders
3. Use `serializeFolder()` recursive function in the output mapping
4. Root-level folders filter `!f.parent_folder_id`
5. Sub-folders nested under their parent via `folders: [...]` key

- [ ] **Step 13.3: Deploy**

```bash
npx supabase functions deploy home-organizer
```

---

### Task 14: Final verification and commit

- [ ] **Step 14.1: Full test pass**

```bash
swift test --package-path Packages/MoonlitCore
```

- [ ] **Step 14.2: Both apps build**

```bash
xcodebuild -project Apps/MoonlitApp/MoonlitApp.xcodeproj -scheme MoonlitApp -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
xcodebuild -project Apps/MoonlitMac/MoonlitMac.xcodeproj -scheme MoonlitMac -destination 'platform=macOS' build 2>&1 | tail -5
```

- [ ] **Step 14.3: Stage all changes**

```bash
git status
```

- [ ] **Step 14.4: Commit**

```bash
git add -A
git commit -m "feat: sub-folder support, genre collection restructure, refresh fix, image fill fix"
```

---

## Verification Checklist

After all tasks complete, verify manually:

- [ ] App launches without crash
- [ ] Home screen: no "Horror genre", "Horror Decades", "Horror Franchises", "International Horror", "Horror Mood & Vibe" rows
- [ ] Home screen: no "Action Collections", "Comedy Collections", etc. rows
- [ ] Home screen: "Film Collections" still shows individual franchise folders (Die Hard, James Bond, etc.)
- [ ] Genres → Horror: shows "Horror Franchises", "International Horror", "Horror Decades", "Horror Mood & Vibe", "Horror genre" as section rows
- [ ] Genres → Action: shows "Action Collections" section row with franchise tiles
- [ ] Tapping a franchise tile (e.g. Halloween) → opens FolderScreen with franchise movies
- [ ] Browse rails (New Horror Movies, etc.) still render below section rows
- [ ] Folder tiles on home screen fill their entire frame (no dark gray bars)
- [ ] Console shows log messages when home-organizer refresh succeeds or fails
- [ ] Disk cache (`~/Library/Caches/MoonlitHomeLayout/home-organizer.json`) is deleted when refresh fails
