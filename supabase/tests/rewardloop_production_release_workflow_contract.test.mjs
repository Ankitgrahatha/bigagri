import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const workflow=readFileSync(new URL("../../.github/workflows/rewardloop-production-release.yml",import.meta.url),"utf8");
const runbook=readFileSync(new URL("../../docs/PRODUCTION_RELEASE_RUNBOOK.md",import.meta.url),"utf8");

test("production release is manual and requires explicit confirmations",()=>{
 assert.match(workflow,/workflow_dispatch:/);
 assert.doesNotMatch(workflow,/^\s*push:/m);
 assert.match(workflow,/confirm_production_release == 'YES'/);
 assert.match(workflow,/auth_leaked_password_protection_enabled == 'YES'/);
 assert.match(workflow,/confirm_live_schema_matches_baseline:/);
 assert.match(workflow,/CONFIRM_LIVE_SCHEMA_MATCHES_BASELINE/);
 assert.match(workflow,/environment: production/);
});

test("production release verifies CI and migration history before mutating production",()=>{
 assert.match(workflow,/RewardLoop isolated database regression/);
 assert.match(workflow,/\["supabase","migration","repair","--status","applied",baseline,"--linked"\]/);
 assert.match(workflow,/Refusing baseline history repair/);
 assert.match(workflow,/CONFIRM_LIVE_SCHEMA_MATCHES_BASELINE.*!=.*"YES"/);
 assert.match(workflow,/supabase db push --linked --dry-run/);
 assert.match(workflow,/supabase db push --linked/);
 assert.match(workflow,/Verify every repository migration is recorded remotely/);
 assert.doesNotMatch(workflow,/supabase db reset --linked/);
});

test("Edge Function deployment follows successful migrations and uses read-only smoke",()=>{
 const migration=workflow.indexOf("Apply reviewed production database migrations");
 const deploy=workflow.indexOf("Deploy the matching RewardLoop API");
 const smoke=workflow.indexOf("Read-only production smoke");
 assert.ok(migration>=0&&deploy>migration&&smoke>deploy);
 assert.match(workflow,/rewardloop-api/);
 assert.match(workflow,/admin_dashboard/);
 assert.match(runbook,/does not create products, issue QR codes, claim points, redeem rewards/);
});
