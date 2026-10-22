-- Product metadata editing preserves immutable SKU and tenant-scoped audit history.
BEGIN;
DO $product_edit_test$
DECLARE
  v_tenant constant uuid := '00000000-0000-4000-8000-00000000e501';
  v_other constant uuid := '00000000-0000-4000-8000-00000000e502';
  v_admin constant uuid := '00000000-0000-4000-8000-00000000e601';
  v_other_admin constant uuid := '00000000-0000-4000-8000-00000000e602';
  v_product constant uuid := '00000000-0000-4000-8000-00000000e701';
  v_result jsonb;
  v_name text;
  v_sku text;
  v_audit integer;
BEGIN
  INSERT INTO auth.users(id) VALUES(v_admin),(v_other_admin);
  INSERT INTO public.tenants(id,name,slug,status,default_locale,public_catalog_enabled)
  VALUES
   (v_tenant,'Edit Tenant','edit-tenant','active','en-IN',false),
   (v_other,'Other Edit Tenant','other-edit-tenant','active','en-IN',false);
  INSERT INTO public.tenant_memberships(tenant_id,user_id,role,status)
  VALUES(v_tenant,v_admin,'brand_admin','active'),(v_other,v_other_admin,'super_admin','active');
  INSERT INTO public.products(id,tenant_id,sku,name,pack_size,active,metadata)
  VALUES(v_product,v_tenant,'EDIT-SKU-01','Old Name','10 g',true,'{}'::jsonb);

  v_result:=public.rewardloop_update_product_internal(v_admin,v_tenant,v_product,'New Hybrid Tomato','25 g');
  IF v_result->>'ok'<>'true' OR v_result#>>'{product,name}'<>'New Hybrid Tomato' OR v_result#>>'{product,pack_size}'<>'25 g' THEN
    RAISE EXCEPTION 'valid product edit failed: %',v_result;
  END IF;
  v_result:=public.rewardloop_update_product_internal(v_admin,v_other,v_product,'Cross Tenant Edit',NULL);
  IF v_result->>'ok'<>'false' OR v_result->>'error'<>'forbidden' THEN
    RAISE EXCEPTION 'cross-tenant edit should be forbidden: %',v_result;
  END IF;
  v_result:=public.rewardloop_update_product_internal(v_admin,v_tenant,v_product,'x',NULL);
  IF v_result->>'ok'<>'false' OR v_result->>'error'<>'invalid_product_details' THEN
    RAISE EXCEPTION 'invalid product name should fail: %',v_result;
  END IF;
  SELECT name,sku INTO v_name,v_sku FROM public.products WHERE id=v_product;
  SELECT count(*) INTO v_audit FROM public.audit_logs WHERE tenant_id=v_tenant AND entity_id=v_product AND action='product_updated';
  IF v_name<>'New Hybrid Tomato' OR v_sku<>'EDIT-SKU-01' OR v_audit<>1 THEN
    RAISE EXCEPTION 'product edit invariant failed: name=%, sku=%, audit=%',v_name,v_sku,v_audit;
  END IF;
  RAISE NOTICE 'PASS: edit validation, tenant isolation, immutable SKU, one audit record';
END
$product_edit_test$;
ROLLBACK;
