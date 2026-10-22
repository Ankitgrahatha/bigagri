-- Product lifecycle status is tenant-scoped, audited, reasoned on deactivation, and idempotent.
BEGIN;
DO $product_lifecycle_test$
DECLARE
  v_tenant_a constant uuid := '00000000-0000-4000-8000-00000000f101';
  v_tenant_b constant uuid := '00000000-0000-4000-8000-00000000f102';
  v_admin_a constant uuid := '00000000-0000-4000-8000-00000000f201';
  v_admin_b constant uuid := '00000000-0000-4000-8000-00000000f202';
  v_product_a constant uuid := '00000000-0000-4000-8000-00000000f301';
  v_result jsonb;
  v_active boolean;
  v_audit_count integer;
BEGIN
  INSERT INTO auth.users(id) VALUES(v_admin_a),(v_admin_b);
  INSERT INTO public.tenants(id,name,slug,status,default_locale,public_catalog_enabled)
  VALUES
   (v_tenant_a,'Lifecycle Tenant A','lifecycle-tenant-a','active','en-IN',false),
   (v_tenant_b,'Lifecycle Tenant B','lifecycle-tenant-b','active','en-IN',false);
  INSERT INTO public.tenant_memberships(tenant_id,user_id,role,status)
  VALUES(v_tenant_a,v_admin_a,'brand_admin','active'),(v_tenant_b,v_admin_b,'super_admin','active');
  INSERT INTO public.products(id,tenant_id,sku,name,active,metadata)
  VALUES(v_product_a,v_tenant_a,'LIFECYCLE-SKU-01','Lifecycle Product',true,'{}'::jsonb);

  v_result := public.rewardloop_set_product_status_internal(v_admin_a,v_tenant_a,v_product_a,false,'retired product');
  IF v_result->>'ok'<>'true' OR v_result->>'active'<>'false' THEN
    RAISE EXCEPTION 'deactivation failed: %',v_result;
  END IF;
  v_result := public.rewardloop_set_product_status_internal(v_admin_a,v_tenant_a,v_product_a,false,'repeat');
  IF v_result->>'ok'<>'true' OR v_result->>'unchanged'<>'true' THEN
    RAISE EXCEPTION 'repeat deactivation should be idempotent: %',v_result;
  END IF;
  v_result := public.rewardloop_set_product_status_internal(v_admin_a,v_tenant_b,v_product_a,true,NULL);
  IF v_result->>'ok'<>'false' OR v_result->>'error'<>'forbidden' THEN
    RAISE EXCEPTION 'cross-tenant product mutation was not denied: %',v_result;
  END IF;
  v_result := public.rewardloop_set_product_status_internal(v_admin_a,v_tenant_a,v_product_a,true,NULL);
  IF v_result->>'ok'<>'true' OR v_result->>'active'<>'true' THEN
    RAISE EXCEPTION 'reactivation failed: %',v_result;
  END IF;

  SELECT active INTO v_active FROM public.products WHERE id=v_product_a;
  SELECT count(*) INTO v_audit_count FROM public.audit_logs
   WHERE tenant_id=v_tenant_a AND entity_id=v_product_a
     AND action IN ('product_activated','product_deactivated');
  IF v_active IS DISTINCT FROM true OR v_audit_count<>2 THEN
    RAISE EXCEPTION 'product status/audit mismatch: active=%, audit=%',v_active,v_audit_count;
  END IF;

  v_result := public.rewardloop_set_product_status_internal(v_admin_a,v_tenant_a,v_product_a,false,'');
  IF v_result->>'ok'<>'false' OR v_result->>'error'<>'invalid_product_status_request' THEN
    RAISE EXCEPTION 'deactivation without a reason should fail: %',v_result;
  END IF;

  RAISE NOTICE 'PASS: tenant scope, audited deactivation/reactivation, reason validation, idempotent repeated status';
END
$product_lifecycle_test$;
ROLLBACK;
