import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const api = readFileSync(new URL("../functions/rewardloop-api/index.ts", import.meta.url), "utf8");
const admin = readFileSync(new URL("../../admin.js", import.meta.url), "utf8");
const migration = readFileSync(new URL("../migrations/20261021201000_admin_dashboard_metrics.sql", import.meta.url), "utf8");

test("dashboard list queries are tenant-scoped, ordered, count-exact, and range paginated", () => {
  const block = api.slice(api.indexOf('if (action === "admin_dashboard")'), api.indexOf('if (action === "verify_partner")'));
  assert.match(block, /\.select\("id,display_name,phone_e164,role,verification_status,preferred_locale,created_at", \{ count: "exact" \}\)/);
  assert.match(block, /\.select\("id,name,status,starts_at,ends_at,budget_minor_units,currency,rules,created_at", \{ count: "exact" \}\)/);
  assert.match(block, /\.select\("id,sku,name,pack_size,active,created_at", \{ count: "exact" \}\)/);
  assert.match(block, /\.range\(pages\.partners \* pageSpecs\.partners\.size/);
  assert.match(block, /\.range\(pages\.redemptions \* pageSpecs\.redemptions\.size/);
  assert.match(block, /\.eq\("tenant_id", tenant\.id\)/);
  assert.match(block, /page_size:\s*pageSpecs\[name\]\.size/);
});

test("dashboard global KPIs come from a separately authorized aggregate RPC", () => {
  assert.match(api, /admin\.rpc\("rewardloop_admin_dashboard_metrics_internal"/);
  assert.match(api, /p_actor_user_id:\s*user\.id/);
  assert.match(api, /p_tenant_id:\s*tenant\.id/);
  assert.match(migration, /partners_pending/);
  assert.match(migration, /qr_codes_issued_total/);
  assert.match(migration, /redemptions_open/);
  assert.match(migration, /m\.role IN \('brand_admin', 'super_admin'\)/);
  assert.match(migration, /m\.status = 'active'/);
});

test("admin frontend keeps page state and does not present current-page length as global totals", () => {
  assert.match(admin, /const pages=\{partners:0,products:0,campaigns:0,batches:0,redemptions:0\}/);
  assert.match(admin, /partners_page:pages\.partners/);
  assert.match(admin, /data\.metrics\?\.partners_total/);
  assert.match(admin, /data\.metrics\?\.redemptions_open/);
  for (const name of ["partners", "products", "campaigns", "batches", "redemptions"]) {
    assert.ok(admin.includes('pager("' + name + '"'), "missing pager for " + name);
  }
  assert.match(admin, /Export current page/);
  assert.match(admin, /current-page partner CSV/);
});
