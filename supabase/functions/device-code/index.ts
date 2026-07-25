import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const moonlitAppURL = Deno.env.get("MOONLIT_APP_URL") || "https://moonlit.app";

const supabase = createClient(supabaseUrl, supabaseServiceKey);

function generateCode(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  return Array.from(
    { length: 6 },
    () => chars[Math.floor(Math.random() * chars.length)]
  ).join("");
}

serve(async (req: Request) => {
  const url = new URL(req.url);
  const action = url.searchParams.get("action");

  if (req.method === "POST" && action === "initiate") {
    const code = generateCode();
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000);

    const { error } = await supabase
      .from("device_codes")
      .insert({ code, expires_at: expiresAt.toISOString(), status: "pending" });

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), { status: 500 });
    }

    return new Response(JSON.stringify({
      code,
      verification_url: `${moonlitAppURL}/activate`,
      expires_in: 600,
    }), { headers: { "Content-Type": "application/json" } });
  }

  if (req.method === "POST" && action === "poll") {
    const { code } = await req.json();

    const { data, error } = await supabase
      .from("device_codes")
      .select("*")
      .eq("code", code)
      .eq("status", "linked")
      .gte("expires_at", new Date().toISOString())
      .single();

    if (error || !data) {
      return new Response(JSON.stringify({ status: "pending" }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    const { data: sessionData, error: sessionError } = await supabase.auth.admin
      .generateLink({ type: "recovery", email: data.user_email ?? "" });

    if (!sessionError) {
      return new Response(JSON.stringify({
        status: "authorized",
        access_token: data.access_token,
        refresh_token: data.refresh_token,
      }), { headers: { "Content-Type": "application/json" } });
    }

    return new Response(JSON.stringify({
      status: "authorized",
      access_token: data.access_token,
      refresh_token: data.refresh_token,
    }), { headers: { "Content-Type": "application/json" } });
  }

  if (req.method === "POST" && action === "link") {
    const { code, user_id } = await req.json();

    if (!code || !user_id) {
      return new Response(JSON.stringify({ error: "code and user_id required" }), { status: 400 });
    }

    const { error } = await supabase
      .from("device_codes")
      .update({ status: "linked", user_id })
      .eq("code", code)
      .eq("status", "pending")
      .gte("expires_at", new Date().toISOString());

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), { status: 500 });
    }

    return new Response(JSON.stringify({ status: "linked" }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ error: "Invalid request" }), { status: 400 });
});
