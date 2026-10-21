import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(
  new URL("../migrations/20261021202000_scope_redemption_replay_to_owner.sql", import.meta.url),
  "utf8",
);

test("redemption replay matches the credited partner owner", () => {
  assert.match(migration, /JOIN public\.partners p[\s\S]*?p\.user_id\s*=\s*p_actor_user_id/i);
  assert.match(migration, /p\.tenant_id=v_tenant_id/i);
});

test("cross-actor key reuse returns a generic conflict with no redemption identifiers", () => {
  assert.match(migration, /error','request_key_conflict','replayed',false/i);
  assert.match(migration, /IF EXISTS\s*\([\s\S]*?r\.request_key=p_request_key[\s\S]*?request_key_conflict/i);
});
