# Task 3 Report: Unified Mac-Style Player and ARVIO-Derived Routing

## Summary

Implemented one shared React player surface and deterministic playback session for browser and Tauri playback. The new planner routes direct media, native/HLS.js HLS, lazy MPEG-TS, Chromium MKV, Mediabunny remux, retained WebCodecs, configured server conversion, MPV, and external/unsupported outcomes while preserving playback handoff state across failures.

Product commit: `989caa5b` (`feat(web): unify player routing and chrome`)

## Implemented Behavior

- Added normalized `PlayerLaunch`, `PlaybackPlan`, adapter state/capability, track, and load contracts.
- Added `PlayerSession` with ordered adapter attempts, 15-second startup timeout (including hung `load()` promises), repeated-buffer detection, no-video/black-frame fallback, cross-attempt position and track preservation, retry, terminal failure, and lazy audio probing.
- Replaced renderer-specific UI with one `UnifiedPlayer` host and `PlayerChrome` for HTML/HLS, Mediabunny, WebCodecs, and MPV.
- Matched the approved Mac measurements: 2.4-second auto-hide, 180ms fade, 256×144 seek preview, 360px audio panel, 500px subtitle panel, and 440px Up Next panel.
- Centralized loading, readiness, errors, resume/start-over, source/audio/subtitle/speed panels, intro skipping, Up Next, progress/completion reporting, hotkeys, fullscreen/PiP/remote controls, and capability gating.
- Added profile-aware per-media engine selection, language/track restoration, intro database/fallback preferences, subtitle appearance propagation, last-source memory, and exact-position cross-source handoff.
- Added direct/native HLS, HLS.js MSE, lazy `mpegts.js`, Chromium MKV, Mediabunny MSE remux, WebCodecs, server remux/transcode, MPV, external, and unsupported routing outcomes.
- Added HEVC, AV1, AC-3, E-AC-3/DD+, Dolby Vision profile 5, archive, audio-only, no-video, black-frame, startup timeout, and repeated-buffer safeguards.
- Added request-header forwarding for protected direct/debrid media through the production and Vite media proxies, HLS.js, MPEG-TS, and MPV. Native HLS is skipped when manifest headers are required.
- Reconciled explicit launch URLs back to their full stream metadata and made provider stream-switch registration safely unregisterable.
- Kept async profile/subtitle reconciliation from recreating an active playback session.
- Completed WebCodecs end-state publication and Mediabunny MSE queue drain/error propagation.
- Kept MPV behind the shared controller, including IPC state, geometry, track/language restoration, external subtitles, subtitle style updates, and honest capability flags.

## TDD Evidence

Tests were added before each production slice for:

1. Launch/adapter normalization and routing matrices.
2. Session fallback, handoff, timeout, buffering, black/no-video, retry, and lazy probes.
3. HTML/HLS/MPEG-TS header behavior, readiness, track restoration, and conservative black-frame detection.
4. Mediabunny, WebCodecs, and Tauri MPV adapter normalization and teardown.
5. Shared chrome dimensions, auto-hide, panels, prompts, errors, hotkeys, and capability gating.
6. Unified renderer fallback/progress/intro behavior and the no-restart reconciliation guarantee.
7. Provider, overlay, shell selection, profile preferences, intro configuration, stalled resolution, and exact-position cross-source integration.
8. Embedded plus appended subtitle identity ordering.

Representative RED runs captured missing modules/contracts first, then expected failures for hung adapter loads, cascading fallback re-entrancy, premature metadata readiness, aggressive black-frame sampling, protected headers, dead-end external outcomes, WebCodecs completion, MPV restoration/capability honesty, and mixed embedded/external subtitle ordering. Each was made GREEN before the next slice.

## Final Verification

- Full Vitest suite: PASS — 44 files, 223 tests.
- Player regression matrix: PASS — 19 files, 116 tests before the final subtitle-order regression; the final full suite includes that additional passing test.
- TypeScript: PASS — `npm run typecheck`.
- Task-owned scoped ESLint: PASS.
- Production build: PASS — `npm run build` (retains the existing large-chunk advisory).
- Whitespace validation: PASS — `git diff --check` and staged diff check.
- Repository-wide ESLint: baseline-red — 89 errors and 9 warnings in legacy/unrelated files such as `AuthProvider`, old renderer components/panels, routes, and collection helpers. No Task 3 scoped lint finding remains.

## Files Changed

- `moonlit-web/api/media-proxy.ts`
- `moonlit-web/package.json` and `package-lock.json`
- `moonlit-web/vite.config.ts`
- `moonlit-web/src/index.css`
- `moonlit-web/src/app/PlayerProvider.tsx` and player integration test
- `moonlit-web/src/components/PlayerOverlay.tsx` and test
- `moonlit-web/src/components/player/PlayerChrome.tsx` and test
- `moonlit-web/src/components/player/UnifiedPlayer.tsx` and test
- `moonlit-web/src/components/player/PlayerShell.tsx`, integration test, and intro/preference/selection helpers and tests
- `moonlit-web/src/components/player/UpNextPanel.tsx`
- `moonlit-web/src/lib/player/contracts.ts`, `routing.ts`, `session.ts`, `media-proxy.ts`, and tests
- `moonlit-web/src/lib/player/adapters/` HTML, Mediabunny, WebCodecs, and MPV adapters and tests
- `moonlit-web/src/lib/webcodecs-player.ts`

## Self-Review and Concerns

- The repository has no Playwright/media-harness setup. Integration coverage uses deterministic media metadata fixtures, mocked HTML media events, MSE/HLS/MPEG-TS engines, and Tauri IPC rather than decoding checked-in encoded video assets in a real browser.
- Chromium MKV eligibility is necessarily a metadata/title heuristic before startup; unknown or mislabeled MKVs rely on runtime failure detection and the ordered fallback chain.
- Browser exposure of embedded HLS audio tracks varies. The shared UI probes `HTMLMediaElement.audioTracks` lazily, but browsers that hide HLS.js audio tracks may not expose every rendition.
- Subtitles delivered after an adapter has already loaded are shown in the shared panel without restarting playback, but an adapter may require a later follow-up to append that late track to the active engine.
- The streaming server must itself be able to retrieve protected upstream media for server remux/transcode routes; direct browser, HLS.js, MPEG-TS, WebCodecs/Mediabunny proxy, and MPV header paths are covered here.
- The production bundle still emits the existing chunk-size warning. MPEG-TS and HLS are lazy-loaded; broader application bundle splitting remains outside this task.
- Unrelated native, portal, legacy submodule, worktree, and pre-existing migration changes were preserved and excluded from the commit.

## Fix Round 1 (2026-08-02)

Review findings in `task-3-review.md` were addressed with RED/GREEN regressions before each production change.

### Security and routing

- Permanently disabled the credential-bearing URL media proxy in both the edge handler and Vite dev middleware (`410 Gone`, `Cache-Control: no-store`). The client proxy builder now fails closed; no raw URL/header query contract remains.
- Source request headers are reduced to a bounded allowlist and attached only to the exact selected source. HLS.js applies them only to same-origin requests. Server, MPV, redirect/cross-origin, backup-source, Mediabunny, and WebCodecs paths never inherit unrelated source credentials.
- Protected direct media now requires a future authenticated opaque proxy session and otherwise opens externally. Protected HLS uses HLS.js exact-origin headers and refuses a headerless native fallback.
- Completed ordered HLS, MPEG-TS (including no-MSE), direct, blocked-codec, server, MPV-preferred, browser, and external fallback ladders. An explicit unsupported/external source no longer prevents selection of a later safe source.

### Lifecycle, state, and handoff

- Added load generations and `AbortSignal` propagation through session, HTML/HLS/MPEG-TS, Mediabunny, WebCodecs, and MPV startup. Replacement sessions await prior teardown; stale async attachments are disposed. A delayed MPV start is explicitly stopped after cancellation.
- Adapter destroy rejection is best-effort and cannot abort fallback. The terminal adapter is disposed before publishing the final error, and Retry begins again from the primary attempt.
- Authoritative profile reconciliation and late subtitle delivery update an active session without rebuilding playback. HTML, Mediabunny, and MPV append late subtitles in place.
- Adapter-local audio/subtitle IDs are cleared across adapter/source boundaries; language and `off` intent are retained and restored by the next renderer.
- Progress writes are serialized. Completion is latched so a later interval cannot write an incomplete state after `ended`; explicit replay/new playback resets the latch.
- MPV and WebCodecs now publish fullscreen changes. MPV publishes PiP state, restores the previous desktop window geometry after PiP, derives `hasVideo` from MPV's track list, and triggers audio-only fallback.

### Interaction, audio, previews, and fixtures

- Panels now focus on open, trap Tab, use one roving listbox Tab stop with arrow/Home/End navigation, close on phase transitions, and restore the opener. Global playback hotkeys ignore interactive controls; overlay Escape cannot close the player while a chrome panel owns it. Keyboard focus suspends auto-hide and keeps controls exposed to accessibility APIs.
- HTML playback retains its HLS.js transport so the first audio-panel open enumerates and selects HLS renditions even when Chromium lacks `HTMLMediaElement.audioTracks`.
- Added a renderer-neutral seek-preview request/result contract. The timeline requests hovered time, follows pointer position, and renders the returned image. Safe direct HTML media uses an isolated element and canvas to produce a real 256×144 JPEG without disturbing playback.
- Added committed, genuinely encoded two-second H.264/AAC MP4 and finite HLS/MPEG-TS fixtures. The integration harness validates auth rejection, no-store behavior, CORS, byte-range `206` delivery, MP4 video/audio track signatures, deterministic duration/end timing, HLS end markers, and MPEG-TS sync bytes.

### Fix-round verification

- Full Vitest suite: PASS — 47 files, 258 tests.
- TypeScript: PASS — `npm run typecheck`.
- Task 3 scoped ESLint: PASS.
- Production build: PASS — `npm run build` (only the existing chunk-size advisory).
- Encoded-media integration harness: PASS — 3 tests.
- Repository-wide ESLint remains baseline-red: 95 errors and 9 warnings in unrelated legacy/application files. All lint findings in the Task 3 fix scope were removed.
