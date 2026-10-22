import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(
  new URL("../migrations/20261023120000_saas_entitlement_resolver.sql", import.meta.url),
  "utf8",
);

test("entitlement resolution requires an active tenant membership", () => {
  assert.match(migration, /m\.tenant_id = p_tenant_id/i);
  assert.match(migration, /m\.user_id = p_actor_user_id/i);
  assert.match(migration, /m\.status = 'active'/i);
  assert.match(migration, /'error', 'forbidden'/i);
});

test("entitlements fail closed for missing, expired, unpaid, or unpublished subscriptions", () => {
  assert.match(migration, /'active', false, 'status', 'none'/i);
  assert.match(migration, /v_subscription\.published_at IS NOT NULL/i);
  assert.match(migration, /v_subscription\.current_period_end > now\(\)/i);
  assert.match(migration, /v_subscription\.trial_end > now\(\)/i);
  assert.match(migration, /'active', false/i);
  assert.match(migration, /v_subscription\.status = 'past_due'/i);
});

test("current subscription state takes precedence over incomplete checkout attempts", () => {
  assert.match(migration, /ORDER BY CASE WHEN s\.status IN \('trialing', 'active', 'past_due', 'paused'\) THEN 0 ELSE 1 END/i);
});

test("entitlement resolver exposes no client-callable privileged RPC", () => {
  assert.match(migration, /REVOKE ALL PRIVILEGES ON FUNCTION public\.resolve_saas_tenant_entitlements_internal\(uuid,uuid\)\s+FROM PUBLIC, anon, authenticated/i);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.resolve_saas_tenant_entitlements_internal\(uuid,uuid\)\s+TO service_role/i);
});
