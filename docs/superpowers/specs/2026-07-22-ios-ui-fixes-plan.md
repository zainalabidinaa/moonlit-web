# Implementation Plan — MoonlitApp iOS Five Fixes

Spec: `2026-07-22-ios-ui-fixes-design.md`

Ordered smallest-blast-radius first, so a build break is always attributable to
the task that just landed. Tasks 1–4 are independent; task 5 is the largest.

Verification gate after **every** task:
```
xcodebuild -scheme MoonlitApp -destination 'generic/platform=iOS Simulator' -configuration Debug build
```
must print `** BUILD SUCCEEDED **`. LSP diagnostics are noise here and are not a
gate. Do not proceed to the next task on a red build.

---

## Task 1 — Shows hero (spec §4)

`Sources/Screens/HomeScreen.swift`, computed property `featuredItems`.

1. Replace `let allRows = catalogRepo.catalogRows` with a `switch` on
   `categoryState.category` producing `scoped`:
   `.featured` → `catalogRepo.catalogRows`;
   `.movies` → `catalogRepo.rows(for: .movies, collectionRepo: collectionRepo)`;
   `.shows` → `catalogRepo.rows(for: .series, collectionRepo: collectionRepo)`.
2. Pass `scoped.compactMap { filteredHomeRow($0, filter: categoryState) }` to
   `HeroCatalogSelector.heroRows(from:)`.
3. Pass `selectedId: categoryState.category == .featured ? heroStore.heroCatalogId : nil`.

Leave the per-row cap logic and the `matchesHomeCategory` filter in the item loop
untouched — it is now a no-op for non-featured but harmless, and still correct
for the genre refinement in `categoryState.genre`.

**Done when:** build succeeds; selecting Shows from the browse menu shows a hero
drawn from a series catalog.

---

## Task 2 — Browse menu stability (spec §2)

### 2a. `Equatable` on the organizer layout

`Packages/MoonlitCore/.../CollectionOrganizerParser.swift` and
`Models/CollectionModels.swift`.

Add `Equatable` to `OrganizedCollections` and to each member type it holds
(`DBCollection`, `DBFolder`, `DBFolderCatalog`, `DBFolderSource` — confirm exact
set by reading the struct). All are value types; conformance is synthesised.

### 2b. Skip no-op layout writes

`HomeScreen.swift`, inside the background `Task` in `loadGlobalOrganizer()`.
After `guard let refreshed = await ...`, add an early return when the refreshed
layout equals what `collectionRepo` already holds, so `apply` and the follow-up
`loadFromCollections` are both skipped. Keep the existing logging for the case
where it *does* change.

### 2c. Freeze the menu's data

`HomeScreen.swift`.

1. Add `@State private var menuMovieGenres: [String] = []`,
   `menuShowGenres: [String] = []`, `menuIsOpen = false`.
2. In `browseMenu`, replace both
   `availableHomeGenres(in: catalogRepo.catalogRows, category:)` calls with the
   corresponding `@State` array.
3. Drive `menuIsOpen` from the `Menu`'s open state.
4. Add `.onChange(of: catalogRepo.catalogRows)` that recomputes both arrays,
   guarded by `!menuIsOpen`, plus a `.task`/`onAppear` seed for first render.

**Done when:** build succeeds; `swift test` in MoonlitCore passes; opening a
submenu and letting a background refresh land no longer collapses the menu.

---

## Task 3 — Genre hub caching (spec §3)

### 3a. Cache in `CatalogRepository`

`Packages/MoonlitCore/.../CatalogRepository.swift`.

1. Add `private var genreHubCache: [String: (content: GenreCatalog.HubContent, at: Date)]`
   and `private static let genreHubTTL: TimeInterval = 6 * 3600`.
2. Add `private static func genreHubKey(genre:mediaKind:)` →
   `"\(GenreCatalog.normalize(genre))|\(mediaKind?.rawValue ?? "any")"`.
3. Add `public func cachedGenreHub(genre:mediaKind:) -> GenreCatalog.HubContent?`
   returning the entry only when within TTL.
4. At the end of `loadGenreHub`, store the assembled `HubContent` before
   returning it.

### 3b. Progressive delivery

Add `loadGenreHubProgressive(genre:collectionRepo:addons:mediaKind:onPartial:)`.
Move the existing body into it, calling `onPartial` twice: once when the TMDB
discover + creative rails resolve, once when the addon browse rails and
collection rails resolve. Reimplement `loadGenreHub` as a thin wrapper that
ignores `onPartial` and returns the final content, so existing callers are
unaffected.

### 3c. Consume it

`Sources/Screens/GenreHubScreen.swift`, `load()`.

1. Before fetching, check `cachedGenreHub`; if hit, assign `browseRails` and set
   `isLoading = false` immediately.
2. Call the progressive variant, merging each partial into `browseRails` by id
   (upsert, preserving order) rather than replacing wholesale.
3. Only show the spinner when `browseRails` is still empty.

**Done when:** build succeeds; a revisited genre paints on the first frame; a
cold genre paints its local sections immediately and fills rails in as they land.

---

## Task 4 — Search (spec §1)

### 4a. Tab wiring

`Sources/ContentView.swift`, `MainTabView`.

1. Change the Settings tab icon `circle.fill` → `gearshape.fill` (both the
   `TabView` and the `NavigationSplitView` sidebar).
2. Extract the tab list so the search tab can be declared conditionally:
   under `#available(iOS 26, *)` declare it **last** as
   `Tab(value: 1, role: .search) { SearchScreen() }`; otherwise keep today's
   inline `Tab("Search", systemImage: "magnifyingglass", value: 1)`.
   `TabView` needs both branches to type-check — use two complete `TabView`
   bodies in an `if #available` rather than trying to vary a single builder.

### 4b. Screen chrome

`Sources/Screens/SearchScreen.swift`.

1. Add the sampled colour constants (`#323434`, `#202222`, `#8E908F`).
2. Replace the background `RoundedRectangle(.ultraThinMaterial) + black 24%`
   with `UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40)`
   filled `.ultraThinMaterial`, overlaid `sheetFill.opacity(0.94)`, clipped to
   the same shape.
3. Gate the duplicate `Text("Search")` title and the hand-built `searchField` to
   the iOS 18 path only. On iOS 26 attach
   `.searchable(text: $query, prompt: "Search…")` and keep the existing
   `.onChange(of: query)` → `performSearch`.
4. Centre the recent-search chips under "Type to search…"; keep them hidden
   while focused (existing `!searchFocused` condition already does this).

**Done when:** build succeeds; on the device Search is a detached circle, opens
as a sheet over Home with a grey panel, and the field replaces the tab bar.

---

## Task 5 — Settings redesign (spec §5)

`Sources/Screens/SettingsScreen.swift` (+ `ConnectAppleIDButton.swift`).

1. Add new row builders alongside the existing ones: `settingsRow(icon:title:subtitle:value:)`
   using a plain white monoline SF Symbol at ~19pt in a 22pt frame, 15pt label,
   chevron at 40% opacity; and `settingsGroup(_:)` wrapping rows in a 16pt-radius
   container with label-inset dividers.
2. Rebuild the identity block: profile card (avatar, name, role badge, Switch
   pill) then the Apple ID row.
3. Refactor `ConnectAppleIDButton` so its label is a compact row with a status
   dot suitable for the identity block. Do not touch `startLink`, `unlink`,
   `checkLink`, the confirmation dialogs, or the error alert.
4. Re-lay the five groups per the spec. **Preserve every role gate verbatim** —
   `roleManager.isAdmin`, `roleManager.profileRole.canManageOwnAddons`,
   `profileManager.isAuthenticated`, and the guest-mode branch.
5. Move Sign Out / Delete Account to the bottom, uncarded; Delete demoted to
   plain text. Keep the confirmation dialog wired.
6. Delete now-unused helpers (`settingsSectionLabel`, `settingsDivider`,
   `settingsRowLabel`) only once nothing references them.

**Checklist before calling this done** — confirm each still renders in the right
branch: Sign in (signed out) · Trakt connect/connected · Admin Dashboard (admin)
· Catalog Management (admin) · Hero Management (admin) · Addons (admin,
premium-self-manage, and guest variants) · Stream Auto-Play (authenticated only)
· TMDB attribution wording unchanged · Connect Apple ID · Sign Out · Delete
Account.

---

## Task 6 — Verify and install

1. `cd Packages/MoonlitCore && swift test`
2. Simulator build (command above) — `** BUILD SUCCEEDED **`
3. macOS compile-check, since `MoonlitCore` changed:
   `xcodebuild build -project MoonlitMac.xcodeproj -scheme MoonlitMac -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
4. Device build for `platform=iOS,id=29E9FC50-BB05-5E86-8BBF-B796F08F975A`
5. `xcrun devicectl device install app --device 29E9FC50-... <path>.app`

The Simulator MCP panel cannot drive a physical device — installation is
`xcodebuild` + `devicectl` only, and on-device visual confirmation is the user's.
