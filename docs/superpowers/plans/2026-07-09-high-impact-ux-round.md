# High-Impact UX Round — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship five independent UX improvements to MoonlitMac — nav cleanup, quick add-to-library, a player autohide fix, onboarding polish, and a direct-file Downloads/offline feature.

**Architecture:** SwiftUI (macOS 14+) app with shared logic in the MoonlitCore Swift package. New pure/business logic (DownloadManager) lands in MoonlitCore with XCTest coverage; SwiftUI view work is verified by build + manual run (the codebase has no view unit tests). Phases are independent and individually shippable — execute and commit them in order.

**Tech Stack:** Swift 5, SwiftUI, AppKit interop, MoonlitCore package, `URLSession` background downloads, `xcodebuild`, XCTest.

**Spec:** `docs/superpowers/specs/2026-07-09-high-impact-ux-round-design.md`

---

## Conventions used throughout

- **Build check (view work):**
  `xcodebuild -scheme MoonlitMac -configuration Debug -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build`
  Expected tail: `** BUILD SUCCEEDED **`
- **Unit tests (MoonlitCore):**
  `swift test --package-path Packages/MoonlitCore --filter <TestName>`
- **New Mac `.swift` files need 4 `project.pbxproj` edits** (no synced groups). Use the verified anchor-insert script (see Task 5.3 for the reusable form). Generate two 24-hex-uppercase UUIDs per file with:
  `python3 -c "import secrets;print(secrets.token_hex(12).upper());print(secrets.token_hex(12).upper())"`
- Repo root: `/Users/zain/projects/Moonlit`. Mac app root: `Apps/MoonlitMac`.
- Commit after each task with a `feat:`/`fix:`/`chore:` message.

---

## Phase 1 — Nav cleanup

### Task 1.1: Delete the dead-code sidebar

**Files:**
- Delete: `Apps/MoonlitMac/Sources/Components/MacSidebar.swift`
- Modify: `Apps/MoonlitMac/MoonlitMac.xcodeproj/project.pbxproj`

- [ ] **Step 1: Confirm it is unused**

Run: `grep -rn "MacSidebar" Apps/MoonlitMac/Sources | grep -v "struct MacSidebar"`
Expected: no output (only the definition exists).

- [ ] **Step 2: Delete the file and its 4 pbxproj references**

```bash
cd /Users/zain/projects/Moonlit/Apps/MoonlitMac
rm Sources/Components/MacSidebar.swift
python3 - MoonlitMac.xcodeproj/project.pbxproj <<'PY'
import sys
p=sys.argv[1]; L=open(p).read().splitlines(keepends=True)
L=[l for l in L if "MacSidebar.swift" not in l]
open(p,"w").writelines(L)
print("removed MacSidebar.swift refs")
PY
plutil -lint MoonlitMac.xcodeproj/project.pbxproj
```
Expected: `... OK` and no remaining `MacSidebar` refs.

- [ ] **Step 3: Build**

Run the build check. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "chore: remove unused MacSidebar (dead-end nav placeholders)"
```

### Task 1.2: Add a Downloads destination to the nav

**Files:**
- Modify: `Apps/MoonlitMac/Sources/Components/PillNavBar.swift` (`MacMainTab` enum + `PillNavBar` body)
- Modify: `Apps/MoonlitMac/Sources/Screens/MacMainView.swift` (`tabContent`)

- [ ] **Step 1: Add the `.downloads` case to `MacMainTab`**

In `PillNavBar.swift`, extend the enum (keep `movies`/`series` shortcuts intact):

```swift
enum MacMainTab: String, CaseIterable {
    case home, movies, series, library, downloads, settings, admin
    // icon:
    // case .downloads: return "arrow.down.circle.fill"
    // label:
    // case .downloads: return "Downloads"
    // keyboardShortcut:
    // case .downloads: return "5"   // bump settings→"6", admin→"7"
}
```
Add the matching `case .downloads` arms to `icon`, `label`, and `keyboardShortcut`, renumbering `settings`/`admin` shortcuts so they stay unique.

- [ ] **Step 2: Render a Downloads icon button in `PillNavBar`**

Inside the trailing `HStack(spacing: 6) { searchField; accountButton }`, add a downloads button before `searchField`:

```swift
Button {
    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { selectedTab = .downloads }
} label: {
    Image(systemName: "arrow.down.circle")
        .font(.system(size: 15, weight: .medium))
        .foregroundColor(selectedTab == .downloads ? .white : .white.opacity(0.6))
        .padding(6)
        .background(selectedTab == .downloads ? Color.white.opacity(0.10) : .clear, in: Circle())
        .contentShape(Circle())
}
.buttonStyle(.plain)
.accessibilityLabel("Downloads")
.keyboardShortcut(MacMainTab.downloads.keyboardShortcut, modifiers: .command)
```

- [ ] **Step 3: Route `.downloads` in `MacMainView.tabContent`**

Add a case to the `switch selectedTab` in `tabContent`:

```swift
case .downloads:
    MacDownloadsView(onSelectMedia: { item in openMedia(item) })
```
(`MacDownloadsView` is created in Phase 5. Until Phase 5 lands, temporarily route to `MacLibraryView(...)` or a `Text("Downloads")` placeholder so the app builds; replace when Phase 5 is done.)

- [ ] **Step 4: Build**

Run the build check. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual check**

Launch the app; a download icon appears in the nav; clicking it selects the Downloads destination; ⌘5 works; Home/Movies/Series/Library unaffected.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: add Downloads destination to PillNavBar"
```

---

## Phase 2 — Quick Add to Library / "My List"

### Task 2.1: Create a reusable `LibraryToggleButton`

**Files:**
- Create: `Apps/MoonlitMac/Sources/Components/LibraryToggleButton.swift`
- Modify: `Apps/MoonlitMac/MoonlitMac.xcodeproj/project.pbxproj`

Rationale: `MediaCard` is `Equatable` on value inputs, so watchlist state can't live inside it (it would skip rebuilds when the library changes). A small overlay view that observes `LibraryRepository.shared` updates independently.

- [ ] **Step 1: Write the view**

```swift
import SwiftUI
import MoonlitCore

/// Circular add/remove-from-library toggle overlaid on media tiles. Observes the
/// shared LibraryRepository so its ✓ state stays live regardless of MediaCard's
/// Equatable body-skipping.
struct LibraryToggleButton: View {
    let item: MetaPreview
    var size: CGFloat = 28

    @EnvironmentObject private var profileManager: ProfileManager
    @ObservedObject private var libraryRepo = LibraryRepository.shared
    @State private var isBusy = false

    private var isSaved: Bool { libraryRepo.isInLibrary(mediaId: item.id) }

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isSaved ? "checkmark" : "plus")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(.black.opacity(0.55), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(isSaved ? 0.5 : 0.22), lineWidth: 0.75))
                .scaleEffect(isBusy ? 0.85 : 1)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isSaved)
        .help(isSaved ? "Remove from Library" : "Add to Library")
    }

    private func toggle() {
        guard let profileId = profileManager.currentProfile?.id else { return }
        isBusy = true
        Task {
            await libraryRepo.toggleLibrary(
                profileId: profileId,
                mediaId: item.id,
                mediaType: item.type.rawValue,
                name: item.name,
                poster: item.poster
            )
            isBusy = false
        }
    }
}
```

- [ ] **Step 2: Register the file in `project.pbxproj`** (4 edits, see Task 5.3 script form; anchor on an existing Components file such as `MediaCard.swift`).

- [ ] **Step 3: Build**

Run the build check. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add LibraryToggleButton for quick add-to-library"
```

### Task 2.2: Overlay the toggle on media tiles

**Files:**
- Modify: `Apps/MoonlitMac/Sources/Components/MediaCard.swift` (`mediaTile`, ~lines 184-217)

- [ ] **Step 1: Add the overlay on the poster artwork**

In `mediaTile`, attach an overlay to the `artwork(...)` block (the one framed to `cardWidth/cardHeight`), visible on hover or when already saved:

```swift
artwork(contentMode: .fill)
    .frame(width: cardWidth, height: cardHeight)
    .modifier(TileChrome(cornerRadius: cornerRadius, isHovering: isHovering, haloColor: haloColor))
    .overlay(alignment: .topTrailing) {
        LibraryToggleButton(item: item)
            .padding(7)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
    }
    .scaleEffect(isHovering ? 1.04 : 1.0)
    .animation(.spring(response: 0.30, dampingFraction: 0.78), value: isHovering)
    .onHover { hovering in
        isHovering = hovering
        if hovering { resolveHaloIfNeeded() }
    }
```
(Show it only on hover to keep tiles clean; saved-state is visible on hover as a ✓. Do **not** add it to folder tiles — only `mediaTile`.)

- [ ] **Step 2: Build**

Run the build check. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual check**

Hover a movie/series poster on Home → ＋ appears top-right; click → becomes ✓ and the title shows in the Library tab; hover again + click ✓ → removed. Relaunch → state persists (Supabase sync).

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: quick add-to-library button on media cards"
```

---

## Phase 3 — Player autohide fix (#9)

### Task 3.1: Sync playback state so controls auto-hide

**Files:**
- Modify: `Apps/MoonlitMac/Sources/Screens/MacPlayerView.swift`

Root cause: `visibility.setPlayback(isPlaying:)` is never called, so `PlayerControlVisibilityState.isPlaying` stays `false` and `shouldScheduleAutoHide` (`controlsVisible && isPlaying`) is always false.

- [ ] **Step 1: Add an `onChange` for `engine.isPlaying`**

Next to the other `.onChange` modifiers in the body (~line 344), add:

```swift
.onChange(of: engine.isPlaying) { _, playing in
    visibility.setPlayback(isPlaying: playing)
    if playing {
        scheduleAutoHideIfNeeded()
    } else {
        hideTask?.cancel()
    }
}
```

- [ ] **Step 2: Build**

Run the build check. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual check**

Play a video → after ~2.4s of no mouse movement the controls fade; move the mouse or press a key → they reappear; pause → controls stay visible.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "fix: player controls now auto-hide during playback"
```

### Task 3.2: Hide the cursor with the controls

**Files:**
- Modify: `Apps/MoonlitMac/Sources/Screens/MacPlayerView.swift` (`showControls()`, `hideControlsIfAllowed()`, plus a disappear cleanup)

- [ ] **Step 1: Hide/show the cursor alongside controls**

```swift
private func showControls() {
    NSCursor.unhide()
    visibility.registerInteraction()
    scheduleAutoHideIfNeeded()
}

private func hideControlsIfAllowed() {
    guard !isSeeking else { return }
    visibility.hideAfterInactivityIfAllowed()
    if !visibility.controlsVisible { NSCursor.hide() }
}
```

- [ ] **Step 2: Ensure the cursor is never left hidden**

On the player root view add:

```swift
.onDisappear { NSCursor.unhide() }
```

- [ ] **Step 3: Build**

Run the build check. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual check**

During playback the cursor disappears with the controls and returns on movement; leaving the player never leaves the cursor stuck hidden.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: hide cursor with player controls"
```

---

## Phase 4 — Onboarding (already largely present)

A 3-page `MacOnboardingView` (welcome → collections → sign-in) already exists in
`MacContentView.swift`, gated by `@AppStorage("moonlit.hasSeenOnboarding")`, and
avatar selection happens in the (now improved) `MacCreateProfile`. The "minimal welcome"
requirement is therefore already met.

### Task 4.1: Verify the existing flow, optional copy polish

**Files:**
- Modify (optional): `Apps/MoonlitMac/Sources/MacContentView.swift`

- [ ] **Step 1: Verify the flow end-to-end**

Reset the flag and relaunch to see onboarding:
`defaults delete com.moonlit.mac moonlit.hasSeenOnboarding` (then run the app).
Expected: welcome → collections → sign-in pages appear once; "Skip"/"Sign in with email" both dismiss and don't reappear on next launch.

- [ ] **Step 2 (optional): tighten copy only if desired**

No structural change required. If polishing, edit the page `Text(...)` strings in the private `MacOnboardingView`. Skip if the current copy is fine.

- [ ] **Step 3: Commit only if changed**

```bash
git add -A && git commit -m "chore: onboarding copy polish"
```

---

## Phase 5 — Downloads / offline (direct files v1)

### Task 5.1: `DownloadItem` model + downloadability check (TDD)

**Files:**
- Create: `Packages/MoonlitCore/Sources/MoonlitCore/Models/DownloadItem.swift`
- Create: `Packages/MoonlitCore/Sources/MoonlitCore/Services/DownloadSupport.swift`
- Test: `Packages/MoonlitCore/Tests/MoonlitCoreTests/DownloadTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import MoonlitCore

final class DownloadTests: XCTestCase {
    func testHLSNotDownloadable() {
        XCTAssertFalse(DownloadSupport.isDownloadable("https://x.com/master.m3u8"))
        XCTAssertFalse(DownloadSupport.isDownloadable("https://x.com/live.m3u8?token=1"))
    }
    func testDirectFilesDownloadable() {
        XCTAssertTrue(DownloadSupport.isDownloadable("https://x.com/movie.mkv"))
        XCTAssertTrue(DownloadSupport.isDownloadable("https://x.com/movie.mp4?e=9"))
    }
    func testProgressFraction() {
        var item = DownloadItem(id: "1", mediaId: "tt1", type: "movie", name: "M",
                                poster: nil, quality: "1080p",
                                remoteURL: "https://x/m.mp4", localFileName: "1.mp4",
                                totalBytes: 200, receivedBytes: 50, state: .downloading,
                                createdAt: Date())
        XCTAssertEqual(item.progress, 0.25, accuracy: 0.001)
        item.totalBytes = 0
        XCTAssertEqual(item.progress, 0)
    }
    func testCodableRoundTrip() throws {
        let item = DownloadItem(id: "1", mediaId: "tt1", type: "movie", name: "M",
                                poster: "p", quality: nil, remoteURL: "u",
                                localFileName: "1.mp4", totalBytes: 10, receivedBytes: 10,
                                state: .completed, createdAt: Date(timeIntervalSince1970: 0))
        let data = try JSONEncoder().encode(item)
        let back = try JSONDecoder().decode(DownloadItem.self, from: data)
        XCTAssertEqual(back, item)
    }
}
```

- [ ] **Step 2: Run — verify it fails**

Run: `swift test --package-path Packages/MoonlitCore --filter DownloadTests`
Expected: FAIL (`DownloadItem` / `DownloadSupport` undefined).

- [ ] **Step 3: Implement the model**

`DownloadItem.swift`:

```swift
import Foundation

public enum DownloadState: String, Codable, Sendable {
    case queued, downloading, paused, completed, failed
}

public struct DownloadItem: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let mediaId: String
    public let type: String
    public let name: String
    public let poster: String?
    public let quality: String?
    public let remoteURL: String
    public var localFileName: String
    public var totalBytes: Int64
    public var receivedBytes: Int64
    public var state: DownloadState
    public let createdAt: Date

    public init(id: String, mediaId: String, type: String, name: String, poster: String?,
                quality: String?, remoteURL: String, localFileName: String,
                totalBytes: Int64, receivedBytes: Int64, state: DownloadState, createdAt: Date) {
        self.id = id; self.mediaId = mediaId; self.type = type; self.name = name
        self.poster = poster; self.quality = quality; self.remoteURL = remoteURL
        self.localFileName = localFileName; self.totalBytes = totalBytes
        self.receivedBytes = receivedBytes; self.state = state; self.createdAt = createdAt
    }

    public var progress: Double {
        totalBytes > 0 ? Double(receivedBytes) / Double(totalBytes) : 0
    }
}
```

`DownloadSupport.swift`:

```swift
import Foundation

public enum DownloadSupport {
    /// v1 supports direct single-file streams only; HLS manifests need remuxing.
    public static func isDownloadable(_ urlString: String) -> Bool {
        let lower = urlString.lowercased()
        guard let comps = URLComponents(string: urlString) else { return false }
        let ext = (comps.path as NSString).pathExtension.lowercased()
        if ext == "m3u8" || ext == "m3u" { return false }
        if lower.contains(".m3u8") { return false }
        return true
    }
}
```

- [ ] **Step 4: Run — verify pass**

Run: `swift test --package-path Packages/MoonlitCore --filter DownloadTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: DownloadItem model + downloadability check (TDD)"
```

### Task 5.2: `DownloadManager` service

**Files:**
- Create: `Packages/MoonlitCore/Sources/MoonlitCore/Services/DownloadManager.swift`
- Test: extend `Packages/MoonlitCore/Tests/MoonlitCoreTests/DownloadTests.swift`

- [ ] **Step 1: Add a persistence round-trip test**

```swift
    func testPersistenceRoundTrip() async {
        let mgr = DownloadManager(persistenceName: "test-downloads-\(UUID().uuidString).json")
        let item = DownloadItem(id: "1", mediaId: "tt1", type: "movie", name: "M", poster: nil,
                                quality: nil, remoteURL: "https://x/m.mp4", localFileName: "1.mp4",
                                totalBytes: 10, receivedBytes: 0, state: .queued, createdAt: Date())
        await mgr.upsertForTest(item)
        let reloaded = DownloadManager(persistenceName: mgr.persistenceNameForTest)
        await reloaded.loadForTest()
        XCTAssertEqual(reloaded.downloads.map(\.id), ["1"])
    }
```

- [ ] **Step 2: Run — verify it fails**

Run: `swift test --package-path Packages/MoonlitCore --filter DownloadTests`
Expected: FAIL (`DownloadManager` undefined).

- [ ] **Step 3: Implement the manager**

Create `DownloadManager.swift` — `@MainActor`, `ObservableObject`, `@Published var downloads: [DownloadItem]`, a `URLSession` with `.background(withIdentifier:)` config and a `URLSessionDownloadDelegate`. Persist `downloads` as JSON in Application Support. Public API:

```swift
@MainActor
public final class DownloadManager: NSObject, ObservableObject {
    public static let shared = DownloadManager()

    @Published public private(set) var downloads: [DownloadItem] = []

    private let persistenceName: String
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.background(withIdentifier: "com.moonlit.mac.downloads")
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    public init(persistenceName: String = "downloads.json") {
        self.persistenceName = persistenceName
        super.init()
        load()
    }

    /// Enqueue a direct-file download. Returns false if the URL is HLS or already present.
    @discardableResult
    public func startDownload(mediaId: String, type: String, name: String, poster: String?,
                              quality: String?, url: String, headers: [String: String]?) -> Bool {
        guard DownloadSupport.isDownloadable(url) else { return false }
        guard !downloads.contains(where: { $0.mediaId == mediaId
            && ($0.state == .queued || $0.state == .downloading || $0.state == .completed) }) else { return false }
        // build DownloadItem, apply headers (minus Range) to a URLRequest,
        // create session.downloadTask(with:), map task→item id, persist, resume.
        // ...
        return true
    }

    public func delete(_ item: DownloadItem) { /* cancel task, remove file, drop entry, persist */ }
    public func localURL(for item: DownloadItem) -> URL { downloadsDirectory().appendingPathComponent(item.localFileName) }

    // Application Support/Moonlit/Downloads
    private func downloadsDirectory() -> URL { /* create if needed */ fatalError("impl") }
    private func load() { /* decode JSON from Application Support; reconcile missing files */ }
    private func persist() { /* encode JSON */ }
}

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated public func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask,
        didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite e: Int64) {
        Task { @MainActor in self.updateProgress(taskId: t.taskIdentifier, received: w, total: e) }
    }
    nonisolated public func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL) {
        // move file to downloadsDirectory synchronously (location is temporary), then:
        Task { @MainActor in self.markCompleted(taskId: t.taskIdentifier) }
    }
    nonisolated public func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError err: Error?) {
        if let err { Task { @MainActor in self.markFailed(taskId: t.taskIdentifier, error: err) } }
    }
}
```

Add small test-only helpers behind the same type: `persistenceNameForTest`, `upsertForTest(_:)`, `loadForTest()` (thin wrappers over `persist()`/`load()` and appending to `downloads`). Implement the `fatalError` stubs and the `// ...` bodies fully — no placeholders in the shipped file. Move the finished temp file inside the delegate callback before returning (URLSession deletes it after).

- [ ] **Step 4: Run — verify pass**

Run: `swift test --package-path Packages/MoonlitCore --filter DownloadTests`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: DownloadManager with background URLSession + JSON persistence"
```

### Task 5.3: `MacDownloadsView` screen

**Files:**
- Create: `Apps/MoonlitMac/Sources/Screens/MacDownloadsView.swift`
- Modify: `Apps/MoonlitMac/MoonlitMac.xcodeproj/project.pbxproj`
- Modify: `Apps/MoonlitMac/Sources/Screens/MacMainView.swift` (replace the Phase-1 placeholder route)

- [ ] **Step 1: Build the screen**

A `ScrollView` list bound to `DownloadManager.shared.downloads`: each row shows poster (`CachedAsyncImage`), name, quality/size, a progress bar when `state == .downloading`, a Play button (enabled when `.completed`) and a Delete button. Empty state: "No downloads yet." Signature:

```swift
struct MacDownloadsView: View {
    var onSelectMedia: (MetaPreview) -> Void = { _ in }
    @ObservedObject private var manager = DownloadManager.shared
    // rows + play(item)->launch player with manager.localURL(for:), delete(item)
}
```
Play builds a local-file `PlayerLaunch` (see how `MacDetailView`/`MacPlayerView` construct `PlayerLaunch` from a resolved stream) using `manager.localURL(for: item)` as `sourceUrl` and launches the player.

- [ ] **Step 2: Register the file in `project.pbxproj`** using the reusable anchor-insert script (anchor on an existing Screens file such as `MacLibraryView.swift`, generate 2 fresh UUIDs):

```bash
cd /Users/zain/projects/Moonlit/Apps/MoonlitMac
read B R <<<"$(python3 -c 'import secrets;print(secrets.token_hex(12).upper(),secrets.token_hex(12).upper())')"
python3 - MoonlitMac.xcodeproj/project.pbxproj "$B" "$R" MacDownloadsView.swift MacLibraryView.swift <<'PY'
import sys
p,b,r,new,anchor=sys.argv[1:6]
L=open(p).read().splitlines(keepends=True)
def after(pred,line):
    for i,x in enumerate(L):
        if pred(x): L.insert(i+1, x[:len(x)-len(x.lstrip())]+line+"\n"); return True
    return False
assert after(lambda x: f"{anchor} in Sources */ = {{isa = PBXBuildFile;" in x,
             f"{b} /* {new} in Sources */ = {{isa = PBXBuildFile; fileRef = {r} /* {new} */; }};")
assert after(lambda x: f"/* {anchor} */ = {{isa = PBXFileReference;" in x,
             f'{r} /* {new} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {new}; sourceTree = "<group>"; }};')
assert after(lambda x: f"/* {anchor} */," in x and "= {" not in x, f"{r} /* {new} */,")
assert after(lambda x: f"/* {anchor} in Sources */," in x, f"{b} /* {new} in Sources */,")
open(p,"w").writelines(L); print("registered", new)
PY
plutil -lint MoonlitMac.xcodeproj/project.pbxproj
```

- [ ] **Step 3: Replace the Phase-1 placeholder route** in `MacMainView.tabContent` with the real `MacDownloadsView(onSelectMedia:)`.

- [ ] **Step 4: Build**

Run the build check. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: MacDownloadsView (offline library screen)"
```

### Task 5.4: Download button in detail

**Files:**
- Modify: `Apps/MoonlitMac/Sources/Screens/MacDetailView.swift` (near the library toggle, ~line 524)

- [ ] **Step 1: Add a download action**

Resolve a stream (reuse the detail view's existing source-selection path via `StreamSourceSelector` / the sources picker to get `sourceUrl` + `sourceHeaders`), then:

```swift
let ok = DownloadManager.shared.startDownload(
    mediaId: detail.id, type: detail.type, name: detail.name,
    poster: detail.poster, quality: chosenStream.quality,
    url: chosenStream.sourceUrl, headers: chosenStream.sourceHeaders)
// if !ok && !DownloadSupport.isDownloadable(chosenStream.sourceUrl): show "Not available offline"
```
Place a download button beside the existing library/play controls; disable/annotate it for HLS sources.

- [ ] **Step 2: Build**

Run the build check. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual check**

Open a title with a direct-file stream → Download → progress appears in the Downloads screen → completes → Play plays the local file with the network off; an HLS-only title shows "Not available offline"; an in-flight download survives an app relaunch.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: start downloads from the detail view"
```

---

## Self-review notes (addressed)

- **Spec coverage:** Phase 1 (nav) ✓, Phase 2 (quick-add) ✓, Phase 3 (autohide + cursor) ✓, Phase 4 (onboarding) — corrected: already exists, reduced to verify/polish ✓, Phase 5 (downloads: model, manager, screen, detail entry, HLS exclusion, offline playback) ✓.
- **Types are consistent:** `DownloadItem`/`DownloadState`/`DownloadSupport.isDownloadable`/`DownloadManager.startDownload`/`localURL(for:)` are used identically across tasks.
- **Known deliberate abbreviations:** Task 5.2's `DownloadManager` body marks internal helpers to be implemented fully in the shipped file (no placeholders ship); the `// ...` and `fatalError` are implementation slots the engineer completes in that same task, not cross-task TODOs.
- **pbxproj:** every new `.swift` file has an explicit registration step; deletions strip refs.
```
