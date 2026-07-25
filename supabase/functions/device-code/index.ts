import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const moonlitAppURL = Deno.env.get("MOONLIT_APP_URL") || "https://trymoonlit.app";

const supabase = createClient(supabaseUrl, supabaseServiceKey);

function generateCode(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  return Array.from(
    { length: 6 },
    () => chars[Math.floor(Math.random() * chars.length)]
  ).join("");
}

function corsHeaders(): Record<string, string> {
  return {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "apikey, Authorization, Content-Type",
  };
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders() });
  }

  const url = new URL(req.url);
  const action = url.searchParams.get("action");

  if (req.method === "POST" && action === "initiate") {
    const code = generateCode();
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000);

    const { error } = await supabase
      .from("device_codes")
      .insert({ code, expires_at: expiresAt.toISOString(), status: "pending" });

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: corsHeaders() });
    }

    return new Response(JSON.stringify({
      code,
      verification_url: `${moonlitAppURL}/activate`,
      expires_in: 600,
    }), { headers: corsHeaders() });
  }

  if (req.method === "POST" && action === "poll") {
    const { code } = await req.json();

    const { data, error } = await supabase
      .from("device_codes")
      .select("status, expires_at, access_token, refresh_token")
      .eq("code", code)
      .single();

    if (error || !data) {
      return new Response(JSON.stringify({ status: "expired" }), { headers: corsHeaders() });
    }

    if (new Date(data.expires_at) < new Date()) {
      return new Response(JSON.stringify({ status: "expired" }), { headers: corsHeaders() });
    }

    if (data.status === "linked" && data.access_token && data.refresh_token) {
      return new Response(JSON.stringify({
        status: "authorized",
        access_token: data.access_token,
        refresh_token: data.refresh_token,
      }), { headers: corsHeaders() });
    }

    return new Response(JSON.stringify({ status: "pending" }), { headers: corsHeaders() });
  }

  // Called by the already-authenticated device (phone/laptop) that just
  // entered the code. It relays its own session tokens so the TV can poll
  // them back — the service-role key can't mint a session for another
  // user, so the authenticated client's own tokens are what get stored.
  if (req.method === "POST" && action === "link") {
    const { code, access_token, refresh_token } = await req.json();

    if (!code || !access_token || !refresh_token) {
      return new Response(
        JSON.stringify({ error: "code, access_token and refresh_token required" }),
        { status: 400, headers: corsHeaders() }
      );
    }

    const { data: userData, error: userError } = await supabase.auth.getUser(access_token);
    if (userError || !userData?.user) {
      return new Response(JSON.stringify({ error: "Invalid session" }), { status: 401, headers: corsHeaders() });
    }

    const { data, error } = await supabase
      .from("device_codes")
      .update({
        status: "linked",
        user_id: userData.user.id,
        access_token,
        refresh_token,
      })
      .eq("code", code)
      .eq("status", "pending")
      .gte("expires_at", new Date().toISOString())
      .select()
      .single();

    if (error || !data) {
      return new Response(
        JSON.stringify({ error: error?.message ?? "Code not found or already used" }),
        { status: 400, headers: corsHeaders() }
      );
    }

    return new Response(JSON.stringify({ status: "linked" }), { headers: corsHeaders() });
  }

  return new Response(JSON.stringify({ error: "Invalid request" }), { status: 400, headers: corsHeaders() });
});
