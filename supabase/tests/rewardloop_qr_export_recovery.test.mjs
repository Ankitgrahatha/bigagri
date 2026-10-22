import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const admin = readFileSync(new URL("../../admin.js", import.meta.url), "utf8");

test("one-time QR tokens stay in memory for retry instead of being persisted", () => {
  assert.match(admin, /pendingQrExport=\{batch_id:String\(r\.batch_id\|\|"unknown"\),tenant_slug:selectedTenantSlug,expected_count:count,codes\}/);
  assert.match(admin, /function downloadPendingQrExport\(\)/);
  assert.match(admin, /document\.getElementById\("download-qr-export"\)\?\.addEventListener/);
  assert.doesNotMatch(admin, /localStorage\.(?:setItem|getItem)\([^)]*(?:qr|token)/i);
  assert.doesNotMatch(admin, /sessionStorage\.(?:setItem|getItem)\([^)]*(?:qr|token)/i);
});

test("QR issuance retains a recovery warning when the one-time API response is incomplete", () => {
  assert.match(admin, /codes\.length!==count/);
  assert.match(admin, /Do not reissue; reconcile batch/);
  assert.match(admin, /renderQrExportNotice/);
  assert.match(admin, /missing tokens cannot be recovered/i);
});

test("clearing an export requires an explicit confirmation", () => {
  assert.match(admin, /Confirm you have securely saved and verified the downloaded QR CSV/);
  assert.match(admin, /if\(!confirm\(prompt\)\)return;\s*pendingQrExport=null/);
});
