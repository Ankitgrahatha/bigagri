-- Product creation authorization, uniqueness, and audit behavior.
-- Disposable PostgreSQL only; every row is rolled back.
BEGIN;

DO $product_creation_test$
DECLARE
  v_tenant_a constant uuid := '00000000-0000-4000-8000-00000000e101';
  v_tenant_b constant uuid := '00000000-0000-4000-8000-00000000e102';
  v_admin_a constant uuid := '00000000-0000-4000-8000-00000000e201';
  v_admin_b constant uuid := '00000000-0000-4000-8000-00000000e202';
  v_farmer constant uuid := '00000000-0000-4000-8000-00000000e203';
  v_created jsonb;
  v_duplicate jsonb;
  v_cross_tenant jsonb;
  v_non_admin jsonb;
  v_product_id uuid;
  v_product_count integer;
  v_audit_count integer;
BEGIN
  INSERT INTO auth.users(id) VALUES (v_admin_a), (v_admin_b), (v_farmer);

  INSERT INTO public.tenants(id,name,slug,status,default_locale,public_catalog_enabled)
  VALUES
    (v_tenant_a,'Product Test Tenant A','product-test-tenant-a','active','en-IN',false),
    (v_tenant_b,'Product Test Tenant B','product-test-tenant-b','active','en-IN',false);

  INSERT INTO public.tenant_memberships(tenant_id,user_id,role,status)
  VALUES
    (v_tenant_a,v_admin_a,'brand_admin','active'),
    (v_tenant_b,v_admin_b,'super_admin','active'),
    (v_tenant_a,v_farmer,'support','active');

  v_created := public.rewardloop_create_product_internal(
    v_admin_a,v_tenant_a,' test-sku-001 ','Hybrid Tomato Seed','10 g'
  );
  IF v_created->>'ok' <> 'true'
     OR v_created#>>'{product,sku}' <> 'TEST-SKU-001'
     OR v_created#>>'{product,name}' <> 'Hybrid Tomato Seed'
     OR v_created#>>'{product,pack_size}' <> '10 g' THEN
    RAISE EXCEPTION 'authorized product creation failed: %',v_created;
  END IF;
  v_product_id := (v_created#>>'{product,id}')::uuid;

  v_duplicate := public.rewardloop_create_product_internal(
    v_admin_a,v_tenant_a,'TEST-SKU-001','Duplicate SKU','25 g'
  );
  IF v_duplicate->>'ok' <> 'false' OR v_duplicate->>'error' <> 'sku_exists' THEN
    RAISE EXCEPTION 'duplicate SKU did not return safe conflict: %',v_duplicate;
  END IF;

  v_cross_tenant := public.rewardloop_create_product_internal(
    v_admin_a,v_tenant_b,'CROSS-TENANT-001','Cross Tenant Product',NULL
  );
  IF v_cross_tenant->>'ok' <> 'false' OR v_cross_tenant->>'error' <> 'forbidden' THEN
    RAISE EXCEPTION 'tenant A admin could create product in tenant B: %',v_cross_tenant;
  END IF;

  v_non_admin := public.rewardloop_create_product_internal(
    v_farmer,v_tenant_a,'FARMER-CREATE-001','Farmer Product',NULL
  );
  IF v_non_admin->>'ok' <> 'false' OR v_non_admin->>'error' <> 'forbidden' THEN
    RAISE EXCEPTION 'non-admin could create product: %',v_non_admin;
  END IF;

  SELECT count(*) INTO v_product_count FROM public.products WHERE tenant_id=v_tenant_a;
  SELECT count(*) INTO v_audit_count FROM public.audit_logs
   WHERE tenant_id=v_tenant_a AND action='product_created' AND entity_id=v_product_id;

  IF v_product_count <> 1 OR v_audit_count <> 1 THEN
    RAISE EXCEPTION 'product/audit counts mismatch: products=%, audit=%',v_product_count,v_audit_count;
  END IF;

  IF has_function_privilege('anon','private.create_rewardloop_product(uuid,uuid,text,text,text)','EXECUTE')
     OR has_function_privilege('authenticated','private.create_rewardloop_product(uuid,uuid,text,text,text)','EXECUTE')
     OR has_function_privilege('anon','public.rewardloop_create_product_internal(uuid,uuid,text,text,text)','EXECUTE')
     OR has_function_privilege('authenticated','public.rewardloop_create_product_internal(uuid,uuid,text,text,text)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.rewardloop_create_product_internal(uuid,uuid,text,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'product creation RPC grants are not least-privilege';
  END IF;

  RAISE NOTICE 'PASS: normalized SKU, admin authorization, tenant isolation, duplicate conflict, single audit row, RPC grants';
END;
$product_creation_test$;

ROLLBACK;
