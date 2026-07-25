# Nested Collection Folders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let portal-managed folders contain ordered child folders and media sources, with the same hierarchy rendered on web, iOS, and macOS.

**Architecture:** Store folder parentage in `folders.parent_folder_id` and store the mixed child order in a new `folder_entries` table. The home-organizer edge function serializes the complete tree and ordered entries; MoonlitCore and the web collection resolver turn that transport model into a per-folder display sequence. The portal is the only editor and performs hierarchy changes through one RPC transaction.

**Tech Stack:** PostgreSQL/Supabase migrations and Edge Functions, React/TypeScript portal and web app, Swift 6/SwiftUI, MoonlitCore XCTest, Vitest.

## Global Constraints

- Supabase is the source of truth; no client writes hierarchy state to local preferences.
- A folder may contain both child folders and media entries.
- `folder_entries.sort_order` is the only ordering used when a folder mixes children and media.
- Root folders use `parent_folder_id = NULL`; old flat data must retain its existing visible order.
- Reject self-parenting, descendants as parents, and cross-collection parenting.
- A bad entry must not prevent valid sibling entries from rendering.
- Existing organizer payloads without `folder_entries` must remain readable as a flat layout.

---

## File Structure

- `moonlit-portal/supabase/migrations/20260713_nested_folder_entries.sql` — schema, backfill, constraints, and transactional RPCs.
- `moonlit-portal/supabase/functions/home-organizer/index.ts` — emits root folders and ordered mixed children.
- `moonlit-portal/src/types/index.ts` — portal hierarchy and entry types.
- `moonlit-portal/src/routes/admin/CatalogPage.tsx` — loads a folder's entries and calls hierarchy RPCs.
- `moonlit-portal/src/components/catalog/FolderGrid.tsx` — root/child folder grid and navigation affordances.
- `moonlit-portal/src/components/catalog/FolderEntriesEditor.tsx` — single draggable mixed folder/source list.
- `Packages/MoonlitCore/Sources/MoonlitCore/Models/CollectionModels.swift` — transport and resolved-entry models.
- `Packages/MoonlitCore/Sources/MoonlitCore/Services/CollectionOrganizerParser.swift` — backward-compatible parsing.
- `Packages/MoonlitCore/Sources/MoonlitCore/Services/CollectionRepository.swift` — root/child and ordered-entry lookups.
- `Packages/MoonlitCore/Sources/MoonlitCore/Services/CatalogRepository.swift` — builds folder rows in portal order.
- `Apps/MoonlitApp/Sources/Screens/FolderScreen.swift` and `Apps/MoonlitMac/Sources/Screens/MacFolderView.swift` — render the unified sequence and route child folders.
- `moonlit-web/src/lib/collections/{types,parser,repository,builder}.ts` — web equivalent of the organizer model and resolver.
- `moonlit-web/src/routes/collections.tsx` — renders an ordered folder sequence.
- `Packages/MoonlitCore/Tests/MoonlitCoreTests/MoonlitCoreTests.swift` and `moonlit-web/src/lib/collections/{repository,builder}.test.ts` — fixture-based parity tests.

### Task 1: Create the database hierarchy and ordered-entry contract

**Files:**
- Create: `moonlit-portal/supabase/migrations/20260713_nested_folder_entries.sql`
- Test: Supabase SQL editor against a disposable migration database

**Produces:** `folders.parent_folder_id`, `folder_entries`, `move_folder`, and `replace_folder_entries` RPCs used by the portal and organizer.

- [ ] **Step 1: Write a failing SQL verification script**

```sql
-- Expected to fail before the migration: relation and RPC do not exist.
select * from folder_entries limit 1;
select move_folder('00000000-0000-0000-0000-000000000000', null, 0);
```

- [ ] **Step 2: Run the verification against the local Supabase database**

Run: `cd /Users/zain/projects/Moonlit/moonlit-portal && supabase db reset`

Expected: the verification fails because `folder_entries` and `move_folder` are absent.

- [ ] **Step 3: Add the migration**

```sql
alter table public.folders
  add column parent_folder_id uuid references public.folders(id) on delete cascade;

create table public.folder_entries (
  id uuid primary key default gen_random_uuid(),
  parent_folder_id uuid not null references public.folders(id) on delete cascade,
  entry_kind text not null check (entry_kind in ('folder', 'catalog', 'source')),
  folder_id uuid references public.folders(id) on delete cascade,
  folder_catalog_id uuid references public.folder_catalogs(id) on delete cascade,
  folder_source_id uuid references public.folder_sources(id) on delete cascade,
  sort_order integer not null,
  unique (parent_folder_id, sort_order),
  check ((entry_kind = 'folder' and folder_id is not null and folder_catalog_id is null and folder_source_id is null)
      or (entry_kind = 'catalog' and folder_id is null and folder_catalog_id is not null and folder_source_id is null)
      or (entry_kind = 'source' and folder_id is null and folder_catalog_id is null and folder_source_id is not null))
);
```

Add a `before insert or update` trigger that rejects a folder entry whose child is in another collection or whose child would introduce a cycle. Backfill one root entry per current folder in `folders.sort_order`; keep each existing folder's own source ordering intact. Implement `replace_folder_entries(p_parent_folder_id uuid, p_entries jsonb)` so it locks the parent and its entries, validates all references, deletes the old sibling entries, and inserts the supplied order atomically.

- [ ] **Step 4: Verify migration behavior**

Run: `cd /Users/zain/projects/Moonlit/moonlit-portal && supabase db reset`

Then run SQL assertions for: a root folder has `parent_folder_id is null`; a folder entry can precede a catalog entry; self/cycle/cross-collection inserts raise an exception; `replace_folder_entries` leaves no partial order after a deliberately invalid payload.

- [ ] **Step 5: Commit**

```bash
git add moonlit-portal/supabase/migrations/20260713_nested_folder_entries.sql
git commit -m "feat: add nested folder hierarchy"
```

### Task 2: Publish hierarchy and ordered entries through the organizer

**Files:**
- Modify: `moonlit-portal/supabase/functions/home-organizer/index.ts`
- Test: `moonlit-portal/supabase/functions/home-organizer/index.test.ts`

**Consumes:** `folder_entries` from Task 1.

**Produces:** Organizer folder records with `parentFolderId` and a `folderEntries` array with `{ parentFolderId, entryKind, folderId?, folderCatalogId?, folderSourceId?, sortOrder }`.

- [ ] **Step 1: Write the failing edge-function fixture test**

```ts
expect(payload[0].folders.find(f => f.id === horrorId)).toMatchObject({ parentFolderId: null });
expect(payload[0].folderEntries.map(e => [e.entryKind, e.sortOrder])).toEqual([
  ['folder', 0], ['catalog', 1], ['folder', 2],
]);
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/zain/projects/Moonlit/moonlit-portal && npm test -- home-organizer`

Expected: FAIL because the organizer does not query or serialize `folder_entries`.

- [ ] **Step 3: Implement the smallest organizer change**

Query `folder_entries` in the same batched pattern used for folders and sources, serialize all folders including navigation-only folders, and output entries sorted by `parent_folder_id`, then `sort_order`. Preserve the existing `sources` array for compatibility; clients that understand `folderEntries` use the unified sequence.

```ts
const entriesByParent: Record<string, FolderEntry[]> = {};
for (const entry of folderEntries.sort((a, b) => a.sort_order - b.sort_order)) {
  (entriesByParent[entry.parent_folder_id] ??= []).push(toEntry(entry));
}
```

- [ ] **Step 4: Run function tests and a local HTTP smoke test**

Run: `cd /Users/zain/projects/Moonlit/moonlit-portal && npm test -- home-organizer && supabase functions serve home-organizer --no-verify-jwt`

Expected: PASS; `curl http://localhost:54321/functions/v1/home-organizer` returns a JSON array containing `folderEntries`.

- [ ] **Step 5: Commit**

```bash
git add moonlit-portal/supabase/functions/home-organizer/index.ts moonlit-portal/supabase/functions/home-organizer/index.test.ts
git commit -m "feat: expose nested folder entries"
```

### Task 3: Add the portal hierarchy editor

**Files:**
- Modify: `moonlit-portal/src/types/index.ts`
- Modify: `moonlit-portal/src/routes/admin/CatalogPage.tsx`
- Modify: `moonlit-portal/src/components/catalog/FolderGrid.tsx`
- Create: `moonlit-portal/src/components/catalog/FolderEntriesEditor.tsx`
- Test: `moonlit-portal/src/components/catalog/FolderEntriesEditor.test.tsx`

**Consumes:** `replace_folder_entries` and `move_folder` from Task 1.

**Produces:** Portal actions to add a child folder, move a folder, and atomically reorder mixed children.

- [ ] **Step 1: Write interaction tests**

```tsx
render(<FolderEntriesEditor entries={[childFolder, catalogSource]} onSave={save} />);
await userEvent.dragAndDrop(screen.getByText('Popular Horror'), screen.getByText('Horror Franchises'));
expect(save).toHaveBeenCalledWith([
  { entryKind: 'catalog', folderCatalogId: 'catalog-1', sortOrder: 0 },
  { entryKind: 'folder', folderId: 'franchises', sortOrder: 1 },
]);
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/zain/projects/Moonlit/moonlit-portal && npm test -- FolderEntriesEditor`

Expected: FAIL because `FolderEntriesEditor` does not exist.

- [ ] **Step 3: Implement portal editing**

Add `parent_folder_id?: string | null` to `Folder` and a discriminated `FolderEntry` type. Change `addFolder(parentFolderId?: string)` to insert a folder with the selected parent's collection and append a folder entry. Let a selected folder open `FolderEntriesEditor`; its single list contains child folder, catalog, and source rows. On drop, call:

```ts
await supabase.rpc('replace_folder_entries', {
  p_parent_folder_id: selectedFolder.id,
  p_entries: entries.map((entry, sortOrder) => ({ ...entry, sortOrder })),
});
```

Use `move_folder` for re-parenting. Display a save error without replacing the last confirmed list. Keep the root `FolderGrid` filtered to `parent_folder_id === null`.

- [ ] **Step 4: Run portal tests and typecheck**

Run: `cd /Users/zain/projects/Moonlit/moonlit-portal && npm test -- FolderEntriesEditor && npm run build`

Expected: PASS and a successful production build.

- [ ] **Step 5: Commit**

```bash
git add moonlit-portal/src/types/index.ts moonlit-portal/src/routes/admin/CatalogPage.tsx moonlit-portal/src/components/catalog/FolderGrid.tsx moonlit-portal/src/components/catalog/FolderEntriesEditor.tsx moonlit-portal/src/components/catalog/FolderEntriesEditor.test.tsx
git commit -m "feat: manage nested folder entries in portal"
```

### Task 4: Parse and resolve nested data in MoonlitCore

**Files:**
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Models/CollectionModels.swift`
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Services/CollectionOrganizerParser.swift`
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Services/CollectionRepository.swift`
- Test: `Packages/MoonlitCore/Tests/MoonlitCoreTests/MoonlitCoreTests.swift`

**Consumes:** Organizer contract from Task 2.

**Produces:** `DBFolder.parentFolderId`, `FolderEntry`, `CollectionRepository.rootFolders(for:)`, and `CollectionRepository.entries(for:)`.

- [ ] **Step 1: Write the failing Swift fixture tests**

```swift
func testOrganizerParsesMixedFolderEntriesInPortalOrder() throws {
    let layout = try CollectionOrganizerParser.parse(jsonData: mixedHierarchyFixture)
    XCTAssertEqual(layout.entries(for: horrorID).map(\.kind), [.folder, .catalog, .folder])
}

func testMissingFolderEntriesFallsBackToFlatFolderSources() throws {
    let layout = try CollectionOrganizerParser.parse(jsonData: legacyFixture)
    XCTAssertEqual(layout.entries(for: legacyFolderID).count, 2)
}
```

- [ ] **Step 2: Run the focused test bundle and confirm failure**

Run: `cd /Users/zain/projects/Moonlit && swift test --package-path Packages/MoonlitCore --filter MoonlitCoreTests/testOrganizerParsesMixedFolderEntriesInPortalOrder`

Expected: FAIL because the parser/model has no entry type.

- [ ] **Step 3: Implement backward-compatible parsing and resolution**

Model each entry as an enum-backed record. `entries(for:)` must return valid entries sorted by `sortOrder`, discard duplicate references, and synthesize legacy catalog/source entries only when the remote payload omitted `folderEntries`. `rootFolders(for:)` filters on `parentFolderId == nil`.

```swift
public enum FolderEntryKind: String, Codable, Sendable { case folder, catalog, source }
public struct FolderEntry: Codable, Identifiable, Sendable {
    public let id: String
    public let parentFolderId: String
    public let kind: FolderEntryKind
    public let folderId: String?
    public let folderCatalogId: String?
    public let folderSourceId: String?
    public let sortOrder: Int
}
```

- [ ] **Step 4: Run all MoonlitCore tests**

Run: `cd /Users/zain/projects/Moonlit && swift test --package-path Packages/MoonlitCore`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/MoonlitCore/Sources/MoonlitCore/Models/CollectionModels.swift Packages/MoonlitCore/Sources/MoonlitCore/Services/CollectionOrganizerParser.swift Packages/MoonlitCore/Sources/MoonlitCore/Services/CollectionRepository.swift Packages/MoonlitCore/Tests/MoonlitCoreTests/MoonlitCoreTests.swift
git commit -m "feat: resolve nested organizer folders"
```

### Task 5: Render ordered mixed folder contents in iOS and macOS

**Files:**
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Services/CatalogRepository.swift`
- Modify: `Apps/MoonlitApp/Sources/Screens/FolderScreen.swift`
- Modify: `Apps/MoonlitMac/Sources/Screens/MacFolderView.swift`
- Test: `Packages/MoonlitCore/Tests/MoonlitCoreTests/MoonlitCoreTests.swift`
- Test: `Apps/MoonlitMac/Tests/MoonlitMacResourceTests.swift`

**Consumes:** Repository resolver from Task 4.

**Produces:** Folder `CatalogRow` values that contain child-folder tiles and media in the exact `folder_entries` order.

- [ ] **Step 1: Write failing row-builder tests**

```swift
func testFolderDisplayRowsInterleaveChildTilesAndSourceMedia() {
    let row = CatalogRepository.folderDisplayRow(for: horrorID, repository: repository, loadedMedia: media)
    XCTAssertEqual(row.items.map(\.id), ["folder_franchises", "tt123", "folder_international"])
}
```

- [ ] **Step 2: Run focused tests and confirm failure**

Run: `cd /Users/zain/projects/Moonlit && swift test --package-path Packages/MoonlitCore --filter MoonlitCoreTests/testFolderDisplayRowsInterleaveChildTilesAndSourceMedia`

Expected: FAIL because catalog loading currently returns a folder's sources only.

- [ ] **Step 3: Implement ordered folder loading**

Update `loadFolderItems` to resolve each entry in order: construct a lightweight `MetaPreview` for child folders; fetch catalog/source media and append only its resulting media to the same result sequence. Preserve pagination only for media entries, and omit broken references while retaining later siblings. Use the existing `folder_` identifier convention so both screens route child tiles through their current navigation closures.

- [ ] **Step 4: Update screens to render mixed content correctly**

Keep the current folder navigation route for an ID beginning with `folder_`. Make `FolderScreen` and `MacFolderView` choose a grid/card layout per item rather than deciding a single all-folder/all-media layout from the sample; folder tiles use their declared shape and media use existing card styling.

- [ ] **Step 5: Run test suites and compile both apps**

Run: `cd /Users/zain/projects/Moonlit && swift test --package-path Packages/MoonlitCore && xcodebuild -project Apps/MoonlitApp/MoonlitApp.xcodeproj -scheme MoonlitApp -sdk iphonesimulator build && xcodebuild -project Apps/MoonlitMac/MoonlitMac.xcodeproj -scheme MoonlitMac build`

Expected: all tests pass and both builds succeed.

- [ ] **Step 6: Commit**

```bash
git add Packages/MoonlitCore/Sources/MoonlitCore/Services/CatalogRepository.swift Apps/MoonlitApp/Sources/Screens/FolderScreen.swift Apps/MoonlitMac/Sources/Screens/MacFolderView.swift Packages/MoonlitCore/Tests/MoonlitCoreTests/MoonlitCoreTests.swift Apps/MoonlitMac/Tests/MoonlitMacResourceTests.swift
git commit -m "feat: show mixed folder contents in native apps"
```

### Task 6: Bring the web collection resolver and folder page to parity

**Files:**
- Modify: `moonlit-web/src/lib/collections/types.ts`
- Modify: `moonlit-web/src/lib/collections/parser.ts`
- Modify: `moonlit-web/src/lib/collections/repository.ts`
- Modify: `moonlit-web/src/lib/collections/builder.ts`
- Modify: `moonlit-web/src/routes/collections.tsx`
- Test: `moonlit-web/src/lib/collections/repository.test.ts`
- Test: `moonlit-web/src/lib/collections/builder.test.ts`

**Consumes:** Organizer contract from Task 2.

**Produces:** A web `resolveFolderFromOrganizer` result with ordered entries and a folder page that renders folders and media in portal order.

- [ ] **Step 1: Write parity tests with the shared mixed fixture**

```ts
expect(resolveFolderFromOrganizer(horrorId)?.entries.map(entry => entry.kind)).toEqual([
  'folder', 'catalog', 'folder',
]);
expect(await buildFolderItems(horrorId, fixture)).toMatchObject([
  { id: `folder_${franchiseId}` }, { id: 'tt123' }, { id: `folder_${internationalId}` },
]);
```

- [ ] **Step 2: Run focused tests and confirm failure**

Run: `cd /Users/zain/projects/Moonlit/moonlit-web && npm test -- repository builder`

Expected: FAIL because the web model has no parent/entry fields.

- [ ] **Step 3: Implement web parsing and ordered display**

Mirror the MoonlitCore transport names: `parentFolderId` and `folderEntries`. The parser must synthesize legacy entries when absent. Make `resolveFolderFromOrganizer` return an `entries` array and have `collections.tsx` map each entry in order: folder entries link to `/collections/$folderId`; source entries use the already resolved media cards/rails. Do not re-sort by type.

- [ ] **Step 4: Run web verification**

Run: `cd /Users/zain/projects/Moonlit/moonlit-web && npm test && npm run build`

Expected: tests and production build pass.

- [ ] **Step 5: Commit**

```bash
git add moonlit-web/src/lib/collections/types.ts moonlit-web/src/lib/collections/parser.ts moonlit-web/src/lib/collections/repository.ts moonlit-web/src/lib/collections/builder.ts moonlit-web/src/routes/collections.tsx moonlit-web/src/lib/collections/repository.test.ts moonlit-web/src/lib/collections/builder.test.ts
git commit -m "feat: render nested folders on web"
```

### Task 7: Validate end-to-end parity and production migration safety

**Files:**
- Modify: `Apps/MoonlitApp/Resources/home-organizer.json`
- Modify: `Apps/MoonlitMac/Resources/home-organizer.json`
- Modify: `moonlit-web/public/home-organizer.json`
- Test: `Packages/MoonlitCore/Tests/MoonlitCoreTests/MoonlitCoreTests.swift`
- Test: `moonlit-web/src/lib/collections/repository.test.ts`

**Consumes:** Tasks 1–6.

**Produces:** A shared nested organizer fixture and evidence that all clients resolve it identically.

- [ ] **Step 1: Add one canonical fixture**

Add a `Genre → Horror` fixture containing the five requested categories, with at least one media entry between child folders. Copy the exact JSON to all three bundled organizer resources.

- [ ] **Step 2: Add exact parity assertions**

```swift
XCTAssertEqual(repository.entries(for: horrorID).map(\.sortOrder), [0, 1, 2, 3, 4])
XCTAssertEqual(repository.rootFolders(for: genreID).map(\.name), ["Horror"])
```

```ts
expect(resolveFolderFromOrganizer(horrorId)?.entries.map(e => e.sortOrder)).toEqual([0, 1, 2, 3, 4]);
```

- [ ] **Step 3: Run all verification commands**

Run: `cd /Users/zain/projects/Moonlit && swift test --package-path Packages/MoonlitCore && cd moonlit-web && npm test && npm run build && cd ../moonlit-portal && npm test && npm run build`

Expected: every test and build passes.

- [ ] **Step 4: Apply migration to a staging project and smoke-test the organizer**

Run: `cd /Users/zain/projects/Moonlit/moonlit-portal && supabase db push --dry-run`

Expected: only `20260713_nested_folder_entries.sql` is proposed. Apply only after the user authorizes the staging deployment, then verify the deployed organizer returns the fixture's ordered entries.

- [ ] **Step 5: Commit**

```bash
git add Apps/MoonlitApp/Resources/home-organizer.json Apps/MoonlitMac/Resources/home-organizer.json moonlit-web/public/home-organizer.json Packages/MoonlitCore/Tests/MoonlitCoreTests/MoonlitCoreTests.swift moonlit-web/src/lib/collections/repository.test.ts
git commit -m "test: verify nested folder parity"
```

## Plan Self-Review

- Spec coverage: Tasks 1–2 cover the durable schema and organizer; Task 3 covers portal editing and atomic errors; Tasks 4–6 cover native and web parsing/rendering; Task 7 covers migration compatibility and cross-client parity.
- Placeholder scan: no unresolved choices or generic testing steps remain; each task names its files, interfaces, tests, commands, and expected outcome.
- Type consistency: `parentFolderId`/`parent_folder_id` and `FolderEntry`/`folder_entries` are the only hierarchy names; `sortOrder`/`sort_order` is authoritative in every layer.
