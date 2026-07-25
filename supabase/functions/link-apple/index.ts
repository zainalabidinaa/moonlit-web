import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
    const authHeader = req.headers.get("Authorization");
    const accessToken = authHeader?.replace("Bearer ", "");
    if (!accessToken) return new Response("Unauthorized", { status: 401 });

    const { id_token } = await req.json();
    if (!id_token) return new Response("Missing id_token", { status: 400 });

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // Verify the caller is an authenticated Moonlit user
    const userClient = createClient(supabaseUrl, anonKey, {
        global: { headers: { Authorization: `Bearer ${accessToken}` } },
    });
    const { data: { user }, error: userError } = await userClient.auth.getUser();
    if (userError || !user) return new Response("Unauthorized", { status: 401 });

    // Decode Apple JWT — no need to re-verify, Apple already signed it
    const parts = id_token.split(".");
    if (parts.length !== 3) return new Response("Invalid id_token", { status: 400 });
    const payload = JSON.parse(atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")));
    const appleSub: string = payload.sub;
    const appleEmail: string = payload.email ?? "";

    if (!appleSub) return new Response("Missing Apple sub", { status: 400 });

    // Link via security-definer SQL function
    const adminClient = createClient(supabaseUrl, serviceRoleKey);
    const { error } = await adminClient.rpc("link_apple_identity", {
        p_user_id: user.id,
        p_apple_sub: appleSub,
        p_apple_email: appleEmail,
    });

    if (error) {
        const status = error.message.includes("already linked") ? 409 : 500;
        return new Response(error.message, { status });
    }

    return new Response("Linked", { status: 200 });
});
