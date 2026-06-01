# LunaMac Redesign — LunaWeb Parity

**Date:** 2026-06-01
**Status:** Approved

## Overview

Redesign LunaMac to match LunaWeb's layout, design language, and feature set. Replace the `NavigationSplitView` sidebar with LunaWeb's floating pill navbar. Add the full media player with AVPlayer. Move `LunaTheme` into `LunaCore` so both platforms share design tokens. Split the 408-line `MacContentView.swift` into separate files following the iOS app's organization.

## Design Tokens (LunaTheme → LunaCore)

| Token | Value | Usage |
|---|---|---|
| `background` | `#0D0D1F` | Page background |
| `surface` | `#1A1A2E` | Cards, sections |
| `surfaceElevated` | `#262638` | Elevated elements |
| `accent` | `#CC66FF` (r:0.8, g:0.4, b:1.0) | Primary accent |
| `primary` | Purple | Buttons, active states |
| `secondary` | Indigo | Secondary accent |
| `textPrimary` | White | Headings |
| `textSecondary` | White 0.7 | Body text |
| `textTertiary` | White 0.5 | Muted text |

## Window Style

- Fully borderless — no title bar, content edge-to-edge
- Custom traffic light buttons (red/yellow/green)
- Minimum size: 900×600

## Navigation — Floating Pill Navbar

- **Position:** Fixed top-center, ~12pt from top, z-index above content
- **Style:** Liquid Glass — pure glass material, no tint, no `.ultraThinMaterial`
- **Shape:** Capsule / rounded-full
- **Border:** Thin white 12% opacity
- **Shadow:** Subtle glow
- **Nav items:** Home (`house.fill`), Search (`magnifyingglass`), Library (`book.fill`), Settings (`gear`), Admin (`shield.fill` — admin only)
- **Active state:** Filled background + white text
- **Inactive state:** 50% opacity white, 80% on hover
- **Profile pill-end:** Colored circle avatar (first letter) + name, tap to switch profiles
- **Separator:** Thin 1px vertical line between nav items and profile
- **Fallback (macOS <26):** `.regularMaterial` / `.thinMaterial`

## File Structure

```
LunaMac/Sources/
├── LunaMacApp.swift                  (entry point, window config)
├── MacContentView.swift              (auth/profile router only)
├── Screens/
│   ├── MacHomeView.swift             (hero + continue watching + catalog rows + collections)
│   ├── MacSearchView.swift           (suggestions + trending + filters)
│   ├── MacDetailView.swift           (cinematic hero + cast + trailers + seasons + source picker)
│   ├── MacLibraryView.swift          (grid + hover remove)
│   ├── MacSettingsView.swift         (profile + addons + sign out)
│   ├── MacAdminView.swift            (collections + invite codes + stats)
│   ├── MacAuthView.swift             (sign in / sign up)
│   ├── MacProfilePicker.swift        ("Who's watching?" grid)
│   ├── MacCreateProfile.swift        (first profile creation)
│   ├── MacPlayerView.swift           (fullscreen player shell)
│   └── MacCollectionDetail.swift     (folder content grid)
├── Components/
│   ├── PillNavBar.swift              (liquid glass floating nav)
│   ├── HomeHero.swift                (hero carousel, auto-rotate 6s)
│   ├── MediaRow.swift                (horizontal scroll row with title)
│   ├── MediaCard.swift               (portrait poster card, hover zoom + play overlay)
│   ├── ContinueWatchingCard.swift    (landscape card with progress bar)
│   ├── FolderTile.swift              (collection folder, glow + GIF hover)
│   ├── StreamSourcePanel.swift       (slide-in source picker, 320pt)
│   ├── PlayerControls.swift          (auto-hide overlay, 3.5s timeout)
│   └── SpeedPicker.swift             (0.5x–2x popover)
└── Resources/
    └── Luna.icns
```

## Home Screen

### Hero Carousel
- 5 featured items, auto-rotates every 6s, pauses on hover
- Full-width backdrop image with gradient fades: top → transparent, left → dark (for text readability), bottom → `luna-bg`
- Logo image preferred over text title
- Meta line: Type · Genre · Year · ★ Rating
- Description (2-line clamp)
- Two CTAs: "Watch Now" (filled accent pill) + "+ My List" (glass pill)
- Page dots at bottom-right

### Continue Watching
- Horizontal scroll row
- Landscape cards (~200×112) with poster thumbnail
- Progress bar (accent color) at bottom of card
- Item name + season/episode label below

### Catalog Rows
- Themed section title (e.g., "Trending Now", "Popular Movies", "Top TV Shows")
- Horizontal scroll of portrait cards (~180×240)
- Hover: scale 1.05, gradient overlay appears, play button fades in
- IMDb rating badge (top-right, yellow)

### Collection Rows
- Admin-curated folder tiles
- Portrait (2:3) or landscape (16:9) shapes
- Hover: purple focus glow
- GIF swap on hover if configured
- Tap → collection detail grid

## Search

- Search bar with magnifying glass icon
- Debounced query (300ms)
- Live dropdown suggestions with posters
- Trending grid as empty-state placeholder
- Type filter pills: All / Movies / Shows
- Recent searches (local storage)

## Detail Page

- Cinematic hero: backdrop image, gradient overlay, logo/title, genre pills
- "Play" (launches source picker → player) + "Watchlist" (toggle save) buttons
- Overview text (expandable)
- Cast & crew horizontal scroll: circular avatars with names, initials fallback
- Trailers section: YouTube thumbnail cards (from Streailer addon + Stremio meta)
- Seasons selector (tabs) + episode cards with thumbnails, air dates, descriptions
- Source picker button → StreamSourcePanel pre-play

## Library

- Adaptive grid of saved items
- Hover: remove button (X or trash icon)
- Empty state: bookmark icon + "Your library is empty" + subtext
- Item count in section header

## Settings

- Profile card: colored circle avatar, name, role badge
- "Switch Profile" button
- Addons section with count: list of installed addons with enable/disable toggles
- Install addon: URL text field + Install button
- Sign Out button (red)

## Admin

- Tabs: Collections, Invite Codes, Stats
- **Collections:** manage rows, folders, catalog assignments
- **Invite Codes:** generate (with max-uses stepper 1–100), list with active/revoked status, revoke button
- **Stats:** admin dashboard metrics

## Player — Full LunaWeb Parity

### Architecture
- Fullscreen `ZStack` overlay with `Color.black` background
- `AVPlayer` via `PlayerEngine` from `LunaCore`
- `PlayerControls` overlay with auto-hide (3.5s timeout)
- Controls always visible when paused or panel open
- Mouse movement resets hide timer

### Layout (three zones)

**Top Zone:** Back button + title + stream info badge (opens Sources panel)

**Center Zone:** Seek Back 15s · Play/Pause (64pt, scales on hover) · Seek Forward 15s

**Bottom Zone:** Title · Scrubber (2pt→5pt on hover track, 14pt round thumb) · Controls row (elapsed · duration | Mute | Subtitles | Speed)

### Stream Source Panel
- Slide-in from right, 320pt wide, dark surface background
- Header: "Sources" title + close (X) button
- Each stream: resolution badge (colored) · video codec · audio codec · HDR badge · file size · debrid source · release group
- Active stream: left border accent + dot indicator
- No web-compatibility filtering (macOS plays everything)

### Keyboard Shortcuts

| Key | Action |
|---|---|
| Space | Play/Pause toggle |
| K | Play/Pause toggle |
| M | Mute toggle |
| C | Subtitles toggle/cycle |
| F | Fullscreen toggle |
| ← | Seek back 15s |
| → | Seek forward 15s |
| ↑ | Volume up |
| ↓ | Volume down |

### Watch Progress
- Saved to Supabase every 10s (existing PlayerEngine behavior)
- Marked completed on `AVPlayerItemDidPlayToEndTime`

### PlayerEngine Additions
- Subtitle track loading from stream manifests
- Stream metadata parsing (resolution, codecs, HDR, file size, debrid source)
- HLS vs MP4 detection

## LunaCore Changes

1. **Move `LunaTheme`** from `LunaApp/Sources/Components/LunaTheme.swift` → `LunaCore/Sources/LunaCore/Theme/LunaTheme.swift`
2. **Add `StreamMetadata` model:** `Resolution`, `Codec`, `SourceInfo` structs
3. **Expand `PlayerEngine`:**
   - `loadSubtitles(from:)` — parse subtitle tracks from stream
   - `parseStreamMetadata(from:)` — extract resolution/codecs from StreamItem description
   - `availableAudioTracks`, `selectedAudioTrack` published properties

## Data Layer

All existing `LunaCore` services are reused unchanged:
- `CatalogRepository`, `SearchRepository`, `LibraryRepository`
- `HomeRepository` (continue watching + featured items)
- `AddonRepository` (Stremio addon management)
- `ProfileManager`, `RoleManager`
- `WatchProgressRepository`
- `AdminService`
- Stremio services: `CatalogService`, `StreamService`, `MetaService`, `SubtitleService`
- Supabase services: `SupabaseClient`, `SupabaseAuth`

## Auth Flow (unchanged from current)

```
MacContentView
  ├── !authenticated → MacAuthView
  ├── authenticated, no profile → MacCreateProfile
  ├── authenticated, has profiles, no current → MacProfilePicker
  └── authenticated, profile selected → MacMainView
```

## macOS Fallbacks

| Feature | macOS 26+ | macOS 14–25 |
|---|---|---|
| Liquid Glass navbar | Pure glass material | `.regularMaterial` / `.thinMaterial` |
| `AVPlayer` HLS | Native | Native |
| SF Symbols | Full set | May need fallback names |

## Non-Goals

- No iOS app changes in this redesign
- No LunaWeb changes
- No changes to Supabase schema
- No Stremio protocol changes
