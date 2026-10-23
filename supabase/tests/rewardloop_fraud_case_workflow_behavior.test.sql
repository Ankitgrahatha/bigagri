-- Tenant isolation and lifecycle tests for the manual fraud-case workflow.
-- Disposable PostgreSQL only; all fixture rows are rolled back.
BEGIN;

DO $fraud_case_workflow_test$
DECLARE
  v_tenant_a constant uuid := '00000000-0000-4000-8000-00000000f101';
  v_tenant_b constant uuid := '00000000-0000-4000-8000-00000000f102';
  v_admin_a constant uuid := '00000000-0000-4000-8000-00000000f201';
  v_admin_b constant uuid := '00000000-0000-4000-8000-00000000f202';
  v_farmer constant uuid := '00000000-0000-4000-8000-00000000f203';
  v_partner_b constant uuid := '00000000-0000-4000-8000-00000000f301';
  v_case_id uuid;
  v_result jsonb;
  v_count integer;
BEGIN
  INSERT INTO auth.users(id) VALUES (v_admin_a),(v_admin_b),(v_farmer);
  INSERT INTO public.tenants(id,name,slug,status,default_locale,public_catalog_enabled)
  VALUES
    (v_tenant_a,'Fraud Tenant A','fraud-tenant-a','active','en-IN',false),
    (v_tenant_b,'Fraud Tenant B','fraud-tenant-b','active','en-IN',false);
  INSERT INTO public.tenant_memberships(tenant_id,user_id,role,status)
  VALUES
    (v_tenant_a,v_admin_a,'brand_admin','active'),
    (v_tenant_b,v_admin_b,'brand_admin','active');
  INSERT INTO public.partners(id,tenant_id,user_id,role,display_name,verification_status)
  VALUES (v_partner_b,v_tenant_b,v_admin_b,'farmer','Tenant B partner','verified');

  v_result := public.rewardloop_create_fraud_case_internal(
    v_admin_a,v_tenant_a,'Repeated QR claim attempts','repeated_claims','high',
    'Several rejected attempts within a short window',NULL,NULL,NULL
  );
  IF v_result->>'ok' <> 'true' THEN
    RAISE EXCEPTION 'authorized case creation failed: %',v_result;
  END IF;
  v_case_id := (v_result->'case'->>'id')::uuid;

  UPDATE public.tenants SET status='suspended' WHERE id=v_tenant_a;
  v_result := public.rewardloop_update_fraud_case_internal(
    v_admin_a,v_tenant_a,v_case_id,'investigating',NULL,NULL,NULL
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'tenant_inactive' THEN
    RAISE EXCEPTION 'suspended tenant case update was not rejected: %',v_result;
  END IF;
  UPDATE public.tenants SET status='active' WHERE id=v_tenant_a;

  v_result := public.rewardloop_create_fraud_case_internal(
    v_admin_a,v_tenant_a,'Cross-tenant partner reference','partner_mismatch','medium',
    'Must not link tenant B partner',v_partner_b,NULL,NULL
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'partner_not_found' THEN
    RAISE EXCEPTION 'cross-tenant partner reference was not rejected: %',v_result;
  END IF;

  v_result := public.rewardloop_create_fraud_case_internal(
    v_admin_a,v_tenant_b,'Cross-tenant case','cross_tenant','high',NULL,NULL,NULL,NULL
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'forbidden' THEN
    RAISE EXCEPTION 'cross-tenant case creation was not rejected: %',v_result;
  END IF;

  v_result := public.rewardloop_create_fraud_case_internal(
    v_farmer,v_tenant_a,'Unauthorized case','unauthorized_case','low',NULL,NULL,NULL,NULL
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'forbidden' THEN
    RAISE EXCEPTION 'non-admin case creation was not rejected: %',v_result;
  END IF;

  v_result := public.rewardloop_update_fraud_case_internal(
    v_admin_a,v_tenant_b,v_case_id,'investigating',NULL,NULL,NULL
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'forbidden' THEN
    RAISE EXCEPTION 'cross-tenant case update was not rejected: %',v_result;
  END IF;

  v_result := public.rewardloop_update_fraud_case_internal(
    v_admin_a,v_tenant_a,v_case_id,'investigating',NULL,NULL,NULL
  );
  IF v_result->>'ok' <> 'true' OR v_result->>'status' <> 'investigating' THEN
    RAISE EXCEPTION 'case investigation transition failed: %',v_result;
  END IF;

  v_result := public.rewardloop_update_fraud_case_internal(
    v_admin_a,v_tenant_a,v_case_id,'investigating',v_admin_b,NULL,NULL
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'assignee_not_authorized' THEN
    RAISE EXCEPTION 'cross-tenant assignee was not rejected: %',v_result;
  END IF;

  v_result := public.rewardloop_update_fraud_case_internal(
    v_admin_a,v_tenant_a,v_case_id,'dismissed',NULL,'insufficient_evidence',''
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'resolution_details_required' THEN
    RAISE EXCEPTION 'resolution without evidence notes was not rejected: %',v_result;
  END IF;

  v_result := public.rewardloop_update_fraud_case_internal(
    v_admin_a,v_tenant_a,v_case_id,'resolved_legitimate',NULL,'false_positive',
    'Review found no evidence of intentional abuse'
  );
  IF v_result->>'ok' <> 'true' OR v_result->>'status' <> 'resolved_legitimate' THEN
    RAISE EXCEPTION 'case resolution failed: %',v_result;
  END IF;

  v_result := public.rewardloop_update_fraud_case_internal(
    v_admin_a,v_tenant_a,v_case_id,'investigating',NULL,NULL,NULL
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'fraud_case_terminal' THEN
    RAISE EXCEPTION 'terminal case was reopened: %',v_result;
  END IF;

  v_result := public.rewardloop_update_fraud_case_internal(
    v_admin_a,v_tenant_a,v_case_id,'dismissed',NULL,'no_evidence',''
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'fraud_case_terminal' THEN
    RAISE EXCEPTION 'terminal case accepted a second resolution: %',v_result;
  END IF;

  SELECT count(*) INTO v_count FROM public.audit_logs
   WHERE tenant_id=v_tenant_a AND entity_type='fraud_case' AND entity_id=v_case_id;
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'case open/investigate/resolve audit count mismatch: %',v_count;
  END IF;

  IF has_table_privilege('anon','public.fraud_cases','SELECT')
     OR has_table_privilege('authenticated','public.fraud_cases','SELECT')
     OR NOT has_table_privilege('service_role','public.fraud_cases','SELECT') THEN
    RAISE EXCEPTION 'fraud case table grants are not service-role only';
  END IF;

  RAISE NOTICE 'PASS: tenant isolation, role checks, lifecycle transitions, terminality, audit history and table grants';
END
$fraud_case_workflow_test$;

ROLLBACK;
