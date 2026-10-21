import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(
  new URL("../migrations/20261021170000_scope_claim_replay_to_actor.sql", import.meta.url),
  "utf8",
);

test("claim replay lookup is scoped to the actor's own partner", () => {
  const replayLookup = migration.slice(
    migration.indexOf("select c.* into v_existing"),
    migration.indexOf("if found then", migration.indexOf("select c.* into v_existing")),
  );
  assert.match(replayLookup, /join public\.partners p/i);
  assert.match(replayLookup, /p\.user_id\s*=\s*p_actor_user_id/i);
  assert.match(replayLookup, /p\.tenant_id\s*=\s*c\.tenant_id/i);
  assert.match(replayLookup, /c\.tenant_id\s*=\s*v_qr\.tenant_id/i);
});

test("claim replay hardening leaves accounting writes on the first-claim path", () => {
  const replayLookupEnd = migration.indexOf(
    "if found then",
    migration.indexOf("select c.* into v_existing"),
  );
  const firstClaimWrite = migration.indexOf("insert into public.claims");
  const ledgerWrite = migration.indexOf("insert into public.points_ledger");
  assert.ok(replayLookupEnd > 0);
  assert.ok(firstClaimWrite > replayLookupEnd);
  assert.ok(ledgerWrite > firstClaimWrite);
  assert.match(migration, /'earn:'\|\|v_claim_id::text/);
});
