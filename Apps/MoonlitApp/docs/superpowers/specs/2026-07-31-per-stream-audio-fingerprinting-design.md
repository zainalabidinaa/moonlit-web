# Per-Stream Audio Fingerprinting Design

**Date:** 2026-07-31

**Status:** Approved concept; awaiting written-spec review

**Scope:** iPhone/iPad MPV player. Native tvOS and macOS players are unchanged.

## Goal

Make Skip Intro timings adapt to the exact stream the user opens without scanning an entire season. Moonlit will analyze only a bounded opening window from the selected stream, align its audio with a locally cached season reference, and cache the resulting timing for that stream.

Fingerprinting augments the existing segment resolver. It does not replace exact embedded chapters or reliable duration-matched timestamps, and it must never delay playback.

## User Experience

1. Playback begins immediately using the existing MPV path.
2. Moonlit checks embedded chapters and the existing remote segment providers.
3. When a compatible season reference exists, Moonlit samples the selected stream's opening window in the background.
4. A high-confidence match produces stream-specific intro boundaries.
5. Skip Intro appears only while playback is inside the verified interval.
6. The result is cached for the exact stream and reused on later playback.

The target is to produce a match within 10 seconds on a seekable direct stream. Analysis times out after 30 seconds and fails silently, leaving existing timestamp behavior intact.

## Supported Detection

- **Intro:** Supported when the selected audio contains the same recurring material as the season reference.
- **Outro:** The architecture permits future outro matching, but the first implementation is intro-only.
- **Recap:** Not fingerprint-detected. Recap audio normally changes per episode, so existing verified recap timestamps remain authoritative.

## Architecture

### `AudioFingerprintReference`

A compact, versioned representation of a known intro:

- canonical media identifier
- season number
- normalized audio-language identifier
- fingerprint algorithm and version
- rolling fingerprint frames
- reference segment duration
- source confidence
- creation and last-validation dates

No raw audio is stored.

### `StreamFingerprintIdentity`

Identifies an analyzed release using the strongest available non-secret attributes:

- canonical episode identifier
- normalized stream URL identity
- file duration bucket and exact measured duration
- selected audio-track language and codec
- content length or stable release metadata when available
- fingerprint algorithm version

Authentication query parameters, cookies, and request headers must not be persisted.

### `StreamAudioSampler`

Opens a separate, cancellable low-priority decode path using the selected stream URL and required headers. It:

- decodes audio only
- downmixes to mono
- resamples to the fingerprint algorithm's required sample rate
- samples only the first 15 minutes
- prefers sparse windows for initial matching
- performs a narrow continuous scan only around a likely match

The sampler never mutates MPV playback state and immediately stops when the player closes, the stream changes, the selected audio language changes, or the timeout expires.

### `AudioFingerprintEngine`

Produces rolling fingerprints and aligns them with a compatible reference. The result includes:

- detected start and end
- similarity score
- aligned-frame coverage
- timing uncertainty
- algorithm version

The engine is independent from networking and playback so deterministic fixtures can test it.

### `IntroFingerprintStore`

Persists references and stream-specific matches locally. Records are invalidated when:

- the algorithm version changes
- measured duration materially changes
- the selected audio language differs
- stream identity changes
- the reference is replaced or corrected

Storage is bounded with least-recently-used eviction.

### `PlaybackSegmentResolver` Integration

Resolution priority becomes:

1. exact embedded chapters
2. valid cached fingerprint match for the exact stream
3. live per-stream fingerprint alignment
4. duration-matched SkipDB.tv
5. duration/version-matched TheIntroDB.org
6. verified IntroDB.app fallback

An exact embedded chapter wins immediately. A live fingerprint match may replace a lower-confidence remote timing only when its confidence and boundary checks pass. SkipDB out-of-range protection continues to stop unsafe fallback.

## Reference Creation

Moonlit does not analyze a whole season.

A season reference can be created from:

1. an exact embedded intro chapter in the selected stream;
2. a duration-matched, high-confidence timestamp that passes boundary validation;
3. a previously stored reference for the same show, season, and audio language; or
4. a future explicit user correction flow.

Episode-only, low-confidence timestamps may be displayed under current fallback rules but cannot silently become fingerprint references.

On the first episode with no trustworthy seed or compatible reference, fingerprint matching is unavailable. Moonlit retains current segment-provider behavior rather than guessing.

## Confidence and Safety

A detected interval is accepted only when:

- similarity exceeds a calibrated threshold;
- enough consecutive fingerprint frames align;
- the proposed interval lies inside the opening analysis window;
- its duration is within configured intro bounds;
- timing uncertainty is below the allowed boundary tolerance; and
- the reference and selected stream use compatible audio languages.

Near-threshold matches are discarded. Automatic seeking is not introduced; the user still presses Skip Intro.

## Performance and Playback Isolation

- Playback has priority over analysis for CPU, networking, and memory.
- Only one analysis task may run for the active player.
- Sampling pauses or cancels during sustained playback buffering.
- The decoder uses bounded buffers and releases them after each sampled window.
- Thermal pressure, low-power mode, network constraints, or memory pressure may suppress analysis.
- Analysis cancellation is tied to the existing stream-switch and player-dismiss lifecycle.

The implementation will be benchmarked on the user's iPhone 17 with representative direct, debrid/MKV, and HLS streams. Estimated detection times are targets, not acceptance evidence.

## Error Handling

Fingerprinting fails silently and records a diagnostic reason without storing URLs or credentials. Expected failures include:

- range requests unsupported
- source headers rejected
- audio track unavailable
- reference language mismatch
- insufficient matching material
- decoding timeout
- user switches streams
- player closes

Failure never produces a skip interval and never blocks the existing resolver.

## Privacy and Security

- Initial implementation is entirely local.
- Raw or decoded audio is never persisted.
- No audio or fingerprint is uploaded.
- Signed URLs, cookies, authorization headers, and addon credentials are excluded from cache keys and logs.
- Cached fingerprints are treated as disposable derived data.

Community fingerprint synchronization is explicitly outside this implementation.

## Testing

### Unit tests

- stable fingerprint generation from normalized PCM
- alignment across leading-offset changes
- tolerance for codec and volume variation
- rejection of unrelated audio
- rejection of short or ambiguous matches
- boundary and duration validation
- language and algorithm-version invalidation
- sanitized stream identity generation
- cache eviction and replacement
- cancellation and timeout behavior

### Integration tests

- embedded chapter bypasses analysis
- cached exact-stream match resolves immediately
- fingerprint result supersedes only lower-confidence timing
- analysis cancellation on source switch
- no player-state mutation by the sampler
- fallback remains available after fingerprint failure
- no fingerprint-based recap is emitted

### Device verification

- playback begins without waiting for analysis
- video remains smooth during sampling
- Skip Intro appears without shifting other controls
- switching streams cancels the old analysis
- closing the player cancels decoding and restores portrait
- repeated playback uses the cached exact-stream match
- app memory and thermal behavior remain acceptable

## Acceptance Criteria

- Only the selected stream is sampled.
- At most the opening 15 minutes are considered.
- Playback is never delayed by fingerprinting.
- A verified stream-specific result is normally available within 10 seconds on a seekable direct stream and analysis stops after 30 seconds.
- No Skip Intro action is produced below the calibrated confidence threshold.
- No raw audio, credentials, or signed URLs are persisted.
- Existing segment providers and player behavior continue to work when fingerprinting is unavailable.
- The completed implementation is locally tested, then built and installed on the user's explicitly requested iPhone 17. No cloud device is used.

## Deferred Work

- Community-hosted fingerprint database
- fingerprint upload or contribution flow
- machine-learned single-episode intro classification
- fingerprint-based recap detection
- tvOS and macOS integration
