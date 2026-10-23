import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(
  new URL("../migrations/20261023110000_saas_plans_and_tenant_subscriptions.sql", import.meta.url),
  "utf8",
);

test("SaaS plan prices and entitlements are versioned with validated values", () => {
  assert.match(migration, /CREATE TABLE private\.saas_plans/i);
  assert.match(migration, /CREATE TABLE private\.saas_plan_versions/i);
  assert.match(migration, /UNIQUE \(plan_id, version_no\)/i);
  assert.match(migration, /currency text NOT NULL CHECK \(currency ~ '\^\[A-Z\]\{3\}\$'\)/i);
  assert.match(migration, /monthly_amount_minor bigint NOT NULL CHECK \(monthly_amount_minor >= 0\)/i);
  assert.match(migration, /yearly_amount_minor bigint NOT NULL CHECK \(yearly_amount_minor >= 0\)/i);
  assert.match(migration, /monthly_provider_plan_id text/i);
  assert.match(migration, /yearly_provider_plan_id text/i);
  assert.match(migration, /published_at IS NULL OR[\s\S]*monthly_provider_plan_id IS NOT NULL AND yearly_provider_plan_id IS NOT NULL/i);
  assert.match(migration, /jsonb_typeof\(entitlements\) = 'object'/i);
  assert.match(migration, /jsonb_typeof\(usage_limits\) = 'object'/i);
});

test("published plan versions are protected from updates and deletion", () => {
  assert.match(migration, /CREATE OR REPLACE FUNCTION private\.prevent_published_saas_plan_version_mutation/i);
  assert.match(migration, /IF OLD\.published_at IS NOT NULL THEN/i);
  assert.match(migration, /published SaaS plan versions are immutable/i);
  assert.match(migration, /BEFORE UPDATE OR DELETE ON private\.saas_plan_versions/i);
});

test("tenant subscriptions enforce one current subscription and provider id uniqueness", () => {
  assert.match(migration, /tenant_id uuid NOT NULL REFERENCES public\.tenants\(id\)/i);
  assert.match(migration, /status IN \('incomplete', 'trialing', 'active', 'past_due', 'paused', 'canceled', 'expired'\)/i);
  assert.match(migration, /billing_interval text NOT NULL CHECK \(billing_interval IN \('monthly', 'yearly'\)\)/i);
  assert.match(migration, /saas_tenant_subscription_one_current_idx/i);
  assert.match(migration, /WHERE status IN \('trialing', 'active', 'past_due', 'paused'\)/i);
  assert.match(migration, /saas_tenant_subscription_provider_id_idx/i);
  assert.match(migration, /current_period_end > current_period_start/i);
  assert.match(migration, /status = 'canceled' AND canceled_at IS NOT NULL/i);
});

test("billing tables are private and unavailable to client roles", () => {
  assert.equal((migration.match(/ENABLE ROW LEVEL SECURITY/g) ?? []).length, 3);
  assert.equal((migration.match(/FORCE ROW LEVEL SECURITY/g) ?? []).length, 3);
  assert.match(migration, /REVOKE ALL PRIVILEGES ON TABLE\s+private\.saas_plans,\s+private\.saas_plan_versions,\s+private\.saas_tenant_subscriptions\s+FROM PUBLIC, anon, authenticated/i);
  assert.match(migration, /GRANT ALL PRIVILEGES ON TABLE\s+private\.saas_plans,\s+private\.saas_plan_versions,\s+private\.saas_tenant_subscriptions\s+TO service_role/i);
});
