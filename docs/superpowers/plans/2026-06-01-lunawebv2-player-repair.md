# LunaWebV2 Player Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore LunaWebV2 stream playback and polish player/source/subtitle UI to the approved Netflix/Stremio direction.

**Architecture:** Keep the work localized to LunaWebV2. Extract pure helpers for stream source typing, stream identity, and Continue Watching labels, then wire those helpers into `Player`, `watch`, `home`, and `stream-cache`.

**Tech Stack:** React 19, Vite, TypeScript, Tailwind, Vidstack, Vitest.

---

### Task 1: Test Harness And Pure Helpers

**Files:**
- Modify: `LunaWebV2/package.json`
- Modify: `LunaWebV2/vite.config.ts`
- Create: `LunaWebV2/src/lib/player-utils.ts`
- Create: `LunaWebV2/src/lib/player-utils.test.ts`

- [ ] Add a `test` script and Vitest dev dependencies.
- [ ] Add Vite test config with `jsdom`, globals, and `@` alias.
- [ ] Write failing tests for stream source typing, stream matching, and Continue Watching labels.
- [ ] Implement `getStreamUrl`, `getVidstackSourceType`, `streamMatchesUrl`, and `formatContinueWatchingTitle`.

### Task 2: Playback Repair

**Files:**
- Modify: `LunaWebV2/src/lib/stream-cache.ts`
- Modify: `LunaWebV2/src/components/Player.tsx`
- Modify: `LunaWebV2/src/routes/watch.tsx`

- [ ] Make cached stream lookup match `url` and `externalUrl`.
- [ ] Make `Player` initialize source type from the URL instead of always HLS.
- [ ] On playback error, fall back only when the current source type was HLS.
- [ ] Ensure stream switching preserves playback position and active stream metadata.

### Task 3: Subtitles Addon And Audio/Subtitles Panel

**Files:**
- Modify: `LunaWebV2/src/lib/supabase.ts`
- Modify: `LunaWebV2/src/lib/stremio.ts`
- Modify: `LunaWebV2/src/components/Player.tsx`

- [ ] Add OpenSubtitles v3 Pro to default addons before the public fallback.
- [ ] Deduplicate subtitle addon URLs and subtitle tracks.
- [ ] Replace the simple caption toggle with a Netflix-style Audio + Subtitles panel.
- [ ] Speaker button remains mute/unmute; volume slider is visible at all times.

### Task 4: Loading And Sources UI

**Files:**
- Modify: `LunaWebV2/src/components/Player.tsx`
- Modify: `LunaWebV2/src/routes/browse.tsx`
- Modify: `LunaWebV2/src/routes/home.tsx`

- [ ] Replace spinner-heavy autoplay overlays with title logo/source names and a subtle progress bar.
- [ ] Redesign the sources panel as a compact right rail inspired by Stremio.
- [ ] Increase player controls to Netflix-like scale while preserving accessible hit targets.

### Task 5: Continue Watching Labels

**Files:**
- Modify: `LunaWebV2/src/routes/home.tsx`

- [ ] Use `formatContinueWatchingTitle` for card titles.
- [ ] Fetch base series metadata with the base IMDb ID and display `Series Title - Episode N` for old entries.
- [ ] Keep progress percentage and season/episode metadata visible.

### Task 6: Verification

**Files:**
- No source edits expected.

- [ ] Run `npm test -- --run` in `LunaWebV2`.
- [ ] Run `npm run build` in `LunaWebV2`.
- [ ] Review `git diff` for unintended changes.
