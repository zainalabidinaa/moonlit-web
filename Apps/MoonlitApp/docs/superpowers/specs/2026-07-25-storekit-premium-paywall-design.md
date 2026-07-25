# StoreKit premium subscriptions + cinematic paywall

## Goal

Sell Moonlit Premium/Premium+ through Apple in-app purchase subscriptions, and gate premium features (starting with playback) behind a paywall instead of the current dead-end "streaming isn't available on this account" alert.

## Compliance context (important, do not skip)

Moonlit currently runs the **reader-app model** (App Store guideline 3.1.3a): it honors externally-granted entitlement but shows no upgrade/buy UI, because that's the tradeoff for skipping Apple's IAP requirement. This project is a deliberate, informed **exit** from that model.

Guideline **3.1.1 (In-App Purchase)** requires that unlocking in-app features/content go through IAP — a real StoreKit paywall is the standard, compliant path, not a workaround. [[moonlit-appstore-survival-model]] should be updated once this ships to record that reader-app mode no longer applies.

One survival-model risk carries forward: Moonlit was built as a Stremio-style addon client, and rights-holder complaints (not App Review) are what killed Stremio/Nuvio. The paywall must never *look like* it's selling access to specific copyrighted titles:
- Paywall copy stays generic ("unlock premium playback / your library"), never implies "buy access to these movies."
- The poster marquee (see below) uses the user's own library or a release calendar, never a general browse-everything catalog — see the marquee section for why this framing is what keeps it safe.

## Scope

**In scope for this spec / this build:**
- StoreKit subscription products (via RevenueCat) for two tiers, gating playback + curated catalogs + watch history (features that already exist in the app today, just ungated).
- The paywall UI/UX (cinematic marquee + offer).
- Entitlement sync back to Supabase `profiles.role` so all existing role-based UI keeps working unchanged.
- Admin/friends & family manual grants continue to work, untouched, free.

**Explicitly out of scope (separate future specs):**
- **Post-credit scene info** — does not exist anywhere in the app today. Needs its own design (data source, where it surfaces in the player UI).
- **Push notifications for new episodes / upcoming releases** — `UpcomingItemsService` tracks upcoming items in-app already, but there is no notification *delivery* mechanism (no `UNUserNotificationCenter` usage anywhere). Needs its own design (opt-in UX, APNs vs local notifications, scheduling).
- tvOS, Android, or any non-iOS platform.

**Self-review flag:** don't list post-credit info or notifications as Premium benefits in the paywall copy until they actually ship. Advertising features that don't exist yet on a purchase screen is a real risk (misleading marketing, potential refund/chargeback exposure, App Review can flag it) independent of the rights-holder concern above. The paywall's feature list should only include what's true at ship time; add lines for the other two features when their specs land and they're live.

## Tiers & products

Two paid tiers via App Store Connect subscription group "Moonlit Premium", each monthly + yearly:
- `premium_monthly` / `premium_yearly` → grants `role = premium`
- `premiumplus_monthly` / `premiumplus_yearly` → grants `role = premiumPlus` (adds `canManageOwnAddons`, unchanged from today)

Actual prices are set in App Store Connect at launch time, not hardcoded.

## Entitlement architecture

`profiles.role` in Supabase remains the single source of truth every existing UI gate already checks — this project does not introduce a second, parallel entitlement system.

**RevenueCat** is the purchase + sync layer:
- Client integrates `RevenueCat` SDK (`Purchases.configure`), with the Supabase user ID set as RevenueCat's `appUserID` — this makes the purchase-to-user mapping automatic, no custom linking table needed.
- A new Supabase edge function receives RevenueCat webhook events (`INITIAL_PURCHASE`, `RENEWAL`, `CANCELLATION`, `EXPIRATION`, `BILLING_ISSUE`) and updates `profiles.role` accordingly.
- **Guard against clobbering manual grants:** add `profiles.subscription_source` (`'storekit' | 'manual' | null`). The webhook only ever sets `role = free` on expiration/cancellation if `subscription_source = 'storekit'` — it must never downgrade a `friendsAndFamily`, `admin`, or manually-granted `premium`/`premiumPlus` row. On a StoreKit purchase, the webhook sets both `role` and `subscription_source = 'storekit'`.
- Client also checks `Purchases.shared.customerInfo` on launch/foreground as a fast local read (RevenueCat caches this) and can trigger a manual re-sync if it disagrees with Supabase, as a fallback to the webhook.

**F&F stays exactly as it works today** — admin manually sets `role = 'friends_and_family'` in Supabase directly, no purchase, no RevenueCat involvement, untouched by this project.

## Paywall UI

Reference implementation prototyped at `Sources/Screens/PaywallScreen.swift` (SwiftUI) — hands this design to RevenueCat's paywall builder as the visual spec, since the shipped paywall renders via `RevenueCatUI` templates (remotely configurable without app updates) rather than hand-maintained SwiftUI.

**Layers, back to front:**
1. `FusionAmbientBackground` ([HomeScreen.swift:812](../../Sources/Screens/HomeScreen.swift)) reused as-is — charcoal gradient base + animated mesh wash, tinted from the extracted colors of the title that triggered the paywall.
2. **Poster marquee**, top ~30% of screen: two rows of poster tiles, counter-scrolling continuously, tilted ~-9° and overscaled so rotation never exposes an edge, masked to fade in from transparent at the very top and dissolve to transparent at the bottom into the offer content.
   - **Content source, in priority order:** the user's own library (`LibraryRepository.shared.libraryItems`) if non-empty; otherwise upcoming/not-yet-released titles (new TMDB discover query, `primary_release_date.gte=today`, styled via the existing `PosterService.posterURL(forImdbId:)` btttr integration). Never a general "browse everything" catalog — see compliance note above for why. The upcoming-releases fallback doubles as a preview of the (future, separate-spec) notifications feature.
   - Driven by `TimelineView(.animation)`, not a repeating `Timer` — [ParallaxHero.swift:224](../../Sources/Components/ParallaxHero.swift) already documents that a repeating timer blocks the run loop under UI automation.
   - `.allowsHitTesting(false)`, honors Reduce Motion by freezing to a static offset.
3. Offer content: headline, tier cards (Premium / Premium+, selected tier highlighted with a white border), monthly/yearly period toggle, feature checklist, CTA, Restore Purchases + auto-renew disclosure (required by Apple on every paywall).

**Buttons/CTAs are white/light solid** (`#F5F5F4` on dark), not the app's orange brand accent — chosen over glass/blurred and orange after side-by-side comparison; reads as an unambiguous "premium" purchase control (Apple TV+/Netflix pattern) against the dark cinematic background. The orange accent survives only as ambient artwork glow (the mesh wash), not on any control.

**Feature list (ship-time only, see scope note above):** unlimited playback, curated catalogs, full watch history synced across devices. (Post-credit info and notifications get added once their specs ship.)

## Gating

Three existing call sites currently do raw string checks (`role == "free"`) and show a dead-end alert with no path forward:
- [DetailScreen.swift:1216](../../Sources/Screens/DetailScreen.swift)
- [HomeScreen.swift:481](../../Sources/Screens/HomeScreen.swift)
- [StreamSelectionScreen.swift:272](../../Sources/Screens/StreamSelectionScreen.swift)

These change to: check `profile.profileRole` (the existing `ProfileRole` enum, not raw strings) and present the RevenueCat paywall instead of the alert when access is denied.

**New gates** (currently ungated, need to be added): curated catalog rows and watch history access, gated the same way — check role, present paywall if free.

Catalog *browsing* beyond curated rows stays open to everyone (per earlier decision) — only curated catalogs specifically and watch history are premium-gated, not general browsing.

## Testing

- StoreKit sandbox testing via Xcode's `.storekit` configuration file for local purchase-flow testing without hitting real App Store Connect.
- Verify: purchase → role updates in Supabase within expected latency; cancellation → role reverts to free (only for `subscription_source = 'storekit'` rows); a manually-granted F&F/premium row survives a RevenueCat webhook for an unrelated event.
- Manual QA: empty-library account sees upcoming-releases marquee; populated-library account sees own posters; Reduce Motion freezes the marquee; VoiceOver reads the paywall sensibly.
