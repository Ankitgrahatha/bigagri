import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(
  new URL("../migrations/20261023160000_saas_checkout_reconciliation_queue.sql", import.meta.url),
  "utf8",
);
const endpoint = readFileSync(
  new URL("../functions/saas-checkout-reconciliation/index.ts", import.meta.url),
  "utf8",
);
const config = readFileSync(new URL("../config.toml", import.meta.url), "utf8");

test("reconciliation queue requires active tenant super-admin membership and bounded age", () => {
  assert.match(migration, /m\.tenant_id = p_tenant_id[\s\S]*m\.user_id = p_actor_user_id[\s\S]*m\.status = 'active'[\s\S]*m\.role = 'super_admin'::public\.partner_role/i);
  assert.match(migration, /p_min_age_minutes < 1 OR p_min_age_minutes > 1440/i);
  assert.match(migration, /s\.status = 'incomplete'/i);
  assert.match(migration, /s\.provider_subscription_id IS NULL/i);
});

test("reconciliation endpoint validates session and never mutates payment state", () => {
  assert.match(endpoint, /db\.auth\.getUser\(tokenMatch\[1\]\)/i);
  assert.match(endpoint, /list_saas_checkout_reconciliation_internal/);
  assert.match(endpoint, /Cache-Control.*no-store/);
  assert.doesNotMatch(endpoint, /finalize_saas_checkout|fail_saas_checkout|UPDATE private\.saas_/i);
  assert.match(config, /\[functions\.saas-checkout-reconciliation\]\s*verify_jwt = true/);
});

test("reconciliation RPC is service-role-only", () => {
  assert.match(migration, /REVOKE ALL PRIVILEGES ON FUNCTION public\.list_saas_checkout_reconciliation_internal\(uuid,uuid,integer\)\s+FROM PUBLIC, anon, authenticated/i);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.list_saas_checkout_reconciliation_internal\(uuid,uuid,integer\)\s+TO service_role/i);
});
