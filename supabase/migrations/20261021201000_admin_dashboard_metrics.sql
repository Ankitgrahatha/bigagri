-- Return exact tenant-scoped admin dashboard metrics without deriving global totals
-- from capped presentation pages. Authorization is rechecked in the RPC itself.

CREATE OR REPLACE FUNCTION private.rewardloop_admin_dashboard_metrics(
  p_actor_user_id uuid,
  p_tenant_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_tenant_status text;
  v_membership_ok boolean;
  v_result jsonb;
BEGIN
  IF p_actor_user_id IS NULL OR p_tenant_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  SELECT t.status::text
    INTO v_tenant_status
    FROM public.tenants t
   WHERE t.id = p_tenant_id;

  IF NOT FOUND OR v_tenant_status <> 'active' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  SELECT EXISTS (
    SELECT 1
      FROM public.tenant_memberships m
     WHERE m.tenant_id = p_tenant_id
       AND m.user_id = p_actor_user_id
       AND m.status = 'active'
       AND m.role IN ('brand_admin', 'super_admin')
  ) INTO v_membership_ok;

  IF NOT v_membership_ok THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  SELECT jsonb_build_object(
    'partners_total', (SELECT count(*) FROM public.partners p WHERE p.tenant_id = p_tenant_id),
    'partners_pending', (SELECT count(*) FROM public.partners p WHERE p.tenant_id = p_tenant_id AND p.verification_status IN ('pending', 'unverified')),
    'campaigns_total', (SELECT count(*) FROM public.campaigns c WHERE c.tenant_id = p_tenant_id),
    'campaigns_active', (SELECT count(*) FROM public.campaigns c WHERE c.tenant_id = p_tenant_id AND c.status = 'active'),
    'products_total', (SELECT count(*) FROM public.products p WHERE p.tenant_id = p_tenant_id),
    'products_active', (SELECT count(*) FROM public.products p WHERE p.tenant_id = p_tenant_id AND p.active),
    'qr_batches_total', (SELECT count(*) FROM public.qr_issuance_batches b WHERE b.tenant_id = p_tenant_id),
    'qr_codes_issued_total', (
      SELECT COALESCE(sum(b.requested_count), 0)
        FROM public.qr_issuance_batches b
       WHERE b.tenant_id = p_tenant_id
         AND b.status IN ('issued', 'revoked')
    ),
    'redemptions_total', (SELECT count(*) FROM public.redemptions r WHERE r.tenant_id = p_tenant_id),
    'redemptions_open', (SELECT count(*) FROM public.redemptions r WHERE r.tenant_id = p_tenant_id AND r.status IN ('reserved', 'approved'))
  ) INTO v_result;

  RETURN v_result || jsonb_build_object('ok', true);
END
$function$;

CREATE OR REPLACE FUNCTION public.rewardloop_admin_dashboard_metrics_internal(
  p_actor_user_id uuid,
  p_tenant_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.rewardloop_admin_dashboard_metrics(p_actor_user_id, p_tenant_id);
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.rewardloop_admin_dashboard_metrics(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.rewardloop_admin_dashboard_metrics(uuid, uuid)
  TO service_role;

REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_admin_dashboard_metrics_internal(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rewardloop_admin_dashboard_metrics_internal(uuid, uuid)
  TO service_role;
