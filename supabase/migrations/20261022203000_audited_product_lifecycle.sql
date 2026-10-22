-- Add audited product lifecycle control. Products are never hard-deleted because issued QR codes
-- and historical claims must retain their product/tenant references.
CREATE OR REPLACE FUNCTION private.set_rewardloop_product_status(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_product_id uuid,
  p_active boolean,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_product public.products%rowtype;
BEGIN
  IF p_actor_user_id IS NULL OR p_tenant_id IS NULL OR p_product_id IS NULL
     OR p_active IS NULL
     OR (NOT p_active AND length(trim(coalesce(p_reason,''))) < 5) THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_product_status_request');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.tenant_memberships m
    WHERE m.tenant_id=p_tenant_id AND m.user_id=p_actor_user_id
      AND m.status='active' AND m.role IN ('brand_admin','super_admin')
  ) THEN
    RETURN jsonb_build_object('ok',false,'error','forbidden');
  END IF;

  SELECT * INTO v_product
    FROM public.products
   WHERE id=p_product_id AND tenant_id=p_tenant_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'error','product_not_found');
  END IF;

  IF v_product.active = p_active THEN
    RETURN jsonb_build_object('ok',true,'unchanged',true,'product_id',v_product.id,'active',v_product.active);
  END IF;

  UPDATE public.products
     SET active=p_active
   WHERE id=v_product.id
   RETURNING * INTO v_product;

  INSERT INTO public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,reason,before_data,after_data)
  VALUES(
    p_tenant_id,p_actor_user_id,
    CASE WHEN p_active THEN 'product_activated' ELSE 'product_deactivated' END,
    'product',v_product.id,nullif(trim(coalesce(p_reason,'')),''),
    jsonb_build_object('active',NOT p_active,'sku',v_product.sku),
    jsonb_build_object('active',p_active,'sku',v_product.sku)
  );

  RETURN jsonb_build_object('ok',true,'product_id',v_product.id,'active',v_product.active);
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.set_rewardloop_product_status(uuid,uuid,uuid,boolean,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.set_rewardloop_product_status(uuid,uuid,uuid,boolean,text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.rewardloop_set_product_status_internal(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_product_id uuid,
  p_active boolean,
  p_reason text
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.set_rewardloop_product_status(
    p_actor_user_id,p_tenant_id,p_product_id,p_active,p_reason
  );
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_set_product_status_internal(uuid,uuid,uuid,boolean,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rewardloop_set_product_status_internal(uuid,uuid,uuid,boolean,text)
  TO service_role;
