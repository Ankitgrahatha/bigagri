import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";
const MAX_BODY_BYTES = 2048;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const PROVIDER_ID_RE = /^sub_[A-Za-z0-9]{4,80}$/;
const DEFAULT_ALLOWED_ORIGINS = ["https://bigagri.vercel.app", "https://growta-rewardloop.vercel.app"];
const ALLOWED_ORIGINS = new Set([...DEFAULT_ALLOWED_ORIGINS, ...(Deno.env.get("ALLOWED_ORIGINS") ?? "").split(",").map(v => v.trim()).filter(Boolean)]);
const CORS_HEADERS = { "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS", "Vary": "Origin", "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" };
function respond(status: number, body: Record<string, unknown>, origin?: string | null) {
  const headers = new Headers(CORS_HEADERS);
  if (origin && ALLOWED_ORIGINS.has(origin)) headers.set("Access-Control-Allow-Origin", origin);
  return new Response(JSON.stringify(body), { status, headers });
}
async function readLimitedBody(req: Request): Promise<Uint8Array | null> {
  const reader = req.body?.getReader(); if (!reader) return new Uint8Array();
  const chunks: Uint8Array[] = []; let total = 0;
  try { while (true) { const { done, value } = await reader.read(); if (done) break; total += value.byteLength; if (total > MAX_BODY_BYTES) { await reader.cancel().catch(() => {}); return null; } chunks.push(value); } }
  catch { return null; } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(total); let offset = 0; for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; } return bytes;
}
const allowedCheckoutUrl = (value: unknown): value is string => typeof value === "string" && /^https:\/\/(?:rzp\.io|razorpay\.com)\//i.test(value);
Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin"); const reply = (status: number, body: Record<string, unknown>) => respond(status, body, origin);
  if (req.method === "OPTIONS") { if (!origin || !ALLOWED_ORIGINS.has(origin)) return reply(403, { ok: false, error: "origin_not_allowed" }); return new Response(null, { status: 204, headers: { ...CORS_HEADERS, "Access-Control-Allow-Origin": origin } }); }
  if (origin && !ALLOWED_ORIGINS.has(origin)) return reply(403, { ok: false, error: "origin_not_allowed" });
  if (req.method !== "POST") return reply(405, { ok: false, error: "method_not_allowed" });
  const tokenMatch = /^Bearer\s+(.+)$/i.exec(req.headers.get("authorization") ?? "");
  if (!tokenMatch) return reply(401, { ok: false, error: "authentication_required" });
  const length = Number(req.headers.get("content-length") ?? "0"); if (Number.isFinite(length) && length > MAX_BODY_BYTES) return reply(413, { ok: false, error: "payload_too_large" });
  const bytes = await readLimitedBody(req); if (!bytes) return reply(413, { ok: false, error: "payload_too_large_or_unreadable" });
  let body: unknown; try { body = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)); } catch { return reply(400, { ok: false, error: "invalid_request" }); }
  if (!body || typeof body !== "object" || Array.isArray(body)) return reply(400, { ok: false, error: "invalid_request" });
  const input = body as Record<string, unknown>;
  const tenantId = typeof input.tenant_id === "string" ? input.tenant_id : "";
  const subscriptionId = typeof input.subscription_id === "string" ? input.subscription_id : "";
  const providerSubscriptionId = typeof input.provider_subscription_id === "string" ? input.provider_subscription_id : "";
  if (!UUID_RE.test(tenantId) || !UUID_RE.test(subscriptionId) || !PROVIDER_ID_RE.test(providerSubscriptionId) || Object.keys(input).some(k => !["tenant_id", "subscription_id", "provider_subscription_id"].includes(k))) return reply(400, { ok: false, error: "invalid_request" });
  const supabaseUrl = Deno.env.get("SUPABASE_URL"); const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const razorpayKeyId = Deno.env.get("RAZORPAY_KEY_ID"); const razorpaySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
  if (!supabaseUrl || !serviceRoleKey || !razorpayKeyId || !razorpaySecret) return reply(503, { ok: false, error: "service_not_configured" });
  const db = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await db.auth.getUser(tokenMatch[1]);
  if (authError || !authData.user) return reply(401, { ok: false, error: "invalid_session" });
  const { data: targetData, error: targetError } = await db.rpc("get_saas_checkout_recovery_target_internal", { p_actor_user_id: authData.user.id, p_tenant_id: tenantId, p_subscription_id: subscriptionId });
  if (targetError) { console.error("checkout_recovery_target_failed", { code: targetError.code ?? "unknown" }); return reply(503, { ok: false, error: "reconciliation_unavailable" }); }
  const target = targetData as Record<string, unknown> | null;
  if (!target || target.ok !== true) { const code = typeof target?.error === "string" ? target.error : "checkout_not_recoverable"; return reply(code === "forbidden" ? 403 : code === "checkout_too_recent" ? 409 : 400, { ok: false, error: code }); }

  let providerResponse: Response;
  try {
    providerResponse = await fetch(`https://api.razorpay.com/v1/subscriptions/${encodeURIComponent(providerSubscriptionId)}`, {
      method: "GET",
      headers: { Authorization: `Basic ${btoa(`${razorpayKeyId}:${razorpaySecret}`)}`, Accept: "application/json" },
      signal: AbortSignal.timeout(8000),
    });
  } catch { return reply(502, { ok: false, error: "provider_lookup_unavailable" }); }
  if (!providerResponse.ok) {
    console.error("checkout_recovery_provider_lookup_failed", { status: providerResponse.status });
    return reply(providerResponse.status === 404 ? 409 : 502, { ok: false, error: providerResponse.status === 404 ? "provider_subscription_not_found_keep_blocked" : "provider_lookup_failed_keep_blocked" });
  }
  let provider: Record<string, unknown>;
  try { const value = await providerResponse.json(); if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("invalid provider object"); provider = value as Record<string, unknown>; }
  catch { return reply(502, { ok: false, error: "provider_response_invalid" }); }
  const notes = provider.notes && typeof provider.notes === "object" && !Array.isArray(provider.notes) ? provider.notes as Record<string, unknown> : {};
  if (provider.id !== providerSubscriptionId || provider.plan_id !== target.expected_provider_plan_id || notes.growta_subscription_id !== subscriptionId || notes.growta_tenant_id !== tenantId || notes.growta_checkout_key !== target.idempotency_key) {
    console.error("checkout_recovery_provider_mismatch", { provider_subscription_id: providerSubscriptionId, local_subscription_id: subscriptionId });
    return reply(409, { ok: false, error: "provider_subscription_mismatch_keep_blocked" });
  }
  const providerStatus = typeof provider.status === "string" ? provider.status : "unknown";
  if (!["created", "authenticated", "active", "pending"].includes(providerStatus)) return reply(409, { ok: false, error: "provider_subscription_status_requires_manual_review", provider_status: providerStatus });
  if (!allowedCheckoutUrl(provider.short_url)) return reply(409, { ok: false, error: "provider_checkout_url_missing_keep_blocked" });
  const { data: finalizeData, error: finalizeError } = await db.rpc("finalize_saas_checkout_internal", { p_subscription_id: subscriptionId, p_provider_subscription_id: providerSubscriptionId, p_checkout_url: provider.short_url });
  if (finalizeError) { console.error("checkout_recovery_finalize_failed", { code: finalizeError.code ?? "unknown" }); return reply(503, { ok: false, error: "reconciliation_persist_failed_keep_blocked" }); }
  const finalized = finalizeData as Record<string, unknown> | null;
  if (!finalized || finalized.ok !== true) { const code = typeof finalized?.error === "string" ? finalized.error : "reconciliation_persist_failed"; return reply(409, { ok: false, error: code }); }
  return reply(200, { ok: true, subscription_id: subscriptionId, provider_subscription_id: providerSubscriptionId, provider_status: providerStatus, checkout_url: provider.short_url });
});
