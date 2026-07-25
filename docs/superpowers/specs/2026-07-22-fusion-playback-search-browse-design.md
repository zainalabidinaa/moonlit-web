# Fusion Playback, Search, and Browse Design

## Goal

Bring three Moonlit interactions into a consistent Fusion-inspired visual language: a compact playback-empty alert, a dedicated modal search experience, and a leading Browse menu that replaces the Home category pills.

## Playback empty alert

When automatic playback completes with no playable source, `StreamSelectionScreen` keeps the title artwork and detail context visible. It overlays a compact centered glass alert containing the episode context (when present) and exactly `No results found.`

The alert is deliberately non-actionable. It is used for both an account with no compatible stream-capable manifest and an account whose formerly available manifest was removed or yields no streams. The stream layer must expose an explicit empty terminal reason for testability, but the visual treatment remains identical.

Manual source selection remains unchanged: it continues to show its existing source picker and no-results message.

## Search modal

Moonlit's Search tab opens a full-height Fusion-style modal when the user activates Search. The existing discovery context is dimmed and blurred behind the modal. Before text entry, the modal shows the title `Search`, a centered magnifier and `Type to search…`, a bottom-anchored search field, and recent searches when available.

Focusing the search field keeps it positioned above the keyboard and reveals a circular close button. Typing clears the empty presentation and recent-search affordance, then runs the current debounced concurrent TMDB/add-on lookup. Results retain the existing Movies, TV Shows, and People navigation behavior. Closing clears the transient query/results and restores the pre-modal state.

## Browse menu

`HomeScreen` replaces `CategoryPillsRow` with a leading toolbar Browse control. The existing profile avatar remains trailing. On iOS 26, the menu adopts the project’s native Liquid Glass treatment; on earlier supported iOS versions it uses the existing glass/material fallback.

The menu contains `Featured`, `Movies`, `Shows`, `Movie categories`, and `Show categories`. Selecting Featured, Movies, or Shows updates the existing `HomeCategoryState`. Selecting a categories destination opens the existing genre hub for its media type. The menu has no new persistence: each Home session starts from the existing category state.

## Constraints

- Do not change playback, TMDB, or add-on network behavior.
- Preserve current deep links to detail, actor, and genre screens.
- Use `Button` for all interactive controls and dedicated accessibility labels.
- Use `#available` with a visual fallback for iOS 26-only Liquid Glass APIs.
- Keep the compact alert copy exactly `No results found.`

## Verification

- Unit-test stream empty-reason classification for no compatible addon and no results from eligible addons.
- Add UI/snapshot coverage for the compact playback alert, search modal resting/focused states, and leading Browse menu placement.
- Build and run the iOS target; verify the three flows on the configured Revyl cloud device.
