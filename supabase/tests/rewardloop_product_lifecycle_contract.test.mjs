import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const api = readFileSync(new URL("../functions/rewardloop-api/index.ts", import.meta.url), "utf8");
const admin = readFileSync(new URL("../../admin.js", import.meta.url), "utf8");
const migration = readFileSync(new URL("../migrations/20261022203000_audited_product_lifecycle.sql", import.meta.url), "utf8");

test("product lifecycle is routed through the common selected-tenant admin gate", () => {
  assert.match(api, /"create_product", "set_product_status", "update_product"\]\.includes\(action\)/);
  assert.match(api, /action === "set_product_status"/);
  assert.match(api, /admin\.rpc\("rewardloop_set_product_status_internal"/);
  assert.match(api, /p_actor_user_id:\s*user\.id/);
  assert.match(api, /p_tenant_id:\s*tenant\.id/);
});

test("product lifecycle preserves history and writes audit events", () => {
  assert.match(migration, /FOR UPDATE/);
  assert.match(migration, /product_deactivated/);
  assert.match(migration, /product_activated/);
  assert.match(migration, /length\(trim\(coalesce\(p_reason,''\)\)\) < 5/);
  assert.match(migration, /REVOKE ALL PRIVILEGES ON FUNCTION public\.rewardloop_set_product_status_internal/);
  assert.match(migration, /TO service_role/);
});

test("admin UI provides deactivate/reactivate controls and requires a reason for deactivation", () => {
  assert.match(admin, /Existing products/);
  assert.match(admin, /data-product-status/);
  assert.match(admin, /Reason for deactivating this product/);
  assert.match(admin, /call\("set_product_status"/);
});

test("product management UI stays hidden until the deployed API advertises the capability", () => {
  assert.match(api, /capabilities:\s*\{[^}]*product_management:\s*true[^}]*\}/);
  assert.match(admin, /data\.capabilities\?\.product_management===true/);
});
