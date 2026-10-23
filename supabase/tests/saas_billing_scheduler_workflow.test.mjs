import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const workflow = readFileSync(
  new URL("../../.github/workflows/rewardloop-billing-webhook-scheduler.yml", import.meta.url),
  "utf8",
);

test("billing scheduler runs at bounded cadence and can open an operator alert", () => {
  assert.match(workflow, /cron: "\*\/5 \* \* \* \*"/);
  assert.match(workflow, /workflow_dispatch:/);
  assert.match(workflow, /issues: write/);
  assert.match(workflow, /timeout-minutes: 3/);
});

test("billing scheduler uses a server-side secret and bounded processor request", () => {
  assert.match(workflow, /secrets\.RAZORPAY_PROCESSOR_SECRET/);
  assert.match(workflow, /x-processor-secret:/);
  assert.match(workflow, /--max-time 30/);
  assert.match(workflow, /functions\/v1\/process-razorpay-webhooks/);
  assert.doesNotMatch(workflow, /echo .*PROCESSOR_SECRET/);
});

test("billing scheduler validates aggregate health and deduplicates open alerts", () => {
  assert.match(workflow, /health_metrics_available/);
  assert.match(workflow, /exhausted_total/);
  assert.match(workflow, /oldest_unprocessed_age_seconds/);
  assert.match(workflow, /failed > 0 or exhausted > 0 or oldest_age > 300/);
  assert.match(workflow, /existing_alert\(\)/);
  assert.match(workflow, /do not add secrets or raw provider payloads/i);
});
