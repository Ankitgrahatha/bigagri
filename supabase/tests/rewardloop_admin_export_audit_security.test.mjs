import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const api = readFileSync(new URL("../functions/rewardloop-api/index.ts", import.meta.url), "utf8");
const admin = readFileSync(new URL("../../admin.js", import.meta.url), "utf8");

test("CSV export audit action shares the authenticated tenant-admin gate", () => {
  const actionList = api.indexOf('"admin_record_export"');
  const membershipCheck = api.indexOf('.eq("tenant_id", tenant.id).eq("user_id", user.id)', api.indexOf('if (["admin_dashboard"'));
  const handler = api.indexOf('if (action === "admin_record_export")');
  assert.ok(actionList >= 0);
  assert.ok(membershipCheck >= 0 && handler > membershipCheck);
  assert.match(admin, /"admin_record_export"/);
});

test("export audit accepts only known export types and bounded page metadata", () => {
  const start = api.indexOf('if (action === "admin_record_export")');
  const end = api.indexOf('if (action === "set_point_value")', start);
  const handler = api.slice(start, end);
  assert.match(handler, /\["partners", "redemptions"\]\.includes\(exportType\)/);
  assert.match(handler, /rowCount < 0 \|\| rowCount > 100/);
  assert.match(handler, /page < 0 \|\| page > 10000/);
  assert.match(handler, /\.from\("audit_logs"\)\.insert/);
  assert.match(handler, /tenant_id: tenant\.id/);
  assert.match(handler, /actor_user_id: user\.id/);
  assert.match(handler, /action: "admin_export_csv_requested"/);
  assert.match(handler, /after_data: \{ export_type: exportType, row_count: rowCount, page \}/);
  assert.doesNotMatch(handler, /phone_e164|display_name|email|exported_rows|body\.rows/);
  assert.match(handler, /admin_export_audit_failed/);
});

test("CSV downloads are blocked if the server cannot audit the export request", () => {
  const partner = admin.slice(admin.indexOf('const exportPartners='), admin.indexOf('const verifyHandler='));
  const redemption = admin.slice(admin.indexOf('const exportRedemptions='), admin.indexOf('root.querySelectorAll("[data-revoke]")'));
  assert.ok(partner.indexOf('await call("admin_record_export"') < partner.indexOf("downloadCsv("));
  assert.ok(redemption.indexOf('await call("admin_record_export"') < redemption.indexOf("downloadCsv("));
  assert.match(partner, /catch\(error\)\{toast\("Export was not started because audit logging failed:/);
  assert.match(redemption, /catch\(error\)\{toast\("Export was not started because audit logging failed:/);
});
