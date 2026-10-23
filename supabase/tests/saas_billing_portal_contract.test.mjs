import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
const migration = readFileSync(new URL("../migrations/20261023170000_saas_billing_portal_catalog.sql", import.meta.url), "utf8");
const endpoint = readFileSync(new URL("../functions/saas-billing-portal/index.ts", import.meta.url), "utf8");
const ui = readFileSync(new URL("../../admin-billing.js", import.meta.url), "utf8");
const html = readFileSync(new URL("../../admin-billing.html", import.meta.url), "utf8");
const config = readFileSync(new URL("../config.toml", import.meta.url), "utf8");
test("billing portal exposes only published plans and tenant-scoped subscription data", () => {
  assert.match(migration, /p\.status = 'published' AND pv\.published_at IS NOT NULL/i);
  assert.match(migration, /m\.tenant_id = p_tenant_id[\s\S]*m\.user_id = p_actor_user_id[\s\S]*m\.status = 'active'[\s\S]*m\.role IN/i);
  assert.match(migration, /WHERE s\.tenant_id = p_tenant_id[\s\S]*ORDER BY s\.created_at DESC/i);
  assert.match(migration, /REVOKE ALL PRIVILEGES ON FUNCTION public\.get_saas_billing_portal_internal\(uuid,uuid\)[\s\S]*FROM PUBLIC, anon, authenticated/i);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.get_saas_billing_portal_internal\(uuid,uuid\) TO service_role/i);
});
test("billing portal endpoint verifies the Supabase user and strict tenant-only request", () => {
  assert.match(endpoint, /db\.auth\.getUser\(tokenMatch\[1\]\)/i);
  assert.match(endpoint, /get_saas_billing_portal_internal/);
  assert.match(endpoint, /MAX_BODY_BYTES = 2048/);
  assert.match(endpoint, /Object\.keys\(body\)\.some\(\(key\) => key !== "tenant_id"\)/);
  assert.match(endpoint, /Cache-Control.*no-store/);
  assert.match(config, /\[functions\.saas-billing-portal\]\s*verify_jwt = true/);
});
test("billing UI reuses idempotency keys for retries and redirects only to provider checkout", () => {
  assert.match(ui, /create-razorpay-subscription/);
  assert.match(ui, /Idempotency-Key/);
  assert.match(ui, /sessionStorage\.getItem\(keyName\)/);
  assert.match(ui, /window\.location\.assign\(result\.data\.checkout_url\)/);
  assert.match(ui, /Do not retry with a new key/i);
  assert.match(ui, /saas-checkout-reconciliation/);
  assert.match(ui, /tenant\?\.role === "super_admin"/);
  assert.match(html, /name="robots" content="noindex,nofollow"/);
});
