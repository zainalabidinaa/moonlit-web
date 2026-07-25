import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// RevenueCat webhook event shapes: https://www.revenuecat.com/docs/webhooks
// Expiration/cancellation events must only revert a row that this webhook
// itself set to 'storekit' — never an admin/manual grant for the same user.
const EXPIRY_EVENT_TYPES = new Set(["EXPIRATION", "CANCELLATION"]);
const PREMIUM_ENTITLEMENT = "premium";
const PREMIUM_PLUS_ENTITLEMENT = "premium_plus";

Deno.serve(async (req) => {
    const secret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");
    const authHeader = req.headers.get("Authorization");
    if (!secret || authHeader !== `Bearer ${secret}`) {
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
        return new Response("ok: no recognized entitlement", { status: 200 });
    }

    const { error } = await adminClient
        .from("profiles")
        .update({ role, subscription_source: "storekit" })
        .eq("user_id", appUserId);
    if (error) return new Response(error.message, { status: 500 });
    return new Response("ok", { status: 200 });
});
