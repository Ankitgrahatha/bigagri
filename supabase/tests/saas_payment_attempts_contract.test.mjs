import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(
  new URL("../migrations/20261023130000_saas_payment_attempts.sql", import.meta.url),
  "utf8",
);

test("payment attempts are idempotent per tenant and provider", () => {
  assert.match(migration, /CREATE TABLE private\.saas_payment_attempts/i);
  assert.match(migration, /UNIQUE \(tenant_id, provider, idempotency_key\)/i);
  assert.match(migration, /saas_payment_attempts_provider_order_idx/i);
  assert.match(migration, /saas_payment_attempts_provider_payment_idx/i);
});

test("payment attempts constrain amount, currency, state, and financial timestamps", () => {
  assert.match(migration, /amount_minor bigint NOT NULL CHECK \(amount_minor > 0\)/i);
  assert.match(migration, /currency text NOT NULL CHECK \(currency ~ '\^\[A-Z\]\{3\}\$'\)/i);
  assert.match(migration, /status IN \('initiated', 'authorized', 'captured', 'failed', 'refunded', 'partially_refunded'\)/i);
  assert.match(migration, /status = 'captured' AND captured_at IS NOT NULL/i);
  assert.match(migration, /status <> 'failed' OR failure_code IS NOT NULL/i);
  assert.match(migration, /status IN \('refunded', 'partially_refunded'\) AND refunded_at IS NOT NULL/i);
});

test("payment attempt records are tenant-scoped and inaccessible to client roles", () => {
  assert.match(migration, /tenant_id uuid NOT NULL REFERENCES public\.tenants\(id\)/i);
  assert.match(migration, /subscription_id uuid REFERENCES private\.saas_tenant_subscriptions\(id\)/i);
  assert.match(migration, /ENABLE ROW LEVEL SECURITY/i);
  assert.match(migration, /FORCE ROW LEVEL SECURITY/i);
  assert.match(migration, /REVOKE ALL PRIVILEGES ON TABLE private\.saas_payment_attempts\s+FROM PUBLIC, anon, authenticated/i);
  assert.match(migration, /GRANT ALL PRIVILEGES ON TABLE private\.saas_payment_attempts TO service_role/i);
});
