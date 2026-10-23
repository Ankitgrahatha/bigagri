import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(new URL("../migrations/20261023200000_tenant_scoped_fraud_case_workflow.sql", import.meta.url), "utf8");
const api = readFileSync(new URL("../functions/rewardloop-api/index.ts", import.meta.url), "utf8");
const admin = readFileSync(new URL("../../admin.js", import.meta.url), "utf8");
const workflow = readFileSync(new URL("../../.github/workflows/rewardloop-production-release.yml", import.meta.url), "utf8");
const behavior = readFileSync(new URL("rewardloop_fraud_case_workflow_behavior.test.sql", import.meta.url), "utf8");

test("fraud case storage is tenant-bound and direct client access is revoked", () => {
  assert.match(migration, /CREATE TABLE public\.fraud_cases/);
  assert.match(migration, /tenant_id uuid NOT NULL REFERENCES public\.tenants/);
  assert.match(migration, /ENABLE ROW LEVEL SECURITY/);
  assert.match(migration, /REVOKE ALL PRIVILEGES ON TABLE public\.fraud_cases FROM PUBLIC, anon, authenticated/);
  assert.match(migration, /GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public\.fraud_cases TO service_role/);
  assert.match(migration, /fraud_cases_status_check/);
  assert.match(migration, /fraud_cases_severity_check/);
});

test("database RPCs enforce active tenant-admin membership and tenant-bound linked records", () => {
  assert.match(migration, /m\.status='active' AND m\.role IN \('brand_admin','super_admin'\)/);
  assert.match(migration, /partner_not_found/);
  assert.match(migration, /claim_not_found/);
  assert.match(migration, /scan_event_not_found/);
  assert.match(migration, /assignee_not_authorized/);
  assert.match(migration, /fraud_case_terminal/);
  assert.match(migration, /resolution_details_required/);
  assert.match(migration, /tenant_inactive/);
  assert.match(migration, /fraud_case_opened/);
  assert.match(migration, /fraud_case_updated/);
});

test("API routes use authenticated tenant context, bounded inputs and the privileged RPCs", () => {
  assert.match(api, /admin_fraud_cases: \{ limit: 30, windowSeconds: 60 \}/);
  assert.match(api, /create_fraud_case: \{ limit: 10, windowSeconds: 60 \}/);
  assert.match(api, /update_fraud_case: \{ limit: 20, windowSeconds: 60 \}/);
  assert.match(api, /rewardloop_create_fraud_case_internal/);
  assert.match(api, /rewardloop_update_fraud_case_internal/);
  assert.match(api, /\.eq\("tenant_id", tenant\.id\)/);
  assert.match(api, /fraud_case_management: true/);
});

test("admin UI exposes a manual, audited case lifecycle without asserting automated fraud verdicts", () => {
  assert.match(admin, /Risk &amp; fraud cases/);
  assert.match(admin, /A case is not an automated fraud verdict/);
  assert.match(admin, /create_fraud_case/);
  assert.match(admin, /update_fraud_case/);
  assert.match(admin, /resolution notes/i);
  assert.match(admin, /fraudCaseStatus/);
  assert.match(admin, /openAdminDialog\(\{title:\"Resolve risk case\"/);
  assert.match(admin, /confirmAdminAction\(\{title:\"Update risk case\"/);
  assert.doesNotMatch(admin, /\b(?:window\.)?prompt\s*\(/);
  assert.doesNotMatch(admin, /\b(?:window\.)?confirm\s*\(/);
});

test("controlled production release explicitly allowlists the fraud workflow migration", () => {
  assert.match(workflow, /20261023200000/);
  assert.match(readFileSync(new URL("../../.github/workflows/rewardloop-claim-replay-db.yml", import.meta.url), "utf8"), /rewardloop_fraud_case_workflow_behavior\.test\.sql/);
  assert.match(behavior, /cross-tenant case creation was not rejected/);
  assert.match(behavior, /terminal case was reopened/);
  assert.match(behavior, /case open\/investigate\/resolve audit count mismatch/);
});
