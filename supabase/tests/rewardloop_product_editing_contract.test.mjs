import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const api=readFileSync(new URL("../functions/rewardloop-api/index.ts",import.meta.url),"utf8");
const admin=readFileSync(new URL("../../admin.js",import.meta.url),"utf8");
const migration=readFileSync(new URL("../migrations/20261022210000_audited_product_editing.sql",import.meta.url),"utf8");

test("product metadata updates use the selected tenant and privileged RPC",()=>{
 assert.match(api,/"set_product_status", "update_product"\]\.includes\(action\)/);
 assert.match(api,/action === "update_product"/);
 assert.match(api,/admin\.rpc\("rewardloop_update_product_internal"/);
 assert.match(api,/p_actor_user_id:\s*user\.id/);
 assert.match(api,/p_tenant_id:\s*tenant\.id/);
});

test("product SKU is not accepted as mutable input and changes are audited",()=>{
 assert.match(migration,/SET name=v_name,pack_size=v_pack_size/);
 assert.doesNotMatch(migration,/SET sku=/i);
 assert.match(migration,/'product_updated'/);
 assert.match(migration,/REVOKE ALL PRIVILEGES ON FUNCTION public\.rewardloop_update_product_internal/);
 assert.match(migration,/TO service_role/);
});

test("admin UI offers product editing while clearly keeping SKU fixed",()=>{
 assert.match(admin,/data-product-edit/);
 assert.match(admin,/SKU remains unchanged/);
 assert.match(admin,/call\("update_product"/);
});
