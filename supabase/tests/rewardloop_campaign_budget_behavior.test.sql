-- Campaign budget cap behavior. Disposable PostgreSQL only; all fixture data rolls back.
BEGIN;

DO $campaign_budget_test$
DECLARE
  v_tenant constant uuid := '00000000-0000-4000-8000-00000000c101';
  v_tenant_unconfigured constant uuid := '00000000-0000-4000-8000-00000000c102';
  v_admin constant uuid := '00000000-0000-4000-8000-00000000c201';
  v_farmer constant uuid := '00000000-0000-4000-8000-00000000c202';
  v_non_admin constant uuid := '00000000-0000-4000-8000-00000000c203';
  v_partner constant uuid := '00000000-0000-4000-8000-00000000c301';
  v_product constant uuid := '00000000-0000-4000-8000-00000000c401';
  v_campaign constant uuid := '00000000-0000-4000-8000-00000000c501';
  v_qr_a constant uuid := '00000000-0000-4000-8000-00000000c601';
  v_qr_b constant uuid := '00000000-0000-4000-8000-00000000c602';
  v_request_a constant uuid := '00000000-0000-4000-8000-00000000c701';
  v_request_b constant uuid := '00000000-0000-4000-8000-00000000c702';
  v_token_a constant text := 'growta-budget-test-token-a-long';
  v_token_b constant text := 'growta-budget-test-token-b-long';
  v_setting jsonb;
  v_first jsonb;
  v_second jsonb;
  v_non_admin_result jsonb;
  v_value_change jsonb;
  v_claims integer;
  v_ledger_count integer;
  v_awarded bigint;
  v_liability_count integer;
  v_liability bigint;
  v_qr_b_status text;
  v_activation_blocked boolean := false;
BEGIN
  INSERT INTO auth.users(id) VALUES (v_admin), (v_farmer), (v_non_admin);

  INSERT INTO public.tenants(id,name,slug,status,default_locale,public_catalog_enabled)
  VALUES
    (v_tenant,'Budget Test Tenant','budget-test-tenant','active','en-IN',false),
    (v_tenant_unconfigured,'Budget Unconfigured Tenant','budget-unconfigured-tenant','active','en-IN',false);

  INSERT INTO public.tenant_memberships(tenant_id,user_id,role,status)
  VALUES (v_tenant,v_admin,'brand_admin','active');

  INSERT INTO public.partners(id,tenant_id,user_id,role,display_name,verification_status)
  VALUES (v_partner,v_tenant,v_farmer,'farmer','Budget Test Farmer','verified');

  INSERT INTO public.products(id,tenant_id,sku,name,active,metadata)
  VALUES (v_product,v_tenant,'BUDGET-TEST-001','Budget Test Product',true,'{}'::jsonb);

  INSERT INTO public.rewardloop_admin_settings(tenant_id)
  VALUES (v_tenant_unconfigured)
  ON CONFLICT (tenant_id) DO NOTHING;

  INSERT INTO public.campaigns(
    id,tenant_id,name,status,starts_at,ends_at,budget_minor_units,currency,rules_version,rules
  )
  VALUES (
    v_campaign,v_tenant,'Atomic Budget Campaign','paused',
    now()-interval '1 hour',now()+interval '1 day',1000,'INR',1,'{}'::jsonb
  );

  INSERT INTO public.qr_codes(
    id,tenant_id,product_id,campaign_id,token_hash,status,entitlement_role,points_value,activated_at
  )
  VALUES
    (v_qr_a,v_tenant,v_product,v_campaign,
     encode(extensions.digest(convert_to(v_token_a,'UTF8'),'sha256'),'hex'),
     'active','farmer',7,now()),
    (v_qr_b,v_tenant,v_product,v_campaign,
     encode(extensions.digest(convert_to(v_token_b,'UTF8'),'sha256'),'hex'),
     'active','farmer',7,now());

  v_setting := public.rewardloop_set_point_value_internal(v_admin,v_tenant,100,'INR');
  IF v_setting->>'ok' <> 'true'
     OR v_setting->>'point_value_minor_units' <> '100'
     OR v_setting->>'point_value_currency' <> 'INR' THEN
    RAISE EXCEPTION 'authorized point valuation setup failed: %',v_setting;
  END IF;

  v_non_admin_result := public.rewardloop_set_point_value_internal(v_non_admin,v_tenant,200,'INR');
  IF v_non_admin_result->>'ok' <> 'false' OR v_non_admin_result->>'error' <> 'forbidden' THEN
    RAISE EXCEPTION 'non-admin point valuation update was not rejected: %',v_non_admin_result;
  END IF;

  UPDATE public.campaigns SET status='active'
   WHERE id=v_campaign AND tenant_id=v_tenant;

  -- 7 points × 100 paise = 700 paise; first claim fits a 1,000-paise budget.
  v_first := private.claim_qr(v_farmer,v_token_a,v_request_a,'budget-test','device-a');
  IF v_first->>'ok' <> 'true'
     OR v_first->>'outcome' <> 'accepted'
     OR v_first->>'points_awarded' <> '7' THEN
    RAISE EXCEPTION 'first budgeted claim should fit: %',v_first;
  END IF;

  -- A second 700-paise liability would raise the total to 1,400 paise; it must fail.
  v_second := private.claim_qr(v_farmer,v_token_b,v_request_b,'budget-test','device-b');
  IF v_second->>'ok' <> 'false'
     OR v_second->>'outcome' <> 'campaign_budget_exhausted'
     OR v_second->>'points_awarded' <> '0'
     OR v_second ? 'claim_id' THEN
    RAISE EXCEPTION 'over-budget claim did not fail safely: %',v_second;
  END IF;

  SELECT count(*) INTO v_claims FROM public.claims
   WHERE tenant_id=v_tenant AND campaign_id=v_campaign;
  SELECT count(*),COALESCE(sum(points_delta),0) INTO v_ledger_count,v_awarded
    FROM public.points_ledger WHERE tenant_id=v_tenant AND partner_id=v_partner;
  SELECT count(*),COALESCE(sum(liability_minor_units),0)
    INTO v_liability_count,v_liability
    FROM public.campaign_liability_ledger
   WHERE tenant_id=v_tenant AND campaign_id=v_campaign AND counts_against_budget;
  SELECT status::text INTO v_qr_b_status FROM public.qr_codes WHERE id=v_qr_b;

  IF v_claims <> 1 OR v_ledger_count <> 1 OR v_awarded <> 7
     OR v_liability_count <> 1 OR v_liability <> 700 OR v_qr_b_status <> 'active' THEN
    RAISE EXCEPTION 'budget accounting mismatch: claims=%, ledger_rows=%, points=%, liability_rows=%, liability=%, second_qr_status=%',
      v_claims,v_ledger_count,v_awarded,v_liability_count,v_liability,v_qr_b_status;
  END IF;

  v_value_change := public.rewardloop_set_point_value_internal(v_admin,v_tenant,101,'INR');
  IF v_value_change->>'ok' <> 'false'
     OR v_value_change->>'error' <> 'pause_budgeted_campaigns_before_changing_point_value' THEN
    RAISE EXCEPTION 'point valuation changed while budgeted campaign active: %',v_value_change;
  END IF;

  -- A budgeted campaign with no point valuation must not activate.
  INSERT INTO public.campaigns(
    id,tenant_id,name,status,starts_at,ends_at,budget_minor_units,currency,rules_version,rules
  )
  VALUES (
    '00000000-0000-4000-8000-00000000c502',v_tenant_unconfigured,'Unconfigured Budget Campaign','paused',
    now()-interval '1 hour',now()+interval '1 day',1000,'INR',1,'{}'::jsonb
  );

  BEGIN
    UPDATE public.campaigns SET status='active'
     WHERE id='00000000-0000-4000-8000-00000000c502' AND tenant_id=v_tenant_unconfigured;
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    v_activation_blocked := true;
  END;

  IF NOT v_activation_blocked THEN
    RAISE EXCEPTION 'budgeted campaign activated without explicit point valuation';
  END IF;

  RAISE NOTICE 'PASS: admin valuation, role denial, exact liability reserve, over-budget rejection, unchanged QR/ledger, rate immutability while active, and activation guard';
END;
$campaign_budget_test$;

ROLLBACK;
