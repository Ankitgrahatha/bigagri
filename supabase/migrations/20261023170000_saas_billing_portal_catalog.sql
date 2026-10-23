-- Tenant-scoped read model for the self-service billing portal.
-- Only published plan versions and the requesting tenant's subscription are returned.
CREATE OR REPLACE FUNCTION private.get_saas_billing_portal(
  p_actor_user_id uuid,
  p_tenant_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_plans jsonb;
  v_subscription jsonb;
BEGIN
  IF p_actor_user_id IS NULL OR p_tenant_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_request');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.tenant_memberships m
    WHERE m.tenant_id = p_tenant_id
      AND m.user_id = p_actor_user_id
      AND m.status = 'active'
      AND m.role IN ('brand_admin'::public.partner_role, 'super_admin'::public.partner_role)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'plan_id', p.id,
    'plan_version_id', pv.id,
    'plan_key', p.plan_key,
    'display_name', p.display_name,
    'version_no', pv.version_no,
    'currency', pv.currency,
    'monthly_amount_minor', pv.monthly_amount_minor,
    'yearly_amount_minor', pv.yearly_amount_minor,
    'monthly_available', pv.monthly_provider_plan_id IS NOT NULL AND pv.monthly_amount_minor > 0,
    'yearly_available', pv.yearly_provider_plan_id IS NOT NULL AND pv.yearly_amount_minor > 0,
    'trial_days', pv.trial_days,
    'entitlements', pv.entitlements,
    'usage_limits', pv.usage_limits
  ) ORDER BY pv.monthly_amount_minor, p.display_name), '[]'::jsonb)
  INTO v_plans
  FROM private.saas_plan_versions pv
  JOIN private.saas_plans p ON p.id = pv.plan_id
  WHERE p.status = 'published' AND pv.published_at IS NOT NULL;

  SELECT CASE WHEN s.id IS NULL THEN NULL ELSE jsonb_build_object(
    'id', s.id,
    'plan_version_id', s.plan_version_id,
    'plan_name', p.display_name,
    'version_no', pv.version_no,
    'status', s.status,
    'billing_interval', s.billing_interval,
    'currency', pv.currency,
    'amount_minor', CASE WHEN s.billing_interval = 'monthly' THEN pv.monthly_amount_minor ELSE pv.yearly_amount_minor END,
    'current_period_start', s.current_period_start,
    'current_period_end', s.current_period_end,
    'cancel_at_period_end', s.cancel_at_period_end,
    'created_at', s.created_at,
    'checkout_url', s.checkout_url
  ) END
  INTO v_subscription
  FROM private.saas_tenant_subscriptions s
  JOIN private.saas_plan_versions pv ON pv.id = s.plan_version_id
  JOIN private.saas_plans p ON p.id = pv.plan_id
  WHERE s.tenant_id = p_tenant_id
  ORDER BY s.created_at DESC
  LIMIT 1;

  RETURN jsonb_build_object('ok', true, 'plans', v_plans, 'subscription', v_subscription);
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.get_saas_billing_portal(uuid,uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.get_saas_billing_portal(uuid,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.get_saas_billing_portal_internal(
  p_actor_user_id uuid,
  p_tenant_id uuid
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.get_saas_billing_portal(p_actor_user_id, p_tenant_id);
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.get_saas_billing_portal_internal(uuid,uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_saas_billing_portal_internal(uuid,uuid) TO service_role;
