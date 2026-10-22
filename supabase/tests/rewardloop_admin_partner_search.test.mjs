import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const admin = readFileSync(new URL("../../admin.js", import.meta.url), "utf8");
const api = readFileSync(new URL("../functions/rewardloop-api/index.ts", import.meta.url), "utf8");

test("partner search and status are sent with the tenant-scoped dashboard request", () => {
  assert.match(admin, /call\("admin_dashboard",\{tenant_slug:selectedTenantSlug,partner_query:partnerQuery,partner_status:partnerStatus,/);
  assert.match(admin, /pages\.partners=0;await refresh\(\)/);
});

test("partner search input is bounded and strips PostgREST filter grammar", () => {
  assert.match(api, /rawPartnerQuery/);
  assert.ok(api.includes('rawPartnerQuery.replace(/[^A-Za-z0-9 +.@-]/g, "").trim().slice(0, 80)'));
  assert.match(api, /A-Za-z0-9/);
  assert.match(api, /slice\(0, 80\)/);
  assert.match(api, /partnersQuery\.or\(/);
  assert.match(api, /display_name\.ilike\.%\$\{partnerQuery\}%,phone_e164\.ilike\.%\$\{partnerQuery\}%/);
});

test("partner status values are validated and pending includes legacy unverified profiles", () => {
  assert.match(api, /\["all", "pending", "verified", "rejected", "suspended"\]\.includes\(partnerStatus\)/);
  assert.match(api, /partnersQuery\.in\("verification_status", \["pending", "unverified"\]\)/);
  assert.match(api, /invalid_partner_status/);
});

test("partner filtering happens before pagination so totals and pages match filters", () => {
  assert.ok(api.indexOf("partnersQuery = partnersQuery.in") < api.indexOf('partnersQuery = partnersQuery.order'));
  assert.match(api, /partnersQuery\.order\("created_at", \{ ascending: false \}\)/);
  assert.match(api, /partnersQuery,\s*admin\.from\("campaigns"\)/);
});

test("the admin UI lets the operator submit a global search and re-query on status changes", () => {
  assert.match(admin, /id="partner-search-submit"/);
  assert.match(admin, /partnerSearch\.addEventListener\("keydown"/);
  assert.match(admin, /partnerStatusSelect\.addEventListener\("change",async\(\)=>\{partnerStatus=partnerStatusSelect\.value;pages\.partners=0;await refresh\(\)\}\)/);
  assert.match(admin, /partnerStatus==="pending"\?\["pending","unverified"\]\.includes\(p\.verification_status\)/);
});
