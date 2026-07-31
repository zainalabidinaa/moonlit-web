# Moonlit Mac-to-Web UI and Player Parity

## Summary

Rebuild Moonlit Web against the approved full parity and Live TV renders. The current Mac worktree is the visual and behavioral source of truth. Keep the approved web top navbar while Home, Movies, Series, Watchlist, Detail, Live TV, Player, and Settings inherit the Mac artwork, spacing, motion, panels, and customization model.

## Global Constraints

- Preserve all unrelated uncommitted work. Writes are scoped to `moonlit-web` and new Supabase migrations needed by this plan.
- Work test-first for behavior changes and run the focused failing test before production code.
- Keep the current web navbar structure with the Moonlit clapperboard icon, Montserrat ExtraBold wordmark, transparent hero state, and blurred scrolled state.
- Use the current uncommitted Mac UI as the source of truth; do not copy the macOS sidebar or window chrome.
- Support browser and Tauri with one renderer-independent player UI.
- Adapt ARVIO playback-routing and recovery patterns only; do not adopt its visual design or AI subtitle features.
- Signed-in preferences sync to Supabase with local offline fallback. IPTV credentials remain encrypted and device-local.
- No playlists, credentials, channels, or media sources are bundled.
- Meet keyboard, screen-reader, reduced-motion, 200% zoom, 320px reflow, and touch-target requirements.

### Task 1: Design foundation, navigation, routes, and profile preferences

- Add shared Mac-derived color, typography, glass, focus, spacing, and motion tokens.
- Refine `AppShell` with the approved icon/wordmark navbar and responsive menu.
- Add functional `/movies`, `/series`, `/live`, and `/watchlist` routes. Redirect `/library` to `/watchlist`; preserve existing detail and watch routes.
- Add versioned `HomePreferences`, `ArtworkPreferences`, `PlayerPreferences`, and expanded `SubtitlePreferences`.
- Add `profile_preferences(profile_id, namespace, schema_version, value, updated_at)` with owner-only RLS.
- Implement per-profile local caching, cloud-newer reconciliation, offline saves, guest-local behavior, and one-time import of existing subtitle/collection keys.
- Add focused tests for routes, navbar state, preference normalization, migration, reconciliation, and local fallbacks.

### Task 2: Home, Movies, Series, Watchlist, and Detail parity

- Match the Mac Home hero: addon landscape first, TMDB backdrop fallback, logo-first layout, one white action, awards/rating metadata, 560px desktop height, 60-second rotation, Mac spring timing, and artwork-derived ambient color.
- Build reusable standard, cinematic, banner, stack, carousel, Top 10, and Continue Watching rails.
- Match the 154x231 card baseline, 1.04 hover, artwork halo, optional preview, scale/radius settings, and trend/quality/genre/rating/age badges.
- Make Movies and Series complete Home-style destinations with hero, filters, continue-watching, and catalog rails.
- Implement Watchlist against `user_lists` with optimistic mutation and full loading/empty/error states.
- Redesign Detail around the 780px hero and the required section order: actions/overview, trailers, episodes, cast, gallery, awards, links, recommendations.
- Keep navigation/artwork alive through partial request failures and add component/data tests.

### Task 3: Unified Mac-style player and ARVIO-derived routing

- Add `PlaybackPlan`, `PlayerAdapter`, `PlayerSession`, and expanded `PlayerLaunch` contracts.
- Move top bar, timeline, controls, panels, prompts, loading, errors, hotkeys, and auto-hide into one React UI shared by Vidstack/HLS, Mediabunny, retained WebCodecs, and MPV adapters.
- Match Mac timing/dimensions: 2.4-second auto-hide, 0.18-second fade, 256x144 seek preview, 360px audio, 500px subtitles, and 440px Up Next.
- Implement direct/native HLS, HLS.js MSE, lazy MPEG-TS, safe Chromium MKV, Mediabunny remux, configured server/debrid remux/transcode, and fallback/external outcomes.
- Detect HEVC, AV1, AC-3, E-AC-3, Dolby Vision profile 5, archive containers, no-video, black frames where possible, startup timeout, and repeated buffering.
- Preserve position/tracks during fallback and lazily probe embedded audio on panel open.
- Keep Tauri MPV behind the same controller and UI, falling back to browser adapters when unavailable.
- Add unit, component, and media-fixture integration tests for routing, state, controls, panels, fallback, live behavior, and Tauri IPC mocks.

### Task 4: Functional Live TV

- Add profile-isolated device-local M3U, Xtream, and XMLTV sources encrypted at rest with Web Crypto and a non-extractable key.
- Implement source switch/edit/delete/refresh, grouped channel search, 150-190px channel tiles, now/next progress, six-hour EPG, fixed channel column, manual matching, live playback, and catch-up URLs.
- Use native Tauri requests and direct browser CORS first.
- Add authenticated short-lived proxy sessions for sources requiring proxying. Accept credentials in POST bodies, rewrite child manifests, allow HTTP(S) only, block private/reserved networks and unsafe redirects, support Range, rate-limit, and set `Cache-Control: no-store`.
- Let browser guests use CORS-compatible sources and require sign-in only for proxy-required sources.
- Add parser, EPG, catch-up, encryption, source repository, proxy security, and UI tests.

### Task 5: Preview-first customization, accessibility, responsive polish, and verification

- Replace placeholder settings with live artwork, playback, and subtitle customization matching Mac controls.
- Add section reset, optimistic local preview, cloud persistence status, platform-capability labels, and desktop-only Anime4K visibility.
- Finish keyboard support, focus management, accessible names/landmarks/live regions, reduced motion, touch targets, responsive reflow, and 200% zoom behavior.
- Add Playwright visual snapshots for desktop, tablet, and mobile against the approved render.
- Run `npm test -- --run`, `npm run typecheck`, `npm run lint`, `npm run build`, and the Tauri build/check available in the environment. Perform final plan audit and code review.
