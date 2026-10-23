-- Billing portal authorization and published-plan visibility regression. Disposable CI DB only.
BEGIN;
DO $billing_portal$
DECLARE
  v_tenant uuid := 'e7b3f8e2-5f33-4c3b-9f2b-6b8200010001';
  v_user uuid := 'e7b3f8e2-5f33-4c3b-9f2b-6b8200010002';
  v_other uuid := 'e7b3f8e2-5f33-4c3b-9f2b-6b8200010099';
  v_plan uuid := 'e7b3f8e2-5f33-4c3b-9f2b-6b8200010003';
  v_version uuid := 'e7b3f8e2-5f33-4c3b-9f2b-6b8200010004';
  v_result jsonb;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_user, 'billing-portal@example.invalid');
  INSERT INTO public.tenants (id, name, slug, status) VALUES (v_tenant, 'Billing portal tenant', 'billing-portal-tenant', 'active');
  INSERT INTO public.tenant_memberships (tenant_id, user_id, role, status) VALUES (v_tenant, v_user, 'super_admin', 'active');
  INSERT INTO private.saas_plans (id, plan_key, display_name, status) VALUES (v_plan, 'portal_test', 'Portal Test', 'published');
  INSERT INTO private.saas_plan_versions (id, plan_id, version_no, currency, monthly_amount_minor, yearly_amount_minor, monthly_provider_plan_id, yearly_provider_plan_id, published_at)
  VALUES (v_version, v_plan, 1, 'INR', 12000, 120000, 'plan_portal_monthly', 'plan_portal_yearly', now());

  v_result := public.get_saas_billing_portal_internal(v_user, v_tenant);
  IF v_result->>'ok' <> 'true' OR jsonb_array_length(v_result->'plans') <> 1
     OR v_result->'plans'->0->>'plan_version_id' <> v_version::text
     OR v_result->'subscription' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'published billing catalog response is incorrect: %', v_result;
  END IF;

  v_result := public.get_saas_billing_portal_internal(v_other, v_tenant);
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'forbidden' THEN
    RAISE EXCEPTION 'unauthorized user was allowed to view tenant billing: %', v_result;
  END IF;
  RAISE NOTICE 'PASS: billing portal catalog is tenant-authorized and only exposes published plans';
END
$billing_portal$;
ROLLBACK;
