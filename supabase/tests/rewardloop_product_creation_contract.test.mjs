import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const api = readFileSync(new URL("../functions/rewardloop-api/index.ts", import.meta.url), "utf8");
const migration = readFileSync(new URL("../migrations/20261022200000_audited_product_creation.sql", import.meta.url), "utf8");

test("product creation is an authenticated admin API action routed through the privileged RPC", () => {
  assert.match(api, /"set_point_value",\s*"create_product"/);
  assert.match(api, /action === "create_product"/);
  assert.match(api, /admin\.rpc\("rewardloop_create_product_internal"/);
  assert.match(api, /p_actor_user_id:\s*user\.id/);
  assert.match(api, /p_tenant_id:\s*tenant\.id/);
  assert.doesNotMatch(api, /from\("products"\)\.insert/);
});

test("product RPC validates admin membership, tenant status, SKU uniqueness and audit logging", () => {
  assert.match(migration, /m\.role IN \('brand_admin', 'super_admin'\)/);
  assert.match(migration, /t\.status = 'active'/);
  assert.match(migration, /EXCEPTION WHEN unique_violation/);
  assert.match(migration, /'product_created'/);
  assert.match(migration, /REVOKE ALL PRIVILEGES ON FUNCTION public\.rewardloop_create_product_internal/);
  assert.match(migration, /TO service_role/);
});
