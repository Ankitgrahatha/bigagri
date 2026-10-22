import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const api = readFileSync(new URL("../functions/rewardloop-api/index.ts", import.meta.url), "utf8");
const admin = readFileSync(new URL("../../admin.js", import.meta.url), "utf8");
const css = readFileSync(new URL("../../admin.css", import.meta.url), "utf8");

test("admin tenant context is derived only from active memberships for the authenticated user", () => {
  assert.match(api, /if \(action === "admin_tenants"\)/);
  assert.match(api, /\.from\("tenant_memberships"\)[\s\S]*?\.eq\("user_id", user\.id\)[\s\S]*?\.eq\("status", "active"\)[\s\S]*?\.in\("role", \["brand_admin", "super_admin"\]\)/);
  assert.match(api, /\.from\("tenants"\)[\s\S]*?\.in\("id", tenantIds\)[\s\S]*?\.eq\("status", "active"\)/);
});

test("admin operations validate the selected tenant slug and still enforce membership", () => {
  assert.match(api, /typeof body\.tenant_slug === "string" \? body\.tenant_slug\.trim\(\) : TENANT_SLUG/);
  assert.match(api, /invalid_tenant_context/);
  assert.match(api, /\.eq\("slug", requestedTenantSlug\)/);
  assert.match(api, /\.eq\("tenant_id", tenant\.id\)\.eq\("user_id", user\.id\).*?\.in\("role", \["brand_admin", "super_admin"\]\)/s);
});

test("admin UI selects only server-provided tenant memberships and sends selected context", () => {
  assert.match(admin, /call\("admin_tenants"\)/);
  assert.match(admin, /const ADMIN_SCOPED_ACTIONS = new Set/);
  assert.match(admin, /tenant_slug:selectedTenantSlug/);
  assert.match(admin, /id="admin-tenant-select"/);
  assert.match(admin, /selectedTenantSlug=event\.currentTarget\.value/);
  assert.match(css, /\.tenant-picker/);
});
