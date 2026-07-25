# Fusion-style hero: textless poster ladder + selectable hero catalog

Date: 2026-07-17
Branch: windows-desktop-phase-1

## Background

Investigating how Fusion (`Fusion 1.2026.188.ipa`) builds its hero revealed:
- The IPA is FairPlay-encrypted, so no source; but linked frameworks are readable.
- **Fusion links no Vision/CoreML** — it does *not* do saliency/face focal cropping.
- Its "subject-centered" look comes from using **raw (textless) portrait posters**, which
  are naturally subject-centered, chosen by `vote_average`.
- `home.hero.query` is a user setting whose values are catalog queries
  (`trending.day`, `trending.week`, `popularity.desc`).

An earlier design in this session (landscape backdrops + Vision focal crop) was therefore
based on a wrong premise and is **abandoned**.

## Problems to solve

1. **Logo'd hero images.** `HeroArtworkProvider` requests only `include_image_language=null`
   at a single hardcoded `w780`. When TMDB has no textless poster it returns `nil`, and
   `ParallaxHero` falls back to `item.artworkURL(preferring: .portrait)` — the addon poster,
   which frequently has title text baked in.
2. **Hero catalog is not user-selectable.** `featuredItems` auto-blends enabled catalog rows.
   Fusion exposes a single configurable catalog (`home.hero.query`).

## Design

### Part A — Image selection (HeroArtworkProvider + CachedAsyncImage)

- Selection unchanged: highest `vote_average` among `include_image_language=null` TMDB
  **posters** (raw/textless). No backdrop fallback (backdrops are landscape; wrong for a
  portrait hero).
- Provider stores the chosen `file_path` per id, and exposes an ordered **candidate URL
  ladder** `[w780, w500, w342]` (valid TMDB portrait sizes, descending).
- New `LadderedCachedImage` (added to `CachedAsyncImage.swift`, no new file) tries each
  candidate in order, stepping down on load failure. Network/cache logic is shared with
  `CachedAsyncImage` via an extracted `CachedImageLoader.load(_:)`.
- Addon poster remains the **last resort** only when TMDB has zero textless posters.
- `heroArtURL(for:)` keeps returning a single URL (first candidate) for existing
  ambient/color-engine callers in `HomeScreen`.

### Part B — Selectable hero catalog (HeroPreferenceStore + HomeScreen + HeroManagementScreen)

- `HeroPreferenceStore` gains persisted `heroCatalogId: String?` (`nil` = default).
  Optional Codable field → backward-compatible decode of existing stored prefs.
- `HeroCatalogSelector` (pure, in MoonlitCore, unit-tested) resolves which `CatalogRow`s
  feed the hero:
  - `heroCatalogId` set and present → `[that row]`.
  - else default (Fusion trending): the available rows among
    `[Trending Movies, Trending TV Shows]`, else `[Popular Movies, Popular TV Shows]`.
  - else fallback → existing behavior (named rows, then any rows with items).
- `HomeScreen.featuredItems` calls the resolver, then keeps its existing cap/interleave/
  category-filter/dedup loop. `perRowCap` becomes `totalCap` when a single row is selected
  so an override catalog can fill the carousel.
- `HeroManagementScreen` gains a top "Hero Source" picker: "Default (Trending)" + each
  available catalog; selection writes `heroCatalogId`. The existing drag-to-reorder/enable
  section is demoted to a fallback (kept, not removed).

## Testing

- MoonlitCore `swift test`: `HeroCatalogSelector` (override, trending default, popular
  fallback, empty fallback) and TMDB candidate-URL builder.
- `xcodebuild -scheme MoonlitApp -destination 'generic/platform=iOS Simulator' -configuration Debug build`.
- Simulator run: confirm hero shows textless posters and the Hero Source picker switches
  the carousel source.

## Out of scope

Vision/CoreML, landscape backdrops, focal cropping, RPDB image sources.
