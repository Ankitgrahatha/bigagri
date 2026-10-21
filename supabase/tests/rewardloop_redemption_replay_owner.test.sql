-- Reusing another user's redemption key must not disclose the redemption or double-spend.
BEGIN;
DO $redemption_replay_owner_test$
DECLARE
  v_tenant constant uuid := '00000000-0000-4000-8000-00000000c101';
  v_user_a constant uuid := '00000000-0000-4000-8000-00000000c201';
  v_user_b constant uuid := '00000000-0000-4000-8000-00000000c202';
  v_partner_a constant uuid := '00000000-0000-4000-8000-00000000c301';
  v_partner_b constant uuid := '00000000-0000-4000-8000-00000000c302';
  v_reward constant uuid := '00000000-0000-4000-8000-00000000c401';
  v_result_a jsonb;
  v_result_b jsonb;
  v_redemption_id uuid;
  v_ledger_count integer;
  v_stock integer;
BEGIN
  INSERT INTO auth.users(id) VALUES(v_user_a),(v_user_b);
  INSERT INTO public.tenants(id,name,slug,status,default_locale)
  VALUES(v_tenant,'Redemption Replay Owner Test','redemption-replay-owner-test','active','en-IN');
  INSERT INTO public.partners(id,tenant_id,user_id,role,display_name,verification_status)
  VALUES
    (v_partner_a,v_tenant,v_user_a,'farmer','Owner A','verified'),
    (v_partner_b,v_tenant,v_user_b,'farmer','Owner B','verified');
  INSERT INTO public.rewards(id,tenant_id,slug,name,category,points_cost,stock_quantity,active,is_demo,sort_order,metadata)
  VALUES(v_reward,v_tenant,'redemption-replay-owner-test','Replay Owner Reward','general',30,3,true,false,1,'{}'::jsonb);
  INSERT INTO public.points_ledger(tenant_id,partner_id,entry_type,points_delta,idempotency_key,reason_code,actor_user_id,metadata)
  VALUES
    (v_tenant,v_partner_a,'earn',100,'owner-test-seed-a','test_seed',v_user_a,'{}'::jsonb),
    (v_tenant,v_partner_b,'earn',100,'owner-test-seed-b','test_seed',v_user_b,'{}'::jsonb);

  v_result_a := private.redeem_reward(v_user_a,v_reward,'owner-bound-redemption-key-01');
  IF v_result_a->>'ok'<>'true' OR v_result_a->>'status'<>'reserved' THEN
    RAISE EXCEPTION 'first redemption failed: %',v_result_a;
  END IF;
  v_redemption_id := (v_result_a->>'redemption_id')::uuid;

  v_result_b := private.redeem_reward(v_user_b,v_reward,'owner-bound-redemption-key-01');
  IF v_result_b->>'ok'<>'false' OR v_result_b->>'error'<>'request_key_conflict'
     OR v_result_b->>'redemption_id' IS NOT NULL OR v_result_b->>'status' IS NOT NULL THEN
    RAISE EXCEPTION 'cross-actor redemption details leaked: %',v_result_b;
  END IF;

  SELECT count(*) INTO v_ledger_count FROM public.points_ledger WHERE tenant_id=v_tenant AND entry_type='redeem_reserve';
  SELECT stock_quantity INTO v_stock FROM public.rewards WHERE id=v_reward;
  IF v_ledger_count<>1 OR v_stock<>2
     OR (SELECT count(*) FROM public.redemptions WHERE tenant_id=v_tenant)<>1
     OR (SELECT COALESCE(sum(points_delta),0) FROM public.points_ledger WHERE tenant_id=v_tenant AND partner_id=v_partner_a)<>70
     OR (SELECT COALESCE(sum(points_delta),0) FROM public.points_ledger WHERE tenant_id=v_tenant AND partner_id=v_partner_b)<>100 THEN
    RAISE EXCEPTION 'cross-actor replay accounting mismatch: ledger=%, stock=%',v_ledger_count,v_stock;
  END IF;
END;
$redemption_replay_owner_test$;
ROLLBACK;
