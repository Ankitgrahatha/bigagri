import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(
  new URL("../migrations/20261021200000_fix_redemption_refund_ledger_type.sql", import.meta.url),
  "utf8",
);

test("refund compensation uses a value in the live ledger_entry_type enum", () => {
  assert.match(migration, /entry_type\s*,[\s\S]*?'redeem_release'/i);
  assert.doesNotMatch(migration, /'redeem_refund'/);
});

test("refund is restricted to unresolved redemptions and restores stock only in compensation path", () => {
  assert.match(migration, /v_redemption\.status NOT IN \('reserved','approved'\)/i);
  assert.match(migration, /redemption-refund:'\|\|v_redemption\.id::text/i);
  assert.match(migration, /UPDATE public\.rewards SET stock_quantity=stock_quantity\+1/i);
});
