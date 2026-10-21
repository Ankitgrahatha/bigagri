-- End-to-end refund and fulfillment accounting tests; disposable PostgreSQL only.
-- Every test data mutation is rolled back. Never execute against production.
BEGIN;

DO $redemption_resolution_test$
DECLARE
  v_tenant constant uuid := '00000000-0000-4000-8000-00000000a101';
  v_user constant uuid := '00000000-0000-4000-8000-00000000a201';
  v_admin constant uuid := '00000000-0000-4000-8000-00000000a202';
  v_partner constant uuid := '00000000-0000-4000-8000-00000000a301';
  v_reward constant uuid := '00000000-0000-4000-8000-00000000a401';
  v_cancel_request constant text := 'resolve-cancel-request-001';
  v_fulfill_request constant text := 'resolve-fulfill-request-001';
  v_cancel jsonb;
  v_cancel_retry jsonb;
  v_fulfill jsonb;
  v_fulfill_retry jsonb;
  v_redemption_cancel uuid;
  v_redemption_fulfill uuid;
  v_balance bigint;
  v_refund_count integer;
  v_stock integer;
  v_status text;
BEGIN
  INSERT INTO auth.users(id) VALUES (v_user), (v_admin);

  INSERT INTO public.tenants(id, name, slug, status, default_locale)
  VALUES (v_tenant, 'Resolution Test Tenant', 'resolution-test-tenant', 'active', 'en-IN');

  INSERT INTO public.tenant_memberships(tenant_id,user_id,role,status)
  VALUES(v_tenant,v_admin,'brand_admin','active');

  INSERT INTO public.partners(id,tenant_id,user_id,role,display_name,verification_status)
  VALUES(v_partner,v_tenant,v_user,'farmer','Resolution Test Partner','verified');

  INSERT INTO public.rewards(
    id,tenant_id,slug,name,category,points_cost,stock_quantity,active,is_demo,sort_order,metadata
  )
  VALUES(v_reward,v_tenant,'resolution-test-reward','Resolution Test Reward','general',30,2,true,false,1,'{}'::jsonb);

  INSERT INTO public.points_ledger(
    tenant_id,partner_id,entry_type,points_delta,idempotency_key,reason_code,actor_user_id,metadata
  )
  VALUES(v_tenant,v_partner,'earn',100,'resolution-seed:'||v_partner::text,'test_seed',v_user,'{}'::jsonb);

  -- Cancellation should refund 30 points, restore stock, and be a no-op on a second attempt.
  v_cancel := private.redeem_reward(v_user,v_reward,v_cancel_request);
  IF v_cancel->>'ok' <> 'true' OR v_cancel->>'status' <> 'reserved' THEN
    RAISE EXCEPTION 'could not reserve cancellation fixture: %',v_cancel;
  END IF;
  v_redemption_cancel := (v_cancel->>'redemption_id')::uuid;

  v_cancel_retry := private.resolve_redemption(v_admin,v_tenant,v_redemption_cancel,'cancelled','test cancellation reason');
  IF v_cancel_retry->>'ok' <> 'true'
     OR v_cancel_retry->>'status' <> 'cancelled'
     OR v_cancel_retry->>'points_refunded' <> '30'
     OR v_cancel_retry->>'balance_after' <> '100' THEN
    RAISE EXCEPTION 'cancellation/refund failed: %',v_cancel_retry;
  END IF;

  v_cancel := private.resolve_redemption(v_admin,v_tenant,v_redemption_cancel,'cancelled','repeat cancellation reason');
  IF v_cancel->>'ok' <> 'false' OR v_cancel->>'error' <> 'redemption_already_resolved' THEN
    RAISE EXCEPTION 'second cancellation was not safely rejected: %',v_cancel;
  END IF;

  SELECT COALESCE(sum(points_delta),0) INTO v_balance
    FROM public.points_ledger WHERE tenant_id=v_tenant AND partner_id=v_partner;
  SELECT count(*) INTO v_refund_count
    FROM public.points_ledger
   WHERE tenant_id=v_tenant AND partner_id=v_partner AND idempotency_key='redemption-refund:'||v_redemption_cancel::text;
  SELECT stock_quantity INTO v_stock FROM public.rewards WHERE id=v_reward AND tenant_id=v_tenant;
  SELECT status INTO v_status FROM public.redemptions WHERE id=v_redemption_cancel;

  IF v_balance <> 100 OR v_refund_count <> 1 OR v_stock <> 2 OR v_status <> 'cancelled' THEN
    RAISE EXCEPTION 'cancellation accounting mismatch: balance=%, refunds=%, stock=%, status=%',v_balance,v_refund_count,v_stock,v_status;
  END IF;

  -- Fulfillment spends the reserved points permanently and must not restore stock.
  v_fulfill := private.redeem_reward(v_user,v_reward,v_fulfill_request);
  IF v_fulfill->>'ok' <> 'true' OR v_fulfill->>'status' <> 'reserved' THEN
    RAISE EXCEPTION 'could not reserve fulfillment fixture: %',v_fulfill;
  END IF;
  v_redemption_fulfill := (v_fulfill->>'redemption_id')::uuid;

  v_fulfill_retry := private.resolve_redemption(v_admin,v_tenant,v_redemption_fulfill,'fulfilled',NULL);
  IF v_fulfill_retry->>'ok' <> 'true'
     OR v_fulfill_retry->>'status' <> 'fulfilled'
     OR v_fulfill_retry->>'points_refunded' <> '0'
     OR v_fulfill_retry->>'balance_after' <> '70' THEN
    RAISE EXCEPTION 'fulfillment accounting failed: %',v_fulfill_retry;
  END IF;

  v_fulfill := private.resolve_redemption(v_admin,v_tenant,v_redemption_fulfill,'cancelled','late cancellation test');
  IF v_fulfill->>'ok' <> 'false' OR v_fulfill->>'error' <> 'redemption_already_resolved' THEN
    RAISE EXCEPTION 'fulfilled redemption was incorrectly resolved again: %',v_fulfill;
  END IF;

  SELECT COALESCE(sum(points_delta),0) INTO v_balance
    FROM public.points_ledger WHERE tenant_id=v_tenant AND partner_id=v_partner;
  SELECT count(*) INTO v_refund_count
    FROM public.points_ledger
   WHERE tenant_id=v_tenant AND partner_id=v_partner AND idempotency_key='redemption-refund:'||v_redemption_fulfill::text;
  SELECT stock_quantity INTO v_stock FROM public.rewards WHERE id=v_reward AND tenant_id=v_tenant;
  SELECT status INTO v_status FROM public.redemptions WHERE id=v_redemption_fulfill;

  IF v_balance <> 70 OR v_refund_count <> 0 OR v_stock <> 1 OR v_status <> 'fulfilled' THEN
    RAISE EXCEPTION 'fulfillment accounting mismatch: balance=%, refunds=%, stock=%, status=%',v_balance,v_refund_count,v_stock,v_status;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.points_ledger WHERE tenant_id=v_tenant AND partner_id=v_partner AND entry_type='redeem_release') THEN
    RAISE EXCEPTION 'refund ledger must use ledger_entry_type redeem_release';
  END IF;

  RAISE NOTICE 'PASS: cancellation refunds once, restores stock once, repeat resolution rejected, fulfillment does not refund, and enum type is valid';
END;
$redemption_resolution_test$;

ROLLBACK;
