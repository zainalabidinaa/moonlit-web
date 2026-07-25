# StoreKit Premium Subscriptions + Cinematic Paywall Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sell Moonlit Premium/Premium+ through Apple in-app purchase subscriptions (via RevenueCat) and gate playback, curated catalogs, and watch history behind a cinematic paywall instead of today's dead-end alert.

**Architecture:** RevenueCat handles StoreKit purchase/restore and app-user-ID-to-receipt mapping; a Supabase edge function receives RevenueCat webhooks and writes `profiles.role`, which stays the single source of truth every existing gate already reads. A new `subscription_source` column stops StoreKit expirations from ever overwriting a manually-granted role (admin/friends & family).

**Tech Stack:** Swift 6 / SwiftUI, RevenueCat SDK (StoreKit 2 under the hood), Supabase (Postgres + Deno edge functions), XCTest / `swift test` for MoonlitCore.

**Spec:** [2026-07-25-storekit-premium-paywall-design.md](../specs/2026-07-25-storekit-premium-paywall-design.md)

---

## Prerequisites (manual, external — not scriptable)

Do these before Task 5 (PurchaseService) needs a real API key, and before Task 3 (webhook) needs a real webhook secret. They don't have tasks below because there's no code to TDD — they're dashboard clicks.

- [ ] App Store Connect: create subscription group "Moonlit Premium" with 4 auto-renewable subscription products — `premium_monthly`, `premium_yearly`, `premiumplus_monthly`, `premiumplus_yearly`.
- [ ] RevenueCat: create a project, connect the App Store Connect app, create two entitlements named exactly `premium` and `premium_plus`, attach the matching products to each. Copy the public (client) API key.
- [ ] RevenueCat: under Integrations → Webhooks, add a webhook pointing at the edge function URL from Task 3 (`https://<project>.supabase.co/functions/v1/revenuecat-webhook`) once it's deployed, with a shared secret — save that secret for Task 3's `REVENUECAT_WEBHOOK_SECRET` env var.
- [ ] Xcode: File → Add Package Dependencies → `https://github.com/RevenueCat/purchases-ios`, add both **RevenueCat** and **RevenueCatUI** libraries to the `MoonlitApp` target (SPM packages don't need the manual `project.pbxproj` file-registration steps that plain `.swift` files do — only new source files need that).
- [ ] Add `REVENUECAT_API_KEY` to `Sources/Info.plist` (string value, the public key copied above).

---

## File Structure

**Create:**
- `Packages/MoonlitCore/Sources/MoonlitCore/Services/EntitlementMapper.swift` — pure, SDK-independent mapping from a set of active entitlement identifiers to a `ProfileRole`. Kept separate from `PurchaseService` specifically so it's testable without mocking RevenueCat's `CustomerInfo` type.
- `Packages/MoonlitCore/Tests/MoonlitCoreTests/EntitlementMapperTests.swift`
- `Packages/MoonlitCore/Sources/MoonlitCore/Services/PurchaseService.swift` — thin RevenueCat SDK wrapper (configure, fetch offerings, purchase, restore).
- `Packages/MoonlitCore/Sources/MoonlitCore/Services/UpcomingReleasesQuery.swift` — pure TMDB discover query-parameter builder for "not yet released" titles, extracted so it's testable without a network call.
- `Packages/MoonlitCore/Tests/MoonlitCoreTests/UpcomingReleasesQueryTests.swift`
- `supabase/migrations/20260725_profiles_subscription_source.sql`
- `supabase/functions/revenuecat-webhook/index.ts`

**Modify:**
- `Packages/MoonlitCore/Sources/MoonlitCore/Models/ProfileModels.swift` — add `ProfileRole.hasPremiumAccess`.
- `Packages/MoonlitCore/Sources/MoonlitCore/Services/TMDBDiscoverService.swift` — add `discoverUpcoming(mediaKind:)` using `UpcomingReleasesQuery`.
- `Sources/Screens/DetailScreen.swift`, `Sources/Screens/HomeScreen.swift`, `Sources/Screens/StreamSelectionScreen.swift` — swap raw `role == "free"` checks for `profile.profileRole.hasPremiumAccess`, present `PaywallScreen` instead of the dead-end alert.
- `Sources/Screens/HomeScreen.swift` — add gates on curated catalog rows and watch history access.
- `Sources/Screens/PaywallScreen.swift` — replace prototype placeholder data with real library/upcoming posters and a real `PurchaseService` call.
- `Sources/MoonlitApp.swift` — configure RevenueCat on launch; remove the throwaway `PAYWALL_PREVIEW` scaffold.

---

## Task 1: `ProfileRole.hasPremiumAccess`

**Files:**
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Models/ProfileModels.swift`
- Test: `Packages/MoonlitCore/Tests/MoonlitCoreTests/ProfileRoleTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MoonlitCore

final class ProfileRoleTests: XCTestCase {
    func testHasPremiumAccess() {
        XCTAssertTrue(ProfileRole.admin.hasPremiumAccess)
        XCTAssertTrue(ProfileRole.friendsAndFamily.hasPremiumAccess)
        XCTAssertTrue(ProfileRole.premium.hasPremiumAccess)
        XCTAssertTrue(ProfileRole.premiumPlus.hasPremiumAccess)
        XCTAssertFalse(ProfileRole.free.hasPremiumAccess)
        XCTAssertFalse(ProfileRole.user.hasPremiumAccess)
        XCTAssertFalse(ProfileRole.restricted.hasPremiumAccess)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/MoonlitCore && swift test --filter ProfileRoleTests`
Expected: FAIL — `value of type 'ProfileRole' has no member 'hasPremiumAccess'`

- [ ] **Step 3: Implement**

In `ProfileModels.swift`, inside `enum ProfileRole`, next to the existing `canBrowse`/`canManageOwnAddons` computed properties, add:

```swift
    /// True for any role that should see premium features (playback beyond the
    /// free tier, curated catalogs, watch history) unlocked — whether granted by
    /// a StoreKit purchase or manually by an admin.
    public var hasPremiumAccess: Bool {
        switch self {
        case .admin, .friendsAndFamily, .premium, .premiumPlus: return true
        case .free, .restricted, .user: return false
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Packages/MoonlitCore && swift test --filter ProfileRoleTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/MoonlitCore/Sources/MoonlitCore/Models/ProfileModels.swift Packages/MoonlitCore/Tests/MoonlitCoreTests/ProfileRoleTests.swift
git commit -m "feat: add ProfileRole.hasPremiumAccess gating helper"
```

---

## Task 2: `EntitlementMapper` (SDK-independent role mapping)

**Files:**
- Create: `Packages/MoonlitCore/Sources/MoonlitCore/Services/EntitlementMapper.swift`
- Test: `Packages/MoonlitCore/Tests/MoonlitCoreTests/EntitlementMapperTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MoonlitCore

final class EntitlementMapperTests: XCTestCase {
    func testPremiumPlusTakesPriorityOverPremium() {
        let active = ActiveEntitlements(identifiers: ["premium", "premium_plus"])
        XCTAssertEqual(EntitlementMapper.role(for: active), .premiumPlus)
    }

    func testPremiumOnly() {
        let active = ActiveEntitlements(identifiers: ["premium"])
        XCTAssertEqual(EntitlementMapper.role(for: active), .premium)
    }

    func testNoRecognizedEntitlementReturnsNil() {
        let active = ActiveEntitlements(identifiers: [])
        XCTAssertNil(EntitlementMapper.role(for: active))
    }

    func testUnrelatedEntitlementIsIgnored() {
        let active = ActiveEntitlements(identifiers: ["some_other_addon"])
        XCTAssertNil(EntitlementMapper.role(for: active))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/MoonlitCore && swift test --filter EntitlementMapperTests`
Expected: FAIL — `cannot find 'ActiveEntitlements' in scope`

- [ ] **Step 3: Implement**

```swift
import Foundation

/// A snapshot of which RevenueCat entitlement identifiers are currently active
/// for a user. Deliberately not RevenueCat's own `CustomerInfo` type, so this
/// mapping is testable without mocking the SDK, and `PurchaseService` is the
/// only file that has to know how to build one.
public struct ActiveEntitlements: Sendable, Equatable {
    public let identifiers: Set<String>
    public init(identifiers: Set<String>) { self.identifiers = identifiers }
}

public enum EntitlementMapper {
    public static let premiumEntitlementID = "premium"
    public static let premiumPlusEntitlementID = "premium_plus"

    /// `nil` means no recognized StoreKit entitlement is active. Callers MUST
    /// NOT treat `nil` as "downgrade to free" unconditionally — a `nil` here
    /// could just mean the user was never a StoreKit subscriber (e.g. an
    /// admin-granted friends & family row), which must not be touched.
    public static func role(for active: ActiveEntitlements) -> ProfileRole? {
        if active.identifiers.contains(premiumPlusEntitlementID) { return .premiumPlus }
        if active.identifiers.contains(premiumEntitlementID) { return .premium }
        return nil
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Packages/MoonlitCore && swift test --filter EntitlementMapperTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/MoonlitCore/Sources/MoonlitCore/Services/EntitlementMapper.swift Packages/MoonlitCore/Tests/MoonlitCoreTests/EntitlementMapperTests.swift
git commit -m "feat: add SDK-independent entitlement-to-role mapping"
```

---

## Task 3: Supabase migration + RevenueCat webhook edge function

**Files:**
- Create: `supabase/migrations/20260725_profiles_subscription_source.sql`
- Create: `supabase/functions/revenuecat-webhook/index.ts`

No XCTest applies here (Deno edge function, no test harness exists yet in `supabase/functions` — verification is manual `curl`, matching how `delete-user`/`catalog-proxy` are verified in this repo).

- [ ] **Step 1: Write the migration**

```sql
-- Tracks whether a profile's premium role came from a StoreKit purchase (via
-- RevenueCat) or was granted manually (admin / friends & family). The
-- RevenueCat webhook must only ever revert `role` to 'free' on expiration when
-- subscription_source = 'storekit' — otherwise an expiring/cancelled StoreKit
-- event could clobber a manually-granted role for the same user.
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS subscription_source text
    CHECK (subscription_source IN ('storekit', 'manual') OR subscription_source IS NULL);
```

- [ ] **Step 2: Apply it**

Run: `supabase db push` (or paste into the Supabase dashboard SQL editor for the project).
Expected: `profiles.subscription_source` column exists, nullable, no default.

- [ ] **Step 3: Write the webhook edge function**

```typescript
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// RevenueCat webhook event shapes: https://www.revenuecat.com/docs/webhooks
// Expiration/cancellation events must only revert a row that this webhook
// itself set to 'storekit' — never an admin/manual grant for the same user.
const EXPIRY_EVENT_TYPES = new Set(["EXPIRATION", "CANCELLATION"]);
const PREMIUM_ENTITLEMENT = "premium";
const PREMIUM_PLUS_ENTITLEMENT = "premium_plus";

Deno.serve(async (req) => {
    const authHeader = req.headers.get("Authorization");
    const expected = `Bearer ${Deno.env.get("REVENUECAT_WEBHOOK_SECRET")}`;
    if (authHeader !== expected) {
        return new Response("Unauthorized", { status: 401 });
    }

    const body = await req.json();
    const event = body.event;
    const appUserId: string | undefined = event?.app_user_id;
    const type: string | undefined = event?.type;
    const entitlementIds: string[] = event?.entitlement_ids ?? [];

    if (!appUserId || !type) {
        return new Response("Malformed event", { status: 400 });
    }

    const adminClient = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    if (EXPIRY_EVENT_TYPES.has(type)) {
        const { error } = await adminClient
            .from("profiles")
            .update({ role: "free", subscription_source: null })
            .eq("user_id", appUserId)
            .eq("subscription_source", "storekit");
        if (error) return new Response(error.message, { status: 500 });
        return new Response("ok", { status: 200 });
    }

    const role = entitlementIds.includes(PREMIUM_PLUS_ENTITLEMENT)
        ? "premium_plus"
        : entitlementIds.includes(PREMIUM_ENTITLEMENT)
        ? "premium"
        : null;

    if (!role) {
        // Event doesn't carry a recognized entitlement (e.g. an unrelated
        // product). Nothing to do — not an error.
        return new Response("ok: no recognized entitlement", { status: 200 });
    }

    const { error } = await adminClient
        .from("profiles")
        .update({ role, subscription_source: "storekit" })
        .eq("user_id", appUserId);
    if (error) return new Response(error.message, { status: 500 });
    return new Response("ok", { status: 200 });
});
```

- [ ] **Step 4: Deploy and set secrets**

```bash
supabase functions deploy revenuecat-webhook
supabase secrets set REVENUECAT_WEBHOOK_SECRET=<the secret you set in RevenueCat's webhook config>
```

- [ ] **Step 5: Verify manually**

```bash
curl -X POST "https://<project>.supabase.co/functions/v1/revenuecat-webhook" \
  -H "Authorization: Bearer <REVENUECAT_WEBHOOK_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{"event":{"type":"INITIAL_PURCHASE","app_user_id":"<a real test user_id>","entitlement_ids":["premium"]}}'
```

Expected: `ok` (200), and that user's `profiles.role` becomes `premium`, `subscription_source` becomes `storekit`. Then re-run with `"type":"EXPIRATION"` and confirm `role` reverts to `free` — and confirm a row with `subscription_source = 'manual'` (e.g. an admin-set friends & family row) is untouched by the same expiration call.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260725_profiles_subscription_source.sql supabase/functions/revenuecat-webhook/index.ts
git commit -m "feat: add RevenueCat webhook edge function + subscription_source column"
```

---

## Task 4: Upcoming-releases query (empty-library paywall fallback)

**Files:**
- Create: `Packages/MoonlitCore/Sources/MoonlitCore/Services/UpcomingReleasesQuery.swift`
- Test: `Packages/MoonlitCore/Tests/MoonlitCoreTests/UpcomingReleasesQueryTests.swift`
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Services/TMDBDiscoverService.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MoonlitCore

final class UpcomingReleasesQueryTests: XCTestCase {
    func testMovieParametersSortByNearestUpcomingReleaseFirst() {
        let params = UpcomingReleasesQuery.parameters(mediaKind: .movie, today: "2026-07-25")
        XCTAssertEqual(params["sort_by"], "primary_release_date.asc")
        XCTAssertEqual(params["primary_release_date.gte"], "2026-07-25")
        XCTAssertEqual(params["vote_count.gte"], "5")
    }

    func testTVUsesFirstAirDateField() {
        let params = UpcomingReleasesQuery.parameters(mediaKind: .tv, today: "2026-07-25")
        XCTAssertEqual(params["sort_by"], "first_air_date.asc")
        XCTAssertEqual(params["first_air_date.gte"], "2026-07-25")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/MoonlitCore && swift test --filter UpcomingReleasesQueryTests`
Expected: FAIL — `cannot find 'UpcomingReleasesQuery' in scope`

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Builds TMDB `/discover` query parameters for titles that have not been
/// released yet — used as the paywall marquee's fallback content when a user
/// has an empty library. Kept as a pure function (no networking) so the
/// query-building logic is unit-testable without hitting TMDB.
public enum UpcomingReleasesQuery {
    public static func parameters(mediaKind: MediaType, today: String) -> [String: String] {
        let dateField = mediaKind == .movie ? "primary_release_date" : "first_air_date"
        return [
            "sort_by": "\(dateField).asc",
            "\(dateField).gte": today,
            "vote_count.gte": "5",
        ]
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Packages/MoonlitCore && swift test --filter UpcomingReleasesQueryTests`
Expected: PASS

- [ ] **Step 5: Wire it into `TMDBDiscoverService`**

In `TMDBDiscoverService.swift`, add a method alongside the existing `discoverGeneral`/`discoverByYear` (mirror their existing request-building/response-parsing pattern in that file — same base URL, API key, and `GenreCatalog.LoadedBrowseRail`/`MetaPreview` mapping already used by `discoverGeneral`):

```swift
    /// Titles not yet released, soonest first — used as the paywall marquee's
    /// fallback when the viewing user has no library items yet.
    public func discoverUpcoming(mediaKind: MediaType, limit: Int = 20) async -> [MetaPreview] {
        let params = UpcomingReleasesQuery.parameters(mediaKind: mediaKind, today: Self.today)
        return await fetchDiscoverPage(mediaKind: mediaKind, extraParams: params, limit: limit)
    }
```

(If `TMDBDiscoverService` doesn't already have a shared `fetchDiscoverPage`-style helper that takes arbitrary extra params, add one by extracting the common request/response logic already duplicated across `discoverByYear`/`discoverGeneral` — don't duplicate a third copy.)

- [ ] **Step 6: Build-verify**

Run: `xcodebuild -scheme MoonlitApp -destination 'generic/platform=iOS Simulator' -configuration Debug build` from `Apps/MoonlitApp`.
Expected: `** BUILD SUCCEEDED **`. (Per [[moonlit-build-verify-commands]] — reuse the warm default DerivedData, don't pass a fresh `-derivedDataPath`.)

- [ ] **Step 7: Commit**

```bash
git add Packages/MoonlitCore/Sources/MoonlitCore/Services/UpcomingReleasesQuery.swift Packages/MoonlitCore/Tests/MoonlitCoreTests/UpcomingReleasesQueryTests.swift Packages/MoonlitCore/Sources/MoonlitCore/Services/TMDBDiscoverService.swift
git commit -m "feat: add upcoming-releases discover query for paywall fallback"
```

---

## Task 5: `PurchaseService` (RevenueCat SDK wrapper)

**Files:**
- Create: `Packages/MoonlitCore/Sources/MoonlitCore/Services/PurchaseService.swift`

Requires the RevenueCat SPM package from Prerequisites. No new XCTest here — this file is a thin adapter over the SDK; its only non-trivial logic (`EntitlementMapper`) is already tested in Task 2. Verification is build + manual sandbox purchase in Task 8.

- [ ] **Step 1: Implement**

```swift
import Foundation
import RevenueCat

@MainActor
public final class PurchaseService: ObservableObject {
    public static let shared = PurchaseService()

    @Published public private(set) var offerings: Offerings?
    /// Non-nil only while a StoreKit entitlement is active for this user —
    /// callers must combine this with the user's existing `profile.role` for
    /// the full picture, not use it as the sole source of truth (a manually
    /// granted role won't show up here).
    @Published public private(set) var storeKitRole: ProfileRole?

    private init() {}

    public func configure(apiKey: String, appUserID: String) {
        Purchases.configure(withAPIKey: apiKey, appUserID: appUserID)
        Task { await refreshEntitlements() }
    }

    public func refreshEntitlements() async {
        guard let info = try? await Purchases.shared.customerInfo() else { return }
        storeKitRole = Self.role(from: info)
    }

    public func loadOfferings() async {
        offerings = try? await Purchases.shared.offerings()
    }

    @discardableResult
    public func purchase(_ package: Package) async throws -> ProfileRole? {
        let result = try await Purchases.shared.purchase(package: package)
        let role = Self.role(from: result.customerInfo)
        storeKitRole = role
        return role
    }

    @discardableResult
    public func restorePurchases() async throws -> ProfileRole? {
        let info = try await Purchases.shared.restorePurchases()
        let role = Self.role(from: info)
        storeKitRole = role
        return role
    }

    private static func role(from customerInfo: CustomerInfo) -> ProfileRole? {
        let active = ActiveEntitlements(identifiers: Set(customerInfo.entitlements.active.keys))
        return EntitlementMapper.role(for: active)
    }
}
```

- [ ] **Step 2: Build-verify**

Run: `xcodebuild -scheme MoonlitApp -destination 'generic/platform=iOS Simulator' -configuration Debug build` from `Apps/MoonlitApp`.
Expected: `** BUILD SUCCEEDED **`. If it fails with "no such module RevenueCat", the Prerequisites SPM step wasn't completed — go add the package in Xcode first.

- [ ] **Step 3: Commit**

```bash
git add Packages/MoonlitCore/Sources/MoonlitCore/Services/PurchaseService.swift
git commit -m "feat: add PurchaseService wrapping RevenueCat purchase/restore"
```

---

## Task 6: Wire `PurchaseService` into app launch

**Files:**
- Modify: `Sources/MoonlitApp.swift`
- Modify: `Sources/Info.plist` (already has the key from Prerequisites)

- [ ] **Step 1: Configure RevenueCat on launch and pass the Supabase user ID as `appUserID`**

In `MoonlitApp.swift`, inside `init()` after `PosterService.registerDefaults()`:

```swift
        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String,
           !apiKey.isEmpty,
           let userId = ProfileManager.shared.currentUserId {
            PurchaseService.shared.configure(apiKey: apiKey, appUserID: userId)
        }
```

(If `ProfileManager` doesn't yet expose a synchronous `currentUserId` at this point in launch — check `Services/ProfileManager.swift` — move this call to wherever the app first has a confirmed authenticated user, e.g. right after sign-in completes, rather than forcing one into `init()`. The requirement is just: configure RevenueCat exactly once, as soon as a Supabase user ID is known, so purchases link to the right account from the start.)

- [ ] **Step 2: Build-verify**

Run: `xcodebuild -scheme MoonlitApp -destination 'generic/platform=iOS Simulator' -configuration Debug build` from `Apps/MoonlitApp`.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Sources/MoonlitApp.swift
git commit -m "feat: configure RevenueCat on launch with the Supabase user ID"
```

---

## Task 7: Gate playback at the three existing call sites

**Files:**
- Modify: `Sources/Screens/DetailScreen.swift:1216,1263,1267-1270` (alert at line 493)
- Modify: `Sources/Screens/HomeScreen.swift:160,481,621-624` (alert at line 449)
- Modify: `Sources/Screens/StreamSelectionScreen.swift:272-275` (alert at line 104)

- [ ] **Step 1: Replace the raw string check + dead-end alert in `DetailScreen.swift`**

Find the guest/free-role block around line 1216 that currently sets `showGuestStreamingAlert = true` on `role == "free"`. Replace the condition with the enum check and present the paywall instead:

```swift
        guard profile.profileRole.hasPremiumAccess else {
            showPaywall = true
            return
        }
```

Add the corresponding state and sheet presentation near where `showGuestStreamingAlert` is declared:

```swift
    @State private var showPaywall = false
```

And where the old alert (`.alert("Streaming unavailable", ...)` around line 493) was shown, replace it with:

```swift
    .sheet(isPresented: $showPaywall) {
        PaywallScreen(
            ambientColor: heroAmbientColor,
            ambientColor2: heroAmbientColor2,
            onClose: { showPaywall = false }
        )
    }
```

Use whatever the file's existing hero-color state variables are named (the hero already extracts ambient colors for `FusionAmbientBackground` — reuse those, don't re-extract).

- [ ] **Step 2: Repeat the same swap in `HomeScreen.swift`**

Replace the `role == "free"` check around line 481/621-624 with `profile.profileRole.hasPremiumAccess`, replace `showFreeUpgradeAlert`'s alert (around line 449) with the same `.sheet` pattern as Step 1. `HomeScreen` doesn't have a single "current hero" ambient color the way `DetailScreen` does — pass the tapped item's own extracted colors if available, otherwise fall back to `PaywallScreen`'s default parameter values (already defined in the prototype).

- [ ] **Step 3: Repeat in `StreamSelectionScreen.swift`**

Same swap for the `role == "free"` check around line 272-275 and the `upgradeAlert` (line 104) → `PaywallScreen` sheet.

- [ ] **Step 4: Build-verify**

Run: `xcodebuild -scheme MoonlitApp -destination 'generic/platform=iOS Simulator' -configuration Debug build` from `Apps/MoonlitApp`.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual QA on simulator**

Using the iOS Simulator MCP: attach, launch the app signed in as a free-role test account, tap play on any title, confirm the paywall sheet appears instead of an alert. Screenshot it.

- [ ] **Step 6: Commit**

```bash
git add Sources/Screens/DetailScreen.swift Sources/Screens/HomeScreen.swift Sources/Screens/StreamSelectionScreen.swift
git commit -m "feat: replace dead-end free-tier alerts with the premium paywall"
```

---

## Task 8: Gate curated catalogs and watch history

**Files:**
- Modify: `Sources/Screens/HomeScreen.swift` (curated catalog rows — find where `loadFreeUserCatalogs` currently branches; per the design spec, general browsing stays open, only the *curated* rows gate)
- Modify: `Sources/Screens/LibraryScreen.swift` (watch history section)

- [ ] **Step 1: Gate curated catalog rows in `HomeScreen.swift`**

Wherever curated catalog rows are rendered (distinct from general browse/search, which stays open per spec), wrap the row's tap-through or the row's data load with the same `profile.profileRole.hasPremiumAccess` check used in Task 7, presenting `PaywallScreen` on a blocked tap rather than silently loading nothing.

- [ ] **Step 2: Gate watch history in `LibraryScreen.swift`**

At the watch-history section's entry point (wherever `WatchProgressRepository.shared` results get rendered), add the same check: if `!profile.profileRole.hasPremiumAccess`, show a compact locked-state row (reuse whatever empty-state pattern `LibraryScreen` already uses elsewhere in the file) that opens `PaywallScreen` on tap, instead of the real history list.

- [ ] **Step 3: Build-verify**

Run: `xcodebuild -scheme MoonlitApp -destination 'generic/platform=iOS Simulator' -configuration Debug build` from `Apps/MoonlitApp`.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual QA**

On the simulator, confirm a free-role account sees the locked state for curated catalogs and watch history, and a premium-role account (temporarily set `role = 'premium'` for the test user directly in Supabase) sees them unlocked.

- [ ] **Step 5: Commit**

```bash
git add Sources/Screens/HomeScreen.swift Sources/Screens/LibraryScreen.swift
git commit -m "feat: gate curated catalogs and watch history behind premium"
```

---

## Task 9: Finalize `PaywallScreen` with real data and a real purchase flow

**Files:**
- Modify: `Sources/Screens/PaywallScreen.swift`
- Modify: `Sources/MoonlitApp.swift` (remove the `PAYWALL_PREVIEW` prototype scaffold)

- [ ] **Step 1: Replace the placeholder `posterURLs` default with real data**

Remove the `var posterURLs: [URL] = []` default-empty-array pattern's caller-side placeholder and add a loader that implements the priority order from the spec (library first, upcoming releases as fallback):

```swift
    static func marqueePosterURLs(libraryItems: [LibraryItem], upcoming: [MetaPreview]) -> [URL] {
        let libraryURLs = libraryItems.compactMap { $0.poster }.compactMap(URL.init(string:))
        if !libraryURLs.isEmpty { return libraryURLs }
        return upcoming.compactMap { $0.poster }.compactMap(URL.init(string:))
    }
```

Call this from wherever `PaywallScreen` is instantiated (the three call sites from Task 7 plus the two from Task 8): fetch `LibraryRepository.shared.libraryItems` (already loaded by the time a paywall can be triggered, since it requires an authenticated profile) and, only if that's empty, call the new `TMDBDiscoverService.discoverUpcoming(mediaKind:)` from Task 4.

- [ ] **Step 2: Wire the "Continue" button to `PurchaseService`**

Replace the empty `Button(action: {})` for Continue with a real purchase call using the selected `tier`/`period` state already tracked in the view:

```swift
    private func purchaseSelectedPackage() async {
        await PurchaseService.shared.loadOfferings()
        guard let package = PurchaseService.shared.offerings?.current?.package(
            identifier: productIdentifier(for: selectedTier, period: selectedPeriod)
        ) else { return }
        do {
            _ = try await PurchaseService.shared.purchase(package)
            onClose()
        } catch {
            // Purchase was cancelled or failed — RevenueCat's error already
            // surfaces a system alert for StoreKit-level failures; nothing
            // else to show here.
        }
    }

    private func productIdentifier(for tier: Tier, period: Period) -> String {
        switch (tier, period) {
        case (.premium, .monthly): return "premium_monthly"
        case (.premium, .yearly): return "premium_yearly"
        case (.premiumPlus, .monthly): return "premiumplus_monthly"
        case (.premiumPlus, .yearly): return "premiumplus_yearly"
        }
    }
```

Wire "Restore purchases" to `try? await PurchaseService.shared.restorePurchases()` the same way.

- [ ] **Step 3: Remove the prototype launch-flag scaffold**

In `MoonlitApp.swift`, delete the `if ProcessInfo.processInfo.arguments.contains("PAYWALL_PREVIEW")` branch added during design exploration — `PaywallScreen` is now reachable through the real gates from Tasks 7-8, so the standalone launch flag is no longer needed.

- [ ] **Step 4: Build-verify**

Run: `xcodebuild -scheme MoonlitApp -destination 'generic/platform=iOS Simulator' -configuration Debug build` from `Apps/MoonlitApp`.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual QA with StoreKit sandbox**

In Xcode, add a local `.storekit` configuration file (Product Configuration Testing) mirroring the 4 real products so purchases can be tested without hitting live App Store Connect. Run on the simulator, trigger the paywall, complete a sandbox purchase, confirm `profiles.role` updates via the webhook (Task 3) within a few seconds.

- [ ] **Step 6: Commit**

```bash
git add Sources/Screens/PaywallScreen.swift Sources/MoonlitApp.swift
git commit -m "feat: wire paywall to real posters and RevenueCat purchase flow"
```

---

## Self-Review Notes

- **Spec coverage:** tiers/products (Task 5/9 product IDs), entitlement architecture + `subscription_source` guard (Tasks 2-3), paywall UI reuse of `FusionAmbientBackground` (already built in the design phase, wired for real in Task 9), gating scope — playback (Task 7), curated catalogs + watch history (Task 8) — all covered. Post-credit info and notifications are explicitly out of scope per the spec and have no tasks here, correctly.
- **Type consistency:** `ProfileRole.hasPremiumAccess` (Task 1) is the one check used in every gate (Tasks 7-8) and in `PurchaseService`'s doc comment — no divergent naming introduced.
- **Placeholder scan:** no TBDs; the two spots that defer exact implementation (Task 6's `currentUserId` location, Task 8's exact curated-row insertion point) point at a specific file/line to go read rather than hand-waving, because the survey that produced this plan didn't capture those exact line numbers — that's a legitimate "go check the current code" pointer, not a placeholder for logic.

---

**Plan complete and saved to `docs/superpowers/plans/2026-07-25-storekit-premium-paywall.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

**Which approach?**
