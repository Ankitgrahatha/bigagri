#!/usr/bin/env bash
# Adversarial concurrency tests run only against the disposable CI PostgreSQL service.
# Uses lock blockers to ensure concurrent calls overlap at the actual database locks.
set -euo pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

TENANT="00000000-0000-4000-8000-000000008001"
USER_A="00000000-0000-4000-8000-000000008002"
USER_B="00000000-0000-4000-8000-000000008003"
TOKEN_SAME="growta-concurrency-token-claim-same"
TOKEN_RACE="growta-concurrency-token-claim-race"
REWARD="00000000-0000-4000-8000-000000008010"
CLAIM_REQUEST_SAME="00000000-0000-4000-8000-000000008020"
CLAIM_REQUEST_RACE_A="00000000-0000-4000-8000-000000008021"
CLAIM_REQUEST_RACE_B="00000000-0000-4000-8000-000000008022"
REDEEM_KEY_SAME="concurrency-redemption-request-same-key"
REDEEM_KEY_A="concurrency-redemption-actor-b-key-a"
REDEEM_KEY_B="concurrency-redemption-actor-b-key-b"

psqlq() {
  psql -X -A -t -q -v ON_ERROR_STOP=1 "$@"
}

# Hold the same transaction-scoped advisory lock the RPC needs, start two callers
# while that lock is held, then let them race in. This avoids merely testing two
# sequential calls that happen to reuse the same idempotency key.
run_pair_behind_lock() {
  local blocker_sql="$1"
  local call_a="$2"
  local call_b="$3"
  local label="$4"
  psqlq -c "$blocker_sql" >/dev/null &
  local blocker_pid=$!
  sleep 0.2
  psqlq -c "SELECT pg_sleep(0.05); SELECT $call_a;" >"$tmp/$label-a.out" &
  local pid_a=$!
  psqlq -c "SELECT pg_sleep(0.05); SELECT $call_b;" >"$tmp/$label-b.out" &
  local pid_b=$!
  wait "$pid_a"
  wait "$pid_b"
  wait "$blocker_pid"
  grep -E '^\{' "$tmp/$label-a.out" >"$tmp/$label-a.json"
  grep -E '^\{' "$tmp/$label-b.out" >"$tmp/$label-b.json"
}

# Identical QR + same actor + same request UUID: one credit, one replay, same claim.
run_pair_behind_lock \
  "BEGIN; SELECT pg_advisory_xact_lock(hashtextextended('$TENANT:claim:$CLAIM_REQUEST_SAME', 0)); SELECT pg_sleep(1.0); COMMIT;" \
  "private.claim_qr('$USER_A', '$TOKEN_SAME', '$CLAIM_REQUEST_SAME', 'concurrency-test', 'device-a')" \
  "private.claim_qr('$USER_A', '$TOKEN_SAME', '$CLAIM_REQUEST_SAME', 'concurrency-test', 'device-b')" \
  "claim-same-key"

# Same QR + same actor but different UUIDs: one accepted claim, one already_claimed.
run_pair_behind_lock \
  "BEGIN; SELECT id FROM public.qr_codes WHERE id='00000000-0000-4000-8000-000000008009' FOR UPDATE; SELECT pg_sleep(1.0); COMMIT;" \
  "private.claim_qr('$USER_A', '$TOKEN_RACE', '$CLAIM_REQUEST_RACE_A', 'concurrency-test', 'device-a')" \
  "private.claim_qr('$USER_A', '$TOKEN_RACE', '$CLAIM_REQUEST_RACE_B', 'concurrency-test', 'device-b')" \
  "claim-different-keys"

# Identical redemption key: one reservation/debit/stock decrement, one safe replay.
run_pair_behind_lock \
  "BEGIN; SELECT pg_advisory_xact_lock(hashtextextended('$TENANT:reward-redemption:$REDEEM_KEY_SAME', 0)); SELECT pg_sleep(1.0); COMMIT;" \
  "private.redeem_reward('$USER_A', '$REWARD', '$REDEEM_KEY_SAME')" \
  "private.redeem_reward('$USER_A', '$REWARD', '$REDEEM_KEY_SAME')" \
  "redeem-same-key"

# Different keys on one actor: the balance lock must prevent two concurrent
# reservations from spending the same 40 points twice on a 30-point reward.
run_pair_behind_lock \
  "BEGIN; SELECT pg_advisory_xact_lock(hashtextextended('$USER_B', 0)); SELECT pg_sleep(1.0); COMMIT;" \
  "private.redeem_reward('$USER_B', '$REWARD', '$REDEEM_KEY_A')" \
  "private.redeem_reward('$USER_B', '$REWARD', '$REDEEM_KEY_B')" \
  "redeem-distinct-keys"

python3 - "$tmp" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])

def pair(label):
    a = json.loads((root / f"{label}-a.json").read_text().strip())
    b = json.loads((root / f"{label}-b.json").read_text().strip())
    return a, b

a, b = pair("claim-same-key")
assert [x.get("outcome") for x in (a, b)] == ["accepted", "accepted"], (a, b)
assert sorted(x.get("replayed") for x in (a, b)) == [False, True], (a, b)
assert a.get("claim_id") == b.get("claim_id"), (a, b)
assert a.get("points_awarded") == b.get("points_awarded") == 10, (a, b)

a, b = pair("claim-different-keys")
assert sorted(x.get("outcome") for x in (a, b)) == ["accepted", "already_claimed"], (a, b)
accepted = next(x for x in (a, b) if x.get("outcome") == "accepted")
denied = next(x for x in (a, b) if x.get("outcome") == "already_claimed")
assert accepted.get("points_awarded") == 10 and "claim_id" in accepted, (a, b)
assert denied.get("points_awarded") == 0 and "claim_id" not in denied, (a, b)

a, b = pair("redeem-same-key")
assert [x.get("ok") for x in (a, b)] == [True, True], (a, b)
assert sorted(x.get("replayed") for x in (a, b)) == [False, True], (a, b)
assert a.get("redemption_id") == b.get("redemption_id"), (a, b)
assert a.get("status") == b.get("status") == "reserved", (a, b)

a, b = pair("redeem-distinct-keys")
assert sorted(x.get("ok") for x in (a, b)) == [False, True], (a, b)
accepted = next(x for x in (a, b) if x.get("ok") is True)
denied = next(x for x in (a, b) if x.get("ok") is False)
assert accepted.get("status") == "reserved", (a, b)
assert denied.get("error") == "insufficient_points", (a, b)

print("PASS: concurrent QR same-key replay, different-key QR race, redemption same-key replay, and per-actor balance serialization")
PY

# Verify the final accounting and inventory totals after all races.
psqlq -c "
DO \$concurrency_final_assertions\$
DECLARE
  v_claims integer;
  v_ledger_count integer;
  v_redeems integer;
  v_a_balance bigint;
  v_b_balance bigint;
  v_stock integer;
BEGIN
  SELECT count(*) INTO v_claims FROM public.claims
   WHERE tenant_id = '$TENANT';
  SELECT count(*) INTO v_ledger_count FROM public.points_ledger
   WHERE tenant_id = '$TENANT';
  SELECT count(*) INTO v_redeems FROM public.redemptions
   WHERE tenant_id = '$TENANT';
  SELECT COALESCE(sum(points_delta),0) INTO v_a_balance FROM public.points_ledger
   WHERE tenant_id='$TENANT' AND partner_id='00000000-0000-4000-8000-000000008004';
  SELECT COALESCE(sum(points_delta),0) INTO v_b_balance FROM public.points_ledger
   WHERE tenant_id='$TENANT' AND partner_id='00000000-0000-4000-8000-000000008005';
  SELECT stock_quantity INTO v_stock FROM public.rewards WHERE id='$REWARD';
  IF v_claims <> 2 OR v_ledger_count <> 6 OR v_redeems <> 2
     OR v_a_balance <> 90 OR v_b_balance <> 10 OR v_stock <> 2 THEN
    RAISE EXCEPTION 'concurrency accounting mismatch: claims=%, ledger=%, redemptions=%, balanceA=%, balanceB=%, stock=%',
      v_claims, v_ledger_count, v_redeems, v_a_balance, v_b_balance, v_stock;
  END IF;
END;
\$concurrency_final_assertions\$;
"
