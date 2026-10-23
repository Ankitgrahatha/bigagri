import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const api = readFileSync(new URL("../functions/rewardloop-api/index.ts", import.meta.url), "utf8");
const admin = readFileSync(new URL("../../admin.js", import.meta.url), "utf8");

test("audit viewer is behind the shared authenticated tenant-admin authorization gate", () => {
  const actionList = api.indexOf('"admin_audit_logs"');
  const membershipCheck = api.indexOf('.eq("tenant_id", tenant.id).eq("user_id", user.id)', api.indexOf('if (["admin_dashboard"'));
  const handler = api.indexOf('if (action === "admin_audit_logs")');
  assert.ok(actionList >= 0);
  assert.ok(membershipCheck >= 0 && handler > membershipCheck);
});

test("audit API is tenant-filtered, paginated, and excludes sensitive before/after payloads", () => {
  const start = api.indexOf('if (action === "admin_audit_logs")');
  const end = api.indexOf('if (action === "admin_record_export")', start);
  const handler = api.slice(start, end);
  assert.match(handler, /\.eq\("tenant_id", tenant\.id\)/);
  assert.match(handler, /\.range\(rawPage \* pageSize, \(rawPage \+ 1\) \* pageSize - 1\)/);
  assert.match(handler, /count: "exact"/);
  assert.match(handler, /order\("created_at", \{ ascending: false \}\)/);
  assert.doesNotMatch(handler, /before_data|after_data|metadata|phone_e164|email/);
});

test("audit UI is capability-gated for backward compatibility and uses server pagination", () => {
  assert.match(api, /capabilities: \{ product_management: true, reward_management: true, tenant_invitations: true, audit_log_viewer: true, fraud_case_management: true \}/);
  assert.match(admin, /if\(data\.capabilities\?\.audit_log_viewer\)/);
  assert.match(admin, /call\("admin_audit_logs",\{tenant_slug:selectedTenantSlug,audit_page:pages\.audit\}\)/);
  assert.match(admin, /Recent audit activity/);
  assert.match(admin, /pager\("audit",data\.pagination\?\.audit\)/);
});
