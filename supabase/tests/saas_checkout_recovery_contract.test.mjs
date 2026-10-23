import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
const migration = readFileSync(new URL("../migrations/20261023180000_saas_checkout_recovery_target.sql", import.meta.url), "utf8");
const endpoint = readFileSync(new URL("../functions/reconcile-razorpay-subscription/index.ts", import.meta.url), "utf8");
const ui = readFileSync(new URL("../../admin-billing.js", import.meta.url), "utf8");
const config = readFileSync(new URL("../config.toml", import.meta.url), "utf8");
test("recovery target is read-only, tenant scoped and super-admin only", () => {
  assert.match(migration, /m\.tenant_id = p_tenant_id[\s\S]*m\.user_id = p_actor_user_id[\s\S]*m\.status = 'active'[\s\S]*m\.role = 'super_admin'/i);
  assert.match(migration, /v_subscription\.status <> 'incomplete'/);
  assert.match(migration, /v_subscription\.provider_subscription_id IS NOT NULL/);
  assert.match(migration, /v_subscription\.created_at > now\(\) - interval '1 minute'/);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.get_saas_checkout_recovery_target_internal\(uuid,uuid,uuid\) TO service_role/i);
  assert.match(migration, /REVOKE ALL PRIVILEGES ON FUNCTION public\.get_saas_checkout_recovery_target_internal\(uuid,uuid,uuid\)[\s\S]*FROM PUBLIC, anon, authenticated/i);
});
test("recovery verifies provider identity, plan, local notes and status before binding", () => {
  assert.match(endpoint, /db\.auth\.getUser\(tokenMatch\[1\]\)/);
  assert.match(endpoint, /get_saas_checkout_recovery_target_internal/);
  assert.match(endpoint, /api\.razorpay\.com\/v1\/subscriptions/);
  assert.match(endpoint, /provider\.plan_id !== target\.expected_provider_plan_id/);
  assert.match(endpoint, /notes\.growta_subscription_id !== subscriptionId/);
  assert.match(endpoint, /notes\.growta_tenant_id !== tenantId/);
  assert.match(endpoint, /notes\.growta_checkout_key !== target\.idempotency_key/);
  assert.ok(endpoint.indexOf("provider.plan_id !== target.expected_provider_plan_id") < endpoint.indexOf("finalize_saas_checkout_internal"));
  assert.match(endpoint, /provider_subscription_not_found_keep_blocked/);
  assert.match(endpoint, /provider_subscription_status_requires_manual_review/);
  assert.match(endpoint, /req\.method === "OPTIONS"/);
  assert.match(endpoint, /ALLOWED_ORIGINS/);
  assert.match(config, /\[functions\.reconcile-razorpay-subscription\]\s*verify_jwt = true/);
});
test("billing portal exposes recovery only on the super-admin reconciliation queue", () => {
  assert.match(ui, /data-reconcile/);
  assert.match(ui, /reconcile-razorpay-subscription/);
  assert.match(ui, /tenant\?\.role === "super_admin"/);
  assert.match(ui, /Growta will verify its plan and private notes before binding/);
});
