-- Read-only tenant-admin queue for incomplete checkouts that need operational review.
CREATE OR REPLACE FUNCTION private.list_saas_checkout_reconciliation(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_min_age_minutes integer DEFAULT 10
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_checkouts jsonb;
BEGIN
  IF p_actor_user_id IS NULL OR p_tenant_id IS NULL
     OR p_min_age_minutes IS NULL
     OR p_min_age_minutes < 1 OR p_min_age_minutes > 1440 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_request');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.tenant_memberships m
    WHERE m.tenant_id = p_tenant_id
      AND m.user_id = p_actor_user_id
      AND m.status = 'active'
      AND m.role = 'super_admin'::public.partner_role
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'subscription_id', s.id,
        'plan_version_id', s.plan_version_id,
        'billing_interval', s.billing_interval,
        'status', s.status,
        'created_at', s.created_at,
        'age_seconds', greatest(0, floor(extract(epoch FROM (now() - s.created_at)))::bigint),
        'provider_subscription_id', s.provider_subscription_id,
        'checkout_url', s.checkout_url,
        'needs_provider_reconciliation', s.provider_subscription_id IS NULL
      )
      ORDER BY s.created_at
    ),
    '[]'::jsonb
  )
  INTO v_checkouts
  FROM private.saas_tenant_subscriptions s
  WHERE s.tenant_id = p_tenant_id
    AND s.status = 'incomplete'
    AND s.checkout_idempotency_key IS NOT NULL
    AND s.created_at < now() - make_interval(mins => p_min_age_minutes);

  RETURN jsonb_build_object('ok', true, 'checkouts', v_checkouts);
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.list_saas_checkout_reconciliation(uuid,uuid,integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.list_saas_checkout_reconciliation(uuid,uuid,integer)
  TO service_role;

CREATE OR REPLACE FUNCTION public.list_saas_checkout_reconciliation_internal(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_min_age_minutes integer DEFAULT 10
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.list_saas_checkout_reconciliation(
    p_actor_user_id, p_tenant_id, p_min_age_minutes
  );
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.list_saas_checkout_reconciliation_internal(uuid,uuid,integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_saas_checkout_reconciliation_internal(uuid,uuid,integer)
  TO service_role;
