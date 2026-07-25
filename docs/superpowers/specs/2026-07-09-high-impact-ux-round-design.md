# High-Impact UX Round — Design Spec

**Date:** 2026-07-09
**App:** MoonlitMac (SwiftUI, macOS 14+; shared logic in MoonlitCore)
**Status:** Approved design → ready for implementation planning

## Context

A follow-up round of user-friendly improvements after the "Thursday fixes." Five
independent features are bundled into one phased spec (per the user's request for a
single plan). They vary greatly in size, so the spec is organized into phases that can
be built and shipped incrementally — phases 1–3 are quick wins, phase 4 is onboarding,
and phase 5 (Downloads) is the large one and lands last.

Decisions locked during brainstorming:
- **Downloads:** direct files only for v1 (MP4/MKV/direct URLs); HLS `.m3u8` is
  explicitly out of scope (would need ffmpeg remux).
- **Discover & Anime nav items:** hidden for now (no half-built screens).
- **Autohide (#9):** treated as a bug — controls currently never hide.
- **Onboarding:** minimal (welcome + avatar), no Trakt/addon prompts.
- Downloads nav = icon button in `PillNavBar`; Downloads metadata = local JSON;
  `MacSidebar.swift` (dead code) is deleted.

Key facts established from the codebase:
- The real nav is `PillNavBar` (Home/Movies/Series/Library + search + account).
  `MacSidebar.swift` is **never instantiated** (dead code) — its Discover/Anime/
  Downloads/Addons entries are not shown to users.
- "Library" already *is* the synced watchlist: `LibraryRepository` has
  `toggleLibrary` / `isInLibrary` / `libraryMediaIds`; `MacLibraryView` is the surface;
  `MacDetailView:524-528` shows the working add/remove pattern.
- Player control autohide exists (`PlayerControlVisibilityState`,
  `MacPlayerView.showControls()/scheduleAutoHideIfNeeded()/hideControlsIfAllowed()`),
  but `visibility.setPlayback(isPlaying:)` is **never called**, so `isPlaying` stays
  `false`, `shouldScheduleAutoHide` is always false, and controls never hide.
- A playable stream is a `PlayerLaunch { sourceUrl: String, sourceHeaders: [String:String]? }`
  (MoonlitCore `StreamModels.swift`). Streams are resolved via `StreamSourceSelector`.
- Addons are already reachable via **Settings → Addons** (`MacSettingsView` `.addons`
  category), and default addons are auto-provided (`MoonlitConfig.defaultAddons`).

---

## Phase 1 — Nav cleanup (Small)

**Goal:** remove dead ends, surface Downloads.

- **Delete** `Sources/Components/MacSidebar.swift` (confirmed unused). Remove its file
  registration from `project.pbxproj` (reverse of the 4-edit add pattern).
- Add a `.downloads` case to `MacMainTab` (`PillNavBar.swift`) with an SF Symbol
  (`arrow.down.circle` / `arrow.down.to.line`) and a keyboard shortcut.
- In `PillNavBar`, render Downloads as an **icon button** beside the search field
  (not a text tab — keeps the tab row uncluttered). Toggling it sets `selectedTab`.
- In `MacMainView`, route `.downloads` in `tabContent` to a new `MacDownloadsView`
  (built in Phase 5; until then a simple placeholder is acceptable, but since we build
  Phase 5 in this round, wire it to the real screen).
- Addons: no new nav (already in Settings). Discover & Anime: not added anywhere.

**Files:** `Sources/Components/PillNavBar.swift`, `Sources/Screens/MacMainView.swift`,
delete `Sources/Components/MacSidebar.swift`, `MoonlitMac.xcodeproj/project.pbxproj`.

---

## Phase 2 — Quick Add to Library / "My List" (Medium)

**Goal:** toggle watchlist membership from anywhere, not just the detail page.

- Add a hover-revealed **＋ / ✓ circular button** overlay to `MediaCard` (top-trailing),
  and to the continue-watching card if practical. On tap it calls
  `libraryRepo.toggleLibrary(profileId:mediaId:mediaType:name:poster:)` and reflects
  `libraryRepo.isInLibrary(mediaId:)` (✓ filled when saved). Reuse the exact call
  pattern from `MacDetailView:524-528`.
- `MediaCard` obtains `profileId` from the `ProfileManager` environment object (already
  injected app-wide) and observes `LibraryRepository.shared` so the icon stays in sync.
- Small state feedback: brief scale/opacity pop on toggle. Guard against acting when
  there is no current profile.
- No backend changes (`LibraryRepository` + Supabase sync already exist).

**Files:** `Sources/Components/MediaCard.swift` (primary), optionally
`Sources/Components/ContinueWatchingCard.swift`.

---

## Phase 3 — Player autohide fix (#9) (Small)

**Goal:** controls actually fade during playback.

- **Root cause:** `visibility.setPlayback(isPlaying:)` is never invoked. Fix in
  `MacPlayerView` by syncing engine → visibility:
  `.onChange(of: engine.isPlaying) { _, playing in visibility.setPlayback(isPlaying: playing); if playing { scheduleAutoHideIfNeeded() } }`.
  Also call `setPlayback(isPlaying:)` once on first frame / playback start.
- When controls hide, **hide the macOS cursor** (`NSCursor.hide()`); restore
  (`NSCursor.unhide()`) on any interaction that calls `showControls()`. Ensure unhide on
  view disappear so the cursor can't get stuck hidden.
- Keep the existing 2.4s inactivity delay and the `isSeeking` guard in
  `hideControlsIfAllowed()`.

**Files:** `Sources/Screens/MacPlayerView.swift`; possibly a small addition to
`PlayerControlVisibilityState` only if needed (prefer not to change it).

---

## Phase 4 — First-run onboarding, minimal (Medium)

**Goal:** a warm first launch instead of dropping into an empty-feeling app.

- New `Sources/Screens/MacOnboardingView.swift`, shown **once**, gated by a
  `UserDefaults` flag (`moonlit.didCompleteOnboarding`).
- Flow: **Welcome** (brand + one line) → **pick avatar + name** (reuse the avatar grid
  built in B2 / `MacCreateProfile`) → **"Start watching"**. No Trakt/addon steps.
- Integrate into `MacContentView` routing, which currently shows `MacCreateProfile` for
  first-run: for a brand-new account with no profile, present the onboarding flow whose
  final step creates the profile (`createProfile(name:avatarId:)`, already extended) and
  sets the completion flag. Returning users are unaffected.

**Files:** new `Sources/Screens/MacOnboardingView.swift`,
`Sources/MacContentView.swift`, `MoonlitMac.xcodeproj/project.pbxproj` (register new file).

---

## Phase 5 — Downloads / offline, direct-files v1 (Large)

**Goal:** save direct-file streams for offline playback.

### Service — `DownloadManager` (MoonlitCore)
- New `Packages/MoonlitCore/Sources/MoonlitCore/Services/DownloadManager.swift`,
  `@MainActor` `ObservableObject` singleton, `@Published var downloads: [DownloadItem]`.
- Model `DownloadItem: Codable, Identifiable`:
  `{ id, mediaId, type, name, poster, quality, remoteURL, localFileName, totalBytes,
  receivedBytes, state, createdAt }` with
  `enum DownloadState { queued, downloading, paused, completed, failed }`.
- Backed by a `URLSession` **background** configuration
  (`URLSessionConfiguration.background(withIdentifier:)`) + `URLSessionDownloadDelegate`
  for progress (`receivedBytes/totalBytes`) and completion; resumes across app relaunch.
- Apply `sourceHeaders` to the download request (same sanitization used by the player,
  excluding `Range`).
- Persist the list as **local JSON** in Application Support (device-local — files are
  not portable, so no Supabase sync). Reconcile on launch: drop entries whose file is
  missing; mark interrupted downloads resumable/failed.

### Storage
- Files in `Application Support/Moonlit/Downloads/<id>.<ext>` (extension inferred from
  the remote URL / content type). Delete removes both the file and the entry.

### Start a download
- Entry point: a **download button** in `MacDetailView` (and/or the sources picker).
  Resolve a stream via the existing `StreamSourceSelector` to obtain `sourceUrl` +
  `sourceHeaders`.
- If the resolved URL is HLS (`.m3u8`, or manifest content type) → **disable** with a
  "Not available offline" note. Otherwise enqueue.
- No duplicate downloads: guard on `mediaId` already `queued/downloading/completed`.

### Offline playback
- New `Sources/Screens/MacDownloadsView.swift`: list of `DownloadItem`s with poster,
  title, size, progress bar (for in-flight), and actions play / delete. Reachable from
  the Phase-1 nav entry.
- Play builds a `PlayerLaunch` pointing at the **local file URL** and launches
  `MPVPlayerEngine`; existing watch-progress/resume applies unchanged.

### Edge cases
- Disk-full / network errors → `state = .failed` with a retry affordance.
- App relaunch → background `URLSession` reattaches and continues; UI rehydrates from
  persisted JSON.

**Files:** new `DownloadManager.swift` + `DownloadItem` model (MoonlitCore), new
`Sources/Screens/MacDownloadsView.swift`, download button in
`Sources/Screens/MacDetailView.swift` (and/or `MacSourcePickerView.swift`),
`MoonlitMac.xcodeproj/project.pbxproj` (register new Mac files).

---

## Cross-cutting notes
- Every new `.swift` file in the Mac target needs 4 manual `project.pbxproj` edits
  (no synced groups). Use the verified script/anchor approach.
- Build verification: `xcodebuild -scheme MoonlitMac -configuration Debug
  -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build`.

## Verification per phase
1. **Nav:** Downloads icon appears in `PillNavBar` and opens `MacDownloadsView`; no
   Discover/Anime dead ends; app builds with `MacSidebar` removed.
2. **Quick-add:** hovering a card shows ＋; tapping saves it (✓) and it appears in
   `MacLibraryView`; tapping again removes it; state persists across relaunch (Supabase).
3. **Autohide:** during playback, controls + cursor fade after ~2.4s of inactivity and
   reappear on mouse move / key; never hide while paused or seeking.
4. **Onboarding:** a fresh account sees welcome → avatar → start; the chosen avatar
   persists; returning users never see it again.
5. **Downloads:** a direct-file stream downloads with visible progress, plays offline
   from the local file, and deletes cleanly; an HLS source shows "not available offline";
   an in-flight download survives an app relaunch.
