import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const receiver = readFileSync(
  new URL("../functions/razorpay-webhook/index.ts", import.meta.url),
  "utf8",
);
const config = readFileSync(new URL("../config.toml", import.meta.url), "utf8");

test("receiver authenticates the raw request body before parsing JSON", () => {
  const rawBodyRead = receiver.indexOf("rawBody = await req.text()");
  const signatureCheck = receiver.indexOf("verifyRazorpayWebhookSignature(rawBody");
  const jsonParse = receiver.indexOf("JSON.parse(rawBody)");
  assert.ok(rawBodyRead >= 0);
  assert.ok(signatureCheck > rawBodyRead);
  assert.ok(jsonParse > signatureCheck);
  assert.match(receiver, /x-razorpay-signature/);
  assert.match(receiver, /x-razorpay-event-id/);
});

test("receiver bounds payload size and requires server-side secrets", () => {
  assert.match(receiver, /MAX_BODY_BYTES = 1024 \* 1024/);
  assert.match(receiver, /RAZORPAY_WEBHOOK_SECRET/);
  assert.match(receiver, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(receiver, /payload_too_large/);
});

test("receiver durably records receipts and acknowledges database errors with retryable status", () => {
  assert.match(receiver, /record_saas_payment_webhook_event_internal/);
  assert.match(receiver, /p_provider_event_id: providerEventId/);
  assert.match(receiver, /respond\(503, \{ ok: false, error: "receipt_unavailable" \}\)/);
  assert.match(receiver, /duplicate: receipt\.duplicate === true/);
});

test("webhook endpoint uses provider signature rather than JWT as its authentication", () => {
  assert.match(config, /\[functions\.razorpay-webhook\]\s*verify_jwt = false/);
  assert.doesNotMatch(receiver, /Access-Control-Allow-Origin/);
});

test("receiver does not log payloads, signatures, or secrets", () => {
  assert.match(receiver, /console\.error\("razorpay_webhook_receipt_failed", \{ code: error\.code \?\? "unknown" \}\)/);
  assert.doesNotMatch(receiver, /console\.(log|error|warn)\([^\n]*(rawBody|signature|webhookSecret|serviceRoleKey|payload)/i);
});
