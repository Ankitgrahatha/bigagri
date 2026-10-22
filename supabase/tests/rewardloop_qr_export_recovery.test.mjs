import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const admin = readFileSync(new URL("../../admin.js", import.meta.url), "utf8");

test("one-time QR tokens stay in memory for retry instead of being persisted", () => {
  assert.ok(admin.includes('pendingQrExport={batch_id:String(r.batch_id||"unknown"),tenant_slug:selectedTenantSlug,expected_count:count,codes,complete}'));
  assert.ok(admin.includes("function downloadPendingQrExport()"));
  assert.ok(admin.includes('document.getElementById("download-qr-export")?.addEventListener'));
  assert.doesNotMatch(admin, /localStorage\.(?:setItem|getItem)\([^)]*(?:qr|token)/i);
  assert.doesNotMatch(admin, /sessionStorage\.(?:setItem|getItem)\([^)]*(?:qr|token)/i);
});

test("QR issuance validates token payload completeness and warns against reissuing", () => {
  assert.ok(admin.includes('codes.length===count&&codes.every(c=>c&&typeof c.qr_id==="string"&&typeof c.token==="string"&&c.token.length>=16'));
  assert.ok(admin.includes('if(!complete)toast("QR export response is incomplete or invalid'));
  assert.ok(admin.includes("renderQrExportNotice"));
  assert.ok(admin.includes("Do not reissue; reconcile batch"));
  assert.ok(admin.includes("Secure or explicitly clear the previous one-time QR export before issuing another batch."));
  assert.ok(admin.includes("missing tokens cannot be recovered"));
});

test("clearing an export requires explicit confirmation", () => {
  assert.ok(admin.includes("Confirm you have securely saved and verified the downloaded QR CSV"));
  assert.ok(admin.includes("const complete=pendingQrExport.complete===true;"));
  assert.ok(admin.includes("if(!confirm(prompt))return;"));
  assert.ok(admin.includes("pendingQrExport=null;draw()"));
});
