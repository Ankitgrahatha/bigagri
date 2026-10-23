-- Behavioral coverage for tenant-scoped reward catalogue CRUD and activation.
-- Runs only against the disposable PostgreSQL service in CI; all fixtures roll back.
BEGIN;

DO $reward_catalogue_test$
DECLARE
  v_tenant_a constant uuid := '00000000-0000-4000-8000-00000000a101';
  v_tenant_b constant uuid := '00000000-0000-4000-8000-00000000a102';
  v_admin_a constant uuid := '00000000-0000-4000-8000-00000000a201';
  v_admin_b constant uuid := '00000000-0000-4000-8000-00000000a202';
  v_reward_id uuid;
  v_reward_b_id uuid;
  v_zero_stock_id uuid;
  v_demo_id uuid := '00000000-0000-4000-8000-00000000a301';
  v_result jsonb;
  v_count integer;
BEGIN
  INSERT INTO auth.users(id) VALUES (v_admin_a),(v_admin_b);
  INSERT INTO public.tenants(id,name,slug,status,default_locale,public_catalog_enabled)
  VALUES
    (v_tenant_a,'Reward Tenant A','reward-tenant-a','active','en-IN',false),
    (v_tenant_b,'Reward Tenant B','reward-tenant-b','active','en-IN',false);
  INSERT INTO public.tenant_memberships(tenant_id,user_id,role,status)
  VALUES (v_tenant_a,v_admin_a,'brand_admin','active'),(v_tenant_b,v_admin_b,'brand_admin','active');

  v_result := public.rewardloop_create_reward_internal(
    v_admin_a,v_tenant_a,'starter-kit','Farmer Starter Kit','किसान किट',
    'Essential tools for the season',NULL,'tools',100,5,10
  );
  IF v_result->>'ok' <> 'true'
     OR v_result->'reward'->>'active' <> 'false'
     OR v_result->'reward'->>'is_demo' <> 'false' THEN
    RAISE EXCEPTION 'authorized reward creation did not create an inactive real reward: %',v_result;
  END IF;
  v_reward_id := (v_result->'reward'->>'id')::uuid;

  v_result := public.rewardloop_create_reward_internal(
    v_admin_a,v_tenant_a,'starter-kit','Duplicate slug','Duplicate',NULL,NULL,'tools',100,5,10
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'reward_slug_exists' THEN
    RAISE EXCEPTION 'duplicate tenant reward slug was not rejected: %',v_result;
  END IF;

  v_result := public.rewardloop_create_reward_internal(
    v_admin_a,v_tenant_b,'cross-tenant','Unauthorized tenant reward',NULL,NULL,NULL,'tools',100,5,10
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'forbidden' THEN
    RAISE EXCEPTION 'cross-tenant reward creation was not rejected: %',v_result;
  END IF;

  v_result := public.rewardloop_create_reward_internal(
    v_admin_a,v_tenant_a,'invalid-cost','Invalid points',NULL,NULL,NULL,'tools',0,5,10
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'invalid_reward_details' THEN
    RAISE EXCEPTION 'invalid points cost was not rejected: %',v_result;
  END IF;

  v_result := public.rewardloop_create_reward_internal(
    v_admin_b,v_tenant_b,'starter-kit','Tenant B Starter Kit',NULL,NULL,NULL,'tools',200,3,10
  );
  IF v_result->>'ok' <> 'true' THEN RAISE EXCEPTION 'same slug in another tenant was rejected: %',v_result; END IF;
  v_reward_b_id := (v_result->'reward'->>'id')::uuid;

  v_result := public.rewardloop_update_reward_internal(
    v_admin_a,v_tenant_a,v_reward_b_id,'Cross-tenant edit',NULL,NULL,NULL,'tools',100,5,10
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'reward_not_found' THEN
    RAISE EXCEPTION 'cross-tenant reward update was not hidden: %',v_result;
  END IF;

  v_result := public.rewardloop_update_reward_internal(
    v_admin_a,v_tenant_a,v_reward_id,'Farmer Starter Kit Plus','किसान किट प्लस',
    'Updated description',NULL,'tools',125,8,20
  );
  IF v_result->>'ok' <> 'true' OR v_result->'reward'->>'points_cost' <> '125'
     OR v_result->'reward'->>'stock_quantity' <> '8' THEN
    RAISE EXCEPTION 'reward update failed: %',v_result;
  END IF;

  v_result := public.rewardloop_set_reward_status_internal(v_admin_a,v_tenant_a,v_reward_id,true,NULL);
  IF v_result->>'ok' <> 'true' OR v_result->>'active' <> 'true' THEN
    RAISE EXCEPTION 'valid reward activation failed: %',v_result;
  END IF;

  v_result := public.rewardloop_update_reward_internal(
    v_admin_a,v_tenant_a,v_reward_id,'Farmer Starter Kit Plus','किसान किट प्लस',
    'Updated description',NULL,'tools',125,0,20
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'deactivate_reward_before_zero_stock' THEN
    RAISE EXCEPTION 'active reward was allowed to become zero-stock: %',v_result;
  END IF;

  v_result := public.rewardloop_set_reward_status_internal(v_admin_a,v_tenant_a,v_reward_id,false,'');
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'invalid_reward_status_request' THEN
    RAISE EXCEPTION 'deactivation without a reason was accepted: %',v_result;
  END IF;
  v_result := public.rewardloop_set_reward_status_internal(v_admin_a,v_tenant_a,v_reward_id,false,'Seasonal reward withdrawn');
  IF v_result->>'ok' <> 'true' OR v_result->>'active' <> 'false' THEN
    RAISE EXCEPTION 'audited reward deactivation failed: %',v_result;
  END IF;

  v_result := public.rewardloop_create_reward_internal(
    v_admin_a,v_tenant_a,'out-of-stock','Out of Stock',NULL,NULL,NULL,'tools',100,0,30
  );
  IF v_result->>'ok' <> 'true' THEN RAISE EXCEPTION 'zero-stock inactive reward creation failed: %',v_result; END IF;
  v_zero_stock_id := (v_result->'reward'->>'id')::uuid;
  v_result := public.rewardloop_set_reward_status_internal(v_admin_a,v_tenant_a,v_zero_stock_id,true,NULL);
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'reward_out_of_stock' THEN
    RAISE EXCEPTION 'zero-stock reward activation was accepted: %',v_result;
  END IF;

  INSERT INTO public.rewards(id,tenant_id,slug,name,category,points_cost,stock_quantity,active,is_demo,sort_order)
  VALUES (v_demo_id,v_tenant_a,'demo-reward','Demo Reward','general',50,10,false,true,999);
  v_result := public.rewardloop_update_reward_internal(
    v_admin_a,v_tenant_a,v_demo_id,'Changed Demo',NULL,NULL,NULL,'general',50,10,999
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'demo_reward_read_only' THEN
    RAISE EXCEPTION 'demo reward edit was accepted: %',v_result;
  END IF;
  v_result := public.rewardloop_set_reward_status_internal(v_admin_a,v_tenant_a,v_demo_id,true,NULL);
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'demo_reward_not_activatable' THEN
    RAISE EXCEPTION 'demo reward activation was accepted: %',v_result;
  END IF;

  SELECT count(*) INTO v_count FROM public.audit_logs
   WHERE tenant_id=v_tenant_a AND entity_type='reward' AND entity_id=v_reward_id;
  IF v_count <> 4 THEN RAISE EXCEPTION 'create/update/activate/deactivate audit count mismatch: %',v_count; END IF;

  IF has_table_privilege('anon','public.rewards','SELECT')
     OR has_table_privilege('authenticated','public.rewards','SELECT')
     OR has_function_privilege('anon','public.rewardloop_create_reward_internal(uuid,uuid,text,text,text,text,text,text,integer,integer,integer)','EXECUTE')
     OR has_function_privilege('authenticated','public.rewardloop_update_reward_internal(uuid,uuid,uuid,text,text,text,text,text,integer,integer,integer)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.rewardloop_set_reward_status_internal(uuid,uuid,uuid,boolean,text)','EXECUTE') THEN
    RAISE EXCEPTION 'reward catalogue table or RPC privileges are not service-role only';
  END IF;

  RAISE NOTICE 'PASS: reward CRUD validation, tenant isolation, explicit activation, demo protection, stock safety, audit trail and privileges';
END
$reward_catalogue_test$;

ROLLBACK;
