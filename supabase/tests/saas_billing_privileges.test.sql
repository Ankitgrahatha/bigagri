-- Runs only against the disposable PostgreSQL database in CI.
DO $saas_billing_security$
DECLARE
  v_table text;
  v_relation text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'saas_payment_webhook_events',
    'saas_plans',
    'saas_plan_versions',
    'saas_tenant_subscriptions',
    'saas_payment_attempts'
  ] LOOP
    v_relation := format('private.%I', v_table);

    IF NOT EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'private'
        AND c.relname = v_table
        AND c.relrowsecurity
        AND c.relforcerowsecurity
    ) THEN
      RAISE EXCEPTION 'billing table % must have RLS enabled and forced', v_relation;
    END IF;

    IF has_table_privilege('anon', v_relation, 'SELECT')
       OR has_table_privilege('anon', v_relation, 'INSERT')
       OR has_table_privilege('authenticated', v_relation, 'SELECT')
       OR has_table_privilege('authenticated', v_relation, 'INSERT') THEN
      RAISE EXCEPTION 'client role unexpectedly has direct access to %', v_relation;
    END IF;

    IF NOT has_table_privilege('service_role', v_relation, 'SELECT')
       OR NOT has_table_privilege('service_role', v_relation, 'INSERT') THEN
      RAISE EXCEPTION 'service_role lacks expected billing access to %', v_relation;
    END IF;

    IF EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'private' AND tablename = v_table
    ) THEN
      RAISE EXCEPTION 'private billing table % unexpectedly has client-facing policies', v_relation;
    END IF;
  END LOOP;

  IF has_function_privilege('anon', 'public.record_saas_payment_webhook_event_internal(text,text,jsonb)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.record_saas_payment_webhook_event_internal(text,text,jsonb)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.record_saas_payment_webhook_event_internal(text,text,jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.process_saas_payment_webhook_event_internal(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.process_saas_payment_webhook_event_internal(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.process_saas_payment_webhook_event_internal(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.process_saas_payment_webhook_batch_internal(integer)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.process_saas_payment_webhook_batch_internal(integer)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.process_saas_payment_webhook_batch_internal(integer)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.resolve_saas_tenant_entitlements_internal(uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.resolve_saas_tenant_entitlements_internal(uuid,uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.resolve_saas_tenant_entitlements_internal(uuid,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'billing RPC grants are not service-role-only';
  END IF;

  IF has_function_privilege('anon', 'public.reserve_saas_checkout_internal(uuid,uuid,uuid,text,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.reserve_saas_checkout_internal(uuid,uuid,uuid,text,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.reserve_saas_checkout_internal(uuid,uuid,uuid,text,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.finalize_saas_checkout_internal(uuid,text,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.finalize_saas_checkout_internal(uuid,text,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.finalize_saas_checkout_internal(uuid,text,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.fail_saas_checkout_reservation_internal(uuid,integer)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.fail_saas_checkout_reservation_internal(uuid,integer)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.fail_saas_checkout_reservation_internal(uuid,integer)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.list_saas_checkout_reconciliation_internal(uuid,uuid,integer)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.list_saas_checkout_reconciliation_internal(uuid,uuid,integer)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.list_saas_checkout_reconciliation_internal(uuid,uuid,integer)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.get_saas_billing_portal_internal(uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.get_saas_billing_portal_internal(uuid,uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.get_saas_billing_portal_internal(uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.get_saas_checkout_recovery_target_internal(uuid,uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.get_saas_checkout_recovery_target_internal(uuid,uuid,uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.get_saas_checkout_recovery_target_internal(uuid,uuid,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'checkout RPC grants are not service-role-only';
  END IF;

  IF has_function_privilege('anon', 'public.get_saas_payment_webhook_health_internal()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.get_saas_payment_webhook_health_internal()', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.get_saas_payment_webhook_health_internal()', 'EXECUTE') THEN
    RAISE EXCEPTION 'webhook health metrics RPC must be service-role-only';
  END IF;

  RAISE NOTICE 'PASS: SaaS billing and checkout tables/RPCs are private/service-role-only';
END
$saas_billing_security$;
