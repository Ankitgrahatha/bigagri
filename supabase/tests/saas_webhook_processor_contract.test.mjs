import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const processor = readFileSync(
  new URL("../migrations/20261023140000_saas_webhook_event_processor.sql", import.meta.url),
  "utf8",
);
const inbox = readFileSync(
  new URL("../migrations/20261023100000_saas_payment_webhook_inbox.sql", import.meta.url),
  "utf8",
);
const worker = readFileSync(
  new URL("../functions/process-razorpay-webhooks/index.ts", import.meta.url),
  "utf8",
);
const config = readFileSync(new URL("../config.toml", import.meta.url), "utf8");

test("processor serializes event and subscription changes and exposes only service-role RPCs", () => {
  assert.match(processor, /WHERE id = p_event_id\s+FOR UPDATE/i);
  assert.match(processor, /FOR UPDATE OF s/i);
  assert.match(processor, /REVOKE ALL PRIVILEGES ON FUNCTION public\.process_saas_payment_webhook_event_internal\(uuid\)\s+FROM PUBLIC, anon, authenticated/i);
  assert.match(processor, /GRANT EXECUTE ON FUNCTION public\.process_saas_payment_webhook_event_internal\(uuid\)\s+TO service_role/i);
});

test("successful charges require captured payment, provider plan, tenant subscription, amount and currency binding", () => {
  assert.match(processor, /v_payment_status <> 'captured'/i);
  assert.match(processor, /v_provider_plan_id <> v_expected_plan_id/i);
  assert.match(processor, /v_payment_entity->>'subscription_id'/i);
  assert.match(processor, /v_payment_amount <> v_expected_amount/i);
  assert.match(processor, /v_payment_currency <> v_subscription\.currency/i);
  assert.match(processor, /current_period_end = v_period_end/i);
  assert.match(processor, /INSERT INTO private\.saas_payment_attempts/i);
  assert.match(processor, /provider_payment_id IS NULL[\s\S]*status = 'initiated'/i);
  assert.match(processor, /SET provider_payment_id = v_provider_payment_id,[\s\S]*status = 'captured'/i);
  assert.match(processor, /SET provider_payment_id = v_provider_payment_id,[\s\S]*status = 'failed'/i);
});

test("processor handles out-of-order events and does not reactivate terminal subscriptions", () => {
  assert.match(processor, /v_event_time < v_subscription\.last_provider_event_created_at/i);
  assert.match(processor, /v_subscription\.status IN \('canceled', 'expired'\)/i);
  assert.match(processor, /processing_result = 'stale'/i);
  assert.match(processor, /processing_result = 'ignored'/i);
});

test("batch worker uses row locks and caps retries for poison events", () => {
  assert.match(processor, /FOR UPDATE SKIP LOCKED/i);
  assert.match(processor, /e\.attempts < 8/i);
  assert.match(processor, /last_attempt_at < now\(\) - \(interval '1 minute' \* LEAST\(e\.attempts, 5\)\)/i);
  assert.match(processor, /'exhausted', v_exhausted/i);
  assert.match(processor, /p_limit < 1 OR p_limit > 100/i);
  assert.match(processor, /process_saas_payment_webhook_event\(v_event_id\)/i);
});

test("processor worker requires a dedicated secret and never logs payment payloads", () => {
  assert.match(worker, /RAZORPAY_PROCESSOR_SECRET/);
  assert.match(worker, /x-processor-secret/);
  assert.match(worker, /constantTimeEqual\(suppliedSecret, expectedSecret\)/i);
  assert.match(worker, /process_saas_payment_webhook_batch_internal/);
  assert.match(worker, /async function readLimitedBody\(req: Request, maxBytes: number\)/);
  assert.match(worker, /readLimitedBody\(req, 4096\)/);
  assert.match(worker, /bodyBytes\.byteLength > 0/);
  assert.match(worker, /Object\.keys\(input\)\.some/);
  assert.match(worker, /exhausted: result\.exhausted/);
  assert.match(config, /\[functions\.process-razorpay-webhooks\]\s*verify_jwt = false/);
  assert.match(worker, /console\.error\("razorpay_webhook_batch_failed", \{ code: error\.code \?\? "unknown" \}\)/);
  assert.doesNotMatch(worker, /console\.(log|error|warn)\([^\n]*(secret|payload|payment)/i);
});

test("inbox only marks processed events with an explicit outcome", () => {
  assert.match(inbox, /status = 'processed' AND processed_at IS NOT NULL AND processing_result IS NOT NULL/i);
  assert.match(inbox, /status <> 'processed' AND processed_at IS NULL AND processing_result IS NULL/i);
});

const healthMigration = readFileSync(
  new URL("../migrations/20261023190000_saas_payment_webhook_health.sql", import.meta.url),
  "utf8",
);

test("webhook worker exports aggregate queue health without payload data", () => {
  for (const field of [
    "'received', count(*) FILTER",
    "'retryable_failed', count(*) FILTER",
    "'exhausted', count(*) FILTER",
    "'stale_processing', count(*) FILTER",
    "'oldest_unprocessed_age_seconds'",
    "REVOKE ALL PRIVILEGES ON FUNCTION public.get_saas_payment_webhook_health_internal()",
    "GRANT EXECUTE ON FUNCTION public.get_saas_payment_webhook_health_internal() TO service_role",
  ]) assert.ok(healthMigration.includes(field), `missing health metric contract: ${field}`);
  assert.ok(worker.includes("get_saas_payment_webhook_health_internal"));
  assert.ok(worker.includes("health_metrics_available"));
  assert.ok(worker.includes("oldest_unprocessed_age_seconds: health.oldest_unprocessed_age_seconds"));
  assert.doesNotMatch(worker, /console\.(log|error|warn)\([^\n]*(payload|payment|secret)/i);
});
