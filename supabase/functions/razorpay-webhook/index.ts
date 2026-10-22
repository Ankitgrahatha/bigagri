import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";
import { verifyRazorpayWebhookSignature } from "../_shared/razorpay_webhook.mjs";

const MAX_BODY_BYTES = 1024 * 1024;
const respond = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return respond(405, { ok: false, error: "method_not_allowed" });

  const declaredLength = Number(req.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > MAX_BODY_BYTES) {
    return respond(413, { ok: false, error: "payload_too_large" });
  }

  const webhookSecret = Deno.env.get("RAZORPAY_WEBHOOK_SECRET");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!webhookSecret || !supabaseUrl || !serviceRoleKey) {
    return respond(503, { ok: false, error: "service_not_configured" });
  }

  let rawBody: string;
  try {
    rawBody = await req.text();
  } catch {
    return respond(400, { ok: false, error: "invalid_body" });
  }
  if (new TextEncoder().encode(rawBody).byteLength > MAX_BODY_BYTES) {
    return respond(413, { ok: false, error: "payload_too_large" });
  }

  const signature = req.headers.get("x-razorpay-signature");
  const verified = await verifyRazorpayWebhookSignature(rawBody, signature, webhookSecret);
  if (!verified) return respond(401, { ok: false, error: "invalid_signature" });

  const providerEventId = req.headers.get("x-razorpay-event-id")?.trim() ?? "";
  if (
    providerEventId.length < 1 ||
    providerEventId.length > 255 ||
    /[\u0000-\u001f\u007f]/.test(providerEventId)
  ) {
    return respond(400, { ok: false, error: "invalid_event_id" });
  }

  let event: Record<string, unknown>;
  try {
    const parsed: unknown = JSON.parse(rawBody);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return respond(400, { ok: false, error: "invalid_event" });
    }
    event = parsed as Record<string, unknown>;
  } catch {
    return respond(400, { ok: false, error: "invalid_event" });
  }

  const eventType = typeof event.event === "string" ? event.event.trim() : "";
  if (eventType.length < 1 || eventType.length > 160) {
    return respond(400, { ok: false, error: "invalid_event" });
  }

  const db = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await db.rpc("record_saas_payment_webhook_event_internal", {
    p_provider_event_id: providerEventId,
    p_event_type: eventType,
    p_payload: event,
  });

  if (error) {
    // Do not log provider payloads, signatures, secrets, or payment/customer details.
    console.error("razorpay_webhook_receipt_failed", { code: error.code ?? "unknown" });
    return respond(503, { ok: false, error: "receipt_unavailable" });
  }

  const receipt = data as Record<string, unknown> | null;
  if (!receipt || receipt.ok !== true) {
    return respond(400, { ok: false, error: "invalid_event" });
  }

  // A duplicate event ID is an already-durably-received delivery; acknowledge it.
  // Subscription/entitlement mutation is intentionally handled by a later processor.
  return respond(200, { ok: true, duplicate: receipt.duplicate === true });
});
