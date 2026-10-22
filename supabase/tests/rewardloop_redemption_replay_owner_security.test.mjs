import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(
  new URL("../migrations/20261021203100_scope_redemption_replay_to_owner.sql", import.meta.url),
  "utf8",
);

test("redemption replay requires both the same reward and the owning actor", () => {
  assert.match(migration, /v_existing\.reward_id\s*=\s*p_reward_id/i);
  assert.match(migration, /p\.user_id\s*=\s*p_actor_user_id/i);
  assert.match(migration, /request_key_conflict/i);
});
