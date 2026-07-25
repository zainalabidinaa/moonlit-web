# MoonlitApp iOS — Five UI/Behaviour Fixes

**Date:** 2026-07-22
**Branch:** `windows-desktop-phase-1`
**Status:** Approved (design render reviewed and approved 2026-07-22)

Five independent defects reported with screen recordings. Each was traced to
specific code before a fix was drafted. This spec covers all five; they share no
state and can be implemented in any order.

Deployment target is **iOS 18.0**, toolchain Xcode 26.3. Anything using an iOS 26
API needs an availability guard plus an iOS 18 fallback path.

---

## 1. Search: adopt the iOS 26 `.search` tab role

### Problem

`SearchScreen` was written to be presented as a sheet — it draws its own 38pt
rounded panel, its own 34pt "Search" title, and its own bottom capsule text
field. It is registered in `MainTabView` as an ordinary tab
(`ContentView.swift:241`), so all that sheet furniture renders flat inside a tab
page. Symptoms:

- Search occupies a fourth slot in the tab pill.
- A large "Search" title duplicates the tab label directly below it.
- A hand-built capsule field floats above the tab bar — two bars stacked.
- The background reads near-black instead of the reference's neutral grey.

The background is the subtle one. `SearchScreen.swift:40-43` fills the panel with
`.ultraThinMaterial` plus a 24% black overlay. A material resolves against
whatever is behind it. In the reference the sheet sits over the Home screen, so
it resolves to a light neutral grey. As an ordinary tab there is nothing behind
it but the black app background, so identical code resolves to near-black.

### Target behaviour

Reproduce the reference recording exactly. Colours sampled from the source at
1206×2622:

| Element | Value |
|---|---|
| Sheet fill | `#323434` at 94% opacity, over a blur |
| Field fill | `#202222` |
| Placeholder text | `#8E908F` |
| Sheet top corner radius | 40pt, square at the bottom |

States:

1. **Home** — three items in the pill (Home / Library / Settings), Search
   detached as a circular glass button to its right.
2. **Search open** — sheet slides up over Home; hero art stays visible above the
   rounded top edge; large "Search" title top-left; centred magnifier and
   "Type to search…"; the tab bar is replaced by the search field.
3. **Focused** — title drops away, field rises onto the keyboard, a circular ✕
   appears to its right to dismiss the sheet.

The sheet presentation, title collapse, ✕, and keyboard avoidance are all
supplied by the `.search` tab role. The only things written by hand are the
panel colour and the empty state.

### Design

`ContentView.swift` — declare the search tab last with `role: .search`, guarded
for iOS 26. On iOS 18 keep today's inline `Tab`, which is the correct fallback:
the detached presentation simply does not exist there.

`SearchScreen.swift`:

- Replace the material-backed panel with an `UnevenRoundedRectangle` (40pt top
  corners) filled `.ultraThinMaterial` and overlaid with `sheetFill.opacity(0.94)`.
  The material supplies blur and depth; the overlay guarantees the colour is
  identical over any backdrop. Deliberately *not* a flat opaque fill — the
  approved design keeps a faint bleed-through of the artwork behind.
- Delete the hand-rolled `searchField` and the duplicate `Text("Search")`.
- Bind the query with `.searchable(text:prompt:)`.
- Keep recent-search chips, centred beneath "Type to search…", hidden on focus.
- On iOS 18, where no system field exists, retain the hand-built field. Both
  paths drive the same `performSearch(_:)`.

Settings tab icon changes `circle.fill` → `gearshape.fill` to match the reference.

### Files

- `Sources/ContentView.swift`
- `Sources/Screens/SearchScreen.swift`

### Revision — 2026-07-22, Binge-derived empty state

The tab wiring and sheet chrome above are unchanged. What changed is the empty
state, after reviewing a recording of the Binge app.

The insight taken from Binge is structural, not cosmetic: **the empty state is
the feature**. Instead of a magnifier and "type to search", the screen is a
browsable surface of tappable tiles, and the search field is one option among
them rather than the only one.

Adopted:

- Large left-aligned title, section headers at ~20pt bold.
- Two-column grid, 12pt gutters, 16pt tile radius, 150pt tile height.
- **Poster-fan tiles** — two or three posters overlapping across the top of each
  tile, rotated `-9° / +4° / +13°` with the middle poster on top, drop-shadowed,
  label centred and truncated beneath. The fan is what makes the grid read as
  stacks worth opening rather than a file browser.
- Grids replaced by results as soon as the query is non-empty.

Explicitly **not** adopted, per the user:

- **The All / Movies / Shows / People filter pills.** Results already arrive
  grouped into People / Movies / TV Shows sections, so the filter would restate
  a distinction the list already draws.
- **Binge's navy palette** (`#10171D` page, `#101921` tile). Applying it to
  Search alone would make the tab read as a different app; applying it app-wide
  is a separate decision. Tiles instead use `white 7%` on the existing sheet with
  a `white 8%` hairline — the same treatment as the redesigned Settings groups.
- **Binge's five inline tabs.** The detached iOS 26 `.search` role stays as
  shipped.

Grid content, per the user's selection:

1. **Recent** — existing recent-search chips, unchanged behaviour.
2. **Browse by Genre** — `GenreCatalog.genres(in:)`, the same source the Home
   browse menu uses. Taps push the existing `GenreHubScreen`.
3. **Movies by Year** — twenty years back from the current year, newest first.
   Taps push a new `YearBrowseScreen`.

Poster sourcing is read-only: both grids scan already-loaded
`catalogRepo.catalogRows` for matching items and take the first three distinct
posters. Nothing fetches on appear. A tile with no posters yet renders a flat
label with a placeholder glyph rather than a gap — the normal state for a second
or two after a cold launch.

`YearBrowseScreen` is backed by a new
`TMDBDiscoverService.discoverByYear(year:mediaKind:)`, which returns `[]` when no
TMDB key is configured; the screen renders that as an empty year, not an error.

Both new views live inside `SearchScreen.swift` rather than new files,
deliberately — see the `moonlit-apps-pbxproj-manual-file-registration` memory;
new `.swift` files need four hand edits to `project.pbxproj`.

### Additional files

- `Packages/MoonlitCore/Sources/MoonlitCore/Services/TMDBDiscoverService.swift`

---

## 2. Browse dropdown collapses mid-interaction

### Problem

Not a menu bug — a view rebuild. In the recording, at the exact frame the
submenu collapses back to the root list, the row behind it changes from
*Trending Shows* to *Continue Watching*. Chain:

1. `loadGlobalOrganizer()` (`HomeScreen.swift:664-681`) launches a detached
   background `Task` that refreshes the home layout from Supabase.
2. On return it calls `collectionRepo.apply(refreshed)` then
   `catalogRepo.loadFromCollections(...)`. Both mutate published state.
3. The menu's contents read that same state:
   `availableHomeGenres(in: catalogRepo.catalogRows, ...)` at
   `HomeScreen.swift:528` and `:533`.
4. The menu lives inside `.toolbar` (`HomeScreen.swift:379-381`), so SwiftUI
   tears the toolbar item down and rebuilds it. UIKit discards the live
   `UIMenu`, and the open submenu dies with it.

### Design

Two changes, both applied.

**A — freeze the menu's data.** Snapshot the genre lists into `@State`
(`menuMovieGenres`, `menuShowGenres`) and refresh them from
`catalogRepo.catalogRows` only while the menu is closed, tracked by a
`menuIsOpen` flag. The menu then reads a value that cannot change during an
interaction, so no background arrival can trigger a rebuild.

**B — stop the churn at the source.** The background refresh re-applies the
layout and reloads every row even when Supabase returned something identical to
what is already applied. Add an equality check and skip the write when nothing
changed. This removes most rebuilds outright and cuts a redundant full catalog
fetch on every launch.

`OrganizedCollections` is currently `Sendable` but not `Equatable`. Conforming it
(and its four member types) to `Equatable` is required for B. All members are
value types, so this is a mechanical conformance.

### Files

- `Sources/Screens/HomeScreen.swift`
- `Packages/MoonlitCore/Sources/MoonlitCore/Services/CollectionOrganizerParser.swift`
- `Packages/MoonlitCore/Sources/MoonlitCore/Models/CollectionModels.swift`

---

## 3. Genre hubs load inconsistently

### Problem

In one recording Adventure appeared instantly and Comedy spun for six seconds.
Nothing about Comedy is slower — Adventure's HTTP responses happened to still be
warm in `URLSession`'s cache. Two independent causes:

**No caching.** `CatalogRepository.loadGenreHub` (`:1033-1098`) refetches
everything on every visit. There is no genre hub cache anywhere in the app.
Whether a hub feels instant is luck.

**All-or-nothing render.** `loadGenreHub` awaits TMDB discover rails, creative
rails, a task-group of a dozen addon catalog fetches, and collection rails, then
returns once at the end (`:1093-1097`). `GenreHubScreen.load()` assigns
`browseRails` from that single return. One slow rail holds the whole screen
behind a spinner.

Note `sectionRows` already renders immediately — it is computed from
`collectionRepo.organized` with no fetch. The spinner is visible because
`browseRails` is empty until everything resolves.

### Design

**Cache.** An in-memory `[String: (content, timestamp)]` on `CatalogRepository`,
keyed by `normalize(genre) | mediaKind`, TTL **6 hours** (approved). Populated at
the end of `loadGenreHub`; read via a new synchronous `cachedGenreHub(genre:mediaKind:)`.
Memory-only for this pass — disk persistence is deliberately deferred, see
Non-goals.

**Stale-while-revalidate.** `GenreHubScreen.load()` paints from cache first and
clears `isLoading` immediately, then refreshes in the background and swaps the
result in. A revisit within TTL shows content on the first frame.

**Progressive rails.** Split the single `await` into two phases so the fast
source lands first: publish TMDB discover + creative rails as soon as they
resolve, then the addon browse rails and collection rails. A new
`loadGenreHubProgressive(...)` takes an `onPartial` callback; `loadGenreHub`
keeps its existing signature and is implemented in terms of it, so no other
caller changes.

### Non-goals

- Disk persistence of the hub cache. Memory-only fixes the reported symptom
  (inconsistency within a session). Disk adds an invalidation surface and, per
  the `catalog-cache-kernel-panic` incident, cache files on this project warrant
  their own careful design pass.
- Background pre-warming of popular genres.

### Files

- `Packages/MoonlitCore/Sources/MoonlitCore/Services/CatalogRepository.swift`
- `Sources/Screens/GenreHubScreen.swift`

---

## 4. Shows category has no hero

### Problem

An ordering bug. `featuredItems` (`HomeScreen.swift:103-130`) passes the
*unfiltered* `catalogRepo.catalogRows` into `HeroCatalogSelector.heroRows`. The
selector prefers "Trending Movies"/"Trending TV Shows", falls back to
"Popular Movies"/"Popular TV Shows", then a named list — and knows nothing about
`categoryState` (`HeroCatalogSelector.swift:18-43`).

Only afterwards does `matchesHomeCategory` filter the chosen row's items to the
selected category. If the resolved row is a movie catalog and the category is
Shows, every item is filtered out, `featuredItems` returns empty, and
`if !featuredItems.isEmpty` (`:177`) skips the entire hero — taking the ambient
background colour with it.

### Design

Filter first, then select. Narrow rows to the active category *before* the
selector sees them:

- `.featured` → `catalogRepo.catalogRows` (unchanged)
- `.movies` → `catalogRepo.rows(for: .movies, collectionRepo:)`
- `.shows` → `catalogRepo.rows(for: .series, collectionRepo:)`

then map through `filteredHomeRow(_:filter:)` before handing to the selector.

Additionally, honour the admin's saved hero override (`heroStore.heroCatalogId`)
only in `.featured`. A hero pinned to a movie catalog must not govern the Shows
page. A genuinely empty category still skips the hero gracefully, as today.

Contained entirely within one computed property. No new types, no new state.

### Files

- `Sources/Screens/HomeScreen.swift`

---

## 5. Settings redesign

### Problem

Today: eight saturated icon-tile colours carrying no meaning, across seven
ad-hoc groups (General, Trakt, Admin, Content Management, Playback, Appearance,
App). Trakt occupies an entire group for one row. Apple ID sits at the very
bottom, below the App group and beside Delete Account. 13pt labels, full-bleed
dividers, tight 11pt vertical padding.

### Target aesthetic

Extracted from the supplied reference screenshots:

- One rounded container per group, 16pt radius
- Monoline outline icons in plain white — no coloured tiles
- Row labels ~15pt regular, up from 13pt
- Dividers inset to the label, not full-bleed
- Chevrons at ~40% opacity
- Large left-aligned title collapsing on scroll

### Structure

Seven groups become five, plus an uncarded identity block:

**Identity** (uncarded, above the first group)
- Profile card — avatar, name, role badge, **Switch** pill (restyled as a glass
  pill; same action, same position)
- **Apple ID** — connected state with status dot — *moved up from the bottom*
- Sign-in prompt when signed out

**Account** — Profiles · Trakt · Metadata & API keys
**Playback** — Video Player · Subtitles · Stream Auto-Play
**Appearance** — Cinematic Mode (inline switch) · Collection Design · App Icon
**Content** — Addons · Catalog Management · Hero Management · Admin Dashboard
**About** — Version · Privacy Policy · Terms of Use · TMDB attribution
**Destructive** (bottom, uncarded) — Sign Out · Delete Account

### Decisions

- Cinematic Mode keeps its inline switch rather than becoming a sub-page.
- Admin rows fold into Content rather than keeping a separate Admin group.
  Existing role gating is preserved exactly — `roleManager.isAdmin` and
  `profileRole.canManageOwnAddons` continue to control visibility.
- The TMDB attribution row is required by TMDB's API terms and must remain,
  with its wording intact.

### Constraints

This is presentation and grouping only. Every row keeps its existing destination,
its existing action, and its existing role gating. `ConnectAppleIDButton` keeps
its confirmation dialogs, error alert, and link/unlink logic untouched — only
its placement and visual treatment change.

### Files

- `Sources/Screens/SettingsScreen.swift`
- `Sources/Components/ConnectAppleIDButton.swift`
- `Sources/ContentView.swift` (tab icon)

---

## Verification

No test target exists for the iOS app; `MoonlitCore` has an SPM test suite.

- `cd Packages/MoonlitCore && swift test` — must pass. Covers the
  `OrganizedCollections` `Equatable` conformance and any `CatalogRepository`
  logic changes.
- `xcodebuild -scheme MoonlitApp -destination 'generic/platform=iOS Simulator' -configuration Debug build`
  from `Apps/MoonlitApp` — must report `** BUILD SUCCEEDED **`.
- Device build and install to the paired iPhone 17 Pro
  (`29E9FC50-BB05-5E86-8BBF-B796F08F975A`) via `xcodebuild` + `xcrun devicectl`.

LSP/SourceKit diagnostics in this repo are unreliable for these targets and must
not be treated as build failures — see the `moonlit-build-verify-commands`
memory. Only `xcodebuild` output counts.

## Risks

- **`.search` role on iOS 26 only.** Deployment target is 18.0, so both paths
  must compile and the iOS 18 path must keep a working search field.
- **Settings is a 1469-line file.** The redesign touches its main `body`
  extensively. Role-gated branches are easy to drop by accident; each must be
  verified present after the rewrite.
- **`Equatable` on `OrganizedCollections`** changes a public type in
  `MoonlitCore`, which `MoonlitMac` also consumes. Additive conformance only, so
  no source break expected, but the macOS target should still compile-check.
