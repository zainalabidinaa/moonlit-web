# Fusion Playback, Search, and Browse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved compact playback alert, Fusion-style search modal, and leading Liquid Glass Browse menu in Moonlit iOS.

**Architecture:** Keep stream classification in MoonlitCore and rendering state in the SwiftUI screens. Introduce small private SwiftUI subviews for the alert, modal, and Browse menu so each screen owns navigation but not unrelated layout details.

**Tech Stack:** Swift 6, SwiftUI, MoonlitCore, XCTest, XcodeGen, Revyl cloud-device verification.

## Global Constraints

- Preserve all pre-existing worktree changes; stage no files because this shared worktree has user changes already staged/unstaged.
- Playback alert copy is exactly `No results found.`
- The alert is compact and overlays the detail artwork; it has no CTA.
- Search retains the existing TMDB and add-on search behavior and only changes presentation.
- Use `Button` and dedicated accessibility labels for all new controls.
- Use native Liquid Glass only under `#available(iOS 26, *)`; use the existing material/glass fallback otherwise.
- Verify on the Revyl cloud device and share its viewer URL when available.

---

### Task 1: Model stream-empty outcomes

**Files:**
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Services/StreamRepository.swift`
- Modify: `Packages/MoonlitCore/Tests/MoonlitCoreTests/MoonlitCoreTests.swift`

**Interfaces:**
- Produces: `public enum StreamEmptyReason: Equatable { case noCompatibleAddon; case noResults }`
- Produces: `@Published public private(set) var emptyReason: StreamEmptyReason?`
- Consumes: `AddonManifest.hasResource(_:)`, `AddonManifest.canHandleStream(type:)`

- [ ] **Step 1: Write failing classification tests**

```swift
func testNoCompatibleAddonSetsEmptyReason() async {
    let repository = StreamRepository.makeForTesting(streamService: .empty)
    await repository.fetchStreams(type: "movie", id: "tt123", addons: [.catalogOnly])
    XCTAssertEqual(repository.emptyReason, .noCompatibleAddon)
}

func testEligibleAddonWithNoStreamsSetsNoResultsReason() async {
    let repository = StreamRepository.makeForTesting(streamService: .empty)
    await repository.fetchStreams(type: "movie", id: "tt123", addons: [.movieStream])
    XCTAssertEqual(repository.emptyReason, .noResults)
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run: `swift test --package-path Packages/MoonlitCore --filter MoonlitCoreTests.StreamEmptyReason`

Expected: compilation failure because `StreamEmptyReason`, the test factory, and `emptyReason` do not exist.

- [ ] **Step 3: Add the minimal public outcome state**

```swift
public enum StreamEmptyReason: Equatable {
    case noCompatibleAddon
    case noResults
}

@Published public private(set) var emptyReason: StreamEmptyReason?

public func clearStreams() {
    streams = []
    emptyReason = nil
    isLoading = false
}
```

Set `.noCompatibleAddon` immediately after an empty eligible-addon filter; reset it before each request; set `.noResults` after all eligible requests complete without a playable result. Do not set a reason for folder or offline early exits.

- [ ] **Step 4: Run the focused tests and verify they pass**

Run: `swift test --package-path Packages/MoonlitCore --filter MoonlitCoreTests.StreamEmptyReason`

Expected: PASS.

### Task 2: Replace the automatic playback message with a compact alert

**Files:**
- Create: `Apps/MoonlitApp/Sources/Components/PlaybackUnavailableAlert.swift`
- Modify: `Apps/MoonlitApp/Sources/Screens/StreamSelectionScreen.swift`
- Test: `Apps/MoonlitApp/Tests/SnapshotTests.swift`

**Interfaces:**
- Consumes: `StreamRepository.emptyReason`, `StreamSelectionScreen.episodeTitle`, `StreamSelectionScreen.mediaName`
- Produces: `PlaybackUnavailableAlert(contextTitle: String?, message: String = "No results found.")`

- [ ] **Step 1: Add a failing snapshot or view assertion**

```swift
func testPlaybackUnavailableAlertUsesApprovedCopy() throws {
    let view = PlaybackUnavailableAlert(contextTitle: "E1 · Pilot")
    assertSnapshot(of: view, as: .image(layout: .device(config: .iPhone13)))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `xcodebuild test -scheme MoonlitApp -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MoonlitAppTests/SnapshotTests/testPlaybackUnavailableAlertUsesApprovedCopy`

Expected: compilation failure because `PlaybackUnavailableAlert` does not exist.

- [ ] **Step 3: Implement the compact alert and overlay it only after a terminal empty request**

```swift
struct PlaybackUnavailableAlert: View {
    let contextTitle: String?

    var body: some View {
        VStack(spacing: 18) {
            if let contextTitle { Text(contextTitle).font(.headline) }
            Text("No results found.")
                .foregroundStyle(.white.opacity(0.65))
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
        .glassCard(cornerRadius: 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No results found")
    }
}
```

In `StreamSelectionScreen`, replace the `automaticStatusOverride` string path with an overlay that is visible when `!streamRepo.isLoading`, `didAutoLaunch`, `cachedPlayableStreams.isEmpty`, and `streamRepo.emptyReason != nil`. Use `"E\\(season) · E\\(episode)"`/episode title when available, otherwise the media name. Keep `PlaybackLoadingView` in loading mode until the request completes.

- [ ] **Step 4: Run targeted tests and build**

Run: `xcodebuild test -scheme MoonlitApp -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MoonlitAppTests/SnapshotTests`

Expected: PASS.

### Task 3: Present Search as Fusion-style modal

**Files:**
- Create: `Apps/MoonlitApp/Sources/Components/FusionSearchModal.swift`
- Modify: `Apps/MoonlitApp/Sources/Screens/SearchScreen.swift`
- Test: `Apps/MoonlitApp/Tests/SnapshotTests.swift`

**Interfaces:**
- Consumes: `RecentSearchesStore.recent`, `SearchScreen.performSearch(_:)`
- Produces: `FusionSearchModal(query:onQueryChange:recentSearches:onSelectRecent:onDismiss:)`

- [ ] **Step 1: Add failing modal state tests**

```swift
func testFusionSearchModalShowsRecentSearchesBeforeEntry() throws {
    let view = FusionSearchModal(
        query: .constant(""), recentSearches: ["Severance"],
        onQueryChange: {}, onSelectRecent: { _ in }, onDismiss: {}
    )
    assertSnapshot(of: view, as: .image(layout: .device(config: .iPhone13)))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `xcodebuild test -scheme MoonlitApp -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MoonlitAppTests/SnapshotTests/testFusionSearchModalShowsRecentSearchesBeforeEntry`

Expected: compilation failure because `FusionSearchModal` does not exist.

- [ ] **Step 3: Implement modal presentation without changing repositories**

```swift
@State private var isSearchModalPresented = false

Button("Search", systemImage: "magnifyingglass") {
    isSearchModalPresented = true
}
.fullScreenCover(isPresented: $isSearchModalPresented) {
    FusionSearchModal(
        query: $query,
        recentSearches: recentSearches.recent,
        onQueryChange: performSearch,
        onSelectRecent: { query = $0 },
        onDismiss: { query = ""; searchRepo.results = []; tmdbResults = .init() }
    )
}
```

Use `@FocusState` in the modal. Show the centered magnifier and `Type to search…` only while the query is empty and the field is not focused. Show recent search chips only while the query is empty. Use a bottom-aligned field, circular Close button, `.background(.ultraThinMaterial)` over a dark, blurred backdrop, and a results scroll view using the existing row views.

- [ ] **Step 4: Run modal tests and build**

Run: `xcodebuild test -scheme MoonlitApp -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MoonlitAppTests/SnapshotTests`

Expected: PASS.

### Task 4: Replace Home category pills with a leading Browse menu

**Files:**
- Create: `Apps/MoonlitApp/Sources/Components/HomeBrowseMenu.swift`
- Modify: `Apps/MoonlitApp/Sources/Screens/HomeScreen.swift`
- Modify: `Apps/MoonlitApp/Sources/Components/CategoryPillsRow.swift` (remove call-site dependence; do not delete the component in this task)
- Test: `Apps/MoonlitApp/Tests/SnapshotTests.swift`

**Interfaces:**
- Consumes: `HomeCategoryState`, `HomeCategoryFilter`, `HomeScreen.selectedGenreMediaKind`, `HomeScreen.showGenre`
- Produces: `HomeBrowseMenu(selection:onSelectCategory:onSelectCategories:)`

- [ ] **Step 1: Add failing menu snapshot/accessibility coverage**

```swift
func testHomeBrowseMenuExposesAllApprovedDestinations() throws {
    let view = HomeBrowseMenu(selection: .constant(.featured), onSelectCategory: { _ in }, onSelectCategories: { _ in })
    assertSnapshot(of: view, as: .image(layout: .device(config: .iPhone13)))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `xcodebuild test -scheme MoonlitApp -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MoonlitAppTests/SnapshotTests/testHomeBrowseMenuExposesAllApprovedDestinations`

Expected: compilation failure because `HomeBrowseMenu` does not exist.

- [ ] **Step 3: Implement leading menu and retain trailing profile**

```swift
.toolbar {
    ToolbarItem(placement: .topBarLeading) {
        HomeBrowseMenu(selection: $categoryState.category,
            onSelectCategory: { categoryState = HomeCategoryState(category: $0) },
            onSelectCategories: { type in
                selectedGenreMediaKind = type
                selectedGenre = nil
                showGenre = true
            })
    }
    ToolbarItem(placement: .topBarTrailing) { profileButton }
}
```

For iOS 26, place the interactive Browse button inside `GlassEffectContainer` and apply `.glassEffect(.regular.interactive(), in: .capsule)` after all layout modifiers. Use `.glassCapsule(interactive: true)` or the existing project fallback for older systems. Remove the `CategoryPillsRow` call beneath `ParallaxHero`; retain existing `visibleCatalogRows` filtering.

- [ ] **Step 4: Run focused tests and build**

Run: `xcodebuild test -scheme MoonlitApp -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MoonlitAppTests/SnapshotTests`

Expected: PASS.

### Task 5: Integrate and verify on device

**Files:**
- Modify only files from Tasks 1–4 when fixing verified issues.

- [ ] **Step 1: Run all core and iOS tests**

Run: `swift test --package-path Packages/MoonlitCore && xcodebuild test -scheme MoonlitApp -destination 'platform=iOS Simulator,name=iPhone 16'`

Expected: PASS.

- [ ] **Step 2: Launch Revyl and share viewer URL immediately**

Run from `Apps/MoonlitApp`: `revyl dev --remote --detach --json`

Expected: JSON response contains `viewer_url`; send it to the user before waiting for the build.

- [ ] **Step 3: Validate each approved outcome**

```bash
revyl dev status
revyl device validation -s 0 "Automatic playback with no source shows a compact No results found alert over the title artwork" --json
revyl device validation -s 0 "Search opens as a full-height Fusion-style modal with recent searches before typing" --json
revyl device validation -s 0 "Home shows Browse on the left and the profile avatar on the right" --json
```

Expected: `last_rebuild.status` is `success` and every validation reports success.

- [ ] **Step 4: Review only the intended diff**

Run: `git diff -- Apps/MoonlitApp/Sources/Screens/StreamSelectionScreen.swift Apps/MoonlitApp/Sources/Screens/SearchScreen.swift Apps/MoonlitApp/Sources/Screens/HomeScreen.swift Apps/MoonlitApp/Sources/Components/PlaybackUnavailableAlert.swift Apps/MoonlitApp/Sources/Components/FusionSearchModal.swift Apps/MoonlitApp/Sources/Components/HomeBrowseMenu.swift Packages/MoonlitCore/Sources/MoonlitCore/Services/StreamRepository.swift`

Expected: only approved behavior and test-supporting changes are present.
