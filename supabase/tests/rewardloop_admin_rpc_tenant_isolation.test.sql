-- Tenant-boundary regression matrix for privileged database RPCs.
-- Only synthetic rows in disposable PostgreSQL; everything is rolled back at the end.
BEGIN;

DO $admin_rpc_tenant_isolation$
DECLARE
  v_tenant_a constant uuid := '00000000-0000-4000-8000-00000000d101';
  v_tenant_b constant uuid := '00000000-0000-4000-8000-00000000d102';
  v_admin_a constant uuid := '00000000-0000-4000-8000-00000000d201';
  v_admin_b constant uuid := '00000000-0000-4000-8000-00000000d202';
  v_farmer_a constant uuid := '00000000-0000-4000-8000-00000000d203';
  v_farmer_b constant uuid := '00000000-0000-4000-8000-00000000d204';
  v_partner_a constant uuid := '00000000-0000-4000-8000-00000000d301';
  v_partner_b constant uuid := '00000000-0000-4000-8000-00000000d302';
  v_product_a constant uuid := '00000000-0000-4000-8000-00000000d401';
  v_product_b constant uuid := '00000000-0000-4000-8000-00000000d402';
  v_campaign_a constant uuid := '00000000-0000-4000-8000-00000000d501';
  v_campaign_b constant uuid := '00000000-0000-4000-8000-00000000d502';
  v_batch_b constant uuid := '00000000-0000-4000-8000-00000000d601';
  v_qr_b constant uuid := '00000000-0000-4000-8000-00000000d602';
  v_reward_a constant uuid := '00000000-0000-4000-8000-00000000d701';
  v_reward_b constant uuid := '00000000-0000-4000-8000-00000000d702';
  v_redemption_a constant uuid := '00000000-0000-4000-8000-00000000d801';
  v_redemption_b constant uuid := '00000000-0000-4000-8000-00000000d802';
  v_result jsonb;
  v_count_before integer;
  v_count_after integer;
  v_status text;
  v_stock integer;
  v_ledger_count integer;
BEGIN
  INSERT INTO auth.users(id) VALUES (v_admin_a),(v_admin_b),(v_farmer_a),(v_farmer_b);

  INSERT INTO public.tenants(id,name,slug,status,default_locale,public_catalog_enabled)
  VALUES
    (v_tenant_a,'RPC Tenant A','rpc-tenant-a','active','en-IN',false),
    (v_tenant_b,'RPC Tenant B','rpc-tenant-b','active','en-IN',false);

  INSERT INTO public.tenant_memberships(tenant_id,user_id,role,status)
  VALUES
    (v_tenant_a,v_admin_a,'brand_admin','active'),
    (v_tenant_b,v_admin_b,'brand_admin','active');

  INSERT INTO public.partners(id,tenant_id,user_id,role,display_name,verification_status)
  VALUES
    (v_partner_a,v_tenant_a,v_farmer_a,'farmer','RPC Farmer A','pending'),
    (v_partner_b,v_tenant_b,v_farmer_b,'farmer','RPC Farmer B','pending');

  INSERT INTO public.products(id,tenant_id,sku,name,active,metadata)
  VALUES
    (v_product_a,v_tenant_a,'RPC-SKU-A','RPC Product A',true,'{}'::jsonb),
    (v_product_b,v_tenant_b,'RPC-SKU-B','RPC Product B',true,'{}'::jsonb);

  INSERT INTO public.campaigns(
    id,tenant_id,name,status,starts_at,ends_at,budget_minor_units,currency,rules_version,rules
  )
  VALUES
    (v_campaign_a,v_tenant_a,'RPC Campaign A','active',now()-interval '1 hour',now()+interval '1 day',0,'INR',1,'{}'::jsonb),
    (v_campaign_b,v_tenant_b,'RPC Campaign B','active',now()-interval '1 hour',now()+interval '1 day',0,'INR',1,'{}'::jsonb);

  INSERT INTO public.qr_issuance_batches(
    id,tenant_id,product_id,campaign_id,created_by,requested_count,points_value,entitlement_role,status
  )
  VALUES(v_batch_b,v_tenant_b,v_product_b,v_campaign_b,v_admin_b,1,10,'farmer','issued');

  INSERT INTO public.qr_codes(
    id,tenant_id,product_id,campaign_id,issuance_batch_id,token_hash,status,entitlement_role,points_value,activated_at,metadata
  )
  VALUES(
    v_qr_b,v_tenant_b,v_product_b,v_campaign_b,v_batch_b,
    encode(extensions.digest(convert_to('rpc-tenant-b-qr-test-token','UTF8'),'sha256'),'hex'),
    'active','farmer',10,now(),'{}'::jsonb
  );

  INSERT INTO public.rewards(
    id,tenant_id,slug,name,category,points_cost,stock_quantity,active,is_demo,sort_order,metadata
  )
  VALUES
    (v_reward_a,v_tenant_a,'rpc-reward-a','RPC Reward A','general',10,5,true,false,1,'{}'::jsonb),
    (v_reward_b,v_tenant_b,'rpc-reward-b','RPC Reward B','general',10,5,true,false,1,'{}'::jsonb);

  INSERT INTO public.redemptions(id,tenant_id,partner_id,reward_id,points_cost,status,request_key)
  VALUES
    (v_redemption_a,v_tenant_a,v_partner_a,v_reward_a,10,'reserved','rpc-request-tenant-a'),
    (v_redemption_b,v_tenant_b,v_partner_b,v_reward_b,10,'reserved','rpc-request-tenant-b');

  -- Admin A must not create a campaign inside tenant B.
  SELECT count(*) INTO v_count_before FROM public.campaigns WHERE tenant_id=v_tenant_b;
  v_result := public.rewardloop_create_campaign_internal(
    v_admin_a,v_tenant_b,'Cross Tenant Campaign',now()-interval '1 hour',now()+interval '1 day',0
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'forbidden' THEN
    RAISE EXCEPTION 'cross-tenant campaign creation was not denied: %',v_result;
  END IF;
  SELECT count(*) INTO v_count_after FROM public.campaigns WHERE tenant_id=v_tenant_b;
  IF v_count_after <> v_count_before THEN
    RAISE EXCEPTION 'cross-tenant create_campaign wrote a record';
  END IF;

  -- An authenticated but non-admin farmer cannot issue a batch.
  v_result := public.rewardloop_issue_qr_batch_internal(
    v_farmer_a,v_tenant_a,v_campaign_a,v_product_a,1,10,'farmer'
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'forbidden' THEN
    RAISE EXCEPTION 'non-admin batch issuance was not denied: %',v_result;
  END IF;

  -- A valid admin for A cannot combine A tenant context with B's product/campaign.
  SELECT count(*) INTO v_count_before FROM public.qr_issuance_batches WHERE tenant_id=v_tenant_a;
  v_result := public.rewardloop_issue_qr_batch_internal(
    v_admin_a,v_tenant_a,v_campaign_b,v_product_b,1,10,'farmer'
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'tenant_product_or_campaign_not_active' THEN
    RAISE EXCEPTION 'cross-tenant product/campaign batch issuance was not denied: %',v_result;
  END IF;
  SELECT count(*) INTO v_count_after FROM public.qr_issuance_batches WHERE tenant_id=v_tenant_a;
  IF v_count_after <> v_count_before THEN
    RAISE EXCEPTION 'cross-tenant batch attempt created a batch';
  END IF;

  -- Batch revocation, partner verification and campaign lifecycle must scope the resource by tenant.
  v_result := public.rewardloop_revoke_qr_batch_internal(
    v_admin_a,v_tenant_a,v_batch_b,'test cross-tenant revocation'
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'batch_not_found' THEN
    RAISE EXCEPTION 'cross-tenant batch revocation was not denied: %',v_result;
  END IF;

  v_result := public.rewardloop_verify_partner_internal(
    v_admin_a,v_tenant_a,v_partner_b,'verified',''
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'partner_not_found' THEN
    RAISE EXCEPTION 'cross-tenant partner verification was not denied: %',v_result;
  END IF;

  v_result := public.rewardloop_verify_partner_internal(
    v_farmer_a,v_tenant_a,v_partner_a,'verified',''
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'forbidden' THEN
    RAISE EXCEPTION 'non-admin partner verification was not denied: %',v_result;
  END IF;

  v_result := public.rewardloop_set_campaign_status_internal(
    v_admin_a,v_tenant_a,v_campaign_b,'paused','test wrong tenant'
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'campaign_not_found' THEN
    RAISE EXCEPTION 'cross-tenant campaign lifecycle change was not denied: %',v_result;
  END IF;

  v_result := public.rewardloop_set_campaign_status_internal(
    v_farmer_a,v_tenant_a,v_campaign_a,'paused','test non-admin'
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'forbidden' THEN
    RAISE EXCEPTION 'non-admin campaign lifecycle change was not denied: %',v_result;
  END IF;

  -- Redemption resolution must not expose or mutate a redemption from another tenant.
  v_result := public.rewardloop_resolve_redemption_internal(
    v_admin_a,v_tenant_a,v_redemption_b,'cancelled','test wrong tenant'
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'redemption_not_found' THEN
    RAISE EXCEPTION 'cross-tenant redemption resolution was not denied: %',v_result;
  END IF;

  v_result := public.rewardloop_resolve_redemption_internal(
    v_farmer_a,v_tenant_a,v_redemption_a,'cancelled','test non-admin'
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'forbidden' THEN
    RAISE EXCEPTION 'non-admin redemption resolution was not denied: %',v_result;
  END IF;

  -- Verify that rejected requests left every tenant-B resource unchanged.
  SELECT status::text INTO v_status FROM public.qr_codes WHERE id=v_qr_b;
  IF v_status <> 'active' THEN
    RAISE EXCEPTION 'cross-tenant revocation changed tenant B QR status: %',v_status;
  END IF;
  SELECT verification_status::text INTO v_status FROM public.partners WHERE id=v_partner_b;
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'cross-tenant verification changed tenant B partner status: %',v_status;
  END IF;
  SELECT status::text INTO v_status FROM public.campaigns WHERE id=v_campaign_b;
  IF v_status <> 'active' THEN
    RAISE EXCEPTION 'cross-tenant lifecycle change mutated tenant B campaign: %',v_status;
  END IF;
  SELECT status::text INTO v_status FROM public.redemptions WHERE id=v_redemption_b;
  IF v_status <> 'reserved' THEN
    RAISE EXCEPTION 'cross-tenant resolution changed tenant B redemption status: %',v_status;
  END IF;
  SELECT stock_quantity INTO v_stock FROM public.rewards WHERE id=v_reward_b;
  SELECT count(*) INTO v_ledger_count FROM public.points_ledger WHERE tenant_id=v_tenant_b;
  IF v_stock <> 5 OR v_ledger_count <> 0 THEN
    RAISE EXCEPTION 'cross-tenant resolution changed tenant B reward/ledger: stock=%, ledger=%',v_stock,v_ledger_count;
  END IF;

  RAISE NOTICE 'PASS: tenant membership, cross-tenant resource binding, and no-mutation assertions across campaign creation, QR issuance/revocation, partner verification, campaign lifecycle and redemption resolution';
END;
$admin_rpc_tenant_isolation$;

ROLLBACK;
