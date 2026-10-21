import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(
  new URL("../migrations/20261021201000_scope_claim_replay_to_owner.sql", import.meta.url),
  "utf8",
);

test("claim replay lookup joins the credited partner and verifies owner identity", () => {
  assert.match(migration, /JOIN public\.partners p[\s\S]*?p\.user_id\s*=\s*p_actor_user_id/i);
});

test("cross-actor reuse of an idempotency UUID returns no claim or points data", () => {
  assert.match(migration, /outcome','request_id_conflict','points_awarded',0,'replayed',false/i);
  assert.match(migration, /IF EXISTS\s*\([\s\S]*?c\.idempotency_key='claim:'\|\|p_request_id::text[\s\S]*?request_id_conflict/i);
});
