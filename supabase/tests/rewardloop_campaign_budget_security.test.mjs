import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(
  new URL("../migrations/20261021202000_atomic_campaign_budget_enforcement.sql", import.meta.url),
  "utf8",
);
const api = readFileSync(new URL("../functions/rewardloop-api/index.ts", import.meta.url), "utf8");
const admin = readFileSync(new URL("../../admin.js", import.meta.url), "utf8");
const behavior = readFileSync(new URL("rewardloop_campaign_budget_behavior.test.sql", import.meta.url), "utf8");

test("budget uses an explicit point valuation in currency minor units", () => {
  assert.match(migration, /point_value_minor_units integer/);
  assert.match(migration, /point_value_currency char\(3\)/);
  assert.match(migration, /v_qr\.points_value::bigint \* v_point_value_minor_units::bigint/);
  assert.match(migration, /v_existing_spend \+ v_liability_minor_units > v_campaign\.budget_minor_units/);
  assert.match(migration, /budget_configuration_required/);
  assert.match(migration, /budget_currency_mismatch/);
});

test("the campaign lock serializes spend checks and liability is written in the claim transaction", () => {
  const claim = migration.slice(migration.indexOf("create or replace function private.claim_qr"));
  const campaignLock = claim.indexOf("for update");
  const spendCheck = claim.indexOf("v_existing_spend + v_liability_minor_units");
  const qrClaim = claim.indexOf("update public.qr_codes set status='claimed'");
  const claimInsert = claim.indexOf("insert into public.claims");
  const liabilityInsert = claim.indexOf("INSERT INTO public.campaign_liability_ledger");
  assert.ok(campaignLock > 0 && spendCheck > campaignLock);
  assert.ok(qrClaim > spendCheck && claimInsert > qrClaim && liabilityInsert > claimInsert);
  assert.match(migration, /claim_id uuid NOT NULL UNIQUE REFERENCES public\.claims\(id\)/);
  assert.match(migration, /campaign_liability_ledger_append_only/);
});

test("valuation writes are admin-authorized, audited and locked while budgeted campaigns are active", () => {
  const setter = migration.slice(
    migration.indexOf("CREATE OR REPLACE FUNCTION private.set_rewardloop_point_value"),
    migration.indexOf("CREATE OR REPLACE FUNCTION public.rewardloop_set_point_value_internal"),
  );
  assert.match(setter, /m\.status='active'/);
  assert.match(setter, /m\.role IN \('brand_admin','super_admin'\)/);
  assert.match(setter, /pause_budgeted_campaigns_before_changing_point_value/);
  assert.match(setter, /point_valuation_updated/);
  assert.match(migration, /A point value and currency must be configured before activating a budgeted campaign/);
});

test("admin route is covered by the common membership gate and saves through the privileged RPC", () => {
  assert.match(api, /"create_campaign", "set_point_value"(?:, "create_product")?\]\.includes\(action\)/);
  const route = api.slice(api.indexOf('if (action === "set_point_value")'), api.indexOf('if (action === "admin_dashboard")'));
  assert.match(route, /rewardloop_set_point_value_internal/);
  assert.match(route, /p_actor_user_id:\s*user\.id/);
  assert.match(route, /p_tenant_id:\s*tenant\.id/);
});

test("admin control room exposes the valuation form and budget behavior has positive/negative integration cases", () => {
  assert.match(admin, /id="point-value-form"/);
  assert.match(admin, /call\("set_point_value"/);
  assert.match(admin, /Point valuation saved/);
  assert.match(behavior, /campaign_budget_exhausted/);
  assert.match(behavior, /budget_configuration_required|budgeted campaign activated without explicit point valuation/);
  assert.match(behavior, /pause_budgeted_campaigns_before_changing_point_value/);
  assert.match(behavior, /v_qr_b_status <> 'active'/);
});
