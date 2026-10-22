import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(
  new URL("../migrations/20261023100000_saas_payment_webhook_inbox.sql", import.meta.url),
  "utf8",
);

test("webhook inbox is private and has provider-scoped event deduplication", () => {
  assert.match(migration, /CREATE TABLE private\.saas_payment_webhook_events/i);
  assert.match(migration, /UNIQUE \(provider, provider_event_id\)/i);
  assert.match(migration, /provider_event_id text NOT NULL/i);
  assert.match(migration, /CHECK \(provider = 'razorpay'\)/i);
});

test("webhook inbox only accepts structured payloads and verified receipts", () => {
  assert.match(migration, /payload jsonb NOT NULL/i);
  assert.match(migration, /jsonb_typeof\(payload\) = 'object'/i);
  assert.match(migration, /signature_verified_at timestamptz NOT NULL/i);
});

test("webhook inbox has constrained lifecycle and safe retry metadata", () => {
  assert.match(migration, /status IN \('received', 'processing', 'processed', 'failed'\)/i);
  assert.match(migration, /attempts integer NOT NULL DEFAULT 0 CHECK \(attempts >= 0\)/i);
  assert.match(migration, /status = 'processed' AND processed_at IS NOT NULL/i);
  assert.match(migration, /status <> 'processed' AND processed_at IS NULL/i);
  assert.match(migration, /last_error_code text/i);
  assert.doesNotMatch(migration, /last_error text/i);
});

test("webhook inbox denies client roles and grants only the service role", () => {
  assert.match(migration, /ENABLE ROW LEVEL SECURITY/i);
  assert.match(migration, /FORCE ROW LEVEL SECURITY/i);
  assert.match(migration, /REVOKE ALL PRIVILEGES ON TABLE private\.saas_payment_webhook_events\s+FROM PUBLIC, anon, authenticated/i);
  assert.match(migration, /GRANT ALL PRIVILEGES ON TABLE private\.saas_payment_webhook_events TO service_role/i);
  assert.doesNotMatch(migration, /CREATE POLICY/i);
});

test("webhook receipt RPC is idempotent and service-role-only", () => {
  assert.match(migration, /ON CONFLICT \(provider, provider_event_id\) DO NOTHING/i);
  assert.match(migration, /CREATE OR REPLACE FUNCTION private\.record_saas_payment_webhook_event/i);
  assert.match(migration, /CREATE OR REPLACE FUNCTION public\.record_saas_payment_webhook_event_internal/i);
  assert.match(migration, /REVOKE ALL PRIVILEGES ON FUNCTION public\.record_saas_payment_webhook_event_internal\(text,text,jsonb\)\s+FROM PUBLIC, anon, authenticated/i);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.record_saas_payment_webhook_event_internal\(text,text,jsonb\)\s+TO service_role/i);
});
