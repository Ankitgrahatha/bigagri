-- Audited product metadata updates. SKU remains immutable to preserve QR/lot traceability.
CREATE OR REPLACE FUNCTION private.update_rewardloop_product(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_product_id uuid,
  p_name text,
  p_pack_size text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_product public.products%rowtype;
  v_old_name text;
  v_old_pack_size text;
  v_name text;
  v_pack_size text;
BEGIN
  v_name := trim(coalesce(p_name,''));
  v_pack_size := nullif(trim(coalesce(p_pack_size,'')),'');
  IF p_actor_user_id IS NULL OR p_tenant_id IS NULL OR p_product_id IS NULL
     OR length(v_name)<2 OR length(v_name)>160 OR length(coalesce(v_pack_size,''))>80 THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_product_details');
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.tenant_memberships m
    WHERE m.tenant_id=p_tenant_id AND m.user_id=p_actor_user_id
      AND m.status='active' AND m.role IN ('brand_admin','super_admin')
  ) THEN
    RETURN jsonb_build_object('ok',false,'error','forbidden');
  END IF;
  SELECT * INTO v_product FROM public.products
   WHERE id=p_product_id AND tenant_id=p_tenant_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'error','product_not_found');
  END IF;
  v_old_name:=v_product.name;
  v_old_pack_size:=v_product.pack_size;
  IF v_old_name IS NOT DISTINCT FROM v_name AND v_old_pack_size IS NOT DISTINCT FROM v_pack_size THEN
    RETURN jsonb_build_object('ok',true,'unchanged',true,'product_id',v_product.id);
  END IF;
  UPDATE public.products SET name=v_name,pack_size=v_pack_size
   WHERE id=v_product.id RETURNING * INTO v_product;
  INSERT INTO public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,before_data,after_data)
  VALUES(
    p_tenant_id,p_actor_user_id,'product_updated','product',v_product.id,
    jsonb_build_object('sku',v_product.sku,'name',v_old_name,'pack_size',v_old_pack_size),
    jsonb_build_object('sku',v_product.sku,'name',v_product.name,'pack_size',v_product.pack_size)
  );
  RETURN jsonb_build_object('ok',true,'product',jsonb_build_object(
    'id',v_product.id,'sku',v_product.sku,'name',v_product.name,'pack_size',v_product.pack_size,'active',v_product.active
  ));
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.update_rewardloop_product(uuid,uuid,uuid,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.update_rewardloop_product(uuid,uuid,uuid,text,text) TO service_role;

CREATE OR REPLACE FUNCTION public.rewardloop_update_product_internal(
  p_actor_user_id uuid,p_tenant_id uuid,p_product_id uuid,p_name text,p_pack_size text
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.update_rewardloop_product(p_actor_user_id,p_tenant_id,p_product_id,p_name,p_pack_size);
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_update_product_internal(uuid,uuid,uuid,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rewardloop_update_product_internal(uuid,uuid,uuid,text,text) TO service_role;
