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
- `moonlit-web/playwright.player.config.ts`, `vite.config.ts`, browser media spec, and encoded player fixtures
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

- The repository now has a Chromium Playwright media harness using checked-in encoded fixtures. It exercises HTML video, HLS.js/MSE, `mpegts.js`, Mediabunny, and WebCodecs through their real adapters. Native MPV remains manual-only because it requires the Tauri/libmpv desktop runtime rather than a browser.
- Chromium MKV eligibility is necessarily a metadata/title heuristic before startup; unknown or mislabeled MKVs rely on runtime failure detection and the ordered fallback chain.
- Browser exposure of embedded HLS audio tracks varies. The shared UI probes `HTMLMediaElement.audioTracks` lazily, but browsers that hide HLS.js audio tracks may not expose every rendition.
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

## Fix Round 2 (2026-08-02)

Review findings in `task-3-rereview-round1.md` were addressed with witnessed RED/GREEN regressions. Both Critical security fixes from round 1 were preserved. The optimistic HTML audio-capability Minor remains deferred as requested, along with the previously documented cumulative-buffering, HLS-recovery, and codec-heuristic Minors.

### Lifecycle and exact-once teardown

- `PlayerSession` now memoizes adapter disposal promises, so fallback, cancellation continuations, terminal exhaustion, Retry, and replacement cannot destroy the same adapter twice.
- HTML destruction joins an unresolved transport attachment before returning and performs its eventual cleanup exactly once. WebCodecs and MPV gate every post-await startup continuation, and WebCodecs engine destruction is idempotent.
- Added RED/GREEN coverage for a pending terminal adapter, unresolved HTML attachment, WebCodecs cancellation during resume seek, and MPV cancellation during track restoration.

### Track identity, late subtitles, and native window state

- Added renderer-neutral track identities containing kind, normalized language, label, source URL where available, and same-kind ordinal. Selection snapshots identity synchronously, so same-language and language-less external tracks survive asynchronous handoff without leaking adapter-local IDs.
- MPV now reconciles `sub-add` results against the native track list, maps app subtitle IDs to numeric native `sid` values, avoids duplicate app/native rows, and never forwards string app IDs to MPV.
- HTML and MPV restore selection by neutral identity. Tests cover the second of two same-language audio tracks, a language-less external subtitle, and manual selection of a late MPV subtitle.
- HTML and WebCodecs listen for native fullscreen changes. MPV listens for native Tauri window state, exits PiP/fullscreen during destroy, restores saved geometry/always-on-top state, and removes the window listener.

### Chrome recovery, focus, and bounded previews

- Terminal error/external states now permit the Sources panel; the complete Choose source → select backup → close flow is covered.
- Listboxes now implement actual roving `tabIndex`: arrow/Home/End movement updates both DOM focus and the sole tab stop, including lists with no selected item.
- Timeline preview work is debounced, abortable, generation-safe, and cached. HTML owns at most one preview worker, aborts it on replacement/destroy, and bounds its cache. Tests cover rapid hover, cancellation, latest-result wins, reuse, and teardown cleanup.

### Real decode harness and discovered integration fix

- Added `@playwright/test`, a dedicated Playwright config/script, WebVTT plus genuine MKV/MPEG-TS fixtures, and Vitest exclusion for the e2e directory.
- Chromium now verifies actual MP4 readiness/dimensions/subtitle selection/JPEG preview/ended, finite HLS.js/MSE playback and ended, dead-source `PlayerSession` fallback, continuous `mpegts.js` decode/progress, Mediabunny MKV remux/decode, and WebCodecs MKV decode.
- Conditional worker-backed adapters receive absolute fixture URLs because blob workers cannot resolve document-root-relative fixture paths. The RED errors were captured at the transport boundary before changing only the test input.
- The real Mediabunny run exposed a production deadlock: fragmented-MP4 MIME discovery waits for the first converted track data, while conversion previously began only after MIME resolution. Conversion and MIME discovery now overlap; a focused unit regression and the real browser decode both pass.
- Native MPV is explicitly annotated as Tauri/libmpv manual-only; its bridge behavior remains covered deterministically in Vitest.

### Fix-round-2 verification

- Full Vitest suite: PASS — 47 files, 272 tests.
- Chromium Playwright media suite: PASS — 6 tests.
- TypeScript: PASS — `npm run typecheck`.
- Task 3 scoped ESLint: PASS.
- Production build: PASS — `npm run build` (only the existing chunk-size advisory).
- Generated Playwright `test-results/.last-run.json` was restored to its pre-task bytes and excluded from the commit.

## Fix Round 3 (2026-08-02)

The six Important groups from `task-3-rereview-round2.md` were addressed with focused RED/GREEN regressions. Both Critical security fixes and every previously closed Important remain preserved. The unbounded HTML preview-cache Minor, optimistic HTML audio-capability Minor, and the other previously documented Minors remain deferred as requested.

### Cancellation and shared-host ownership

- HTML destruction no longer waits on a transport attachment that may ignore cancellation forever. It invalidates the attachment generation, tears down listeners immediately, and retains late-result cleanup so a transport that eventually resolves cannot attach to or mutate a replacement host.
- MPV bridge ownership is now explicit per active load. An old adapter still stops its own late start after cancellation, but only while it remains the process-global bridge owner; a late old continuation cannot stop a newer replacement session.
- WebCodecs permits a second cleanup after a previously disposed engine's asynchronous load settles, closing resources created after the first destroy. Per-engine canvas ownership preserves the dimensions claimed by a replacement using the shared host, so stale cleanup cannot restore the retired renderer's canvas state.

### Subtitle races and neutral track handoff

- MPV resolves mapped app subtitle IDs before considering native numeric IDs, so digit-only Stremio IDs cannot be misrouted as native `sid` values. A click made before `sub-add` mapping completes is queued and applied when the map is published.
- Neutral track lookup now prioritizes source URL and same-kind ordinal before fuzzy language/label matching, restoring the correct member of otherwise identical audio and subtitle rows.
- `PlayerSession` records user track selection synchronously and ignores stale adapter selection events until the requested selection is acknowledged. `UnifiedPlayer` reads the live session handoff for immediate source switches, including MPV selections made before native acknowledgement.

### Modal focus and preview isolation

- Modal Tab containment now considers only enabled controls with `tabIndex >= 0`, preserving the roving listbox tab stop in both directions. The speed panel assigns its first preset as the fallback tab stop when playback reports a non-preset rate.
- Seek-preview state is scoped to both active attempt and current stream identity. A scope change advances the result generation, aborts pending capture, clears the timestamp cache, and makes an already rendered frame ineligible immediately; the same timestamp on a replacement source requests a fresh image.

### Fix-round-3 verification

- Full Vitest suite: PASS — 47 files, 281 tests.
- Chromium Playwright media suite: PASS — 6 tests.
- TypeScript: PASS — `npm run typecheck`.
- Task 3 scoped ESLint: PASS.
- Production build: PASS — `npm run build` (only the existing chunk-size advisory).
- Whitespace validation: PASS — `git diff --check`.
