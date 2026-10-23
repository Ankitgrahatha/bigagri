import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";

const MAX_BODY_BYTES = 2048;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const respond = (status: number, body: Record<string, unknown>) => new Response(JSON.stringify(body), {
  status, headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
});
async function readLimitedBody(req: Request): Promise<Uint8Array | null> {
  const reader = req.body?.getReader();
  if (!reader) return new Uint8Array();
  const chunks: Uint8Array[] = []; let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read(); if (done) break;
      total += value.byteLength;
      if (total > MAX_BODY_BYTES) { await reader.cancel().catch(() => {}); return null; }
      chunks.push(value);
    }
  } catch { return null; } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(total); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return bytes;
}
Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return respond(405, { ok: false, error: "method_not_allowed" });
  const tokenMatch = /^Bearer\s+(.+)$/i.exec(req.headers.get("authorization") ?? "");
  if (!tokenMatch) return respond(401, { ok: false, error: "authentication_required" });
  const length = Number(req.headers.get("content-length") ?? "0");
  if (Number.isFinite(length) && length > MAX_BODY_BYTES) return respond(413, { ok: false, error: "payload_too_large" });
  const bytes = await readLimitedBody(req);
  if (!bytes) return respond(413, { ok: false, error: "payload_too_large_or_unreadable" });
  let input: unknown;
  try { input = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)); }
  catch { return respond(400, { ok: false, error: "invalid_request" }); }
  if (!input || typeof input !== "object" || Array.isArray(input)) return respond(400, { ok: false, error: "invalid_request" });
  const body = input as Record<string, unknown>;
  const tenantId = typeof body.tenant_id === "string" ? body.tenant_id : "";
  if (!UUID_RE.test(tenantId) || Object.keys(body).some((key) => key !== "tenant_id")) return respond(400, { ok: false, error: "invalid_request" });
  const url = Deno.env.get("SUPABASE_URL"); const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return respond(503, { ok: false, error: "service_not_configured" });
  const db = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await db.auth.getUser(tokenMatch[1]);
  if (authError || !authData.user) return respond(401, { ok: false, error: "invalid_session" });
  const { data, error } = await db.rpc("get_saas_billing_portal_internal", { p_actor_user_id: authData.user.id, p_tenant_id: tenantId });
  if (error) { console.error("saas_billing_portal_failed", { code: error.code ?? "unknown" }); return respond(503, { ok: false, error: "billing_portal_unavailable" }); }
  const result = data as Record<string, unknown> | null;
  if (!result || result.ok !== true) {
    const code = typeof result?.error === "string" ? result.error : "billing_portal_failed";
    return respond(code === "forbidden" ? 403 : 400, { ok: false, error: code });
  }
  return respond(200, { ok: true, plans: result.plans, subscription: result.subscription ?? null });
});
