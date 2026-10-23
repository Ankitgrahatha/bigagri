import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(
  new URL("../migrations/20261023150000_saas_checkout_reservation.sql", import.meta.url),
  "utf8",
);
const endpoint = readFileSync(new URL("../functions/create-razorpay-subscription/index.ts", import.meta.url), "utf8");
const config = readFileSync(new URL("../config.toml", import.meta.url), "utf8");

test("checkout reservation verifies active tenant membership and published plan configuration", () => {
  assert.match(migration, /m\.tenant_id = p_tenant_id[\s\S]*m\.user_id = p_actor_user_id[\s\S]*m\.status = 'active'/i);
  assert.match(migration, /v_plan\.published_at IS NULL OR v_plan\.plan_status <> 'published'/i);
  assert.match(migration, /v_amount IS NULL OR v_amount <= 0 OR v_provider_plan_id IS NULL/i);
  assert.match(migration, /pg_advisory_xact_lock\(hashtextextended\(p_tenant_id::text, 0\)\)/i);
});

test("checkout reservation and finalization are service-role-only and idempotent", () => {
  assert.match(migration, /UNIQUE INDEX saas_tenant_subscription_checkout_idempotency_idx/i);
  assert.match(migration, /UNIQUE INDEX saas_tenant_one_incomplete_checkout_idx/i);
  assert.match(migration, /checkout_reconciliation_required/i);
  assert.match(migration, /provider_subscription_conflict/i);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.reserve_saas_checkout_internal\(uuid,uuid,uuid,text,text\)\s+TO service_role/i);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.finalize_saas_checkout_internal\(uuid,text,text\)\s+TO service_role/i);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.fail_saas_checkout_reservation_internal\(uuid,integer\)\s+TO service_role/i);
});

test("checkout endpoint authenticates the Supabase user and validates request boundaries", () => {
  assert.match(endpoint, /db\.auth\.getUser\(tokenMatch\[1\]\)/i);
  assert.match(endpoint, /reserve_saas_checkout_internal/);
  assert.match(endpoint, /Idempotency-Key|idempotency-key/i);
  assert.match(endpoint, /readLimitedBody/);
  assert.match(endpoint, /MAX_BODY_BYTES = 4096/);
  assert.match(endpoint, /RAZORPAY_KEY_ID/);
  assert.match(endpoint, /RAZORPAY_KEY_SECRET/);
  assert.match(endpoint, /RAZORPAY_MONTHLY_TOTAL_COUNT/);
  assert.match(endpoint, /RAZORPAY_YEARLY_TOTAL_COUNT/);
});

test("provider failures never trigger automatic duplicate subscription creation", () => {
  assert.match(endpoint, /checkout_reconciliation_required/);
  assert.match(endpoint, /fail_saas_checkout_reservation_internal/);
  assert.match(endpoint, /finalize_saas_checkout_internal/);
  assert.match(endpoint, /Do not return the checkout URL unless its provider ID is durably bound/i);
  assert.match(endpoint, /notes:[\s\S]*growta_subscription_id/);
  assert.match(config, /\[functions\.create-razorpay-subscription\]\s*verify_jwt = true/);
});
