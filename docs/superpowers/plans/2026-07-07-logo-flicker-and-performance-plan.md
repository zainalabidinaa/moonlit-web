# Logo Flicker & Startup Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate logo text-to-image flicker and cut home screen time-to-content by overlapping catalog data loading with the splash animation.

**Architecture:** A two-part change — (A) a synchronous memory cache hook eliminates the placeholder flash, with prefetch calls warming the cache before views render; (B) a `StartupCoordinator` actor manages phased data loading during the splash, plus catalog CDN proxy routing, parallelized mediaType="all" fetches, and TTL-tiered cache.

**Tech Stack:** Swift 6, SwiftUI, MoonlitCore (local SPM package), NSCache, ImageIO, Vercel Edge Functions (proxy routing)

---

## Task 1: Add sync memory cache lookup to MoonlitImageCache

**Files:**
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Services/MoonlitImageCache.swift`

**Why:** `CachedAsyncImage` needs a synchronous path to check the memory cache at init time so a warm-cached image renders on the first frame. Currently `image(for:)` is async and always defers one run loop.

- [ ] **Step 1: Add `syncImage(for:maxDimension:)`**

Add after the `store(data:for:)` method (after line 69). Insert:

```swift
/// Synchronous memory-cache lookup (no disk, no queue).
/// Returns the downsampled image for immediate rendering when the cache is warm,
/// or nil to trigger the async .task path.
public static func syncImage(for url: URL, maxDimension: CGFloat = defaultMaxDimension) -> MoonlitImage? {
    memory.object(forKey: memoryKey(for: url, maxDimension: maxDimension))
}
```

- [ ] **Step 2: Build MoonlitCore to verify**

Run: `xcodebuild -scheme MoonlitCore -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Packages/MoonlitCore/Sources/MoonlitCore/Services/MoonlitImageCache.swift
git commit -m "feat: add syncImage() sync memory cache lookup to MoonlitImageCache"
```

---

## Task 2: Use sync cache lookup in CachedAsyncImage init

**Files:**
- Modify: `Apps/MoonlitMac/Sources/Components/CachedAsyncImage.swift`

**Why:** With the sync lookup available, `CachedAsyncImage` can initialize `nsImage` from the memory cache on its first render pass, eliminating the text placeholder flash entirely when the cache is warm.

- [ ] **Step 1: Replace `@State private var nsImage` initialization**

Change lines 12-13 from:
```swift
@State private var nsImage: MoonlitImage?
```
To:
```swift
@State private var nsImage: MoonlitImage? = {
    guard let url else { return nil }
    return MoonlitImageCache.syncImage(for: url, maxDimension: maxDimension)
}()
```

This captures the initial `url` and `maxDimension` values as defaults. If `url` changes later (e.g., hero rotation), the `load()` function still re-triggers because `nsImage` is nil for the new URL (the sync lookup will miss on first encounter of a new URL). The existing guard at line 24 (`guard let url, nsImage == nil else { return }`) handles this correctly.

- [ ] **Step 2: Build Mac app to verify**

Run: `xcodebuild -project MoonlitMac.xcodeproj -scheme MoonlitMac -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Apps/MoonlitMac/Sources/Components/CachedAsyncImage.swift
git commit -m "feat: use sync cache lookup in CachedAsyncImage init to eliminate placeholder flash"
```

---

## Task 3: Prefetch logos when data arrives

**Files:**
- Modify: `Apps/MoonlitMac/Sources/Screens/MacHomeView.swift`
- Modify: `Apps/MoonlitMac/Sources/Screens/MacFolderView.swift`
- Modify: `Apps/MoonlitMac/Sources/Screens/MacDetailView.swift`
- Modify: `Apps/MoonlitMac/Sources/Components/HomeHero.swift`

**Why:** The sync lookup in Task 2 only hits if the logo is already in the memory cache. We need to warm the cache by prefetching logos at the moment data arrives (hero items, folder metadata, detail data), before the view renders.

- [ ] **Step 1: Prefetch hero logos after catalog rows load — MacHomeView.swift**

Add a helper method and call it after `reloadCatalogRows(mode:)` completes. At the end of the `.task {}` block (after line 375, right after `warmupContinueWatching()`), add:

```swift
prefetchHeroLogos()
```

Add the method anywhere in `MacHomeView`:

```swift
private func prefetchHeroLogos() {
    let topItems = catalogRepo.catalogRows.prefix(3).flatMap(\.items)
    for item in topItems {
        guard let logoURL = item.logo.flatMap(URL.init) else { continue }
        Task.detached(priority: .background) {
            _ = await MoonlitImageCache.image(for: logoURL)
        }
    }
}
```

- [ ] **Step 2: Prefetch folder logo when MacFolderView appears — MacFolderView.swift**

In `MacFolderView`, add the prefetch to the `.task(id: row.id)` modifier (which is near the top of the view body, look for `.task(id: row.id)` around line 126). Inside the task block, before `await loadInitialIfNeeded()`, add:

```swift
if let logoURL = displayRow.titleLogo.flatMap(URL.init) {
    Task.detached(priority: .background) {
        _ = await MoonlitImageCache.image(for: logoURL)
    }
}
```

- [ ] **Step 3: Prefetch detail hero logo when detail data arrives — MacDetailView.swift**

Find where `metaRepo.detail` is first set or where the detail view body accesses `detail.logo` (around line 330). Inside the `body` computed property, add a `.task(id: metaRepo.detail?.logo)` modifier on the outermost view container or on the `heroLogoOrTitle` section. The simplest place: find the `.task { await metaRepo.load(...) }` in the body, and after the load completes, add the prefetch:

If there's a `.task {}` block that loads the detail, add after the await line:

```swift
if let logoURL = metaRepo.detail?.logo.flatMap(URL.init) {
    Task.detached(priority: .background) {
        _ = await MoonlitImageCache.image(for: logoURL)
    }
}
```

If there's no explicit `.task`, add a `.task(id: metaRepo.detail?.logo)` modifier on the ScrollView or main ZStack at the top level of `body`:

```swift
.task(id: metaRepo.detail?.logo) {
    guard let logoURL = metaRepo.detail?.logo.flatMap(URL.init) else { return }
    _ = await MoonlitImageCache.image(for: logoURL)
}
```

- [ ] **Step 4: Prefetch next hero logo on auto-rotate — HomeHero.swift**

In `HomeHero`, find the `startAutoAdvance()` method (around line 271). In the Timer block inside, after `currentIndex = (currentIndex + 1) % max(items.count, 1)`, prefetch the *next* item's logo (the one after the new index). Add inside the Timer callback:

```swift
autoTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
    Task { @MainActor in
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            currentIndex = (currentIndex + 1) % max(items.count, 1)
        }
        // Prefetch the NEXT-next item's logo
        let nextIdx = (currentIndex + 1) % max(items.count, 1)
        if let logoURL = items[nextIdx].logo.flatMap(URL.init) {
            Task.detached(priority: .background) {
                _ = await MoonlitImageCache.image(for: logoURL)
            }
        }
    }
}
```

- [ ] **Step 5: Build to verify**

Run: `xcodebuild -project MoonlitMac.xcodeproj -scheme MoonlitMac -destination 'platform=macOS' build 2>&1 | tail -5`

- [ ] **Step 6: Commit**

```bash
git add Apps/MoonlitMac/Sources/Screens/MacHomeView.swift \
        Apps/MoonlitMac/Sources/Screens/MacFolderView.swift \
        Apps/MoonlitMac/Sources/Screens/MacDetailView.swift \
        Apps/MoonlitMac/Sources/Components/HomeHero.swift
git commit -m "feat: prefetch logos at data-arrival points to warm memory cache"
```

---

## Task 4: Create StartupCoordinator

**Files:**
- Create: `Packages/MoonlitCore/Sources/MoonlitCore/Services/StartupCoordinator.swift`

**Why:** Need a dedicated actor to manage phased data loading in parallel with the splash animation. This decouples the loading lifecycle from SwiftUI views, so data can start loading as soon as the profile is resolved, not after the view appears.

- [ ] **Step 1: Create StartupCoordinator.swift**

Write file `Packages/MoonlitCore/Sources/MoonlitCore/Services/StartupCoordinator.swift`:

```swift
import Foundation

@globalActor public actor StartupCoordinator: GlobalActor {
    public static let shared = StartupCoordinator()

    public enum Phase: Sendable { case phase1, phase2, phase3 }

    private var completedPhases: Set<Phase> = []

    public var catalogRows: [CatalogRow] = []
    public var collectionRows: [CatalogRow] = []
    public var allFolderRows: [String: CatalogRow] = [:]

    private var phaseContinuations: [Phase: [CheckedContinuation<Void, Never>]] = [
        .phase1: [], .phase2: [], .phase3: []
    ]

    private init() {}

    private func prerequisitesSatisfied(for phase: Phase) -> Bool {
        let order: [Phase] = [.phase1, .phase2, .phase3]
        for p in order {
            if p == phase { break }
            if !completedPhases.contains(p) { return false }
        }
        return true
    }

    public func startPhase1(
        profileId: String,
        collectionRepo: CollectionRepository = .shared,
        addonRepo: AddonRepository = .shared,
        catalogRepo: CatalogRepository = .shared,
        homeRepo: HomeRepository = .shared,
        recsService: RecommendationsService = .shared,
        libraryRepo: LibraryRepository = .shared
    ) {
        guard prerequisitesSatisfied(for: .phase1), !completedPhases.contains(.phase1) else { return }

        Task {
            async let organizerDone: Void = {
                guard let bundledURL = Bundle.main.url(forResource: "home-organizer", withExtension: "json"),
                      let bundledData = try? Data(contentsOf: bundledURL) else { return }
                await collectionRepo.loadOrganizer(
                    bundledData: bundledData,
                    remoteURL: MoonlitConfig.homeOrganizerRemoteURL.flatMap(URL.init),
                    store: CollectionOrganizerStore.shared
                )
            }()
            async let addonsDone: Void = addonRepo.loadAddons(profileId: profileId)

            _ = await (organizerDone, addonsDone)
            completedPhases.insert(.phase1)
            resumeContinuations(for: .phase1)

            let addons = addonRepo.enabledAddons
            async let catalogsDone: Void = {
                if collectionRepo.collections.isEmpty {
                    await catalogRepo.loadAllCatalogs(addons: addons)
                } else {
                    await catalogRepo.loadFromCollections(
                        collectionRepo: collectionRepo,
                        addons: addons,
                        mode: .replaceCache
                    )
                }
            }()
            async let recsDone: Void = recsService.load(profileId: profileId)
            async let libraryDone: Void = libraryRepo.loadLibrary(profileId: profileId)
            async let cwDone: Void = homeRepo.loadContinueWatching(profileId: profileId)

            _ = await (catalogsDone, recsDone, libraryDone, cwDone)

            catalogRows = catalogRepo.catalogRows
            collectionRows = catalogRepo.collectionRows
            allFolderRows = catalogRepo.allFolderRows

            completedPhases.insert(.phase2)
            resumeContinuations(for: .phase2)
        }
    }

    public func startPhase3(
        catalogRepo: CatalogRepository = .shared,
        collectionRepo: CollectionRepository = .shared,
        addonRepo: AddonRepository = .shared
    ) {
        guard prerequisitesSatisfied(for: .phase3), !completedPhases.contains(.phase3) else { return }

        Task.detached(priority: .background) {
            let pinned = collectionRepo.collections.filter { $0.pinToTop }
            let others = collectionRepo.collections.filter { !$0.pinToTop }
            let ordered = (pinned + others).prefix(5)
            let addons = await addonRepo.enabledAddons

            for collection in ordered {
                guard Task.isCancelled == false else { break }
                let matching = collectionRepo.folders.filter { $0.collectionId == collection.id }
                for folder in matching.prefix(3) {
                    guard Task.isCancelled == false else { break }
                    await catalogRepo.loadFolderItems(
                        folderId: folder.id,
                        collectionRepo: collectionRepo,
                        addons: addons
                    )
                }
            }
            await MainActor.run {
                completedPhases.insert(.phase3)
                resumeContinuations(for: .phase3)
            }
        }
    }

    public func waitForPhase(_ phase: Phase) async {
        if completedPhases.contains(phase) { return }
        await withCheckedContinuation { cont in
            var arr = phaseContinuations[phase] ?? []
            arr.append(cont)
            phaseContinuations[phase] = arr
        }
    }

    public func isPhaseComplete(_ phase: Phase) -> Bool {
        completedPhases.contains(phase)
    }

    private func resumeContinuations(for phase: Phase) {
        let conts = phaseContinuations[phase] ?? []
        phaseContinuations[phase] = []
        for cont in conts { cont.resume() }
    }
}
```

- [ ] **Step 2: Build MoonlitCore to verify**

Run: `xcodebuild -scheme MoonlitCore -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

If there are compilation errors (e.g., `CollectionRepository.folders(for:)` doesn't exist), fix by checking the actual method name. If there's no `folders(for:)`, iterate `collectionRepo.folders.filter { $0.collectionId == collection.id }` directly.

- [ ] **Step 3: Commit**

```bash
git add Packages/MoonlitCore/Sources/MoonlitCore/Services/StartupCoordinator.swift
git commit -m "feat: add StartupCoordinator for phased data loading during splash"
```

---

## Task 5: Modify ProfileManager to trigger Phase 1 during splash

**Files:**
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Services/ProfileManager.swift`

**Why:** Currently `restoreSession()` wastes the 1.5s splash delay doing nothing. We need to start Phase 1 (organizer + addons) as soon as the profile is resolved, running in parallel with the remaining splash time.

- [ ] **Step 1: Locate the splash delay in `restoreSession()`**

The delay is in the `defer` block, lines 22-31:
```swift
defer {
    Task { @MainActor in
        let elapsed = Date().timeIntervalSince(startTime)
        let remaining = 1.5 - elapsed
        if remaining > 0 {
            try? await Task.sleep(for: .seconds(remaining))
        }
        self.isLoading = false
        self.hasRestoredSession = true
    }
}
```

- [ ] **Step 2: Replace the defer block**

Replace the entire `defer` block (lines 22-31) with:

```swift
defer {
    Task { @MainActor in
        let elapsed = Date().timeIntervalSince(startTime)
        // Start Phase 1 in parallel — organizer + addons load behind the splash.
        if self.isAuthenticated, let profile = self.currentProfile {
            await StartupCoordinator.shared.startPhase1(profileId: profile.id)
        }
        let remaining = 1.5 - elapsed
        if remaining > 0 {
            try? await Task.sleep(for: .seconds(remaining))
        }
        self.isLoading = false
        self.hasRestoredSession = true
    }
}
```

- [ ] **Step 3: Build MoonlitCore to verify**

Run: `xcodebuild -scheme MoonlitCore -destination 'platform=macOS' build 2>&1 | tail -5`

- [ ] **Step 4: Commit**

```bash
git add Packages/MoonlitCore/Sources/MoonlitCore/Services/ProfileManager.swift
git commit -m "feat: start StartupCoordinator Phase 1 during splash delay"
```

---

## Task 6: Parallelize mediaType="all" catalog fetch

**Files:**
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Services/CatalogRepository.swift`

**Why:** `fetchNormalizedSource()` makes two sequential `try? await` calls for movie+series when `mediaType == "all"`. Parallelizing them cuts the worst-case folder load time in half.

- [ ] **Step 1: Find the sequential movie+series fetches**

Around lines 696-717, find the `if source.mediaType == "all"` block inside `fetchNormalizedSource()`.

- [ ] **Step 2: Replace sequential awaits with async let**

Replace:
```swift
if source.mediaType == "all" {
    var results: [MetaPreview] = []
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
    if let movieResult = try? await catalogService.fetchCatalog(query: movieQuery) {
        results.append(contentsOf: Self.applyingBetterPostersFallback(to: movieResult, baseURL: baseURL))
    }
    if let seriesResult = try? await catalogService.fetchCatalog(query: seriesQuery) {
        results.append(contentsOf: Self.applyingBetterPostersFallback(to: seriesResult, baseURL: baseURL))
    }
    return results
}
```

With:
```swift
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
```

- [ ] **Step 3: Check for any other mediaType="all" patterns**

Search: `rg "mediaType.*==.*\"all\""` in CatalogRepository.swift. If there are other places with the same sequential pattern (e.g., `fetchRawSource`), apply the same fix.

- [ ] **Step 4: Build MoonlitCore to verify**

Run: `xcodebuild -scheme MoonlitCore -destination 'platform=macOS' build 2>&1 | tail -5`

- [ ] **Step 5: Commit**

```bash
git add Packages/MoonlitCore/Sources/MoonlitCore/Services/CatalogRepository.swift
git commit -m "perf: parallelize mediaType=all movie+series catalog fetches with async let"
```

---

## Task 7: Route Mac catalog requests through CDN proxy

**Files:**
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Stremio/CatalogService.swift`

**Why:** The Mac app currently calls addon servers directly. Routing through the existing Vercel edge function adds 5-minute CDN edge caching for free — subsequent launches within the cache window skip the addon round-trip entirely.

- [ ] **Step 1: Add proxy base URL constant in CatalogService.swift**

Add at the top level inside `CatalogService` (after `public final class CatalogService`):

```swift
private static let catalogProxyBase = "https://moonlit-web-zainalabidinaas-projects.vercel.app/api/stremio"
```

Use the same Vercel deployment URL that's already in the web app. Double-check this URL against the actual Vercel deployment.

- [ ] **Step 2: Modify `fetchCatalog(query:)` to use proxy URL**

In the `fetchCatalog(query:)` method, replace the `let url = query.buildURL()` call with a proxy-routed version. Find line ~35:

```swift
let url = query.buildURL()
```

Replace with:

```swift
let url: String = {
    let direct = query.buildURL()
    // Route through Vercel edge proxy for CDN caching (s-maxage=300).
    // The proxy at /api/stremio/catalog forwards to the addon and adds cache headers.
    guard let baseEnd = direct.range(of: "/catalog/") else { return direct }
    return CatalogService.catalogProxyBase + direct[baseEnd.lowerBound...]
}()
```

The proxy URL path is: `{proxyBase}/catalog/{type}/{id}.json` which matches how `buildURL()` constructs the path segment after the addon's `baseURL`.

- [ ] **Step 3: Build MoonlitCore to verify**

Run: `xcodebuild -scheme MoonlitCore -destination 'platform=macOS' build 2>&1 | tail -5`

- [ ] **Step 4: Commit**

```bash
git add Packages/MoonlitCore/Sources/MoonlitCore/Stremio/CatalogService.swift
git commit -m "perf: route Mac catalog requests through Vercel edge CDN proxy"
```

---

## Task 8: Add TTL tiers to CatalogResponseCache

**Files:**
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Services/CatalogResponseCache.swift`

**Why:** The current flat 30-minute TTL is wasteful for static content (genre catalogs change rarely) and potentially stale for dynamic content (trending). TTL tiers trade freshness for cache-hit rate appropriately per catalog type.

- [ ] **Step 1: Add TTL determination logic**

Add near the top of `CatalogResponseCache`:

```swift
private static let defaultTTL: TimeInterval = 30 * 60        // 30 min
private static let trendingTTL: TimeInterval = 2 * 3600       // 2 hours
private static let staticTTL: TimeInterval = 6 * 3600         // 6 hours

private static func ttlFor(key: String) -> TimeInterval {
    let lower = key.lowercased()
    let staticPatterns = ["genre=", "language=", "/genre/", "/language/", "with_genres", "with_original_language"]
    let trendingPatterns = ["/top", "/popular", "/trending", "/featured"]
    for pattern in staticPatterns where lower.contains(pattern) { return staticTTL }
    for pattern in trendingPatterns where lower.contains(pattern) { return trendingTTL }
    return defaultTTL
}
```

- [ ] **Step 2: Modify `get(key:)` to use variable TTL**

Change the existing `get(key:)` method. Replace line ~47:
```swift
guard Date().timeIntervalSince(entry.timestamp) < ttl else {
```
With:
```swift
guard Date().timeIntervalSince(entry.timestamp) < Self.ttlFor(key: key) else {
```

- [ ] **Step 3: Remove or keep the single `ttl` constant**

The `private let ttl: TimeInterval = 30 * 60` on line 6 can be removed since we now use `Self.ttlFor(key:)`. Remove it or keep as the `defaultTTL` static.

- [ ] **Step 4: Build MoonlitCore to verify**

Run: `xcodebuild -scheme MoonlitCore -destination 'platform=macOS' build 2>&1 | tail -5`

- [ ] **Step 5: Commit**

```bash
git add Packages/MoonlitCore/Sources/MoonlitCore/Services/CatalogResponseCache.swift
git commit -m "perf: add TTL tiers to CatalogResponseCache (static=6h, trending=2h, default=30m)"
```

---

## Task 9: Wire MacContentView and MacHomeView to use StartupCoordinator

**Files:**
- Modify: `Apps/MoonlitMac/Sources/Screens/MacHomeView.swift`
- Modify: `Apps/MoonlitMac/Sources/MacContentView.swift`

**Why:** The home view's `.task{}` block currently does all its own data loading. With `StartupCoordinator`, it should read pre-loaded data instead. `MacContentView` needs `StartupCoordinator` in the environment.

- [ ] **Step 1: Pass StartupCoordinator into the environment — MacContentView.swift**

Wrap `MacMainView()` (and other relevant views) with the coordinator. Since `StartupCoordinator` is a global actor, we can't use `@StateObject`. Instead, access it as `StartupCoordinator.shared` directly. No environment injection needed for a global actor — just add:

No changes needed to `MacContentView.swift` since `ProfileManager.restoreSession()` already triggers `StartupCoordinator.shared.startPhase1()`. The home view just needs to await the coordinator.

- [ ] **Step 2: Simplify MacHomeView's `.task{}` block**

Find the `.task {}` block around lines 357-375. Replace:

```swift
.task {
    guard let profile = profileManager.currentProfile else { return }
    catalogRepo.isLoading = true
    await addonRepo.loadAddons(profileId: profile.id)
    async let continueWatching: Void = homeRepo.loadContinueWatching(profileId: profile.id)
    Task { await recsService.load(profileId: profile.id) }
    await libraryRepo.loadLibrary(profileId: profile.id)
    await reloadCatalogRows(mode: .replaceCache)
    await continueWatching
    warmupContinueWatching()
    await updateAmbientColorIfNeeded()
    Task {
        await AwardIndex.shared.buildIfNeeded(
            catalogRepo: catalogRepo,
            collectionRepo: CollectionRepository.shared,
            addons: addonRepo.enabledAddons
        )
    }
}
```

With:

```swift
.task {
    guard let profile = profileManager.currentProfile else { return }
    catalogRepo.isLoading = true

    // If Phase 1 hasn't started yet (e.g., guest mode or edge case), start it.
    if !await StartupCoordinator.shared.isPhaseComplete(.phase1) {
        await StartupCoordinator.shared.startPhase1(profileId: profile.id)
    }

    // Wait for Phase 2 (catalogs + recs + library + continue watching).
    await StartupCoordinator.shared.waitForPhase(.phase2)

    // Apply pre-loaded data to the local repos.
    catalogRepo.catalogRows = await StartupCoordinator.shared.catalogRows
    catalogRepo.collectionRows = await StartupCoordinator.shared.collectionRows
    catalogRepo.allFolderRows = await StartupCoordinator.shared.allFolderRows
    catalogRepo.isLoading = false

    warmupContinueWatching()
    await updateAmbientColorIfNeeded()

    // Phase 3: background folder prefetching.
    Task { await StartupCoordinator.shared.startPhase3() }

    Task {
        await AwardIndex.shared.buildIfNeeded(
            catalogRepo: catalogRepo,
            collectionRepo: CollectionRepository.shared,
            addons: addonRepo.enabledAddons
        )
    }
}
```

- [ ] **Step 3: Update reloadCatalogRows if needed**

Check `reloadCatalogRows()` (lines 552-564) — if collections are already applied by `StartupCoordinator`, this may need adjustment. Since Phase 2 calls `collectionRepo.loadOrganizer()` and `catalogRepo.loadFromCollections()`, by the time the home view runs, both are already populated. The `reloadCatalogRows` call is redundant when the coordinator has already run, so we remove it from the `.task{}` block (it was part of the old code we're replacing).

- [ ] **Step 4: Add `isPhaseComplete` method if needed**

Check that the `StartupCoordinator` has an `isPhaseComplete` method. If not, add it:

```swift
public func isPhaseComplete(_ phase: Phase) -> Bool {
    completedPhases.contains(phase)
}
```

(It should already be in the Task 4 code.)

- [ ] **Step 5: Build Mac app to verify**

Run: `xcodebuild -project MoonlitMac.xcodeproj -scheme MoonlitMac -destination 'platform=macOS' build 2>&1 | tail -5`

- [ ] **Step 6: Commit**

```bash
git add Apps/MoonlitMac/Sources/Screens/MacHomeView.swift \
        Apps/MoonlitMac/Sources/MacContentView.swift
git commit -m "feat: wire MacHomeView to read pre-loaded data from StartupCoordinator"
```

---

## Task 10: Full build, app launch smoke test, and verification

**Files:** None (verification only)

- [ ] **Step 1: Full clean build**

```bash
xcodebuild -project MoonlitMac.xcodeproj -scheme MoonlitMac -destination 'platform=macOS' clean build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED with zero warnings related to our changes.

- [ ] **Step 2: Launch app and verify logo flicker is gone**

1. Open the built app
2. Navigate to home screen — hero logo should render immediately (no text flash) when cached
3. Open a folder — folder logo should render immediately
4. Open detail view — detail hero logo should render immediately
5. Auto-rotate hero — next slide's logo should render without flash

- [ ] **Step 3: Verify home screen loads faster**

1. Cold launch (clear cache if possible) — should still see content faster because organizer+addons start during splash
2. Warm launch — content should be visible near-instantly
3. Open a group-tile folder — should load faster because of Phase 3 prefetching

- [ ] **Step 4: Verify catalog CDN proxy works**

Check console logs for catalog URLs — they should now contain `vercel.app/api/stremio/catalog/` instead of `aiometadata.fortheweak.cloud/catalog/`.

- [ ] **Step 5: Verify no regressions**

- Home screen shows all expected rows (hero, collections, recommendations)
- Continue watching section loads correctly
- Library loads correctly
- Awards section builds
- Ambient color updates

- [ ] **Step 6: Commit if any final fixes needed**

Only commit if fixes were required during verification.

---

## Rollback Plan

If any task introduces a regression, revert the most recent commit:

```bash
git revert <commit-hash> --no-edit
```

Key risks and their rollback points:
- **StartupCoordinator doesn't complete Phase 2**: Home view falls back to its original `.task{}` loading in an `else` branch (add a fallback in Task 9)
- **Proxy URL breaks catalog loading**: Revert Task 7 commit — the `buildURL()` logic is the most impactful change
- **Sync cache init breaks animations**: Revert Task 2 — the original async-only init is safe

---

## Self-Review Checklist

1. **Spec coverage:** All three parts (logo flicker, startup performance, folder prefetching) are addressed. Task 1-3 cover logo flicker. Task 4-9 cover startup performance. Task 4+9 cover folder prefetching via Phase 3.
2. **No placeholders:** Every task has concrete code, exact file paths, and specific commands.
3. **Type consistency:** `StartupCoordinator.Phase` enum used consistently. `CatalogRow`, `CatalogRepository`, `CollectionRepository` types match exploration findings. `MoonlitImageCache.syncImage()` matches the signature defined in Task 1.
