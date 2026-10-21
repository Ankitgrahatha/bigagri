import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(
  new URL("../migrations/20261021182000_scope_redemption_replay_to_actor.sql", import.meta.url),
  "utf8",
);

test("redemption replay only reveals the existing redemption to its owning partner", () => {
  const existingLookup = migration.slice(
    migration.indexOf("SELECT r.*"),
    migration.indexOf("IF FOUND THEN", migration.indexOf("SELECT r.*")),
  );
  assert.match(existingLookup, /r\.tenant_id\s*=\s*v_request_tenant_id/i);
  assert.match(existingLookup, /r\.request_key\s*=\s*p_request_key/i);

  const replayGuard = migration.slice(
    migration.indexOf("IF FOUND THEN"),
    migration.indexOf("-- Do not return IDs", migration.indexOf("IF FOUND THEN")),
  );
  assert.match(replayGuard, /v_existing\.reward_id\s*=\s*p_reward_id/i);
  assert.match(replayGuard, /p\.id\s*=\s*v_existing\.partner_id/i);
  assert.match(replayGuard, /p\.user_id\s*=\s*p_actor_user_id/i);
});

test("key collisions return a generic conflict without another partner's redemption details", () => {
  const conflict = migration.slice(
    migration.indexOf("-- Do not return IDs"),
    migration.indexOf("-- A user may try different request keys", migration.indexOf("-- Do not return IDs")),
  );
  assert.match(conflict, /'request_key_conflict'/);
  assert.doesNotMatch(conflict, /'redemption_id'|'status'|'points_cost'|'balance_after'/);
});

test("redemption key and actor locks serialize idempotency and balance checks", () => {
  assert.match(migration, /:reward-redemption:'\s*\|\|\s*p_request_key/);
  assert.match(migration, /hashtextextended\(p_actor_user_id::text,\s*0\)/);
});

test("partner and reward access are constrained to the reward tenant", () => {
  assert.match(migration, /p\.tenant_id\s*=\s*v_request_tenant_id/i);
  assert.match(migration, /rw\.tenant_id\s*=\s*v_partner\.tenant_id/i);
});

test("redemption creates one reservation, a ledger debit, stock decrement and audit record", () => {
  const firstDebit = migration.search(/INSERT INTO public\.points_ledger/i);
  const stockDebit = migration.search(/UPDATE public\.rewards\s+SET stock_quantity\s*=\s*stock_quantity\s*-\s*1/i);
  const audit = migration.search(/INSERT INTO public\.audit_logs/i);
  assert.ok(firstDebit > 0);
  assert.ok(stockDebit > firstDebit);
  assert.ok(audit > stockDebit);
});
