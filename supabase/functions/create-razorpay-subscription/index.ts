import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";

const MAX_BODY_BYTES = 4096;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const IDEMPOTENCY_RE = /^[A-Za-z0-9._:-]{16,128}$/;
const respond = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });

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

function parseCycleCount(value: string | undefined): number | null {
  if (!value || !/^[0-9]{1,3}$/.test(value)) return null;
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= 1 && parsed <= 100 ? parsed : null;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return respond(405, { ok: false, error: "method_not_allowed" });
  const declaredLength = Number(req.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > MAX_BODY_BYTES) {
    return respond(413, { ok: false, error: "payload_too_large" });
  }

  const authorization = req.headers.get("authorization") ?? "";
  const tokenMatch = /^Bearer\s+(.+)$/i.exec(authorization);
  const idempotencyKey = req.headers.get("idempotency-key")?.trim() ?? "";
  if (!tokenMatch) return respond(401, { ok: false, error: "authentication_required" });
  if (!IDEMPOTENCY_RE.test(idempotencyKey)) {
    return respond(400, { ok: false, error: "invalid_idempotency_key" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const razorpayKeyId = Deno.env.get("RAZORPAY_KEY_ID");
  const razorpayKeySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
  if (!supabaseUrl || !serviceRoleKey || !razorpayKeyId || !razorpayKeySecret) {
    return respond(503, { ok: false, error: "service_not_configured" });
  }

  const bodyBytes = await readLimitedBody(req);
  if (!bodyBytes) return respond(413, { ok: false, error: "payload_too_large_or_unreadable" });
  let body: unknown;
  try {
    body = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bodyBytes));
  } catch {
    return respond(400, { ok: false, error: "invalid_request" });
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return respond(400, { ok: false, error: "invalid_request" });
  }

  const input = body as Record<string, unknown>;
  const tenantId = typeof input.tenant_id === "string" ? input.tenant_id : "";
  const planVersionId = typeof input.plan_version_id === "string" ? input.plan_version_id : "";
  const billingInterval = input.billing_interval;
  if (!UUID_RE.test(tenantId) || !UUID_RE.test(planVersionId)
      || (billingInterval !== "monthly" && billingInterval !== "yearly")
      || Object.keys(input).some((key) => !["tenant_id", "plan_version_id", "billing_interval"].includes(key))) {
    return respond(400, { ok: false, error: "invalid_request" });
  }

  const totalCount = parseCycleCount(
    billingInterval === "monthly"
      ? Deno.env.get("RAZORPAY_MONTHLY_TOTAL_COUNT")
      : Deno.env.get("RAZORPAY_YEARLY_TOTAL_COUNT"),
  );
  if (totalCount === null) return respond(503, { ok: false, error: "billing_cycle_policy_not_configured" });

  const db = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await db.auth.getUser(tokenMatch[1]);
  if (authError || !authData.user) return respond(401, { ok: false, error: "invalid_session" });

  const { data: reservationData, error: reservationError } = await db.rpc("reserve_saas_checkout_internal", {
    p_actor_user_id: authData.user.id,
    p_tenant_id: tenantId,
    p_plan_version_id: planVersionId,
    p_billing_interval: billingInterval,
    p_idempotency_key: idempotencyKey,
  });
  if (reservationError) {
    console.error("saas_checkout_reservation_failed", { code: reservationError.code ?? "unknown" });
    return respond(503, { ok: false, error: "checkout_reservation_unavailable" });
  }

  const reservation = reservationData as Record<string, unknown> | null;
  if (!reservation || reservation.ok !== true) {
    const code = typeof reservation?.error === "string" ? reservation.error : "checkout_reservation_failed";
    if (code === "forbidden") return respond(403, { ok: false, error: code });
    if (code === "plan_unavailable" || code === "plan_not_configured") return respond(422, { ok: false, error: code });
    if (code === "checkout_reconciliation_required") {
      return respond(409, { ok: false, error: code, subscription_id: reservation?.subscription_id });
    }
    if (code === "pending_checkout_exists" || code === "idempotency_key_conflict" || code === "subscription_already_exists") {
      return respond(409, { ok: false, error: code });
    }
    return respond(400, { ok: false, error: code });
  }

  if (reservation.reused === true) {
    return respond(200, {
      ok: true,
      reused: true,
      subscription_id: reservation.subscription_id,
      checkout_url: reservation.checkout_url,
    });
  }
  if (reservation.created !== true
      || typeof reservation.subscription_id !== "string"
      || typeof reservation.provider_plan_id !== "string"
      || typeof reservation.amount_minor !== "number"
      || typeof reservation.currency !== "string") {
    return respond(503, { ok: false, error: "checkout_reservation_invalid_response" });
  }

  let providerResponse: Response;
  try {
    providerResponse = await fetch("https://api.razorpay.com/v1/subscriptions", {
      method: "POST",
      headers: {
        "Authorization": `Basic ${btoa(`${razorpayKeyId}:${razorpayKeySecret}`)}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        plan_id: reservation.provider_plan_id,
        total_count: totalCount,
        quantity: 1,
        customer_notify: 1,
        notes: {
          growta_tenant_id: tenantId,
          growta_subscription_id: reservation.subscription_id,
          growta_checkout_key: idempotencyKey,
        },
      }),
      signal: AbortSignal.timeout(15000),
    });
  } catch {
    // A network timeout is ambiguous: Razorpay may have created the subscription.
    // Keep the reservation blocked and require provider reconciliation; never retry
    // creation automatically with a new provider subscription.
    return respond(503, {
      ok: false,
      error: "checkout_reconciliation_required",
      subscription_id: reservation.subscription_id,
    });
  }

  if (!providerResponse.ok) {
    if (providerResponse.status >= 400 && providerResponse.status < 500) {
      const { error } = await db.rpc("fail_saas_checkout_reservation_internal", {
        p_subscription_id: reservation.subscription_id,
        p_provider_http_status: providerResponse.status,
      });
      if (error) {
        console.error("saas_checkout_rejection_persist_failed", { code: error.code ?? "unknown" });
        return respond(503, { ok: false, error: "checkout_reconciliation_required", subscription_id: reservation.subscription_id });
      }
      return respond(422, { ok: false, error: "provider_rejected_checkout" });
    }
    return respond(503, {
      ok: false,
      error: "checkout_reconciliation_required",
      subscription_id: reservation.subscription_id,
    });
  }

  let provider: Record<string, unknown>;
  try {
    const parsed: unknown = await providerResponse.json();
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("invalid response");
    provider = parsed as Record<string, unknown>;
  } catch {
    return respond(503, { ok: false, error: "checkout_reconciliation_required", subscription_id: reservation.subscription_id });
  }

  const providerSubscriptionId = typeof provider.id === "string" ? provider.id : "";
  const checkoutUrl = typeof provider.short_url === "string" ? provider.short_url : "";
  if (!providerSubscriptionId || !/^https:\/\/(rzp\.io|razorpay\.com)\//.test(checkoutUrl)) {
    return respond(503, { ok: false, error: "checkout_reconciliation_required", subscription_id: reservation.subscription_id });
  }

  const { data: finalizedData, error: finalizeError } = await db.rpc("finalize_saas_checkout_internal", {
    p_subscription_id: reservation.subscription_id,
    p_provider_subscription_id: providerSubscriptionId,
    p_checkout_url: checkoutUrl,
  });
  const finalized = finalizedData as Record<string, unknown> | null;
  if (finalizeError || !finalized || finalized.ok !== true) {
    console.error("saas_checkout_finalize_failed", { code: finalizeError?.code ?? "state_conflict" });
    // Do not return the checkout URL unless its provider ID is durably bound to the
    // local subscription; the webhook processor depends on this association.
    return respond(503, { ok: false, error: "checkout_reconciliation_required", subscription_id: reservation.subscription_id });
  }

  return respond(201, {
    ok: true,
    reused: false,
    subscription_id: reservation.subscription_id,
    checkout_url: checkoutUrl,
  });
});
