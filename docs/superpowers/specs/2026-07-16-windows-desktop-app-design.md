# Moonlit for Windows — Design Document

**Date:** 2026-07-16
**Status:** Approved for implementation planning
**Scope:** A Windows desktop app with full feature parity to the macOS app (Apps/MoonlitMac), built as a Tauri 2 shell around an evolved `moonlit-web`, with libmpv playback.

---

## 1. Goal & Non-Goals

### Goal
Ship Moonlit for Windows with **everything the macOS app has** — same design language, same feature set, same playback capability — using the existing `moonlit-web` React codebase as the UI layer inside a Tauri 2 shell with native libmpv playback.

### Non-Goals (v1)
- **Casting** (AirPlay is Apple-only; Chromecast/DLNA deferred — Harbor's MIT Rust cast server is a future reference)
- **Linux/macOS Tauri builds** — Windows-only; the native SwiftUI Mac app remains the flagship on macOS
- **Replacing the native Mac app** — it stays as-is
- **Torrent/infohash playback** — matches current web behavior (filtered out); Mac app parity here is via debrid-resolved direct streams

### Key Decisions (user-approved)
| Decision | Choice |
|---|---|
| Casting on Windows | Dropped for v1 |
| Platform strategy | Windows-only; keep native Mac app |
| Codebase | Evolve `moonlit-web` in place (one codebase for web + desktop) |
| Design bar | "Extreme polish" — full Mac design-language parity, design system built **before** feature work |

---

## 2. Why not alternatives (context)

- **Swift on Windows:** No SwiftUI/AppKit on Windows. The Mac app's ~22.5k LOC UI layer plus libmpv/OpenGL glue, PiP (NSWindow), and Apple Sign In are Apple-only. Dead end.
- **Flutter/Compose rewrite:** A third codebase re-implementing both UI and MoonlitCore logic. Months more work for the same outcome.
- **Chosen: Tauri 2 + React + libmpv** — proven by Harbor (github.com/harborstremio/harbor, MIT): Tauri 2 Rust shell, WebView2, React 19 frontend, libmpv sidecar, NSIS installer. We reference their integration patterns directly.

---

## 3. Architecture

```
moonlit-web/
├── src/                    React 19 + TS + Tailwind + TanStack Router/Query (existing, evolved)
│   ├── lib/platform/       NEW: isDesktop() capability detection + Tauri bridge client
│   ├── lib/design/         NEW: design tokens, color-extraction worker client
│   ├── components/...      Rebuilt to Mac design system
│   └── ...
├── src-tauri/              NEW: Rust shell
│   ├── src/player/         libmpv embed (child HWND), command/event bridge
│   ├── src/downloads/      Download manager (queue/pause/resume/persist)
│   ├── src/deeplink/       moonlit:// handler (single instance)
│   └── tauri.conf.json     frameless window, updater, NSIS bundling
├── scripts/setup-sidecars  NEW: fetch libmpv per-platform (Harbor pattern)
└── api/                    Vercel edge fns (web-only; desktop calls addons directly)
```

### 3.1 One codebase, two targets
- `isDesktop()` (Tauri detection) gates desktop-only capability: libmpv player, downloads, deep links, window chrome.
- Web build on Vercel is untouched; it keeps the Vidstack/hls.js/Mediabunny player and edge-function proxies.
- Desktop calls Stremio addons directly (no Vercel proxy), matching Mac app behavior.
- All new features (Trakt, IPTV, Awards, hubs) are written platform-agnostic where possible, so the web app inherits them.

### 3.2 Player: libmpv under transparent WebView2
- libmpv renders into a **native child HWND** created by the Rust shell, positioned beneath a **transparent WebView2**; React draws 100% of the player UI on top (Harbor's proven approach).
- Rust↔JS bridge via Tauri commands (load/play/pause/seek/speed/volume/track select/sub+audio delay/external sub add/shader toggle/screenshot) and events (position, duration, buffering, track lists, video params/aspect, EOF, errors).
- mpv config parity with Mac: `vo=gpu` into child window, Anime4K GLSL shader chain (Clamp_Highlights, Restore_CNN_M, Upscale_Denoise_CNN_x2_M), HTTP headers per-stream, resume position, speed 0.25–2×.
- Sidecars fetched by setup script (not committed): libmpv Windows build; ffmpeg only if later needed for thumbnails.
- Seek-preview thumbnails: mpv screenshot-based capture (Mac `PlayerThumbnailer` equivalent) cached per item.
- Web fallback player remains for the browser target only.

### 3.3 Rust responsibilities
| Module | Responsibility |
|---|---|
| `player` | libmpv lifecycle, child HWND, property observation → events, commands |
| `downloads` | Queued/downloading/completed/failed/paused state machine, resumable HTTP downloads, `downloads.json` persistence in `%APPDATA%/Moonlit/Downloads/`, direct-file-only rule (reject `.m3u8`) |
| `deeplink` | `moonlit://` registration, single-instance forwarding (Trakt OAuth callback) |
| `window` | Frameless main window (min 900×600), custom min/max/close, player aspect-ratio resize, PiP always-on-top mini window |

---

## 4. Design System (Phase 2 — built before features)

The web app currently uses a **different design language** (orange `#FF8A35` accent, Inter font, linear CSS transitions, 2 glass utilities, no artwork-derived color). Full findings in Appendix B. Parity work:

### 4.1 Tokens
- **Colors:** Mac palette — bg `#0D0D0D`, surface `#1A1A1A`, elevated `#242424`; text tiers white @ 1.0/0.70/0.50; outline white 0.08. **White accent** replaces orange. **HarborGold `#D4AF37`** only for ratings/badges/selected category pills. Player palette (opaque Harbor panels): canvas `#111213`, elevated `#252628`, edge `rgba(60,61,63,0.55)`.
- **Radii:** 6 / 10 / 14 / 18 token scale (small/control/card/large), replacing ad-hoc Tailwind values.
- **Shadows:** Mac values (tile lift `black 0.40` r16 y10; harbor panel `black 0.80` r30 y14; glass capsule variants).
- **Genre colors:** port the 16 Oklch gradient triples to CSS `oklch()`.

### 4.2 Typography
- Self-host **Montserrat-ExtraBold** (wordmark/branding, tracking 2) + heading/body stack matching Mac's 11-tier scale (10–40pt) with breakpoint multipliers (1.0/1.05/1.1/1.15); monospaced timecodes in player.

### 4.3 Glass vocabulary
- Port all Mac glass variants as utilities: `glass-card` (r18, blur + white 0.10 stroke), `dark-glass-capsule` (white 0.16 stroke 0.8px), `liquid-glass-capsule` (blur + `rgba(0,0,0,0.28)` tint + shadow r12 y4), `glass-circle`, glass icon button (46×46), etc. Budget: limit stacked `backdrop-filter` layers per view for compositor performance.

### 4.4 Motion
- **framer-motion** springs replacing linear CSS transitions, using Mac's spring table: tile hover (response .30 / damping .78, scale 1.04), hero manual (.42/.82), hero auto (.50/.82), nav (.30/.75), library toggle (.25/.60), panels (.40/.85), etc. Ease curves kept where Mac uses them (hero crossfade easeInOut .35s, ambient .9s, pills .15–.18s). Respect `prefers-reduced-motion`.

### 4.5 Artwork color engine (biggest differentiator)
- OffscreenCanvas + Web Worker ports of both Mac pipelines, cached per artwork URL:
  - **TileHaloColor:** downsample ~36px, 16³ RGB histogram with chroma² weighting, filter (brightness 0.10–0.92, sat ≥0.12), boost sat×1.7 (0.70–1.0), brightness×1.25 (0.60–0.95) → per-card hover halo (2-layer radial glow, blur 30 @ 0.66 + blur 60 @ 0.30).
  - **FusionAmbient:** downscale 40px, box-blur kernel 21, left/right dual-color extraction (avg 40% / max 60%), ambient boost sat×3.0 brightness×1.5 → hero backdrop wash, detail-page wash, fluid blooms styles.

### 4.6 Core component kit
MediaCard (halo, RatingBadge in HarborGold, hover library toggle), all **5 row layouts** (standard / heroBanner / cardStack / cinematic / topTen), category pill rails (gold selected) + genre rail with trailing fade mask, HomeHero (ambient gradients, 4-stop image mask, logo art, genre label, award badge, chevrons, animated page indicator, 60s auto-advance, crossfade), `StrokeSpinner` (25% arc, 0.7s linear), shimmer skeletons (1.5s sweep), witty-caption loading view, glass empty/error states, rows with `overflow: visible` + scroll masking so halos aren't clipped.

---

## 5. Feature Parity Plan

Complete ~200-item inventory in Appendix A. Grouped by work type:

### A. Exists in moonlit-web — rebuild to Mac design
Home (hero/rails/continue watching), search overlay (hybrid local+TMDB+addon, recents, genre browse), detail pages, collections/folders, library (watchlist/liked/upcoming), profiles + email auth + invite codes, admin invite codes, settings shell, onboarding (3-step + guest mode), source picker.

### B. New ports (TS re-implementations of MoonlitCore logic + new UI)
| Feature | Scope |
|---|---|
| **Trakt** | PKCE OAuth via `moonlit://trakt-callback` deep link, tokens in Supabase `trakt_oauth_tokens`, auto-refresh, watchlist fetch/merge into Library, show/movie calendars, settings connect/disconnect. (Scrobbling is NOT in the Mac app; progress sync stays Supabase-only.) |
| **IPTV / Live TV** | M3U parser (tvg-* attrs, catchup attrs), Xtream client (auth, categories, channels, EPG), XMLTV parser + gzip, EPG index + manual override matching UI, EPG grid guide (6h window, 30-min ticks, now-line, catch-up indicators), catchup URL builder (default/append/shift/flussonic/xtream strategies), source form (M3U/Xtream/EPG-only), per-source chips, channel grid grouped by category, source repository with refresh/edit/delete |
| **Awards Hub** | AwardBody catalog (laurels, tints, serif titles), AwardIndex over catalog rows, hub view (gallery mosaic + 18-preview grid + people rails; searchable list mode), award badges on detail pages + hero |
| **Downloads** | Rust download manager (see 3.3), downloads view (poster/status/progress/play/delete), offline playback via mpv `file://`, downloadable-check (direct files only), download button on detail pages |
| **Hubs & pages** | Genre hubs (18 tiles → franchise/sub-genre/decade rails, vote-count filter), language hubs (18 tiles → featured/series/movies rails), actor bio (TMDB person, credits by department, awards), episode detail page, franchise/collection page, streaming service view |
| **Settings parity** | Subtitle appearance (4 presets + 15 options + live preview), playback prefs (autoplay next, next-episode threshold, preferred audio/sub languages, skip-intro + IntroDB + auto-skip + fallback skip durations, Anime4K, compatible-formats filter, cache mode), stream autoplay (manual/automatic, timeout, addon allow-list), collection design (per-row poster/landscape/list), catalog management, hero management, metadata integrations (TMDB/TVDB keys, Trakt), cinematic mode toggle |
| **Recommendations & home organizer** | "For You" service (present but hidden, matching Mac flag), remote home-organizer config from edge function + bundled fallback |

### C. Player parity (libmpv)
Speed picker (0.25–2×), audio/sub track panels with delay sliders (±10s), external subtitles from addons (SRT/VTT parse + overlay, preferred-language preselect), subtitle appearance rendering, Anime4K toggle, seek thumbnails, resume prompt (>10s, 8s auto-dismiss) + Supabase progress sync + last-source cache, 4K preference + in-player source switching (position preserved) + auto-next-candidate on error + preflight checks + stream check pill, prev/next episode + Up Next panel (season picker, threshold-triggered) + episode/title info panels, skip intro (IntroDB + fallback 30–120s), screenshot to `Pictures\Moonlit Screenshots`, window resize-to-aspect, fullscreen, PiP mini window (prev/next/play/exit chrome), hotkeys (Space, ←→ ±5s, ↑↓ vol ±5%, F, M, C), controls fade, volume/mute.

### D. Windows substitutions
| macOS | Windows |
|---|---|
| AirPlay (AVRoutePickerView) | Dropped v1 |
| Native Apple Sign In (ASAuthorization) | Supabase Apple OAuth web flow (same accounts) |
| NSWindow PiP reparenting | Tauri always-on-top frameless mini window |
| ⌘1–⌘8 nav | Ctrl+1–8 |
| Traffic lights / hiddenTitleBar | Frameless window + custom min/max/close (Mac-style chrome) |
| AVPlayer/KSPlayer per-media engine picker | Hidden on desktop (mpv only) |
| `~/Pictures/Moonlit Screenshots` | `%USERPROFILE%\Pictures\Moonlit Screenshots` |
| `~/Library/Application Support/Moonlit/Downloads` | `%APPDATA%\Moonlit\Downloads` |

---

## 6. Phases

1. **Foundation** — Tauri scaffold in `moonlit-web`, frameless chrome + custom window controls, `isDesktop()` module, `moonlit://` deep links + single instance, CI (GitHub Actions `windows-latest`: typecheck, vitest, `cargo test`, NSIS artifact per commit), Windows 11 ARM VM dev loop. *Exit: existing web UI boots in the Tauri window.*
2. **Mac Design System** — Section 4 in full. *Exit: token/glass/motion/color-engine kit with visual test page; no orange remains.*
3. **Screen rebuild** — home, detail, search, library, settings shell, nav, onboarding/auth/profiles rebuilt on the system; Ctrl+1–8; cinematic mode. *Exit: side-by-side screen parity vs Mac (Appendix B gap table as criteria).*
4. **Player core** — Section 3.2 + C. *Exit: plays the same Stremio streams as the Mac app incl. HEVC/DTS MKV, all tracks/subs/resume/switching verified on real hardware.*
5. **Feature ports** — Section B (parallelizable per feature; TDD for parsers/services). *Exit: Appendix A checklist items green.*
6. **Ship** — NSIS installer, Tauri auto-updater, code-signing decision, real x64 PC validation pass, v1 tag. *Exit: installable signed-or-accepted build passing the full ~200-item parity checklist.*

---

## 7. Testing Strategy

- **TDD (vitest)** for all ported logic: M3U/XMLTV/Xtream parsers, catchup URL builder, EPG index, award index, Trakt client, subtitle parsing, stream selection/preflight, color-extraction math (port Mac values as fixtures).
- **`cargo test`** for Rust: download state machine, mpv command mapping, deep-link parsing.
- **Daily dev:** `pnpm tauri dev` in Windows 11 ARM VM (Parallels/UTM). Caveat: ARM VM video behavior differs; playback validation happens on real hardware.
- **CI:** GitHub Actions `windows-latest` — typecheck, vitest, cargo test, NSIS installer artifact per commit.
- **Final validation:** real x64 PC for GPU/codec/HDR (HEVC, DTS/TrueHD, HDR passthrough) — VMs are not representative.
- **Acceptance:** Appendix A inventory is the parity checklist; Appendix B gap table is the per-screen design checklist.

---

## 8. Risks

| Risk | Mitigation |
|---|---|
| libmpv-under-WebView2 embed complexity (z-order, transparency, DPI, fullscreen) | Do it in Phase 4 as a dedicated phase; Harbor (MIT) as working reference; spike first, fallback is separate native player window (matches Mac's separate player window model anyway) |
| Backdrop-blur performance on low-end Windows GPUs | Glass budget per view; measure in VM + real hardware; degrade to solid tints |
| Scope (~200 items) | Inventory-driven checklists; phases independently shippable; features parallelizable |
| moonlit-web drift vs root `src/` duplicate | `moonlit-web/` is canonical (Vercel deploys it); root `src/` untouched by this project |
| ARM VM masks video bugs | Real x64 hardware gate before ship |

---

## Appendix A — macOS Feature Inventory (parity checklist)

The authoritative ~200-item inventory extracted from Apps/MoonlitMac + Packages/MoonlitCore. Summary by area (full detail lives in the implementation plan tasks):

1. **App structure:** entry/session restore splash, 3-step onboarding + guest mode, auth (email/password, sign-up + invite code, Apple), profile picker/create (20+ avatars), main tab shell (Home, Movies, Series, Live TV, Library, Downloads, Settings, Admin), pill nav (brand, tabs, search, account menu, ⌘1–8), search overlay (local+TMDB+addon hybrid, recents, jump-to, genre browse, people), back-button overlay stack.
2. **Home:** hero carousel (logo art, rating badge, watch/more-info, ambient background, award badge, chevrons, indicator, 60s auto-advance), continue watching (progress, mark watched/remove, stream warmup ×5), For You (hidden flag), 18 genre + 18 language tiles, catalog rows (poster/landscape/list styles, infinite scroll), category pills, home-organizer remote config + bundled fallback, hero artwork provider (TMDB best backdrop + cache).
3. **Content pages:** detail (hero, ratings, seasons/episodes, cast, related, awards, trailers, franchise, like/watched/download, stale indicator), episode detail, actor bio, franchise page, media browse (movies/series rails + genre popover), genre hub (franchise/sub-genre/decade rails, vote filter), language hub, streaming service view, folder grid (landscape auto-detect, infinite scroll).
4. **Live TV:** source chips, channel grid (search, category groups, logos, now-playing), EPG guide (6h, ticks, now-line, catchup replay), EPG manual matching, source form (M3U/Xtream/EPG-only), auto-detection, refresh/edit/delete, gzip.
5. **Downloads:** state machine, direct-file-only check, start from detail, dedupe, persistence, offline playback, list UI, nav tab.
6. **Library:** watchlist + liked (all/movies/series filters), upcoming (liked items with airdates).
7. **Awards:** body catalog, hub (gallery/list, people rails, search), badges, index, people services.
8. **Admin:** invite codes (generate 1–100 uses, list, revoke), catalog management (show/hide/expand), hero management (rows, priority, enable).
9. **Settings:** general (metadata integrations, Trakt, system addon info), playback (14 options), subtitle appearance (15 options + presets + live preview), appearance (cinematic mode, collection design), stream autoplay, account (profile card, version, sign out).
10. **Addons:** install by URL, category groups, enable/disable, reorder, delete, pinned system addon.
11. **Player:** everything in Section 5C plus source picker (grouped by addon+resolution, cached-only filter, 4K toggle, compatibility warnings, preflight).
12. **Auth/profiles:** session restore, token refresh w/ 401 handling, sign out, per-profile data isolation, roles/admin gating, guest mode.
13. **Platform:** deep link `moonlit://trakt-callback`, Montserrat registration, custom window chrome, player window aspect sizing. (No menu-bar app, no notifications, no launch-at-login, no Sparkle — nothing to port.)

## Appendix B — Design Gap Summary (Mac vs current moonlit-web)

Authoritative values captured 2026-07-16 from code inspection. Critical gaps, priority order:

1. **Artwork color engine** — Mac has two pipelines (FusionAmbient backgrounds, TileHalo hover glows); web has none (hardcoded orange glow). Exact algorithms + boost values in Section 4.5.
2. **Accent system** — web is orange `#FF8A35`; Mac is white accent + HarborGold `#D4AF37` (ratings/badges/pills only).
3. **Motion** — web is linear CSS; Mac uses ~15 spring configs (tile .30/.78 scale 1.04; hero .42/.82 & .50/.82; nav .30/.75; library .25/.60; panels .40/.85; +ease curves: crossfade .35, ambient .9, pills .15–.18).
4. **Glass** — web has 2 utilities; Mac has 10+ variants (values in Section 4.3).
5. **Typography** — web Inter-only; Mac Montserrat-ExtraBold branding + 11-tier scale w/ breakpoint multipliers + mono timecodes.
6. **Loading states** — Mac stroke spinner (0.7s, 25% arc), shimmer skeletons (1.5s), 25 witty captions, breathing wordmark (3.2s); web has a basic CSS spinner.
7. **Row variety** — Mac 5 layouts; web 1.
8. **Category pill rails** — missing entirely on web (gold selected, fade-masked genre rail).
9. **Tokens** — Mac radii 6/10/14/18 + deliberate shadows; web ad-hoc Tailwind.
10. **Hero** — web missing ambient washes, 4-stop mask, genre label, award badge, chevrons, animated indicator, crossfade; web keeps its parallax (richer than Mac; retain).
11. **Player panels** — Mac opaque Harbor panels (`#252628`, edge border, shadow r30 y14); web translucent `#141414` + blur.
12. **Card details** — Mac: r14/16, hover white 0.14 border @0.75px, spring scale 1.04, halo, HarborGold IMDb capsule, hover library toggle; web: r12, ring white/10, CSS scale 1.025, no halo, yellow-400 text.

Web constraints accepted: no native `.glassEffect` (blur+tint approximation), no CSS springs (framer-motion), backdrop-filter perf budget, fonts self-hosted woff2 `font-display: swap`, Oklch→sRGB via CSS `oklch()`.
