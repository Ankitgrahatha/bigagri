-- Exact dashboard counts must be tenant-scoped and independent of page limits.
-- All fixture rows are rolled back. Run only in the disposable PostgreSQL CI database.
BEGIN;

DO $dashboard_metrics_test$
DECLARE
  v_tenant constant uuid := '00000000-0000-4000-8000-00000000b101';
  v_admin constant uuid := '00000000-0000-4000-8000-00000000b201';
  v_non_admin constant uuid := '00000000-0000-4000-8000-00000000b202';
  v_farmer_a constant uuid := '00000000-0000-4000-8000-00000000b203';
  v_farmer_b constant uuid := '00000000-0000-4000-8000-00000000b204';
  v_partner_a constant uuid := '00000000-0000-4000-8000-00000000b301';
  v_partner_b constant uuid := '00000000-0000-4000-8000-00000000b302';
  v_product constant uuid := '00000000-0000-4000-8000-00000000b401';
  v_campaign constant uuid := '00000000-0000-4000-8000-00000000b501';
  v_batch_a constant uuid := '00000000-0000-4000-8000-00000000b601';
  v_batch_b constant uuid := '00000000-0000-4000-8000-00000000b602';
  v_reward constant uuid := '00000000-0000-4000-8000-00000000b701';
  v_redemption_a constant uuid := '00000000-0000-4000-8000-00000000b801';
  v_redemption_b constant uuid := '00000000-0000-4000-8000-00000000b802';
  v_metrics jsonb;
  v_denied jsonb;
BEGIN
  INSERT INTO auth.users(id) VALUES (v_admin), (v_non_admin), (v_farmer_a), (v_farmer_b);
  INSERT INTO public.tenants(id,name,slug,status,default_locale,public_catalog_enabled)
  VALUES(v_tenant,'Metrics Test Tenant','metrics-test-tenant','active','en-IN',false);
  INSERT INTO public.tenant_memberships(tenant_id,user_id,role,status)
  VALUES(v_tenant,v_admin,'brand_admin','active');
  INSERT INTO public.partners(id,tenant_id,user_id,role,display_name,verification_status)
  VALUES
   (v_partner_a,v_tenant,v_farmer_a,'farmer','Pending Metrics Farmer','pending'),
   (v_partner_b,v_tenant,v_farmer_b,'farmer','Verified Metrics Farmer','verified');
  INSERT INTO public.products(id,tenant_id,sku,name,active,metadata)
  VALUES(v_product,v_tenant,'METRICS-SKU','Metrics Product',true,'{}'::jsonb);
  INSERT INTO public.campaigns(id,tenant_id,name,status,starts_at,ends_at,budget_minor_units,currency,rules_version,rules)
  VALUES(v_campaign,v_tenant,'Metrics Active Campaign','active',now()-interval '1 hour',now()+interval '1 day',10000,'INR',1,'{}'::jsonb);
  INSERT INTO public.qr_issuance_batches(
    id,tenant_id,product_id,campaign_id,created_by,requested_count,points_value,entitlement_role,status
  ) VALUES
    (v_batch_a,v_tenant,v_product,v_campaign,v_admin,20,10,'farmer','issued'),
    (v_batch_b,v_tenant,v_product,v_campaign,v_admin,5,10,'farmer','revoked');
  INSERT INTO public.rewards(id,tenant_id,slug,name,category,points_cost,stock_quantity,active,is_demo,sort_order,metadata)
  VALUES(v_reward,v_tenant,'metrics-reward','Metrics Reward','general',20,5,true,false,1,'{}'::jsonb);
  INSERT INTO public.redemptions(id,tenant_id,partner_id,reward_id,points_cost,status,request_key)
  VALUES
    (v_redemption_a,v_tenant,v_partner_a,v_reward,20,'reserved','metrics-request-001'),
    (v_redemption_b,v_tenant,v_partner_b,v_reward,20,'fulfilled','metrics-request-002');

  v_metrics := public.rewardloop_admin_dashboard_metrics_internal(v_admin,v_tenant);

  IF v_metrics->>'ok' <> 'true'
     OR v_metrics->>'partners_total' <> '2'
     OR v_metrics->>'partners_pending' <> '1'
     OR v_metrics->>'campaigns_total' <> '1'
     OR v_metrics->>'campaigns_active' <> '1'
     OR v_metrics->>'products_total' <> '1'
     OR v_metrics->>'products_active' <> '1'
     OR v_metrics->>'qr_batches_total' <> '2'
     OR v_metrics->>'qr_codes_issued_total' <> '25'
     OR v_metrics->>'redemptions_total' <> '2'
     OR v_metrics->>'redemptions_open' <> '1' THEN
    RAISE EXCEPTION 'exact dashboard metrics mismatch: %',v_metrics;
  END IF;

  v_denied := public.rewardloop_admin_dashboard_metrics_internal(v_non_admin,v_tenant);
  IF v_denied->>'ok' <> 'false' OR v_denied->>'error' <> 'forbidden' THEN
    RAISE EXCEPTION 'non-admin must not retrieve dashboard metrics: %',v_denied;
  END IF;

  IF has_function_privilege('anon','public.rewardloop_admin_dashboard_metrics_internal(uuid,uuid)','EXECUTE')
     OR has_function_privilege('authenticated','public.rewardloop_admin_dashboard_metrics_internal(uuid,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'client roles unexpectedly can call metrics RPC directly';
  END IF;
  IF NOT has_function_privilege('service_role','public.rewardloop_admin_dashboard_metrics_internal(uuid,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'service_role cannot invoke metrics RPC';
  END IF;

  RAISE NOTICE 'PASS: exact tenant-scoped global counts and non-admin/direct-client denial';
END;
$dashboard_metrics_test$;

ROLLBACK;
