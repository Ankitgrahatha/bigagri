-- Read-only authorization and target details for verifying an ambiguous provider checkout.
CREATE OR REPLACE FUNCTION private.get_saas_checkout_recovery_target(
  p_actor_user_id uuid, p_tenant_id uuid, p_subscription_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private' AS $function$
DECLARE v_subscription record;
BEGIN
  IF p_actor_user_id IS NULL OR p_tenant_id IS NULL OR p_subscription_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_request');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.tenant_memberships m
    WHERE m.tenant_id = p_tenant_id AND m.user_id = p_actor_user_id
      AND m.status = 'active' AND m.role = 'super_admin'::public.partner_role
  ) THEN RETURN jsonb_build_object('ok', false, 'error', 'forbidden'); END IF;
  SELECT s.id, s.tenant_id, s.plan_version_id, s.billing_interval, s.status,
    s.checkout_idempotency_key, s.provider_subscription_id, s.created_at,
    CASE WHEN s.billing_interval = 'monthly' THEN pv.monthly_provider_plan_id
         WHEN s.billing_interval = 'yearly' THEN pv.yearly_provider_plan_id ELSE NULL END AS expected_provider_plan_id
  INTO v_subscription FROM private.saas_tenant_subscriptions s
  JOIN private.saas_plan_versions pv ON pv.id = s.plan_version_id
  WHERE s.id = p_subscription_id AND s.tenant_id = p_tenant_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'checkout_not_found'); END IF;
  IF v_subscription.status <> 'incomplete' OR v_subscription.checkout_idempotency_key IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'checkout_not_recoverable');
  END IF;
  IF v_subscription.provider_subscription_id IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'provider_subscription_already_bound');
  END IF;
  IF v_subscription.expected_provider_plan_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'plan_not_configured');
  END IF;
  IF v_subscription.created_at > now() - interval '1 minute' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'checkout_too_recent');
  END IF;
  RETURN jsonb_build_object('ok', true, 'tenant_id', v_subscription.tenant_id,
    'subscription_id', v_subscription.id, 'billing_interval', v_subscription.billing_interval,
    'idempotency_key', v_subscription.checkout_idempotency_key,
    'expected_provider_plan_id', v_subscription.expected_provider_plan_id);
END $function$;
REVOKE ALL PRIVILEGES ON FUNCTION private.get_saas_checkout_recovery_target(uuid,uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.get_saas_checkout_recovery_target(uuid,uuid,uuid) TO service_role;
CREATE OR REPLACE FUNCTION public.get_saas_checkout_recovery_target_internal(
  p_actor_user_id uuid, p_tenant_id uuid, p_subscription_id uuid
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private' AS $function$
  SELECT private.get_saas_checkout_recovery_target(p_actor_user_id, p_tenant_id, p_subscription_id);
$function$;
REVOKE ALL PRIVILEGES ON FUNCTION public.get_saas_checkout_recovery_target_internal(uuid,uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_saas_checkout_recovery_target_internal(uuid,uuid,uuid) TO service_role;
