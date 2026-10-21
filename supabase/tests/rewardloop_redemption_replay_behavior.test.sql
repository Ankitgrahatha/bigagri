-- Runs only against an isolated disposable PostgreSQL database.
-- All fixture rows are rolled back. Never execute against production.
BEGIN;

DO $redemption_replay_test$
DECLARE
  v_tenant_id constant uuid := '00000000-0000-4000-8000-000000000111';
  v_user_a constant uuid := '00000000-0000-4000-8000-000000000211';
  v_user_b constant uuid := '00000000-0000-4000-8000-000000000212';
  v_partner_a constant uuid := '00000000-0000-4000-8000-000000000311';
  v_partner_b constant uuid := '00000000-0000-4000-8000-000000000312';
  v_reward_id constant uuid := '00000000-0000-4000-8000-000000000411';
  v_request_key constant text := 'redemption-request-key-a';
  v_first jsonb;
  v_retry jsonb;
  v_other_actor jsonb;
  v_redemption_count integer;
  v_reserve_count integer;
  v_ledger_sum bigint;
  v_stock integer;
BEGIN
  INSERT INTO auth.users(id) VALUES (v_user_a), (v_user_b);

  INSERT INTO public.tenants(id, name, slug, status, default_locale)
  VALUES (v_tenant_id, 'Redemption Replay Tenant', 'redeem-replay-tenant', 'active', 'en-IN');

  INSERT INTO public.partners(
    id, tenant_id, user_id, role, display_name, verification_status
  )
  VALUES
    (v_partner_a, v_tenant_id, v_user_a, 'farmer', 'Redeem Actor A', 'verified'),
    (v_partner_b, v_tenant_id, v_user_b, 'farmer', 'Redeem Actor B', 'verified');

  INSERT INTO public.rewards(
    id, tenant_id, slug, name, category, points_cost, stock_quantity, active, is_demo, sort_order, metadata
  )
  VALUES (
    v_reward_id, v_tenant_id, 'test-reward-replay', 'Test Reward for Replay',
    'general', 30, 2, true, false, 10, '{}'::jsonb
  );

  INSERT INTO public.points_ledger(
    tenant_id, partner_id, entry_type, points_delta, idempotency_key,
    reason_code, actor_user_id, metadata
  )
  VALUES (
    v_tenant_id, v_partner_a, 'earn', 100, 'test-seed:' || v_partner_a::text,
    'test_seed', v_user_a, '{}'::jsonb
  );

  v_first := private.redeem_reward(v_user_a, v_reward_id, v_request_key);
  IF v_first->>'ok' <> 'true'
     OR v_first->>'status' <> 'reserved'
     OR v_first->>'points_cost' <> '30'
     OR v_first->>'balance_after' <> '70'
     OR v_first->>'replayed' <> 'false' THEN
    RAISE EXCEPTION 'first redemption did not reserve as expected: %', v_first;
  END IF;

  v_retry := private.redeem_reward(v_user_a, v_reward_id, v_request_key);
  IF v_retry->>'ok' <> 'true'
     OR v_retry->>'status' <> 'reserved'
     OR v_retry->>'replayed' <> 'true'
     OR v_retry->>'redemption_id' IS DISTINCT FROM v_first->>'redemption_id' THEN
    RAISE EXCEPTION 'same-actor retry was not idempotent: first=%, retry=%', v_first, v_retry;
  END IF;

  v_other_actor := private.redeem_reward(v_user_b, v_reward_id, v_request_key);
  IF v_other_actor->>'ok' <> 'false'
     OR v_other_actor->>'error' <> 'request_key_conflict'
     OR v_other_actor ? 'redemption_id'
     OR v_other_actor ? 'status'
     OR v_other_actor ? 'points_cost'
     OR v_other_actor ? 'balance_after' THEN
    RAISE EXCEPTION 'another actor received the redemption or amount: %', v_other_actor;
  END IF;

  SELECT count(*) INTO v_redemption_count
    FROM public.redemptions
   WHERE tenant_id = v_tenant_id;

  SELECT count(*) INTO v_reserve_count
    FROM public.points_ledger
   WHERE tenant_id = v_tenant_id AND partner_id = v_partner_a AND entry_type = 'redeem_reserve';

  SELECT COALESCE(sum(points_delta), 0) INTO v_ledger_sum
    FROM public.points_ledger
   WHERE tenant_id = v_tenant_id AND partner_id = v_partner_a;

  SELECT stock_quantity INTO v_stock
    FROM public.rewards WHERE id = v_reward_id AND tenant_id = v_tenant_id;

  IF v_redemption_count <> 1 OR v_reserve_count <> 1
     OR v_ledger_sum <> 70 OR v_stock <> 1 THEN
    RAISE EXCEPTION 'duplicate redemption changed accounting: redemptions=%, reserve_entries=%, ledger_balance=%, stock=%',
      v_redemption_count, v_reserve_count, v_ledger_sum, v_stock;
  END IF;

  -- A request key reused by the same actor for a different reward must conflict too.
  INSERT INTO public.rewards(
    id, tenant_id, slug, name, category, points_cost, stock_quantity, active, is_demo, sort_order, metadata
  )
  VALUES (
    '00000000-0000-4000-8000-000000000412', v_tenant_id, 'test-reward-replay-2',
    'Second Test Reward', 'general', 20, 2, true, false, 20, '{}'::jsonb
  );

  v_other_actor := private.redeem_reward(
    v_user_a, '00000000-0000-4000-8000-000000000412', v_request_key
  );

  IF v_other_actor->>'ok' <> 'false'
     OR v_other_actor->>'error' <> 'request_key_conflict'
     OR v_other_actor ? 'redemption_id' THEN
    RAISE EXCEPTION 'same actor reusing a key for a different reward did not fail safely: %', v_other_actor;
  END IF;

  IF has_function_privilege('anon', 'private.redeem_reward(uuid,uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon unexpectedly has EXECUTE on private.redeem_reward';
  END IF;
  IF has_function_privilege('authenticated', 'private.redeem_reward(uuid,uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated unexpectedly has EXECUTE on private.redeem_reward';
  END IF;
  IF NOT has_function_privilege('service_role', 'private.redeem_reward(uuid,uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'service_role is missing EXECUTE on private.redeem_reward';
  END IF;

  RAISE NOTICE 'PASS: first redemption, same-actor replay, cross-actor key conflict, one ledger debit, stock decremented once, RPC grants';
END;
$redemption_replay_test$;

ROLLBACK;
