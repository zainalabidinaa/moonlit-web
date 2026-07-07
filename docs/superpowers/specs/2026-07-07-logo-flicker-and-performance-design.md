# Logo Flicker & Startup Performance Design

**Date:** 2026-07-07
**Status:** Design approved, pending implementation plan

## Overview

Two related problems: (1) logos flash a text placeholder before the image renders, and (2) home screen catalog loading feels slow due to sequential bottlenecks during startup.

Root cause for both: data loading is deferred until after views render, rather than being pre-warmed in parallel with the splash animation.

---

## Part 1: Logo Flicker

### Current Behavior

`CachedAsyncImage` renders `placeholder()` (text title) synchronously because `nsImage` starts as `nil`. The `.task { await load() }` modifier fires on the next run loop iteration. Even for a memory-cached logo, there is always at least one frame of visible text before the image swaps in.

Affected surfaces:
- Home hero logo → flashes text title (`heroTitle`)
- Detail hero logo → flashes serif text title with gradient (`heroTextTitle`)
- Folder hero logo → flashes `Color.clear` (empty space) then image appears
- Player loading overlay logo → flashes text title with pulsing animation

### Solution

#### 1. Add synchronous memory cache lookup to `MoonlitImageCache`

```swift
// MoonlitImageCache.swift — new method
public static func syncImage(for url: URL, maxDimension: CGFloat = defaultMaxDimension) -> MoonlitImage? {
    memory.object(forKey: memoryKey(for: url, maxDimension: maxDimension))
}
```

Direct `NSCache.object(forKey:)` — synchronous, no disk, no queue. Returns nil on miss; caller falls through to async `.task` path.

#### 2. Use sync lookup at `CachedAsyncImage` init

```swift
// CachedAsyncImage.swift — change @State init
@State private var nsImage: MoonlitImage? = {
    guard let url else { return nil }
    return MoonlitImageCache.syncImage(for: url, maxDimension: maxDimension)
}()
```

On warm memory cache hit, the image renders on the first frame — no placeholder flash. On miss, `.task { await load() }` fires as before.

#### 3. Prefetch logos when data arrives

Add fire-and-forget prefetch calls at key data-arrival points:

| Trigger | File | What to prefetch |
|---------|------|-----------------|
| `loadFromCollections()` returns catalog rows | `CatalogRepository.swift` | Hero item logos for top 3 items |
| `MacFolderView` appears with `row.titleLogo` | `MacFolderView.swift` | Folder logo |
| `MacDetailView` appears with `detail.logo` | `MacDetailView.swift` | Detail hero logo |
| `HomeHero` auto-rotates to next item | `HomeHero.swift` | Next item's logo |

Prefetch uses the existing `MoonlitImageCache.image(for:maxDimension:)` (async, disk+network) — it warms the memory cache so the sync lookup hits when the view renders.

### Files Changed

- `Packages/MoonlitCore/Sources/MoonlitCore/Services/MoonlitImageCache.swift` — add `syncImage()`
- `Apps/MoonlitMac/Sources/Components/CachedAsyncImage.swift` — sync init
- `Apps/MoonlitMac/Sources/Screens/MacHomeView.swift` — prefetch hero logos
- `Apps/MoonlitMac/Sources/Screens/MacDetailView.swift` — prefetch detail logo
- `Apps/MoonlitMac/Sources/Screens/MacFolderView.swift` — prefetch folder logo
- `Apps/MoonlitMac/Sources/Components/HomeHero.swift` — prefetch next logo on rotate

---

## Part 2: Startup Performance

### Current Flow (timeline)

```
T+0ms     : ProfileManager.init() → Task { restoreSession() }
T+0ms     : restoreSession() — SessionStore.load(), Supabase auth refresh
T+0ms     : restoreSession() — loadProfiles() from Supabase
T+0-1500ms: MANDATORY 1.5s splash delay (even if auth completed in 50ms)
T+1500ms  : hasRestoredSession = true → MacContentView renders MacHomeView
T+1500ms  : MacHomeView.task{} fires:
             1. loadAddons()           ← 1 Supabase + 5 HTTP (parallel within step)
             2. loadContinueWatching() ← async let (concurrent with 3,4)
             3. recsService.load()     ← detached Task (concurrent)
             4. libraryRepo.loadLibrary()
             5. reloadCatalogRows()    ← WAITS for step 1 (needs addon URLs)
                → loadGlobalOrganizer() (bundled JSON, instant)
                → loadFromCollections() (N parallel catalog fetches)
```

### Bottlenecks

1. **1.5s forced splash delay** — dead time. Auth + data loading could overlap with splash animation.
2. **Sequential addon → catalog dependency** — catalog fetches can't start until addon manifest URLs resolve.
3. **Cold `CatalogResponseCache`** (30-min TTL) — first launch after TTL expires hits network for every catalog.
4. **Mac app bypasses CDN proxy** — catalog requests go directly to addon servers (e.g., `aiometadata.fortheweak.cloud`) instead of through the Vercel edge function that adds `s-maxage=300` CDN caching.
5. **No folder prefetching** — opening a group-tile folder triggers a cold network fetch.
6. **mediaType="all" sources** make two sequential `await` calls (movie + series) instead of parallel.

### Solution

#### 1. `StartupCoordinator` — phased loading during splash

New actor in MoonlitCore that manages phased data loading in parallel with the splash animation:

```
StartupCoordinator (actor)
  Phase 0: Auth + profiles          ← ProfileManager (unchanged)
  Phase 1: [organizer, addons]      ← starts when profile resolved, during splash
  Phase 2: [catalog rows, recs, library, continue watching]
  Phase 3: [folder prefetch, ambient color]
```

`ProfileManager.restoreSession()` triggers Phase 1 after auth resolves, then if splash minimum time remains, sleeps only the remaining time. Phase 1 runs concurrently with the remaining sleep.

```swift
// ProfileManager.swift — replace dead sleep
let elapsed = Date().timeIntervalSince(startTime)
// Fire Phase 1 — runs in background while splash finishes
Task { await StartupCoordinator.shared.startPhase1(profileId: profileId) }
let remaining = 1.5 - elapsed
if remaining > 0 {
    try? await Task.sleep(for: .seconds(remaining))
}
self.hasRestoredSession = true
```

`MacHomeView.task{}` becomes lightweight — reads pre-loaded data from `StartupCoordinator.shared` instead of triggering fresh network calls. If the coordinator isn't done yet, it awaits the relevant phase:

```swift
// MacHomeView.task{} — simplified
await StartupCoordinator.shared.waitForPhase2() // blocks until addons+catalogs ready
// Data is already loaded; just apply to UI
catalogRepo.catalogRows = StartupCoordinator.shared.catalogRows
```

#### 2. Parallelize mediaType="all" fetch

In `CatalogRepository.fetchNormalizedSource()`, change two sequential `try? await` to `async let`:

```swift
// Before (sequential):
if let movieResult = try? await catalogService.fetchCatalog(query: movieQuery) { ... }
if let seriesResult = try? await catalogService.fetchCatalog(query: seriesQuery) { ... }

// After (parallel):
async let movieResult = catalogService.fetchCatalog(query: movieQuery)
async let seriesResult = catalogService.fetchCatalog(query: seriesQuery)
let movieItems = (try? await movieResult)?.items ?? []
let seriesItems = (try? await seriesResult)?.items ?? []
```

#### 3. Catalog CDN proxy for Mac

Route Mac app catalog requests through the existing Vercel edge function (`/api/stremio/catalog`) instead of directly to addon servers:

```swift
// CatalogService.swift — buildURL()
let proxyBase = "https://moonlit-web-zainalabidinaas-projects.vercel.app/api/stremio"
let url = "\(proxyBase)/catalog/\(type)/\(id).json?skip=\(skip)"
```

The edge function adds `Cache-Control: public, s-maxage=300, stale-while-revalidate=600`. Subsequent requests within 5 minutes hit the Vercel edge cache — no round-trip to the addon server.

#### 4. `CatalogResponseCache` TTL tiers

| Catalog type | TTL | Rationale |
|-------------|-----|-----------|
| Genre/language catalogs | 6 hours | Static content, changes rarely |
| Popular/Trending | 2 hours | Moderate churn |
| New releases / search | 30 minutes (unchanged) | High churn |

Determined by examining the catalog query's `id` field and matching against known patterns.

#### 5. Folder prefetching (Phase 3)

After home screen renders (Phase 2 complete), `StartupCoordinator` fires low-priority background tasks to prefetch content for visible group tiles:

1. Identify top 5 visible group tiles (folders with >1 source)
2. Pinned collections (`pin_to_top = true`) — always prefetch first
3. Call `catalogRepo.loadFolderItems()` with low QoS
4. Results populate `allFolderRows` cache — `MacFolderView.loadInitialIfNeeded()` returns instantly on `displayRow.items.isEmpty == false`

No new cache layer — existing cache gets populated earlier.

### Files Changed

- `Packages/MoonlitCore/Sources/MoonlitCore/Services/StartupCoordinator.swift` — new
- `Apps/MoonlitMac/Sources/Services/ProfileManager.swift` — trigger Phase 1 during splash
- `Apps/MoonlitMac/Sources/Screens/MacContentView.swift` — read from coordinator
- `Apps/MoonlitMac/Sources/Screens/MacHomeView.swift` — lightweight task, trigger Phase 3
- `Packages/MoonlitCore/Sources/MoonlitCore/Services/CatalogRepository.swift` — parallel mediaType all
- `Packages/MoonlitCore/Sources/MoonlitCore/Services/CatalogService.swift` — proxy routing
- `Packages/MoonlitCore/Sources/MoonlitCore/Services/CatalogResponseCache.swift` — TTL tiers

---

## Part 3: Risk Assessment

| Risk | Mitigation |
|------|-----------|
| Sync cache lookup returns stale image after URL changes | Keyed by URL string — URL change = cache miss |
| Proxy routing breaks for addon URLs with auth headers | Proxy is a transparent pass-through — no auth changes |
| Phase 2 takes longer than 1.5s splash | Home view awaits coordinator — shows spinner if not ready |
| Folder prefetch overwhelms bandwidth | Low QoS, max 5 folders, stops on background |
| TTL tier misclassification shows stale data | Conservative defaults; can be adjusted per TTL |

## Not in Scope

- Pre-bundled catalog snapshots at build time (Approach 3 — future follow-up)
- Server-side recommendation regeneration changes
- Real-time WebSocket updates for catalog changes
- Rewriting the home-organizer edge function
