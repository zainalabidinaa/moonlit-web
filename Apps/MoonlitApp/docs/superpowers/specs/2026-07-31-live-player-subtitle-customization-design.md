# Live Player Subtitle Customization Design

## Goal

Make the iOS player’s native Audio and Subtitles controls visually consistent and stable, keep player controls visible while any menu or panel is in use, and provide live subtitle styling and timing controls without covering the playing video.

The native tvOS player remains unchanged.

## Native Track Menus

- Keep Audio and Subtitles as native SwiftUI `Menu` presentations.
- Apply the same reusable Liquid Glass control modifier used by adjacent player buttons, including the 44-by-44-point target.
- Keep the extracted track-menu view structurally independent of timeline progress updates.
- Order the Subtitles menu as:
  1. Customize Subtitles
  2. Available language groups
  3. Off
- Order language groups using a stable global-popularity priority. Sort languages outside the priority list alphabetically and keep unknown-language tracks last.
- Group variants with the same canonical language in a native submenu.

## Stable Panel and Auto-Hide Lifecycle

- Keep the player-controls subtree mounted while hidden. Use opacity and hit-testing state instead of conditionally adding and removing the subtree.
- Cancel and suspend the auto-hide task whenever any of these presentations is active:
  - Audio menu
  - Subtitles menu
  - More menu
  - Subtitle customization drawer
  - Info or InSight panel
  - Sources panel
  - Episodes sheet
  - 4K confirmation dialog
- Resume the auto-hide countdown only after no presentation remains active.
- Native menu presentation callbacks do not participate in `Equatable` identity, so playback progress cannot recreate an open menu.

## Live Subtitle Customization Drawer

- Replace the player-launched full-screen subtitle appearance sheet with an in-player trailing drawer.
- The drawer width is 34 percent of the landscape player, capped at 380 points. It respects safe-area insets and uses a scrollable Liquid Glass surface.
- Keep the movie or episode playing behind the drawer.
- Keep active subtitle text visible and constrain it to the unobstructed portion of the player while the drawer is open.
- Provide a clear close action with a minimum 44-by-44-point target.
- Settings launched outside the player continue using the existing full-screen Subtitle Appearance screen.

The drawer sections are:

1. Synchronization
2. Quick Presets
3. Font
4. Colors
5. Position
6. Advanced
7. Reset

All controls update playback immediately.

## Subtitle Synchronization

Use one session-scoped subtitle offset for both rendering paths:

- Embedded subtitles: apply the offset through MPV’s `sub-delay`.
- Downloaded subtitles: subtract the same offset from the playback position used by the app’s cue lookup.

The two user-facing synchronization methods are:

- **Use Track Timing:** reset the offset to zero and use the timing authored into the selected subtitle track.
- **Manual Offset:** adjust between -30 and +30 seconds in 0.1-second slider increments, with additional Earlier and Later buttons that move by 0.5 seconds.

The offset resets when playback is cleaned up or a different stream is launched because timing mismatches are release-specific. “Use Track Timing” does not claim to speech-analyze mismatched releases.

## iPhone Preset Sizing

Applying a preset on iPhone also applies an iPhone-appropriate base font size:

- Minimal: 20 points
- Boxed: 21 points
- Standard: 22 points
- Classic: 23 points

The existing scale control remains available. Applying the same presets on iPad uses 26, 27, 28, and 29 points respectively. The Settings screen selects the preset size for the current device idiom.

## Accessibility and Motion

- Every trigger, close action, and timing step action has an accessible name and at least a 44-by-44-point target.
- The drawer enters and exits with a short movement-and-opacity transition.
- Reduced Motion uses opacity without spatial movement.
- Native menus remain native and preserve VoiceOver menu semantics.

## Verification

- Unit test canonical grouping and popularity ordering, including unknown languages last.
- Unit test subtitle offset clamping, zero-reset behavior, and preset sizing.
- Verify that the same offset changes embedded and downloaded subtitle timing.
- Verify that playback progress updates do not change native-menu identity.
- Verify auto-hide remains suspended for each menu and panel and resumes after dismissal.
- Build and install on the connected iPhone.
- On-device checks:
  - Audio/Subtitles buttons match adjacent glass controls.
  - Native menus remain open without flicker.
  - Customize Subtitles is the first subtitle-menu item.
  - Languages appear in popularity order and Off appears last.
  - The drawer leaves the playing video and subtitle preview visible.
  - Presets produce readable iPhone subtitle sizes.
  - Track Timing and Manual Offset update active subtitles immediately.
