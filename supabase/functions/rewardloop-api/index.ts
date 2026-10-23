import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PUBLIC_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? "";
const TENANT_SLUG = "growta-rewardloop";
const MAX_REQUEST_BODY_BYTES = 64 * 1024;
// Production is the only built-in browser origin. Add preview/custom origins
// explicitly through ALLOWED_ORIGINS in Edge Function secrets.
const DEFAULT_ALLOWED_ORIGINS = ["https://bigagri.vercel.app"];
const CONFIGURED_ALLOWED_ORIGINS = (Deno.env.get("ALLOWED_ORIGINS") ?? "")
  .split(",").map((origin) => origin.trim()).filter(Boolean);
const ALLOWED_ORIGINS = new Set([
  ...DEFAULT_ALLOWED_ORIGINS,
  ...CONFIGURED_ALLOWED_ORIGINS,
]);
const corsHeaders = {
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
};

function respond(status: number, payload: Record<string, unknown>, origin?: string | null) {
  const headers = new Headers(corsHeaders);
  if (origin && ALLOWED_ORIGINS.has(origin)) headers.set("Access-Control-Allow-Origin", origin);
  return new Response(JSON.stringify(payload), { status, headers });
}

async function readLimitedJson(req: Request): Promise<{ ok: true; value: unknown } | { ok: false; tooLarge: boolean }> {
  const contentLength = Number(req.headers.get("content-length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > MAX_REQUEST_BODY_BYTES) return { ok: false, tooLarge: true };
  if (!req.body) return { ok: true, value: {} };
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > MAX_REQUEST_BODY_BYTES) {
        await reader.cancel().catch(() => {});
        return { ok: false, tooLarge: true };
      }
      chunks.push(value);
    }
  } catch {
    return { ok: false, tooLarge: false };
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  try {
    return { ok: true, value: JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)) };
  } catch {
    return { ok: false, tooLarge: false };
  }
}

type RedisLimitResult = { allowed: boolean; retryAfterSeconds?: number; configured: boolean };

// Optional defence-in-depth burst limiting. Database constraints and the existing
// invalid-token counter remain authoritative; this cache never controls balances,
// stock, tenant membership, permissions, or claim/redemption idempotency.
async function checkRedisRateLimit(
  action: string,
  actorId: string,
  limit: number,
  windowSeconds: number,
): Promise<RedisLimitResult> {
  const rawUrl = Deno.env.get("UPSTASH_REDIS_REST_URL") ?? "";
  const token = Deno.env.get("UPSTASH_REDIS_REST_TOKEN") ?? "";
  if (!rawUrl || !token) return { allowed: true, configured: false };

  let endpoint: URL;
  try {
    endpoint = new URL(rawUrl);
    if (endpoint.protocol !== "https:" || !endpoint.hostname.endsWith(".upstash.io")) {
      return { allowed: true, configured: false };
    }
  } catch {
    return { allowed: true, configured: false };
  }

  // Resolve rate limits before tenant membership/context to reject abusive requests early.
  // Scope by verified actor + action globally: never let an untrusted tenant_slug
  // supplied in the request create fresh buckets and bypass throttling.
  const key = `rewardloop:v1:actor:${actorId}:${action}`;
  const script = [
    "local n = redis.call('INCR', KEYS[1])",
    "if n == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end",
    "local ttl = redis.call('TTL', KEYS[1])",
    "return {n, ttl}",
  ].join("\n");

  try {
    const response = await fetch(endpoint.toString(), {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(["EVAL", script, "1", key, String(windowSeconds)]),
      signal: AbortSignal.timeout(1200),
    });
    if (!response.ok) throw new Error("Redis request failed");
    const payload = await response.json();
    const result = payload?.result;
    const count = Array.isArray(result) ? Number(result[0]) : NaN;
    const ttl = Array.isArray(result) ? Number(result[1]) : windowSeconds;
    if (!Number.isSafeInteger(count) || count < 1) throw new Error("Redis response invalid");
    if (count > limit) {
      return {
        allowed: false,
        retryAfterSeconds: Math.max(1, Number.isFinite(ttl) ? ttl : windowSeconds),
        configured: true,
      };
    }
    return { allowed: true, configured: true };
  } catch {
    // Fail open to existing database-level protections when Redis is unavailable.
    // Never log the token, URL, actor identifier, or raw request payload.
    return { allowed: true, configured: true };
  }
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  const originAllowed = !origin || ALLOWED_ORIGINS.has(origin);
  const reply = (status: number, payload: Record<string, unknown>) => respond(status, payload, origin);
  if (!originAllowed) return new Response(null, { status: 403, headers: { "Vary": "Origin", "Cache-Control": "no-store" } });
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: { ...corsHeaders, ...(origin ? { "Access-Control-Allow-Origin": origin } : {}) } });
  if (req.method !== "POST") return reply(405, { ok: false, error: "method_not_allowed" });

  try {
    if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !PUBLIC_KEY) {
      return reply(500, { ok: false, error: "server_configuration_missing" });
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) return reply(401, { ok: false, error: "authentication_required" });

    // Verify the caller's JWT with Supabase Auth. Never accept a user ID from request data.
    const userClient = createClient(SUPABASE_URL, PUBLIC_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    const user = userData?.user;
    if (userError || !user) return reply(401, { ok: false, error: "invalid_session" });

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const parsedBody = await readLimitedJson(req);
    if (!parsedBody.ok) return reply(parsedBody.tooLarge ? 413 : 400, { ok: false, error: parsedBody.tooLarge ? "payload_too_large" : "invalid_request" });
    if (!parsedBody.value || typeof parsedBody.value !== "object" || Array.isArray(parsedBody.value)) return reply(400, { ok: false, error: "invalid_request" });
    const body = parsedBody.value as Record<string, unknown>;
    const action = typeof body.action === "string" ? body.action : "";

    const ratePolicy: Record<string, { limit: number; windowSeconds: number }> = {
      profile: { limit: 30, windowSeconds: 60 },
      claim: { limit: 30, windowSeconds: 60 },
      redeem: { limit: 15, windowSeconds: 60 },
      admin_dashboard: { limit: 60, windowSeconds: 60 },
      verify_partner: { limit: 30, windowSeconds: 60 },
      issue_qr_batch: { limit: 10, windowSeconds: 60 },
      revoke_qr_batch: { limit: 10, windowSeconds: 60 },
      resolve_redemption: { limit: 30, windowSeconds: 60 },
      set_campaign_status: { limit: 20, windowSeconds: 60 },
      create_campaign: { limit: 10, windowSeconds: 60 },
      admin_record_export: { limit: 10, windowSeconds: 60 },
      admin_audit_logs: { limit: 30, windowSeconds: 60 },
      admin_tenants: { limit: 30, windowSeconds: 60 },
      set_point_value: { limit: 10, windowSeconds: 60 },
      create_product: { limit: 20, windowSeconds: 60 },
      update_product: { limit: 30, windowSeconds: 60 },
      set_product_status: { limit: 20, windowSeconds: 60 },
      create_reward: { limit: 15, windowSeconds: 60 },
      update_reward: { limit: 30, windowSeconds: 60 },
      set_reward_status: { limit: 20, windowSeconds: 60 },
      admin_fraud_cases: { limit: 30, windowSeconds: 60 },
      create_fraud_case: { limit: 10, windowSeconds: 60 },
      update_fraud_case: { limit: 20, windowSeconds: 60 },
      admin_tenant_invitations: { limit: 30, windowSeconds: 60 },
      create_tenant_invitation: { limit: 5, windowSeconds: 60 },
      revoke_tenant_invitation: { limit: 10, windowSeconds: 60 },
      accept_tenant_invitation: { limit: 5, windowSeconds: 900 },
    };
    const policy = ratePolicy[action];
    if (policy) {
      const rate = await checkRedisRateLimit(action, user.id, policy.limit, policy.windowSeconds);
      if (!rate.allowed) {
        const headers = new Headers(corsHeaders);
        headers.set("Retry-After", String(rate.retryAfterSeconds ?? policy.windowSeconds));
        if (origin && ALLOWED_ORIGINS.has(origin)) headers.set("Access-Control-Allow-Origin", origin);
        return new Response(JSON.stringify({ ok: false, error: "rate_limited" }), { status: 429, headers });
      }
    }

    // Invitation acceptance is intentionally available before the caller has tenant
    // membership. The database RPC verifies the confirmed auth email and one-time hash.
    if (action === "accept_tenant_invitation") {
      const token = typeof body.token === "string" ? body.token.trim().toLowerCase() : "";
      if (!/^[a-f0-9]{64}$/.test(token)) return reply(400, { ok: false, error: "invalid_invitation" });
      const tokenHashBytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
      const tokenHash = Array.from(new Uint8Array(tokenHashBytes), byte => byte.toString(16).padStart(2, "0")).join("");
      const { data, error } = await admin.rpc("rewardloop_accept_tenant_invitation_internal", {
        p_actor_user_id: user.id, p_token_hash: tokenHash,
      });
      if (error) return reply(500, { ok: false, error: "invitation_acceptance_failed" });
      if (!data || data.ok !== true) {
        const status = data?.error === "email_not_confirmed" || data?.error === "invitation_email_mismatch" ? 403 :
          data?.error === "tenant_inactive" || data?.error === "membership_conflict" ? 409 :
          data?.error === "invitation_expired" ? 410 : data?.error === "invalid_invitation" ? 404 : 400;
        return reply(status, { ok: false, error: data?.error || "invitation_acceptance_failed" });
      }
      return reply(200, data);
    }

    // List only active tenants for which this authenticated user has an active
    // tenant-admin membership. Client-provided tenant IDs/slugs never grant access.
    if (action === "admin_tenants") {
      const { data: memberships, error: membershipsError } = await admin
        .from("tenant_memberships")
        .select("tenant_id,role")
        .eq("user_id", user.id)
        .eq("status", "active")
        .in("role", ["brand_admin", "super_admin"]);
      if (membershipsError) return reply(500, { ok: false, error: "admin_tenant_context_failed" });

      const roleByTenant = new Map<string, string>();
      for (const membership of memberships || []) {
        if (!roleByTenant.has(membership.tenant_id)) roleByTenant.set(membership.tenant_id, membership.role);
      }
      const tenantIds = [...roleByTenant.keys()];
      if (!tenantIds.length) return reply(200, { ok: true, tenants: [] });

      const { data: tenants, error: tenantsError } = await admin
        .from("tenants")
        .select("id,name,slug,status")
        .in("id", tenantIds)
        .eq("status", "active")
        .order("name", { ascending: true });
      if (tenantsError) return reply(500, { ok: false, error: "admin_tenant_context_failed" });
      return reply(200, {
        ok: true,
        tenants: (tenants || []).map((tenant) => ({
          ...tenant,
          role: roleByTenant.get(tenant.id) || "brand_admin",
        })),
      });
    }

    if (action === "profile") {
      const requestedTenantSlug = typeof body.tenant_slug === "string" ? body.tenant_slug.trim() : TENANT_SLUG;
      if (!/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(requestedTenantSlug)) {
        return reply(400, { ok: false, error: "tenant_slug_invalid" });
      }
      const displayName = typeof body.display_name === "string" ? body.display_name.trim() : "";
      const phone = typeof body.phone_e164 === "string" ? body.phone_e164.trim() : "";
      const locale = body.preferred_locale === "en-IN" ? "en-IN" : "hi-IN";
      if (displayName.length < 2 || displayName.length > 160) {
        return reply(400, { ok: false, error: "display_name_invalid" });
      }
      if (phone && !/^\+[1-9]\d{7,14}$/.test(phone)) {
        return reply(400, { ok: false, error: "phone_must_be_e164" });
      }

      const { data: tenant, error: tenantError } = await admin
        .from("tenants").select("id,status,default_locale,public_catalog_enabled").eq("slug", requestedTenantSlug).maybeSingle();
      if (tenantError || !tenant || tenant.status !== "active" || tenant.public_catalog_enabled !== true) {
        return reply(503, { ok: false, error: "tenant_unavailable" });
      }

      const { data: existing, error: existingError } = await admin
        .from("partners").select("id,role,display_name,phone_e164,preferred_locale,verification_status")
        .eq("tenant_id", tenant.id).eq("user_id", user.id).maybeSingle();
      if (existingError) return reply(500, { ok: false, error: "profile_lookup_failed" });

      if (existing) {
        const { data: updated, error: updateError } = await admin.from("partners")
          .update({ display_name: displayName, phone_e164: phone || null, preferred_locale: locale, updated_at: new Date().toISOString() })
          .eq("id", existing.id)
          .select("id,role,display_name,phone_e164,preferred_locale,verification_status").single();
        if (updateError) return reply(500, { ok: false, error: "profile_update_failed" });
        return reply(200, { ok: true, profile: updated });
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
        if (raced) return reply(200, { ok: true, profile: raced });
        return reply(500, { ok: false, error: "profile_create_failed" });
      }
      return reply(200, { ok: true, profile: created });
    }

    if (action === "claim") {
      const token = typeof body.token === "string" ? body.token.trim() : "";
      const requestId = typeof body.request_id === "string" ? body.request_id : "";
      if (token.length < 16 || token.length > 512) return reply(400, { ok: false, error: "invalid_code" });
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(requestId)) {
        return reply(400, { ok: false, error: "invalid_request_id" });
      }
      const { data, error } = await admin.rpc("rewardloop_claim_qr_internal", {
        p_actor_user_id: user.id,
        p_token: token,
        p_request_id: requestId,
        p_app_version: "growta-rewardloop-pwa/1.0.0",
        p_device_ref_hash: null,
      });
      if (error) return reply(500, { ok: false, error: "claim_processing_failed" });
      return reply(200, data && typeof data === "object" ? data : { ok: false, error: "unexpected_claim_response" });
    }

    if (action === "redeem") {
      const rewardId = typeof body.reward_id === "string" ? body.reward_id : "";
      const requestKey = typeof body.request_key === "string" ? body.request_key : "";
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(rewardId)) {
        return reply(400, { ok: false, error: "invalid_reward" });
      }
      if (requestKey.length < 8 || requestKey.length > 160) return reply(400, { ok: false, error: "invalid_request_key" });
      const { data, error } = await admin.rpc("rewardloop_redeem_internal", {
        p_actor_user_id: user.id,
        p_reward_id: rewardId,
        p_request_key: requestKey,
      });
      if (error) return reply(500, { ok: false, error: "redemption_processing_failed" });
      return reply(200, data && typeof data === "object" ? data : { ok: false, error: "unexpected_redemption_response" });
    }

    if (["admin_dashboard", "admin_audit_logs", "admin_record_export", "verify_partner", "issue_qr_batch", "revoke_qr_batch", "resolve_redemption", "set_campaign_status", "create_campaign", "set_point_value", "create_product", "set_product_status", "update_product", "create_reward", "update_reward", "set_reward_status", "admin_fraud_cases", "create_fraud_case", "update_fraud_case", "admin_tenant_invitations", "create_tenant_invitation", "revoke_tenant_invitation"].includes(action)) {
      // Keep legacy callers working on the original tenant, but allow an explicit
      // tenant context only after checking active membership below.
      const requestedTenantSlug = typeof body.tenant_slug === "string" ? body.tenant_slug.trim() : TENANT_SLUG;
      if (!/^[a-z0-9][a-z0-9-]{1,62}$/.test(requestedTenantSlug)) {
        return reply(400, { ok: false, error: "invalid_tenant_context" });
      }
      const { data: tenant, error: tenantError } = await admin.from("tenants").select("id,name,slug,status").eq("slug", requestedTenantSlug).maybeSingle();
      if (tenantError || !tenant || tenant.status !== "active") return reply(503, { ok: false, error: "tenant_unavailable" });
      const { data: membership, error: membershipError } = await admin.from("tenant_memberships").select("role,status")
        .eq("tenant_id", tenant.id).eq("user_id", user.id).eq("status", "active").in("role", ["brand_admin", "super_admin"]).maybeSingle();
      if (membershipError) return reply(500, { ok: false, error: "admin_authorization_check_failed" });
      if (!membership) return reply(403, { ok: false, error: "admin_access_required" });

      if (action === "admin_tenant_invitations") {
        const page = Number(body.invitations_page ?? 0);
        if (!Number.isSafeInteger(page) || page < 0 || page > 10000) {
          return reply(400, { ok: false, error: "invalid_invitations_page" });
        }
        const { data, error, count } = await admin.from("tenant_invitations")
          .select("id,email,role,status,invited_by,accepted_by,expires_at,accepted_at,revoked_at,created_at", { count: "exact" })
          .eq("tenant_id", tenant.id).order("created_at", { ascending: false }).order("id", { ascending: false })
          .range(page * 20, page * 20 + 19);
        if (error) return reply(500, { ok: false, error: "tenant_invitations_load_failed" });
        return reply(200, { ok: true, invitations: data || [], pagination: { page, page_size: 20, total: count || 0 } });
      }

      if (action === "create_tenant_invitation") {
        const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
        if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
          return reply(400, { ok: false, error: "invalid_invitation_email" });
        }
        const tokenBytes = new Uint8Array(32);
        crypto.getRandomValues(tokenBytes);
        const token = Array.from(tokenBytes, byte => byte.toString(16).padStart(2, "0")).join("");
        const tokenHashBytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
        const tokenHash = Array.from(new Uint8Array(tokenHashBytes), byte => byte.toString(16).padStart(2, "0")).join("");
        const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
        const { data, error } = await admin.rpc("rewardloop_create_tenant_invitation_internal", {
          p_actor_user_id: user.id, p_tenant_id: tenant.id, p_email: email,
          p_role: "brand_admin", p_token_hash: tokenHash, p_expires_at: expiresAt,
        });
        if (error) return reply(500, { ok: false, error: "tenant_invitation_create_failed" });
        if (!data || data.ok !== true) {
          const status = data?.error === "forbidden" ? 403 :
            ["invitation_already_pending", "already_tenant_admin"].includes(data?.error) ? 409 :
            data?.error === "tenant_inactive" ? 503 : 400;
          return reply(status, { ok: false, error: data?.error || "tenant_invitation_create_failed" });
        }
        // Return the raw token only inside this one-time link response. It is never persisted.
        const inviteOrigin = origin && ALLOWED_ORIGINS.has(origin) ? origin : DEFAULT_ALLOWED_ORIGINS[0];
        const inviteUrl = new URL("/admin.html", inviteOrigin);
        inviteUrl.hash = `invite=${token}`;
        return reply(201, { ...data, invite_url: inviteUrl.toString() });
      }

      if (action === "revoke_tenant_invitation") {
        const invitationId = typeof body.invitation_id === "string" ? body.invitation_id : "";
        const reason = typeof body.reason === "string" ? body.reason.trim().slice(0, 500) : "";
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(invitationId) || reason.length < 5) {
          return reply(400, { ok: false, error: "invalid_invitation_revoke_request" });
        }
        const { data, error } = await admin.rpc("rewardloop_revoke_tenant_invitation_internal", {
          p_actor_user_id: user.id, p_tenant_id: tenant.id, p_invitation_id: invitationId, p_reason: reason,
        });
        if (error) return reply(500, { ok: false, error: "tenant_invitation_revoke_failed" });
        if (!data || data.ok !== true) {
          const status = data?.error === "forbidden" ? 403 : data?.error === "invitation_not_found" ? 404 : 400;
          return reply(status, { ok: false, error: data?.error || "tenant_invitation_revoke_failed" });
        }
        return reply(200, data);
      }

      if (action === "admin_fraud_cases") {
        const rawPage = Number(body.fraud_cases_page ?? 0);
        const statusFilter = typeof body.fraud_case_status === "string" ? body.fraud_case_status : "all";
        if (!Number.isSafeInteger(rawPage) || rawPage < 0 || rawPage > 10000 ||
            !["all","open","investigating","confirmed_fraud","resolved_legitimate","dismissed"].includes(statusFilter)) {
          return reply(400, { ok: false, error: "invalid_fraud_case_filter" });
        }
        let query = admin.from("fraud_cases")
          .select("id,title,reason_code,severity,status,summary,partner_id,claim_id,scan_event_id,assigned_to,opened_by,resolution_code,resolution_notes,created_at,updated_at,resolved_at", { count: "exact" })
          .eq("tenant_id", tenant.id);
        if (statusFilter !== "all") query = query.eq("status", statusFilter);
        const { data: cases, error: casesError, count } = await query
          .order("created_at", { ascending: false }).order("id", { ascending: false })
          .range(rawPage * 20, (rawPage + 1) * 20 - 1);
        if (casesError) return reply(500, { ok: false, error: "admin_fraud_cases_load_failed" });
        return reply(200, { ok: true, cases: cases || [], pagination: { page: rawPage, page_size: 20, total: count || 0 } });
      }

      if (action === "admin_audit_logs") {
        const rawPage = Number(body.audit_page ?? 0);
        if (!Number.isSafeInteger(rawPage) || rawPage < 0 || rawPage > 100000) {
          return reply(400, { ok: false, error: "invalid_audit_page" });
        }
        const pageSize = 20;
        const { data: rows, error: auditError, count } = await admin
          .from("audit_logs")
          .select("id,actor_user_id,action,entity_type,entity_id,request_id,reason,created_at", { count: "exact" })
          .eq("tenant_id", tenant.id)
          .order("created_at", { ascending: false })
          .order("id", { ascending: false })
          .range(rawPage * pageSize, (rawPage + 1) * pageSize - 1);
        if (auditError) return reply(500, { ok: false, error: "admin_audit_logs_load_failed" });
        return reply(200, {
          ok: true,
          logs: rows || [],
          pagination: { page: rawPage, page_size: pageSize, total: count || 0 },
        });
      }

      if (action === "admin_record_export") {
        const exportType = typeof body.export_type === "string" ? body.export_type : "";
        const rowCount = Number(body.row_count);
        const page = Number(body.page);
        if (!["partners", "redemptions"].includes(exportType) ||
            !Number.isSafeInteger(rowCount) || rowCount < 0 || rowCount > 100 ||
            !Number.isSafeInteger(page) || page < 0 || page > 10000) {
          return reply(400, { ok: false, error: "invalid_export_audit_request" });
        }

        // Record export intent only; never copy exported PII into the audit payload.
        // The export itself remains limited to the current tenant-scoped page already
        // returned by admin_dashboard.
        const requestId = crypto.randomUUID();
        const { error: auditInsertError } = await admin.from("audit_logs").insert({
          tenant_id: tenant.id,
          actor_user_id: user.id,
          action: "admin_export_csv_requested",
          entity_type: "export",
          request_id: requestId,
          reason: "CSV export requested",
          after_data: { export_type: exportType, row_count: rowCount, page },
        });
        if (auditInsertError) return reply(500, { ok: false, error: "admin_export_audit_failed" });
        return reply(200, { ok: true, request_id: requestId });
      }

      if (action === "create_fraud_case") {
        const title = typeof body.title === "string" ? body.title.trim() : "";
        const reasonCode = typeof body.reason_code === "string" ? body.reason_code.trim().toLowerCase() : "";
        const severity = typeof body.severity === "string" ? body.severity.trim().toLowerCase() : "medium";
        const summary = typeof body.summary === "string" ? body.summary.trim() : "";
        const optionalUuid = (value: unknown) => typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value) ? value : null;
        if (title.length < 3 || title.length > 160 || !/^[a-z][a-z0-9_]{2,63}$/.test(reasonCode) ||
            !["low","medium","high","critical"].includes(severity) || summary.length > 2000 ||
            (body.partner_id != null && !optionalUuid(body.partner_id)) ||
            (body.claim_id != null && !optionalUuid(body.claim_id)) ||
            (body.scan_event_id != null && !optionalUuid(body.scan_event_id))) {
          return reply(400, { ok: false, error: "invalid_fraud_case_details" });
        }
        const { data, error } = await admin.rpc("rewardloop_create_fraud_case_internal", {
          p_actor_user_id: user.id, p_tenant_id: tenant.id, p_title: title, p_reason_code: reasonCode,
          p_severity: severity, p_summary: summary || null,
          p_partner_id: optionalUuid(body.partner_id), p_claim_id: optionalUuid(body.claim_id),
          p_scan_event_id: optionalUuid(body.scan_event_id),
        });
        if (error) return reply(500, { ok: false, error: "fraud_case_create_failed" });
        if (!data || data.ok !== true) return reply(data?.error === "forbidden" ? 403 : 400, data || { ok: false, error: "fraud_case_create_failed" });
        return reply(201, data);
      }

      if (action === "update_fraud_case") {
        const caseId = typeof body.case_id === "string" ? body.case_id : "";
        const status = typeof body.status === "string" ? body.status.trim().toLowerCase() : "";
        const assignedTo = body.assigned_to == null || body.assigned_to === "" ? null : body.assigned_to;
        const resolutionCode = typeof body.resolution_code === "string" ? body.resolution_code.trim().toLowerCase() : "";
        const resolutionNotes = typeof body.resolution_notes === "string" ? body.resolution_notes.trim() : "";
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(caseId) ||
            !["open","investigating","confirmed_fraud","resolved_legitimate","dismissed"].includes(status) ||
            (assignedTo !== null && (typeof assignedTo !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{12}$/i.test(assignedTo))) ||
            resolutionCode.length > 64 || resolutionNotes.length > 2000) {
          return reply(400, { ok: false, error: "invalid_fraud_case_update" });
        }
        const { data, error } = await admin.rpc("rewardloop_update_fraud_case_internal", {
          p_actor_user_id: user.id, p_tenant_id: tenant.id, p_case_id: caseId, p_new_status: status,
          p_assigned_to: assignedTo, p_resolution_code: resolutionCode || null,
          p_resolution_notes: resolutionNotes || null,
        });
        if (error) return reply(500, { ok: false, error: "fraud_case_update_failed" });
        if (!data || data.ok !== true) return reply(data?.error === "forbidden" ? 403 : 400, data || { ok: false, error: "fraud_case_update_failed" });
        return reply(200, data);
      }

      if (action === "set_point_value") {
        const pointValue = Number(body.point_value_minor_units);
        const currency = String(body.point_value_currency || "").trim().toUpperCase();
        if (!Number.isSafeInteger(pointValue) || pointValue < 1 || pointValue > 1000000 || !/^[A-Z]{3}$/.test(currency)) {
          return reply(400, { ok: false, error: "invalid_point_value" });
        }
        const { data, error } = await admin.rpc("rewardloop_set_point_value_internal", {
          p_actor_user_id: user.id,
          p_tenant_id: tenant.id,
          p_point_value_minor_units: pointValue,
          p_point_value_currency: currency,
        });
        if (error) return reply(500, { ok: false, error: "point_value_save_failed" });
        if (!data || data.ok !== true) {
          return reply(data?.error === "forbidden" ? 403 : 400, {
            ok: false, error: data?.error || "point_value_save_failed"
          });
        }
        return reply(200, data);
      }

      if (action === "create_reward") {
        const slug = typeof body.slug === "string" ? body.slug.trim().toLowerCase() : "";
        const name = typeof body.name === "string" ? body.name.trim() : "";
        const nameHi = typeof body.name_hi === "string" ? body.name_hi.trim() : "";
        const description = typeof body.description === "string" ? body.description.trim() : "";
        const descriptionHi = typeof body.description_hi === "string" ? body.description_hi.trim() : "";
        const category = typeof body.category === "string" ? body.category.trim().toLowerCase() : "general";
        const pointsCost = Number(body.points_cost);
        const stockRaw = body.stock_quantity;
        const stockQuantity = stockRaw === undefined || stockRaw === null || stockRaw === "" ? null : Number(stockRaw);
        const sortOrder = body.sort_order === undefined ? 100 : Number(body.sort_order);
        const optionalTextInvalid = ["name_hi", "description", "description_hi"].some(key => body[key] != null && typeof body[key] !== "string");
        if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug) || slug.length > 80 || name.length < 2 || name.length > 160 ||
            nameHi.length > 160 || description.length > 2000 || descriptionHi.length > 2000 ||
            !/^[a-z][a-z0-9_-]{1,63}$/.test(category) || !Number.isSafeInteger(pointsCost) || pointsCost < 1 || pointsCost > 100000000 ||
            (stockQuantity !== null && (!Number.isSafeInteger(stockQuantity) || stockQuantity < 0)) ||
            !Number.isSafeInteger(sortOrder) || sortOrder < 0 || sortOrder > 100000 || optionalTextInvalid) {
          return reply(400, { ok: false, error: "invalid_reward_details" });
        }
        const { data, error } = await admin.rpc("rewardloop_create_reward_internal", {
          p_actor_user_id: user.id, p_tenant_id: tenant.id, p_slug: slug, p_name: name,
          p_name_hi: nameHi || null, p_description: description || null, p_description_hi: descriptionHi || null,
          p_category: category, p_points_cost: pointsCost, p_stock_quantity: stockQuantity, p_sort_order: sortOrder,
        });
        if (error) return reply(500, { ok: false, error: "reward_create_failed" });
        if (!data || data.ok !== true) {
          const status = data?.error === "forbidden" ? 403 : data?.error === "reward_slug_exists" ? 409 : 400;
          return reply(status, { ok: false, error: data?.error || "reward_create_failed" });
        }
        return reply(201, data);
      }

      if (action === "update_reward") {
        const rewardId = typeof body.reward_id === "string" ? body.reward_id : "";
        const name = typeof body.name === "string" ? body.name.trim() : "";
        const nameHi = typeof body.name_hi === "string" ? body.name_hi.trim() : "";
        const description = typeof body.description === "string" ? body.description.trim() : "";
        const descriptionHi = typeof body.description_hi === "string" ? body.description_hi.trim() : "";
        const category = typeof body.category === "string" ? body.category.trim().toLowerCase() : "general";
        const pointsCost = Number(body.points_cost);
        const stockRaw = body.stock_quantity;
        const stockQuantity = stockRaw === undefined || stockRaw === null || stockRaw === "" ? null : Number(stockRaw);
        const sortOrder = body.sort_order === undefined ? 100 : Number(body.sort_order);
        const optionalTextInvalid = ["name_hi", "description", "description_hi"].some(key => body[key] != null && typeof body[key] !== "string");
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(rewardId) ||
            name.length < 2 || name.length > 160 || nameHi.length > 160 || description.length > 2000 || descriptionHi.length > 2000 ||
            !/^[a-z][a-z0-9_-]{1,63}$/.test(category) || !Number.isSafeInteger(pointsCost) || pointsCost < 1 || pointsCost > 100000000 ||
            (stockQuantity !== null && (!Number.isSafeInteger(stockQuantity) || stockQuantity < 0)) ||
            !Number.isSafeInteger(sortOrder) || sortOrder < 0 || sortOrder > 100000 || optionalTextInvalid) {
          return reply(400, { ok: false, error: "invalid_reward_details" });
        }
        const { data, error } = await admin.rpc("rewardloop_update_reward_internal", {
          p_actor_user_id: user.id, p_tenant_id: tenant.id, p_reward_id: rewardId, p_name: name,
          p_name_hi: nameHi || null, p_description: description || null, p_description_hi: descriptionHi || null,
          p_category: category, p_points_cost: pointsCost, p_stock_quantity: stockQuantity, p_sort_order: sortOrder,
        });
        if (error) return reply(500, { ok: false, error: "reward_update_failed" });
        if (!data || data.ok !== true) {
          const status = data?.error === "forbidden" ? 403 : data?.error === "reward_not_found" ? 404 : 400;
          return reply(status, { ok: false, error: data?.error || "reward_update_failed" });
        }
        return reply(200, data);
      }

      if (action === "set_reward_status") {
        const rewardId = typeof body.reward_id === "string" ? body.reward_id : "";
        const active = body.active;
        const reason = typeof body.reason === "string" ? body.reason.trim().slice(0, 500) : "";
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{12}$/i.test(rewardId) ||
            typeof active !== "boolean" || (!active && reason.length < 5)) {
          return reply(400, { ok: false, error: "invalid_reward_status_request" });
        }
        const { data, error } = await admin.rpc("rewardloop_set_reward_status_internal", {
          p_actor_user_id: user.id, p_tenant_id: tenant.id, p_reward_id: rewardId, p_active: active, p_reason: reason || null,
        });
        if (error) return reply(500, { ok: false, error: "reward_status_update_failed" });
        if (!data || data.ok !== true) {
          const status = data?.error === "forbidden" ? 403 : data?.error === "reward_not_found" ? 404 :
            ["reward_out_of_stock", "demo_reward_not_activatable"].includes(data?.error) ? 409 : 400;
          return reply(status, { ok: false, error: data?.error || "reward_status_update_failed" });
        }
        return reply(200, data);
      }

      if (action === "update_product") {
        const productId = typeof body.product_id === "string" ? body.product_id : "";
        const name = typeof body.name === "string" ? body.name.trim() : "";
        const packSize = typeof body.pack_size === "string" ? body.pack_size.trim() : "";
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(productId) ||
            name.length < 2 || name.length > 160 || packSize.length > 80) {
          return reply(400, { ok: false, error: "invalid_product_details" });
        }
        const { data, error } = await admin.rpc("rewardloop_update_product_internal", {
          p_actor_user_id: user.id,
          p_tenant_id: tenant.id,
          p_product_id: productId,
          p_name: name,
          p_pack_size: packSize || null,
        });
        if (error) return reply(500, { ok: false, error: "product_update_failed" });
        if (!data || data.ok !== true) {
          const status = data?.error === "forbidden" ? 403 : data?.error === "product_not_found" ? 404 : 400;
          return reply(status, { ok: false, error: data?.error || "product_update_failed" });
        }
        return reply(200, data);
      }

      if (action === "set_product_status") {
        const productId = typeof body.product_id === "string" ? body.product_id : "";
        const active = body.active;
        const reason = typeof body.reason === "string" ? body.reason.trim().slice(0, 500) : "";
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(productId) ||
            typeof active !== "boolean" || (!active && reason.length < 5)) {
          return reply(400, { ok: false, error: "invalid_product_status_request" });
        }
        const { data, error } = await admin.rpc("rewardloop_set_product_status_internal", {
          p_actor_user_id: user.id,
          p_tenant_id: tenant.id,
          p_product_id: productId,
          p_active: active,
          p_reason: reason || null,
        });
        if (error) return reply(500, { ok: false, error: "product_status_update_failed" });
        if (!data || data.ok !== true) {
          const status = data?.error === "forbidden" ? 403 : data?.error === "product_not_found" ? 404 : 400;
          return reply(status, { ok: false, error: data?.error || "product_status_update_failed" });
        }
        return reply(200, data);
      }

      if (action === "create_product") {
        const sku = typeof body.sku === "string" ? body.sku.trim().toUpperCase() : "";
        const name = typeof body.name === "string" ? body.name.trim() : "";
        const packSize = typeof body.pack_size === "string" ? body.pack_size.trim() : "";
        if (!/^[A-Z0-9][A-Z0-9._/-]{0,63}$/.test(sku) ||
            name.length < 2 || name.length > 160 || packSize.length > 80) {
          return reply(400, { ok: false, error: "invalid_product_details" });
        }
        const { data, error } = await admin.rpc("rewardloop_create_product_internal", {
          p_actor_user_id: user.id,
          p_tenant_id: tenant.id,
          p_sku: sku,
          p_name: name,
          p_pack_size: packSize || null,
        });
        if (error) return reply(500, { ok: false, error: "product_create_failed" });
        if (!data || data.ok !== true) {
          const status = data?.error === "forbidden" ? 403 : data?.error === "sku_exists" ? 409 : 400;
          return reply(status, { ok: false, error: data?.error || "product_create_failed" });
        }
        return reply(201, data);
      }

      if (action === "admin_dashboard") {
        const pageSpecs = {
          partners: { key: "partners_page", size: 50 },
          campaigns: { key: "campaigns_page", size: 20 },
          products: { key: "products_page", size: 50 },
          rewards: { key: "rewards_page", size: 50 },
          batches: { key: "batches_page", size: 20 },
          redemptions: { key: "redemptions_page", size: 20 },
        } as const;

        const pages: Record<keyof typeof pageSpecs, number> = {
          partners: 0, campaigns: 0, products: 0, rewards: 0, batches: 0, redemptions: 0,
        };
        for (const [name, spec] of Object.entries(pageSpecs) as [keyof typeof pageSpecs, typeof pageSpecs[keyof typeof pageSpecs]][]) {
          const raw = body[spec.key];
          if (raw === undefined || raw === null || raw === "") continue;
          const value = Number(raw);
          if (!Number.isSafeInteger(value) || value < 0 || value > 10000) {
            return reply(400, { ok: false, error: "invalid_dashboard_page" });
          }
          pages[name] = value;
        }

        const rawPartnerQuery = typeof body.partner_query === "string" ? body.partner_query : "";
        // Restrict the search grammar before embedding it in PostgREST's OR filter.
        // Commas, parentheses, percent signs, backslashes and filter operators are excluded.
        const partnerQuery = rawPartnerQuery.replace(/[^A-Za-z0-9 +.@-]/g, "").trim().slice(0, 80);
        const partnerStatus = typeof body.partner_status === "string" ? body.partner_status : "all";
        if (!["all", "pending", "verified", "rejected", "suspended"].includes(partnerStatus)) {
          return reply(400, { ok: false, error: "invalid_partner_status" });
        }

        let partnersQuery = admin.from("partners")
          .select("id,display_name,phone_e164,role,verification_status,preferred_locale,created_at", { count: "exact" })
          .eq("tenant_id", tenant.id);
        if (partnerQuery) {
          partnersQuery = partnersQuery.or(`display_name.ilike.%${partnerQuery}%,phone_e164.ilike.%${partnerQuery}%`);
        }
        if (partnerStatus === "pending") {
          partnersQuery = partnersQuery.in("verification_status", ["pending", "unverified"]);
        } else if (partnerStatus !== "all") {
          partnersQuery = partnersQuery.eq("verification_status", partnerStatus);
        }
        partnersQuery = partnersQuery.order("created_at", { ascending: false }).order("id", { ascending: false })
          .range(pages.partners * pageSpecs.partners.size, (pages.partners + 1) * pageSpecs.partners.size - 1);

        const [partners, campaigns, products, rewards, batches, redemptions] = await Promise.all([
          partnersQuery,
          admin.from("campaigns")
            .select("id,name,status,starts_at,ends_at,budget_minor_units,currency,rules,created_at", { count: "exact" })
            .eq("tenant_id", tenant.id).order("created_at", { ascending: false }).order("id", { ascending: false })
            .range(pages.campaigns * pageSpecs.campaigns.size, (pages.campaigns + 1) * pageSpecs.campaigns.size - 1),
          admin.from("products")
            .select("id,sku,name,pack_size,active,created_at", { count: "exact" })
            .eq("tenant_id", tenant.id).order("name").order("id")
            .range(pages.products * pageSpecs.products.size, (pages.products + 1) * pageSpecs.products.size - 1),
          admin.from("rewards")
            .select("id,slug,name,name_hi,description,description_hi,category,points_cost,stock_quantity,active,is_demo,sort_order,created_at", { count: "exact" })
            .eq("tenant_id", tenant.id).order("sort_order").order("name").order("id")
            .range(pages.rewards * pageSpecs.rewards.size, (pages.rewards + 1) * pageSpecs.rewards.size - 1),
          admin.from("qr_issuance_batches")
            .select("id,product_id,campaign_id,requested_count,points_value,entitlement_role,status,created_at,completed_at", { count: "exact" })
            .eq("tenant_id", tenant.id).order("created_at", { ascending: false }).order("id", { ascending: false })
            .range(pages.batches * pageSpecs.batches.size, (pages.batches + 1) * pageSpecs.batches.size - 1),
          admin.from("redemptions")
            .select("id,partner_id,reward_id,points_cost,status,created_at,fulfilled_at", { count: "exact" })
            .eq("tenant_id", tenant.id).order("created_at", { ascending: false }).order("id", { ascending: false })
            .range(pages.redemptions * pageSpecs.redemptions.size, (pages.redemptions + 1) * pageSpecs.redemptions.size - 1),
        ]);
        if ([partners, campaigns, products, rewards, batches, redemptions].some(x => x.error)) {
          return reply(500, { ok: false, error: "admin_dashboard_load_failed" });
        }

        const redemptionRows = redemptions.data || [];
        const partnerIds = [...new Set(redemptionRows.map(r => r.partner_id))];
        const rewardIds = [...new Set(redemptionRows.map(r => r.reward_id))];
        const [redemptionPartners, redemptionRewards, metricsResult] = await Promise.all([
          admin.from("partners").select("id,display_name,phone_e164").eq("tenant_id", tenant.id)
            .in("id", partnerIds.length ? partnerIds : ["00000000-0000-0000-0000-000000000000"]),
          admin.from("rewards").select("id,name,name_hi,is_demo").eq("tenant_id", tenant.id)
            .in("id", rewardIds.length ? rewardIds : ["00000000-0000-0000-0000-000000000000"]),
          admin.rpc("rewardloop_admin_dashboard_metrics_internal", {
            p_actor_user_id: user.id,
            p_tenant_id: tenant.id,
          }),
        ]);
        if (redemptionPartners.error || redemptionRewards.error) {
          return reply(500, { ok: false, error: "admin_dashboard_enrichment_failed" });
        }
        if (metricsResult.error || !metricsResult.data || metricsResult.data.ok !== true) {
          return reply(500, { ok: false, error: "admin_dashboard_metrics_failed" });
        }

        const partnerById = new Map((redemptionPartners.data || []).map(p => [p.id, p]));
        const rewardById = new Map((redemptionRewards.data || []).map(r => [r.id, r]));
        const enrichedRedemptions = redemptionRows.map(r => ({
          ...r,
          partner_name: partnerById.get(r.partner_id)?.display_name || "Partner",
          partner_phone: partnerById.get(r.partner_id)?.phone_e164 || "",
          reward_name: rewardById.get(r.reward_id)?.name || "Reward",
          reward_is_demo: rewardById.get(r.reward_id)?.is_demo ?? false,
        }));

        const pagination = Object.fromEntries(
          (Object.keys(pageSpecs) as (keyof typeof pageSpecs)[]).map(name => [
            name,
            {
              page: pages[name],
              page_size: pageSpecs[name].size,
              total: ({
                partners: partners.count,
                campaigns: campaigns.count,
                products: products.count,
                rewards: rewards.count,
                batches: batches.count,
                redemptions: redemptions.count,
              })[name] ?? 0,
            },
          ]),
        );

        return reply(200, {
          ok: true,
          tenant,
          role: membership.role,
          capabilities: { product_management: true, reward_management: true, tenant_invitations: true, audit_log_viewer: true, fraud_case_management: true },
          metrics: metricsResult.data,
          pagination,
          partners: partners.data || [],
          campaigns: campaigns.data || [],
          products: products.data || [],
          rewards: rewards.data || [],
          batches: batches.data || [],
          redemptions: enrichedRedemptions,
        });
      }
      if (action === "verify_partner") {
        const partnerId = typeof body.partner_id === "string" ? body.partner_id : "";
        const status = typeof body.status === "string" ? body.status : "";
        const reason = typeof body.reason === "string" ? body.reason.trim().slice(0, 500) : "";
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(partnerId) || !["verified", "rejected", "suspended"].includes(status)) return reply(400, { ok: false, error: "invalid_verification_request" });
        const { data, error } = await admin.rpc("rewardloop_verify_partner_internal", { p_actor_user_id: user.id, p_tenant_id: tenant.id, p_partner_id: partnerId, p_new_status: status, p_reason: reason || null });
        if (error) return reply(500, { ok: false, error: "partner_verification_failed" });
        return reply(200, data && typeof data === "object" ? data : { ok: false, error: "unexpected_verification_response" });
      }
      if (action === "issue_qr_batch") {
        const campaignId = typeof body.campaign_id === "string" ? body.campaign_id : "";
        const productId = typeof body.product_id === "string" ? body.product_id : "";
        const count = Number(body.count), pointsValue = Number(body.points_value);
        const role = typeof body.entitlement_role === "string" ? body.entitlement_role : "farmer";
        const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
        if (!uuid.test(campaignId) || !uuid.test(productId) || !Number.isInteger(count) || count < 1 || count > 1000 || !Number.isInteger(pointsValue) || pointsValue < 1 || pointsValue > 1000000 || !["farmer", "retailer", "distributor"].includes(role)) return reply(400, { ok: false, error: "invalid_batch_request" });
        const { data, error } = await admin.rpc("rewardloop_issue_qr_batch_internal", { p_actor_user_id: user.id, p_tenant_id: tenant.id, p_campaign_id: campaignId, p_product_id: productId, p_count: count, p_points_value: pointsValue, p_entitlement_role: role });
        if (error) return reply(500, { ok: false, error: "qr_batch_issue_failed" });
        return reply(200, data && typeof data === "object" ? data : { ok: false, error: "unexpected_batch_response" });
      }
      if (action === "revoke_qr_batch") {
        const batchId = typeof body.batch_id === "string" ? body.batch_id : "";
        const reason = typeof body.reason === "string" ? body.reason.trim().slice(0, 500) : "";
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(batchId) || reason.length < 5) return reply(400, { ok: false, error: "invalid_revoke_request" });
        const { data, error } = await admin.rpc("rewardloop_revoke_qr_batch_internal", { p_actor_user_id: user.id, p_tenant_id: tenant.id, p_batch_id: batchId, p_reason: reason });
        if (error) return reply(500, { ok: false, error: "qr_batch_revoke_failed" });
        return reply(200, data && typeof data === "object" ? data : { ok: false, error: "unexpected_revoke_response" });
      }
      if (action === "create_campaign") {
        const name = typeof body.name === "string" ? body.name.trim().slice(0, 120) : "";
        const startsAt = typeof body.starts_at === "string" && body.starts_at ? new Date(body.starts_at) : null;
        const endsAt = typeof body.ends_at === "string" && body.ends_at ? new Date(body.ends_at) : null;
        const budget = Number(body.budget_minor_units);
        if (name.length < 3 || !Number.isSafeInteger(budget) || budget < 0 || budget > 1000000000000 ||
            (startsAt && !Number.isFinite(startsAt.getTime())) || (endsAt && !Number.isFinite(endsAt.getTime()))) {
          return reply(400, { ok: false, error: "invalid_campaign_details" });
        }
        const { data, error } = await admin.rpc("rewardloop_create_campaign_internal", {
          p_actor_user_id: user.id, p_tenant_id: tenant.id, p_name: name,
          p_starts_at: startsAt ? startsAt.toISOString() : null,
          p_ends_at: endsAt ? endsAt.toISOString() : null, p_budget_minor_units: budget
        });
        if (error) return reply(500, { ok: false, error: "campaign_create_failed" });
        return reply(200, data && typeof data === "object" ? data : { ok: false, error: "unexpected_campaign_response" });
      }
      if (action === "set_campaign_status") {
        const campaignId = typeof body.campaign_id === "string" ? body.campaign_id : "";
        const status = typeof body.status === "string" ? body.status : "";
        const reason = typeof body.reason === "string" ? body.reason.trim().slice(0, 500) : "";
        if (!/^[0-9a-f-]{36}$/i.test(campaignId) || !["active", "paused", "archived"].includes(status) || (status !== "active" && reason.length < 5)) {
          return reply(400, { ok: false, error: "invalid_campaign_status_request" });
        }
        const { data, error } = await admin.rpc("rewardloop_set_campaign_status_internal", {
          p_actor_user_id: user.id, p_tenant_id: tenant.id, p_campaign_id: campaignId, p_new_status: status, p_reason: reason || null
        });
        if (error) return reply(500, { ok: false, error: "campaign_status_update_failed" });
        return reply(200, data && typeof data === "object" ? data : { ok: false, error: "unexpected_campaign_response" });
      }
      if (action === "resolve_redemption") {
        const redemptionId = typeof body.redemption_id === "string" ? body.redemption_id : "";
        const status = typeof body.status === "string" ? body.status : "";
        const reason = typeof body.reason === "string" ? body.reason.trim().slice(0, 500) : "";
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(redemptionId) || !["fulfilled", "cancelled", "rejected"].includes(status) || (status !== "fulfilled" && reason.length < 5)) {
          return reply(400, { ok: false, error: "invalid_redemption_resolution" });
        }
        const { data, error } = await admin.rpc("rewardloop_resolve_redemption_internal", {
          p_actor_user_id: user.id,
          p_tenant_id: tenant.id,
          p_redemption_id: redemptionId,
          p_new_status: status,
          p_reason: reason || null,
        });
        if (error) return reply(500, { ok: false, error: "redemption_resolution_failed" });
        return reply(200, data && typeof data === "object" ? data : { ok: false, error: "unexpected_redemption_response" });
      }
    }

    return reply(400, { ok: false, error: "unknown_action" });
  } catch {
    // Avoid returning raw exception details or credentials to the client.
    return reply(500, { ok: false, error: "unexpected_server_error" });
  }
});