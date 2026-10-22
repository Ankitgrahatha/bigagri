import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const app = readFileSync(new URL("../../app.js", import.meta.url), "utf8");
const api = readFileSync(new URL("../functions/rewardloop-api/index.ts", import.meta.url), "utf8");

test("storefront selects a tenant by public slug while keeping the current tenant as default", () => {
  assert.match(app, /DEFAULT_TENANT_SLUG\s*=\s*"growta-rewardloop"/);
  assert.match(app, /new URLSearchParams\(window\.location\.search\)\.get\("tenant"\)/);
  assert.match(app, /function storefrontRedirectUrl/);
  assert.match(app, /emailRedirectTo:storefrontRedirectUrl\(\)/);
  assert.match(app, /storefrontRedirectUrl\(\{ auth: "reset" \}\)/);
  assert.match(app, /public_catalog_enabled/);
  assert.match(app, /data\.public_catalog_enabled !== true/);
});

test("profile writes send the selected tenant and API validates public catalog opt-in", () => {
  assert.equal((app.match(/api\("profile", \{ tenant_slug: TENANT_SLUG/g) || []).length, 2);
  assert.match(api, /const requestedTenantSlug = typeof body\.tenant_slug === "string" \? body\.tenant_slug\.trim\(\) : TENANT_SLUG/);
  assert.match(api, /tenant_slug_invalid/);
  assert.match(api, /public_catalog_enabled/);
  assert.match(api, /tenant\.public_catalog_enabled !== true/);
  assert.match(api, /\.eq\("tenant_id", tenant\.id\)\.eq\("user_id", user\.id\)/);
});
