import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const sql = readFileSync(new URL("rewardloop_admin_rpc_tenant_isolation.test.sql", import.meta.url), "utf8");
const api = readFileSync(new URL("../functions/rewardloop-api/index.ts", import.meta.url), "utf8");

test("RPC isolation integration matrix covers all privileged admin operations", () => {
  for (const rpc of [
    "rewardloop_create_campaign_internal",
    "rewardloop_issue_qr_batch_internal",
    "rewardloop_revoke_qr_batch_internal",
    "rewardloop_verify_partner_internal",
    "rewardloop_set_campaign_status_internal",
    "rewardloop_resolve_redemption_internal",
  ]) assert.ok(sql.includes(rpc), "missing integration coverage for " + rpc);
  assert.match(sql, /cross-tenant campaign creation was not denied/);
  assert.match(sql, /cross-tenant product\/campaign batch issuance was not denied/);
  assert.match(sql, /cross-tenant batch revocation was not denied/);
  assert.match(sql, /cross-tenant partner verification was not denied/);
  assert.match(sql, /cross-tenant campaign lifecycle change was not denied/);
  assert.match(sql, /cross-tenant redemption resolution was not denied/);
  assert.match(sql, /tenant B QR status/);
  assert.match(sql, /tenant B redemption status/);
});

test("main admin route has a centralized active-membership gate before privileged admin actions", () => {
  const start = api.indexOf('if (["admin_dashboard"');
  const end = api.indexOf('if (action === "admin_dashboard")', start);
  assert.ok(start >= 0 && end > start);
  const gate = api.slice(start, end);
  assert.match(gate, /tenant_memberships/);
  assert.match(gate, /user\.id/);
  assert.match(gate, /status", "active"/);
  assert.match(gate, /brand_admin", "super_admin/);
});
