-- Read-only entitlement resolution. A subscription status alone is insufficient:
-- the plan version must be published and the paid/trial period must still be current.
-- Callers must authenticate the actor before invoking this service-role-only RPC.
CREATE OR REPLACE FUNCTION private.resolve_saas_tenant_entitlements(
  p_actor_user_id uuid,
  p_tenant_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_subscription record;
  v_is_active boolean := false;
BEGIN
  IF p_actor_user_id IS NULL OR p_tenant_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_request');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.tenant_memberships m
    WHERE m.tenant_id = p_tenant_id
      AND m.user_id = p_actor_user_id
      AND m.status = 'active'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  SELECT
    s.id,
    s.status,
    s.current_period_end,
    s.trial_end,
    p.plan_key,
    pv.id AS plan_version_id,
    pv.entitlements,
    pv.usage_limits,
    pv.published_at
  INTO v_subscription
  FROM private.saas_tenant_subscriptions s
  JOIN private.saas_plan_versions pv ON pv.id = s.plan_version_id
  JOIN private.saas_plans p ON p.id = pv.plan_id
  WHERE s.tenant_id = p_tenant_id
  ORDER BY s.created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'active', false, 'status', 'none');
  END IF;

  v_is_active :=
    v_subscription.published_at IS NOT NULL
    AND (
      (v_subscription.status = 'active'
        AND v_subscription.current_period_end IS NOT NULL
        AND v_subscription.current_period_end > now())
      OR
      (v_subscription.status = 'trialing'
        AND v_subscription.trial_end IS NOT NULL
        AND v_subscription.trial_end > now())
    );

  IF NOT v_is_active THEN
    RETURN jsonb_build_object(
      'ok', true,
      'active', false,
      'status', v_subscription.status
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'active', true,
    'status', v_subscription.status,
    'plan_key', v_subscription.plan_key,
    'plan_version_id', v_subscription.plan_version_id,
    'entitlements', v_subscription.entitlements,
    'usage_limits', v_subscription.usage_limits,
    'period_end', v_subscription.current_period_end,
    'trial_end', v_subscription.trial_end
  );
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.resolve_saas_tenant_entitlements(uuid,uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.resolve_saas_tenant_entitlements(uuid,uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.resolve_saas_tenant_entitlements_internal(
  p_actor_user_id uuid,
  p_tenant_id uuid
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.resolve_saas_tenant_entitlements(p_actor_user_id, p_tenant_id);
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.resolve_saas_tenant_entitlements_internal(uuid,uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_saas_tenant_entitlements_internal(uuid,uuid)
  TO service_role;
