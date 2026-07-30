# Player Track Panels and Glass Controls Design

## Scope

Refresh the iOS player’s audio/subtitle controls and lower chrome without changing
the tvOS player or MPV playback architecture. Also split the iOS Detail page’s
combined list action into separate add and bookmark controls.

## Player Track Panel

Replace the two SwiftUI `Menu` controls with one stable custom overlay driven by a
single optional destination: Audio or Subtitles. Capture the active track list and
selection before presenting the overlay. Playback timeline updates must not rebuild
or dismiss the panel.

The panel uses a full-height-safe landscape sheet/card with a dimmed backdrop,
Liquid Glass on iOS 26, and the existing material fallback on older iOS versions.
Only the panel content transitions when switching between Audio and Subtitles.
Closing the panel resumes the normal player-control auto-hide timer.

## Track Modeling and Language Groups

Introduce a typed audio-track record containing MPV track ID, normalized language
code, optional title, display label, and selection state. Subtitle and audio
language codes are normalized to canonical lower-case ISO identifiers, with
`und` used for missing metadata.

Both lists group tracks by localized language name. A language with one track is a
direct selection row; a language with multiple tracks expands to variants such as
Original, Commentary, Forced, SDH, or the source-provided title. Duplicate display
names receive a stable ordinal suffix. The MPV track ID remains the selection key,
so localized or duplicate labels cannot select the wrong stream.

## Subtitle Appearance

The Subtitles panel has two tabs:

- Languages: Off plus the grouped subtitle tracks.
- Appearance: Standard, Boxed, Classic, and Minimal presets; text-size and vertical-
  position sliders; and an Advanced action.

Changes write through the existing `SubtitleAppearanceStore` and update active
subtitles immediately. Advanced presents the existing complete
`SubtitleAppearanceScreen` without leaving playback.

## Player Chrome

Match the supplied Apple TV reference more closely:

- Place elapsed time immediately before the timeline and remaining time immediately
  after it, eliminating the separate time row.
- Render Info and InSight as interactive Liquid Glass capsules on iOS 26 with the
  existing material fallback.
- Preserve current 44-point minimum targets, accessible names, transport geometry,
  and landscape safe-area positioning.

## Detail Actions

Keep the primary Play button unchanged. Beside it, show two independent 50-point
circular actions on iOS:

- Plus opens `AddToListSheet` for the full collection of list/like/watched choices.
- Bookmark directly toggles Watchlist through `LibraryRepository`.

Both use interactive Liquid Glass on iOS 26 and a circular material fallback. The
bookmark becomes filled when saved. tvOS retains its existing layout and behavior.

## Flicker and State Rules

The track panel must not refresh MPV tracks after presentation. Track refresh occurs
before snapshot capture, and repeated equivalent MPV results are ignored. The panel
owns expansion, tab, and scroll state so progress publisher updates cannot reset it.
Panel presentation pauses control auto-hide; dismissal restarts it once.

## Verification

- Unit-test language normalization, grouping, duplicate variants, and stable MPV-ID
  selection for audio and subtitles.
- Unit-test snapshot equivalence so repeated MPV refreshes do not invalidate an open
  panel.
- Build the iOS app and install it on the connected iPhone.
- On-device acceptance: panels remain open without flicker during playback; language
  groups expand correctly; appearance changes update subtitles; time labels flank
  the scrubber; Info/InSight and Detail actions render as glass; plus and bookmark
  perform distinct actions.
