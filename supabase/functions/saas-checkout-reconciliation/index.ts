import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";

const MAX_BODY_BYTES = 2048;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DEFAULT_ALLOWED_ORIGINS = ["https://bigagri.vercel.app"];
const ALLOWED_ORIGINS = new Set([
  ...DEFAULT_ALLOWED_ORIGINS,
  ...(Deno.env.get("ALLOWED_ORIGINS") ?? "").split(",").map((value) => value.trim()).filter(Boolean),
]);
const CORS_HEADERS = {
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, idempotency-key",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
};
function respond(status: number, body: Record<string, unknown>, origin?: string | null) {
  const headers = new Headers(CORS_HEADERS);
  if (origin && ALLOWED_ORIGINS.has(origin)) headers.set("Access-Control-Allow-Origin", origin);
  return new Response(JSON.stringify(body), { status, headers });
}

async function readLimitedBody(req: Request): Promise<Uint8Array | null> {
  const reader = req.body?.getReader();
  if (!reader) return new Uint8Array();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > MAX_BODY_BYTES) {
        await reader.cancel().catch(() => {});
        return null;
      }
      chunks.push(value);
    }
  } catch {
    return null;
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin");
  const reply = (status: number, body: Record<string, unknown>) => respond(status, body, origin);
  if (req.method === "OPTIONS") {
    if (!origin || !ALLOWED_ORIGINS.has(origin)) return reply(403, { ok: false, error: "origin_not_allowed" });
    return new Response(null, { status: 204, headers: { ...CORS_HEADERS, "Access-Control-Allow-Origin": origin } });
  }
  if (origin && !ALLOWED_ORIGINS.has(origin)) return reply(403, { ok: false, error: "origin_not_allowed" });
  if (req.method !== "POST") return reply(405, { ok: false, error: "method_not_allowed" });
  const authorization = req.headers.get("authorization") ?? "";
  const tokenMatch = /^Bearer\s+(.+)$/i.exec(authorization);
  if (!tokenMatch) return reply(401, { ok: false, error: "authentication_required" });

  const declaredLength = Number(req.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > MAX_BODY_BYTES) {
    return reply(413, { ok: false, error: "payload_too_large" });
  }
  const bytes = await readLimitedBody(req);
  if (!bytes) return reply(413, { ok: false, error: "payload_too_large_or_unreadable" });

  let body: unknown;
  try {
    body = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    return reply(400, { ok: false, error: "invalid_request" });
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return reply(400, { ok: false, error: "invalid_request" });
  }

  const input = body as Record<string, unknown>;
  const tenantId = typeof input.tenant_id === "string" ? input.tenant_id : "";
  const minAge = input.min_age_minutes === undefined ? 10 : input.min_age_minutes;
  if (!UUID_RE.test(tenantId) || !Number.isInteger(minAge) || Number(minAge) < 1 || Number(minAge) > 1440
      || Object.keys(input).some((key) => !["tenant_id", "min_age_minutes"].includes(key))) {
    return reply(400, { ok: false, error: "invalid_request" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) return reply(503, { ok: false, error: "service_not_configured" });

  const db = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await db.auth.getUser(tokenMatch[1]);
  if (authError || !authData.user) return reply(401, { ok: false, error: "invalid_session" });

  const { data, error } = await db.rpc("list_saas_checkout_reconciliation_internal", {
    p_actor_user_id: authData.user.id,
    p_tenant_id: tenantId,
    p_min_age_minutes: Number(minAge),
  });
  if (error) {
    console.error("saas_checkout_reconciliation_failed", { code: error.code ?? "unknown" });
    return reply(503, { ok: false, error: "reconciliation_unavailable" });
  }

  const result = data as Record<string, unknown> | null;
  if (!result || result.ok !== true) {
    const code = typeof result?.error === "string" ? result.error : "reconciliation_failed";
    return reply(code === "forbidden" ? 403 : 400, { ok: false, error: code });
  }
  return reply(200, { ok: true, checkouts: result.checkouts });
});
