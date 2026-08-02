# Preferred Audio & Subtitle Language Design

**Date:** 2026-08-02

**Status:** Approved concept; awaiting written-spec review

**Scope:** iOS app (`Apps/MoonlitApp`, iOS target only — tvOS/macOS unchanged). Settings UI, a one-time post-profile prompt, and wiring the preference into playback. Cross-platform sync reuses the `profile_preferences` table that `moonlit-web` already writes to.

## Goal

Let a user set a preferred audio language and a preferred subtitle language once, then have every stream selection and every playback session respect it automatically — without re-selecting a track every time they hit play.

## Current State (why this is mostly wiring, not new modeling)

Two pieces of this feature already exist in the codebase but were never connected to anything:

- [`VideoPlayerPreferenceStore`](../../../../../Packages/MoonlitCore/Sources/MoonlitCore/Services/VideoPlayerPreferenceStore.swift) already has `preferredAudioLanguage` / `preferredSubtitleLanguage` (device-local `UserDefaults`, ISO 639-1 code or `nil`) and a `PlaybackLanguage` catalog of 26 languages with ISO 639-2 aliases.
- [`StreamSourceSelector`](../../../../../Packages/MoonlitCore/Sources/MoonlitCore/Services/StreamSourceSelector.swift) already threads a `preferredAudioLanguage` parameter through its ranking functions (`initialStream`, `rankedCandidates`, `candidatesForAutoPlay`, `cachedCandidates`) to rank streams whose filename advertises a matching dub higher.

Neither is reachable today: no Settings UI sets them, no onboarding step exists, and every call site (`StreamSelectionScreen`, `PlayerScreen`, `SourcesPanel`) calls the ranking functions without passing the parameter, so it's always `nil`. `MPVPlayerEngine` never sets mpv's `alang`/`slang` options, so there's also no auto-selection of an embedded audio/subtitle track by language.

Separately, `moonlit-web` already implements the exact same feature end-to-end: [`profile-preferences.ts`](../../../../../moonlit-web/src/lib/preferences/profile-preferences.ts) defines a `PlayerPreferences` interface (autoplay, skip-intro, cache mode, per-type players, and — the two fields we care about — `preferredAudioLanguage: string | null` / `preferredSubtitleLanguage: string | null`), normalizes and validates it (`nullableLanguage`: lowercase, 2–3 letters), and syncs it to Supabase's `profile_preferences` table (migration `20260731_profile_preferences.sql`) under `namespace = 'player'`, with local-storage caching, offline fallback, and cloud-newer-wins reconciliation by `updated_at` timestamp.

**Implication:** the `player` namespace row for any user who has touched moonlit-web already contains real data (their autoplay/skip-intro/cache settings). iOS must not blindly overwrite that row — it must read the existing JSON blob, set only the two language keys, and write the blob back. iOS is explicitly **not** taking on full parity sync of the other ~13 `PlayerPreferences` fields in this change — that's a separate, larger project.

## Non-Goals

- Syncing any `PlayerPreferences` field other than `preferredAudioLanguage` / `preferredSubtitleLanguage`.
- Syncing `subtitles`-namespace (appearance) or `home`/`artwork`-namespace preferences.
- tvOS or macOS changes.
- An "always show subtitles in this language" auto-enable behavior (explicitly decided against — matching track auto-*selects*, it doesn't force subtitles on when the audio already matches).
- Building a generalized bidirectional preferences-sync framework for iOS. This is a narrow, purpose-built sync path for two fields; a general framework (if ever needed) is future work.

## Data Model

No schema change needed — reuses the existing `profile_preferences` table:

```
profile_preferences(profile_id uuid, namespace text, schema_version int, value jsonb, updated_at timestamptz)
```

iOS reads/writes `namespace = 'player'`, merging only these two keys into whatever JSON blob is already there:

```json
{
  "preferredAudioLanguage": "en",
  "preferredSubtitleLanguage": null
}
```

- Values are lowercase ISO 639-1 codes (e.g. `"en"`, `"es"`) or `null`/absent for "no preference" — matches `PlaybackLanguage.code` and the web's `nullableLanguage` validator exactly.
- `schema_version` stays whatever the row already has (web currently uses `1`); iOS does not bump or care about this field beyond passing it through unchanged if present, or writing `1` if the row doesn't exist yet.

## Architecture

### 1. `ProfilePreferencesService` (new, MoonlitCore)

A small service, not a general framework — two operations:

```swift
public enum ProfilePreferencesService {
    /// Reads the `player` namespace row for this profile and pulls just the two
    /// language keys out of it. Returns (nil, nil) if the row doesn't exist yet
    /// or on any network failure — callers fall back to the local cache.
    static func fetchLanguagePreferences(profileId: String) async -> (audio: String?, subtitle: String?)

    /// Read-merge-write: fetches the current `player` row's JSON (if any),
    /// overwrites only the changed key, preserves every other field untouched,
    /// and upserts with a fresh `updated_at`. Fire-and-forget from callers —
    /// errors are logged, not surfaced (the local write already succeeded).
    static func setPreferredAudioLanguage(_ code: String?, profileId: String) async
    static func setPreferredSubtitleLanguage(_ code: String?, profileId: String) async
}
```

Uses the existing `SupabaseClient.select`/`upsert(into:onConflict:value:)` — no new HTTP plumbing needed. `onConflict: "profile_id,namespace"` matches the table's primary key, same pattern `ProfileManager.updateProfile` already uses for the `profiles` table.

Reconciliation is intentionally simple, not full last-write-wins: iOS pulls once per profile-select (see below) and pushes on every local change. This can race with a simultaneous web edit on another device, same as any last-write-wins system without a merge UI — acceptable here since it's exactly two independent scalar fields, not a large object where partial loss would be surprising.

### 2. `VideoPlayerPreferenceStore` stays the synchronous local cache

Playback code (`StreamSourceSelector` callers, `MPVPlayerEngine`) cannot await a network call mid-playback-start, so `VideoPlayerPreferenceStore.preferredAudioLanguage`/`preferredSubtitleLanguage` remain exactly as they are today: synchronous `UserDefaults`-backed properties. Nothing about their existing get/set signature changes.

What's new is who calls them and when:

- **Pull** — `ProfileManager`, right after a profile is selected or restored (mirroring where it already calls `AddonRepository.loadAddons(profileId:)` in `ContentView`/`MainTabView`), calls `ProfilePreferencesService.fetchLanguagePreferences(profileId:)` and, if either value is non-nil, writes it into `VideoPlayerPreferenceStore`. Guest mode (`guestMode == true`, no authenticated profile) skips this entirely — local store is the only source of truth for guests.
- **Push** — the two Settings picker rows (see below) set `VideoPlayerPreferenceStore` directly (instant local UI update) and, if there's a current authenticated profile, also fire `Task { await ProfilePreferencesService.setPreferred...(code, profileId: id) }`.

### 3. Wiring the preference into actual playback behavior

This is the part that's silently missing today even for a hardcoded value:

- `StreamSelectionScreen`, `PlayerScreen` (both `cachedCandidates` call sites and `candidatesForAutoPlay`), and `SourcesPanel`'s two `rankedCandidates` calls all start passing `preferredAudioLanguage: VideoPlayerPreferenceStore.shared.preferredAudioLanguage`.
- `MPVPlayerEngine.setupPlayer(with:)` sets mpv's `alang` option from `preferredAudioLanguage` and `slang` from `preferredSubtitleLanguage` (both optional — omitted when `nil`, leaving mpv's existing `subs-match-os-language`/`subs-fallback` behavior as the fallback for subtitles, and mpv's own default track selection for audio). This is the mechanism that actually auto-selects a matching **embedded** track on load; `PlaybackLanguage`'s stream-ranking logic (already wired via the selector calls above) is what ranks **separate stream sources** (e.g. a dubbed release) higher when multiple exist.
- External subtitle preselection: wherever `SubtitleModal`/`PlayerScreen` currently pick a default subtitle from a loaded list (if anywhere), prefer a matching-language item when `preferredSubtitleLanguage` is set and multiple are available. (To be confirmed against current code during planning — if no such default-selection logic exists today, this is a no-op and subtitles simply stay off until the user picks one, consistent with the "auto-select only" decision.)

### 4. Settings UI

New "Languages" section in `VideoPlayerSettingsScreen`, between "Playback" and "Skip Intro" — two `pickerRow`s ("Preferred Audio", "Preferred Subtitles"), options built from `PlaybackLanguage.all` plus a leading "System Default" (`nil`) option, using the screen's existing `pickerRow`/`glassCard` pattern verbatim (no new visual component).

### 5. One-time post-profile prompt

Not a page inside `OnboardingView.swift` — that carousel's login/profile pages are unwired stubs; real auth and profile creation happen afterward, in `ContentView`'s branching. The prompt is a new screen inserted into `ContentView` between profile selection/creation and `MainTabView`:

```
profileManager.currentProfile != nil
  → needsLanguagePrompt(for: profile) ? LanguagePreferenceScreen() : MainTabView()
```

`needsLanguagePrompt`:
- `false` immediately for guest mode (nothing to check server-side; guest already only uses local defaults and isn't blocked from Settings).
- `false` if a local per-profile flag (`moonlit.hasPromptedLanguagePrefs.<profileId>`) is already set.
- Otherwise, after the pull in step 2 above has run for this profile: `true` if both `VideoPlayerPreferenceStore` language values are still `nil` (meaning nothing came back from Supabase and nothing local either), `false` if the pull populated either one.
- Whether the user sets values or taps "Skip for now," the local flag is set immediately so the prompt never nags on this device again. If they skip, a different device signed into the same account still gets prompted once, since nothing was written to Supabase — matching "only if there's nothing in the database."

Visuals: modeled on `CreateFirstProfileScreen`'s "ALMOST THERE" treatment (black background, `SplashStarField`, gold `#C8941A` accent, bold white title) since it occupies the same "one last setup step" moment right after profile creation. Two tappable rows (Audio, Subtitles) opening a language picker, "Continue" primary button, "Skip for now" text link. Confirmed against the mockup shown in chat.

## Testing

- `ProfilePreferencesService`: unit tests for read-merge-write (existing blob with unrelated keys is preserved), missing-row case, and network-failure fallback.
- `StreamSourceSelector`: existing tests already cover `preferredAudioLanguage` ranking logic — no new coverage needed there, just confirm call sites now pass it (covered by call-site tests / manual verification).
- `VideoPlayerPreferenceStore`: existing pattern (get/set round-trip) extended with a quick check that the two properties are unaffected by this change (they already existed).
- Manual/simulator verification: set a language in Settings, confirm mpv's `alang`/`slang` are set on next playback (log line or debugger check), and confirm the one-time prompt shows once, respects skip, and doesn't reappear.

## Open Question for Planning

Whether `PlayerScreen`/`SubtitleModal` currently has *any* default-subtitle-selection logic to hook the "prefer matching language" behavior into, or whether subtitles are purely manual-select today. Resolve by reading that code during plan-writing rather than guessing here.
