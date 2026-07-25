# Moonlit for Windows — Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox syntax.

**Goal:** Build `Apps/MoonlitWindows/` — a React + Tauri 2 desktop app that replicates the macOS Moonlit app's exact screen structure, navigation model, component library, and data flow, reusing only the Tauri Rust shell, data services, and design tokens from moonlit-web.

**Source of truth:** The Mac app at `Apps/MoonlitMac/Sources/` is the authoritative spec. Every screen is rebuilt to match its SwiftUI equivalent in layout, motions, and interaction.

**Branch:** `windows-desktop-phase-1` (continue on it). **Directory:** `Apps/MoonlitWindows/` (greenfield, side-by-side with `Apps/MoonlitMac/`).

---

## Architecture Overview

```
Apps/MoonlitWindows/
├── package.json                 NEW: React 19 + Tauri deps (no Vidstack/TanStack Router)
├── vite.config.ts               NEW: desktop-only Vite config
├── tsconfig.json                NEW
├── tsconfig.app.json            NEW
├── tsconfig.node.json           NEW
├── tailwind.config.js           COPY from moonlit-web
├── postcss.config.js            NEW
├── index.html                   NEW: Tauri entry point
├── public/
│   ├── fonts/Montserrat*.ttf    COPY from moonlit-web
│   └── home-organizer.json      COPY from moonlit-web
├── scripts/
│   └── fetch-libmpv.mjs         COPY from moonlit-web
├── src-tauri/                   COPY from moonlit-web/src-tauri/ (entire Rust shell + icons)
├── src/
│   ├── main.tsx                 NEW: app bootstrap
│   ├── index.css                COPY from moonlit-web
│   ├── app/
│   │   ├── AuthProvider.tsx     MOVE from moonlit-web
│   │   └── PlayerProvider.tsx   MOVE from moonlit-web (adapt PlayerLaunch interface)
│   ├── lib/
│   │   ├── design/              COPY from moonlit-web/src/lib/design/ (tokens, motion, color engine)
│   │   ├── platform/            COPY from moonlit-web/src/lib/platform/ (isDesktop, mpv, net, deeplink)
│   │   ├── services/            MOVE from moonlit-web/src/lib/services/ (api.ts, supabase)
│   │   ├── stremio.ts           MOVE from moonlit-web
│   │   ├── player-utils.ts      MOVE from moonlit-web
│   │   ├── subtitle-preferences.ts  MOVE from moonlit-web
│   │   ├── last-stream.ts       MOVE from moonlit-web
│   │   ├── stream-cache.ts      MOVE from moonlit-web
│   │   ├── config.ts            MOVE from moonlit-web
│   │   ├── streaming-server.ts  MOVE from moonlit-web
│   │   ├── types.ts             MOVE from moonlit-web (extend for new components)
│   │   └── player/              MOVE from moonlit-web (preflight, intro timestamps)
│   │
│   ├── shell/                    NEW: navigation and overlay stack
│   │   ├── Shell.tsx            State-driven: tab switching + overlay priority stack + search toggle
│   │   ├── PillNavBar.tsx       "MOONLIT" wordmark, 8 tabs with layoutId spring, search, avatar, shortcuts
│   │   ├── BackButton.tsx       Dark glass capsule "← Back"
│   │   ├── WindowControls.tsx   MOVE from moonlit-web
│   │   └── SessionGate.tsx      Session → onboarding → auth → profile picker → MainView (mirrors MacContentView)
│   │
│   ├── screens/
│   │   ├── HomeScreen.tsx       NEW from MacHomeView spec
│   │   ├── BrowseScreen.tsx     NEW from MacMediaBrowseView spec (Movies & Series tabs reuse this)
│   │   ├── DetailScreen.tsx     NEW from MacDetailView spec
│   │   ├── PlayerScreen.tsx     NEW from MacPlayerView spec + MpvPlayer integration
│   │   ├── SearchScreen.tsx     NEW from MacSearchView spec (full-screen overlay)
│   │   ├── LibraryScreen.tsx    NEW from MacLibraryView spec
│   │   ├── LiveTVScreen.tsx     NEW from MacLiveTVView spec
│   │   ├── GenreHubScreen.tsx   NEW from MacGenreHubView spec
│   │   ├── LanguageHubScreen.tsx  NEW from MacLanguageHubView spec
│   │   ├── ActorBioScreen.tsx   NEW from MacActorBioView spec
│   │   ├── FolderScreen.tsx     NEW from MacFolderView spec
│   │   ├── AwardHubScreen.tsx   NEW from MacAwardHubView spec
│   │   ├── SettingsScreen.tsx   NEW from MacSettingsView spec
│   │   ├── AdminScreen.tsx      NEW from MacAdminView spec
│   │   ├── AddonsScreen.tsx     NEW from MacAddonsView spec
│   │   ├── DownloadsScreen.tsx  NEW from MacDownloadsView spec
│   │   └── StreamingServiceScreen.tsx  NEW from MacStreamingServiceView spec
│   │
│   └── components/
│       ├── MediaCard.tsx        NEW: poster/landscape/square, halo, RatingBadge, library toggle, spring
│       ├── MediaRow.tsx         NEW: header, 5 layout styles (standard/heroBanner/cardStack/cinematic/topTen)
│       ├── FolderTile.tsx       NEW: 140×210 or 220×124, halo, spring, focus-gif
│       ├── ContinueWatchingCard.tsx NEW: 240×135, progress bar, context menu
│       ├── HomeHero.tsx         NEW: 560px, ambient washes, logo, 60s auto-advance, chevrons, dots, award badge
│       ├── RatingBadge.tsx      NEW: IMDb capsule, gold
│       ├── CategoryPills.tsx    NEW: gold selected, genre rail with fade mask
│       ├── GenreTile.tsx        NEW: 18 genres, 210×168, Oklch gradients, skewed backdrops
│       ├── LanguageTile.tsx     NEW: 18 languages, 210×168, endonym overlay
│       ├── StrokeSpinner.tsx    NEW: SVG ring, 25% arc, 0.7s linear
│       ├── ShimmerCard.tsx      NEW: white/10 + 1.5s sweep
│       ├── LoadingView.tsx      NEW: spinner + 25 random cinematic captions
│       ├── EmptyState.tsx       NEW: glass circle icon + message + optional CTA
│       ├── ErrorState.tsx       NEW: glass circle icon + message + retry
│       ├── EpisodeRow.tsx       NEW: still 260×146 + progress + meta + watched toggle
│       ├── CastCard.tsx         NEW: photo + name + character, spring hover
│       ├── ChannelGridView.tsx  NEW: grouped by category, search, sticky headers
│       ├── EPGGuideView.tsx     NEW: 6h window, 30-min ticks, now-line, catchup indicators
│       ├── IPTVSourceForm.tsx   NEW: M3U/Xtream/EPG-only toggle
│       ├── AwardBadge.tsx       NEW: laurel + asset + caption
│       ├── PosterCard.tsx       NEW: tunable size/radius (respects user prefs)
│       ├── ProfileAvatar.tsx    NEW: simple pic + admin badge
│       └── player/
│           ├── MpvPlayer.tsx    MOVE from moonlit-web (already built for desktop)
│           ├── MpvTracksPanel.tsx MOVE from moonlit-web
│           ├── UpNextPanel.tsx  MOVE from moonlit-web
│           ├── ResumePrompt.tsx MOVE from moonlit-web
│           ├── StreamCheckPill.tsx MOVE from moonlit-web
│           ├── AudioTrackPanel.tsx  NEW: mpv-driven audio track list + delay slider
│           ├── SubtitleTrackPanel.tsx NEW: embedded + external subtitles + styling
│           ├── EpisodeInfoPanel.tsx NEW: guest stars, directors, writers
│           ├── TitleInfoPanel.tsx NEW: poster, genre, cast, rating
│           └── SourcePickerPanel.tsx NEW: source list grouped by addon, auto/manual modes
```

---

## Phases

### Phase 1 — Scaffold + Config
Create `Apps/MoonlitWindows/` with working Vite + React + Tauri + Tailwind + framer-motion. Entry point renders the shell with a placeholder screen. Typecheck + build green. CI workflow updated to point at the new directory.

Files: `package.json`, `vite.config.ts`, `tsconfig*.json`, `tailwind.config.js`, `postcss.config.js`, `index.html`, `src/main.tsx`, `src/index.css`.
Copy: `src-tauri/`, `scripts/`, `public/fonts/`, `public/home-organizer.json`, `.gitignore` patterns.
Verify: `cargo check`, `npm run typecheck`, `npm run build`, `npx tauri dev` (window opens).

### Phase 2 — Data Layer + Platform
Copy all service/platform/design modules from moonlit-web into the new src. Verify imports compile. No screens — just the library.

Copy list: `src/lib/design/`, `src/lib/platform/`, `src/lib/services/`, `src/lib/stremio.ts`, `src/lib/player-utils.ts`, `src/lib/subtitle-preferences.ts`, `src/lib/last-stream.ts`, `src/lib/stream-cache.ts`, `src/lib/config.ts`, `src/lib/streaming-server.ts`, `src/lib/types.ts`, `src/lib/player/`, `src/app/AuthProvider.tsx`, `src/app/PlayerProvider.tsx`.

### Phase 3 — Shell (Navigation + Gate)
- `Shell.tsx`: state-driven overlays matching MacMainView. State: `activeTab`, `overlay` (detail/genre/language/award/actor/folder/streamingService — highest priority wins), `searchOpen`, `settingsOpen`, `playerOpen`. ZStack layout with opacity/transform transitions. No route library — just conditional rendering with framer-motion AnimatePresence.
- `PillNavBar.tsx`: floating pill with glass-liquid-capsule, "MOONLIT" wordmark, 8 tabs with layoutId spring, search button, profile avatar, Ctrl+1-8
- `SessionGate.tsx`: session restore → onboarding → auth → profile picker → Shell (mirrors MacContentView route chain)
- `BackButton.tsx`: dark glass capsule, triggers overlay dismissal
- `WindowControls.tsx`: moved from moonlit-web

### Phase 4 — Component Library
Build the shared components that every screen uses. Each component is a direct visual port of its Mac SwiftUI equivalent, with the same dimensions, springs, and glasses.
1. `StrokeSpinner`, `ShimmerCard`, `LoadingView`, `EmptyState`, `ErrorState`, `ProfileAvatar`
2. `RatingBadge`, `CategoryPills`, `AwardBadge`
3. `PosterCard` (tunable), `MediaCard` (3 variants + halo + library toggle), `FolderTile`
4. `MediaRow` (5 layouts + header + chevron), `ContinueWatchingCard`, `HomeHero`, `CastCard`

### Phase 5 — Core Screens
The high-impact screens. Each built to match its Mac.swift source file section by section.
1. **HomeScreen** — from MacHomeView. Hero + category pills + continue watching + genre tiles (18) + language tiles (18) + catalog rows.
2. **BrowseScreen** — from MacMediaBrowseView. Genre popover, portal rows, TMDB discover rails.
3. **DetailScreen** — from MacDetailView (1500 lines). Hero, overview, episodes, cast, awards, trailers, more-like-this.
4. **PlayerScreen** — from MacPlayerView + existing MpvPlayer. Top bar, controls, auto-hide, intro skip, screenshot, stream check.
5. **SearchScreen** — from MacSearchView. Empty state (recents + jump-to + genre pills), results, people row, two-column lists.
6. **LibraryScreen** — from MacLibraryView. Watchlist + Liked with filters, grid poster cards.

### Phase 6 — Specialized Screens
1. **GenreHubScreen** + **LanguageHubScreen** — Oklch ambient, TMDB rails, vote-count filter
2. **LiveTVScreen** + EPG guide + IPTVSourceForm — source chips, channel grid, EPG timeline
3. **AwardHubScreen** + **ActorBioScreen** — gallery/list, film/people rails, credit timeline
4. **FolderScreen** + **StreamingServiceScreen** — poster/landscape grid, service hero
5. **SettingsScreen** + **AdminScreen** + **AddonsScreen** + **DownloadsScreen**

### Phase 7 — CI + Integration
1. Update CI workflow: paths → `Apps/MoonlitWindows/**`, working-directory updated.
2. Dev scripts: `dev:installer`, `dev:dev`. Push, verify CI green with NSIS artifact.

### Phase 8 — Polish + VM Verification
- Side-by-side screenshot comparison vs Mac app per screen
- `npm run build`, typecheck, vitest — green
- Windows 11 ARM VM: Home → Browse → Detail → Player → Search → Library flow
- Real x64 hardware: HEVC/DTS/HDR codec validation

---

## Key Design Decisions

1. **No router library** — Mac uses state-based overlay navigation (booleans, not routes). Replicated exactly in React: `Shell.tsx` is a state machine with AnimatePresence transitions.

2. **Exact Mac dimensions** — MediaCard 154×231, FolderTile 140×210/220×124, ContinueWatching 240×135, hero 560px, genre/language tiles 210×168.

3. **Data services copied, not rewritten** — `stremio.ts`, `api.ts`, `player-utils.ts` etc. come directly from moonlit-web. All Stremio/Supabase logic is identical.

4. **Player reuses existing MpvPlayer** — The React component built in moonlit-web moves directly.

5. **Web Vercel deploy untouched** — moonlit-web continues to exist and ship as before.

6. **Design tokens are identical** — Same tailwind.config.js, index.css, framer-motion springs, artwork color engine.

---

## Verification per Phase

| Phase | Verification |
|-------|-------------|
| 1 | `cargo check` + `npm run typecheck` + `npm run build` + `npm run tauri dev` |
| 2 | Import paths resolve; typecheck green |
| 3 | Tab switching; keyboard shortcuts; overlay push/pop; auth/profiles flow |
| 4 | Vitest tests pass; visual parity vs Mac component screenshots |
| 5-6 | Each screen renders with mock data; layout matches Mac spec |
| 7 | CI green with NSIS artifact |
| 8 | Side-by-side screenshot comparison; VM smoke test |
