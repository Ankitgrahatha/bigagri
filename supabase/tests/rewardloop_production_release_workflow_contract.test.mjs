import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const workflow=readFileSync(new URL("../../.github/workflows/rewardloop-production-release.yml",import.meta.url),"utf8");
const runbook=readFileSync(new URL("../../docs/PRODUCTION_RELEASE_RUNBOOK.md",import.meta.url),"utf8");
const liveParitySql=readFileSync(new URL("../ops/verify_live_schema_baseline.sql",import.meta.url),"utf8");

test("production release is manual and requires explicit confirmations",()=>{
 assert.match(workflow,/workflow_dispatch:/);
 assert.doesNotMatch(workflow,/^\s*push:/m);
 assert.match(workflow,/confirm_production_release == 'YES'/);
 assert.match(workflow,/auth_leaked_password_protection_enabled == 'YES'/);
 assert.match(workflow,/confirm_live_schema_matches_baseline:/);
 assert.match(workflow,/confirm_billing_test_secrets_configured == 'YES'/);
 assert.match(workflow,/confirm_billing_test_secrets_configured:/);
 assert.match(workflow,/confirm_backup_restore_ready == 'YES'/);
 assert.match(workflow,/confirm_backup_restore_ready:/);
 assert.match(workflow,/CONFIRM_LIVE_SCHEMA_MATCHES_BASELINE/);
 assert.match(workflow,/environment: production/);
 assert.match(workflow,/environments\/production/);
 assert.match(workflow,/required_reviewers/);
});

test("production release verifies CI and migration history before mutating production",()=>{
 assert.match(workflow,/RewardLoop isolated database regression/);
 assert.match(workflow,/\["supabase","migration","repair","--status","applied",baseline,"--linked"\]/);
 assert.match(workflow,/Refusing baseline history repair/);
 assert.ok(workflow.indexOf("Verify live schema fingerprints before migration-history repair") < workflow.indexOf("Reconcile only the verified baseline and validate migration allowlist"));
 assert.ok(workflow.indexOf("Verify live schema fingerprints before migration-history repair") < workflow.indexOf('subprocess.run(["supabase","migration","repair"'));
 assert.match(workflow,/CONFIRM_LIVE_SCHEMA_MATCHES_BASELINE.*!=.*"YES"/);
 assert.match(workflow,/supabase secrets list --project-ref/);
 assert.match(workflow,/Verify live schema fingerprints before migration-history repair/);
 assert.match(workflow,/api\.supabase\.com\/v1\/projects\/\$SUPABASE_PROJECT_REF\/database\/query/);
 assert.match(workflow,/supabase\/ops\/verify_live_schema_baseline\.sql/);
 assert.match(workflow,/baseline_matches/);
 assert.match(workflow,/RAZORPAY_WEBHOOK_SECRET/);
 assert.match(workflow,/RAZORPAY_PROCESSOR_SECRET/);
 assert.match(workflow,/supabase db push --linked --dry-run/);
 assert.match(workflow,/supabase db push --linked/);
 assert.match(workflow,/Verify every repository migration is recorded remotely/);
 assert.doesNotMatch(workflow,/supabase db reset --linked/);
});

test("Edge Function deployment follows successful migrations and uses read-only smoke",()=>{
 const migration=workflow.indexOf("Apply reviewed production database migrations");
 const deploy=workflow.indexOf("Deploy the reviewed RewardLoop and SaaS billing Edge Functions");
 const smoke=workflow.indexOf("Read-only production smoke");
 assert.ok(migration>=0&&deploy>migration&&smoke>deploy);
 for (const fn of ["rewardloop-api","rewardloop-admin-settings","razorpay-webhook","create-razorpay-subscription","reconcile-razorpay-subscription","saas-checkout-reconciliation","saas-billing-portal","process-razorpay-webhooks"]) {
  assert.match(workflow,new RegExp(fn));
 }
 assert.match(workflow,/admin_dashboard/);
 assert.match(workflow,/\/admin-billing\.html/);
 assert.match(workflow,/razorpay-webhook/);
 assert.match(workflow,/webhook_code.*401/s);
 assert.match(workflow,/503 means required server-side configuration is missing/);
 assert.match(runbook,/does not create products, issue QR codes, claim points, redeem rewards/);
});


test("live schema parity probe is read-only and matches the captured catalog fingerprint contract",()=>{
 assert.match(liveParitySql,/557cf04098d8519f16d8cc1a9d145088734cb6ef9cefce7bf3dcc467098719a2/);
 assert.match(liveParitySql,/33c1dc63ba89a52e68e4d54ea54e2ee971269dfcd3821b339fcdbc499e09ebf2/);
 assert.match(liveParitySql,/e42d1fab480c15e989b9c1ed6bb57176c1c2f3bf3440817df91e39bbe59a40a4/);
 assert.match(liveParitySql,/9d67f1e13fcaca28de634af6810f33d0b478806b62b6c49b69d4a2469a7e8a1d/);
 assert.match(liveParitySql,/baseline_matches/);
 assert.doesNotMatch(liveParitySql,/\b(?:INSERT|UPDATE|DELETE|ALTER|DROP|CREATE|GRANT|REVOKE)\b/i);
});


test("live schema parity probe checks captured default ACL fingerprint",()=>{
 assert.match(liveParitySql,/default_acl_match/);
 assert.match(liveParitySql,/642e160f2667b54bde03a979af4eb14bb818281cb3f628f4910ab24426bb1792/);
 assert.match(liveParitySql,/baseline_matches AND default_acl_match|default_acl_match AND function_acl_match/);
});


test("pre-baseline fingerprint check is skipped after baseline migration is already recorded",()=>{
 const gate=workflow.slice(workflow.indexOf("Verify live schema fingerprints before migration-history repair"),workflow.indexOf("Reconcile only the verified baseline and validate migration allowlist"));
 assert.match(gate,/supabase migration list --linked/);
 assert.match(gate,/20261021083000/);
 assert.match(gate,/Baseline already recorded/);
 assert.match(gate,/if \\[\\[ "\$baseline_already_recorded" == "yes" \\]\\]/);
});
