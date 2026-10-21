import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PUBLIC_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? "";
const TENANT_SLUG = "growta-rewardloop";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
};

function respond(status: number, payload: Record<string, unknown>) {
  return new Response(JSON.stringify(payload), { status, headers: corsHeaders });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return respond(405, { ok: false, error: "method_not_allowed" });

  try {
    if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !PUBLIC_KEY) {
      return respond(500, { ok: false, error: "server_configuration_missing" });
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) return respond(401, { ok: false, error: "authentication_required" });

    // Verify the caller's JWT with Supabase Auth. Never accept a user ID from request data.
    const userClient = createClient(SUPABASE_URL, PUBLIC_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    const user = userData?.user;
    if (userError || !user) return respond(401, { ok: false, error: "invalid_session" });

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const body = await req.json().catch(() => ({}));
    const action = typeof body.action === "string" ? body.action : "";

    if (action === "profile") {
      const displayName = typeof body.display_name === "string" ? body.display_name.trim() : "";
      const phone = typeof body.phone_e164 === "string" ? body.phone_e164.trim() : "";
      const locale = body.preferred_locale === "en-IN" ? "en-IN" : "hi-IN";
      if (displayName.length < 2 || displayName.length > 160) {
        return respond(400, { ok: false, error: "display_name_invalid" });
      }
      if (phone && !/^\+[1-9]\d{7,14}$/.test(phone)) {
        return respond(400, { ok: false, error: "phone_must_be_e164" });
      }

      const { data: tenant, error: tenantError } = await admin
        .from("tenants").select("id,status,default_locale").eq("slug", TENANT_SLUG).maybeSingle();
      if (tenantError || !tenant || tenant.status !== "active") {
        return respond(503, { ok: false, error: "tenant_unavailable" });
      }

      const { data: existing, error: existingError } = await admin
        .from("partners").select("id,role,display_name,phone_e164,preferred_locale,verification_status")
        .eq("tenant_id", tenant.id).eq("user_id", user.id).maybeSingle();
      if (existingError) return respond(500, { ok: false, error: "profile_lookup_failed" });

      if (existing) {
        const { data: updated, error: updateError } = await admin.from("partners")
          .update({ display_name: displayName, phone_e164: phone || null, preferred_locale: locale, updated_at: new Date().toISOString() })
          .eq("id", existing.id)
          .select("id,role,display_name,phone_e164,preferred_locale,verification_status").single();
        if (updateError) return respond(500, { ok: false, error: "profile_update_failed" });
        return respond(200, { ok: true, profile: updated });
      }

      const { data: created, error: createError } = await admin.from("partners").insert({
        tenant_id: tenant.id,
        user_id: user.id,
        role: "farmer",
        display_name: displayName,
        phone_e164: phone || null,
        preferred_locale: locale,
        verification_status: "pending",
      }).select("id,role,display_name,phone_e164,preferred_locale,verification_status").single();

      if (createError) {
        // A concurrent onboarding request may have created the profile first.
        const { data: raced } = await admin.from("partners")
          .select("id,role,display_name,phone_e164,preferred_locale,verification_status")
          .eq("tenant_id", tenant.id).eq("user_id", user.id).maybeSingle();
        if (raced) return respond(200, { ok: true, profile: raced });
        return respond(500, { ok: false, error: "profile_create_failed" });
      }
      return respond(200, { ok: true, profile: created });
    }

    if (action === "claim") {
      const token = typeof body.token === "string" ? body.token.trim() : "";
      const requestId = typeof body.request_id === "string" ? body.request_id : "";
      if (token.length < 16 || token.length > 512) return respond(400, { ok: false, error: "invalid_code" });
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(requestId)) {
        return respond(400, { ok: false, error: "invalid_request_id" });
      }
      const { data, error } = await admin.rpc("rewardloop_claim_qr_internal", {
        p_actor_user_id: user.id,
        p_token: token,
        p_request_id: requestId,
        p_app_version: "growta-rewardloop-pwa/1.0.0",
        p_device_ref_hash: null,
      });
      if (error) return respond(500, { ok: false, error: "claim_processing_failed" });
      return respond(200, data && typeof data === "object" ? data : { ok: false, error: "unexpected_claim_response" });
    }

    if (action === "redeem") {
      const rewardId = typeof body.reward_id === "string" ? body.reward_id : "";
      const requestKey = typeof body.request_key === "string" ? body.request_key : "";
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(rewardId)) {
        return respond(400, { ok: false, error: "invalid_reward" });
      }
      if (requestKey.length < 8 || requestKey.length > 160) return respond(400, { ok: false, error: "invalid_request_key" });
      const { data, error } = await admin.rpc("rewardloop_redeem_internal", {
        p_actor_user_id: user.id,
        p_reward_id: rewardId,
        p_request_key: requestKey,
      });
      if (error) return respond(500, { ok: false, error: "redemption_processing_failed" });
      return respond(200, data && typeof data === "object" ? data : { ok: false, error: "unexpected_redemption_response" });
    }

    return respond(400, { ok: false, error: "unknown_action" });
  } catch {
    // Avoid returning raw exception details or credentials to the client.
    return respond(500, { ok: false, error: "unexpected_server_error" });
  }
});