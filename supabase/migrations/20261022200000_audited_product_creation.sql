-- Add audited, tenant-authorized product creation for the RewardLoop admin API.
-- This migration is source-only until the production migration history release gate is completed.

CREATE OR REPLACE FUNCTION private.create_rewardloop_product(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_sku text,
  p_name text,
  p_pack_size text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_product public.products%rowtype;
  v_sku text;
  v_name text;
  v_pack_size text;
BEGIN
  v_sku := upper(trim(coalesce(p_sku, '')));
  v_name := trim(coalesce(p_name, ''));
  v_pack_size := nullif(trim(coalesce(p_pack_size, '')), '');

  IF p_actor_user_id IS NULL OR p_tenant_id IS NULL
     OR v_sku !~ '^[A-Z0-9][A-Z0-9._/-]{0,63}$'
     OR length(v_name) < 2 OR length(v_name) > 160
     OR length(coalesce(v_pack_size, '')) > 80 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_product_details');
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM public.tenant_memberships m
     WHERE m.tenant_id = p_tenant_id
       AND m.user_id = p_actor_user_id
       AND m.status = 'active'
       AND m.role IN ('brand_admin', 'super_admin')
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.tenants t
     WHERE t.id = p_tenant_id AND t.status = 'active'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'tenant_inactive');
  END IF;

  BEGIN
    INSERT INTO public.products(tenant_id, sku, name, pack_size, active, metadata)
    VALUES (p_tenant_id, v_sku, v_name, v_pack_size, true, '{}'::jsonb)
    RETURNING * INTO v_product;
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sku_exists');
  END;

  INSERT INTO public.audit_logs(tenant_id, actor_user_id, action, entity_type, entity_id, after_data)
  VALUES (
    p_tenant_id, p_actor_user_id, 'product_created', 'product', v_product.id,
    jsonb_build_object('sku', v_product.sku, 'name', v_product.name,
      'pack_size', v_product.pack_size, 'active', v_product.active)
  );

  RETURN jsonb_build_object(
    'ok', true,
    'product', jsonb_build_object(
      'id', v_product.id, 'tenant_id', v_product.tenant_id,
      'sku', v_product.sku, 'name', v_product.name,
      'pack_size', v_product.pack_size, 'active', v_product.active,
      'created_at', v_product.created_at
    )
  );
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.create_rewardloop_product(uuid,uuid,text,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.create_rewardloop_product(uuid,uuid,text,text,text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.rewardloop_create_product_internal(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_sku text,
  p_name text,
  p_pack_size text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.create_rewardloop_product(
    p_actor_user_id, p_tenant_id, p_sku, p_name, p_pack_size
  );
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_create_product_internal(uuid,uuid,text,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rewardloop_create_product_internal(uuid,uuid,text,text,text)
  TO service_role;
