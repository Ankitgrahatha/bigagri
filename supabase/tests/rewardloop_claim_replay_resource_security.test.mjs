import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(
  new URL("../migrations/20261021183000_bind_claim_replay_to_qr.sql", import.meta.url),
  "utf8",
);

test("claim idempotency key is serialized before QR row locking", () => {
  const lock = migration.indexOf(":claim:' || p_request_id::text");
  const qrLock = migration.indexOf("for update", migration.indexOf("where q.id = v_qr.id"));
  assert.ok(lock > 0, "tenant/request advisory lock missing");
  assert.ok(qrLock > lock, "request lock must precede QR row lock");
});

test("claim replay must match both the QR resource and authenticated actor", () => {
  const lookup = migration.slice(
    migration.indexOf("select c.* into v_existing"),
    migration.indexOf("select p.* into v_partner"),
  );
  assert.match(lookup, /v_existing\.qr_code_id\s*=\s*v_qr\.id/i);
  assert.match(lookup, /p\.user_id\s*=\s*p_actor_user_id/i);
  assert.match(lookup, /'request_id_conflict'/);
  const conflict = lookup.slice(lookup.indexOf("'request_id_conflict'"));
  assert.doesNotMatch(conflict, /'claim_id'|'replayed'|'points_awarded'\s*,\s*v_existing/i);
});

test("claim writes retain claim-before-ledger accounting after QR lock", () => {
  const qrUpdate = migration.indexOf("update public.qr_codes set status='claimed'");
  const claimInsert = migration.indexOf("insert into public.claims");
  const ledgerInsert = migration.indexOf("insert into public.points_ledger");
  assert.ok(qrUpdate > 0 && claimInsert > qrUpdate && ledgerInsert > claimInsert);
});
