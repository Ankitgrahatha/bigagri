-- Audited reward catalogue management. Rewards are created inactive and activated explicitly.
-- Existing redemption history is preserved; demo rewards cannot be activated or edited.

CREATE OR REPLACE FUNCTION private.create_rewardloop_reward(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_slug text,
  p_name text,
  p_name_hi text,
  p_description text,
  p_description_hi text,
  p_category text,
  p_points_cost integer,
  p_stock_quantity integer,
  p_sort_order integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_slug text := lower(trim(coalesce(p_slug,'')));
  v_name text := trim(coalesce(p_name,''));
  v_name_hi text := nullif(trim(coalesce(p_name_hi,'')), '');
  v_description text := nullif(trim(coalesce(p_description,'')), '');
  v_description_hi text := nullif(trim(coalesce(p_description_hi,'')), '');
  v_category text := lower(trim(coalesce(p_category,'general')));
  v_reward public.rewards%rowtype;
BEGIN
  IF p_actor_user_id IS NULL OR p_tenant_id IS NULL
     OR v_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' OR length(v_slug) > 80
     OR length(v_name) < 2 OR length(v_name) > 160
     OR length(coalesce(v_name_hi,'')) > 160
     OR length(coalesce(v_description,'')) > 2000
     OR length(coalesce(v_description_hi,'')) > 2000
     OR v_category !~ '^[a-z][a-z0-9_-]{1,63}$'
     OR p_points_cost IS NULL OR p_points_cost < 1 OR p_points_cost > 100000000
     OR (p_stock_quantity IS NOT NULL AND p_stock_quantity < 0)
     OR p_sort_order IS NULL OR p_sort_order < 0 OR p_sort_order > 100000 THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_reward_details');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.tenant_memberships m
    WHERE m.tenant_id=p_tenant_id AND m.user_id=p_actor_user_id
      AND m.status='active' AND m.role IN ('brand_admin','super_admin')
  ) THEN
    RETURN jsonb_build_object('ok',false,'error','forbidden');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.tenants t WHERE t.id=p_tenant_id AND t.status='active') THEN
    RETURN jsonb_build_object('ok',false,'error','tenant_inactive');
  END IF;

  INSERT INTO public.rewards(
    tenant_id,slug,name,name_hi,description,description_hi,category,points_cost,
    stock_quantity,active,is_demo,sort_order,metadata
  ) VALUES (
    p_tenant_id,v_slug,v_name,v_name_hi,v_description,v_description_hi,v_category,p_points_cost,
    p_stock_quantity,false,false,p_sort_order,'{}'::jsonb
  ) RETURNING * INTO v_reward;

  INSERT INTO public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,after_data)
  VALUES (p_tenant_id,p_actor_user_id,'reward_created','reward',v_reward.id,
    jsonb_build_object('slug',v_reward.slug,'name',v_reward.name,'category',v_reward.category,
      'points_cost',v_reward.points_cost,'stock_quantity',v_reward.stock_quantity,'active',v_reward.active));

  RETURN jsonb_build_object('ok',true,'reward',jsonb_build_object(
    'id',v_reward.id,'slug',v_reward.slug,'name',v_reward.name,'name_hi',v_reward.name_hi,
    'description',v_reward.description,'description_hi',v_reward.description_hi,
    'category',v_reward.category,'points_cost',v_reward.points_cost,
    'stock_quantity',v_reward.stock_quantity,'active',v_reward.active,'is_demo',v_reward.is_demo,
    'sort_order',v_reward.sort_order,'created_at',v_reward.created_at
  ));
EXCEPTION WHEN unique_violation THEN
  RETURN jsonb_build_object('ok',false,'error','reward_slug_exists');
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.create_rewardloop_reward(uuid,uuid,text,text,text,text,text,text,integer,integer,integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.create_rewardloop_reward(uuid,uuid,text,text,text,text,text,text,integer,integer,integer)
  TO service_role;

CREATE OR REPLACE FUNCTION public.rewardloop_create_reward_internal(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_slug text,
  p_name text,
  p_name_hi text,
  p_description text,
  p_description_hi text,
  p_category text,
  p_points_cost integer,
  p_stock_quantity integer,
  p_sort_order integer
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.create_rewardloop_reward(
    p_actor_user_id,p_tenant_id,p_slug,p_name,p_name_hi,p_description,p_description_hi,
    p_category,p_points_cost,p_stock_quantity,p_sort_order
  );
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_create_reward_internal(uuid,uuid,text,text,text,text,text,text,integer,integer,integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rewardloop_create_reward_internal(uuid,uuid,text,text,text,text,text,text,integer,integer,integer)
  TO service_role;

CREATE OR REPLACE FUNCTION private.update_rewardloop_reward(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_reward_id uuid,
  p_name text,
  p_name_hi text,
  p_description text,
  p_description_hi text,
  p_category text,
  p_points_cost integer,
  p_stock_quantity integer,
  p_sort_order integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_reward public.rewards%rowtype;
  v_name text := trim(coalesce(p_name,''));
  v_name_hi text := nullif(trim(coalesce(p_name_hi,'')), '');
  v_description text := nullif(trim(coalesce(p_description,'')), '');
  v_description_hi text := nullif(trim(coalesce(p_description_hi,'')), '');
  v_category text := lower(trim(coalesce(p_category,'general')));
  v_before jsonb;
BEGIN
  IF p_actor_user_id IS NULL OR p_tenant_id IS NULL OR p_reward_id IS NULL
     OR length(v_name) < 2 OR length(v_name) > 160
     OR length(coalesce(v_name_hi,'')) > 160
     OR length(coalesce(v_description,'')) > 2000
     OR length(coalesce(v_description_hi,'')) > 2000
     OR v_category !~ '^[a-z][a-z0-9_-]{1,63}$'
     OR p_points_cost IS NULL OR p_points_cost < 1 OR p_points_cost > 100000000
     OR (p_stock_quantity IS NOT NULL AND p_stock_quantity < 0)
     OR p_sort_order IS NULL OR p_sort_order < 0 OR p_sort_order > 100000 THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_reward_details');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.tenant_memberships m
    WHERE m.tenant_id=p_tenant_id AND m.user_id=p_actor_user_id
      AND m.status='active' AND m.role IN ('brand_admin','super_admin')
  ) THEN
    RETURN jsonb_build_object('ok',false,'error','forbidden');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.tenants t WHERE t.id=p_tenant_id AND t.status='active') THEN
    RETURN jsonb_build_object('ok',false,'error','tenant_inactive');
  END IF;

  SELECT * INTO v_reward FROM public.rewards
   WHERE id=p_reward_id AND tenant_id=p_tenant_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','reward_not_found'); END IF;
  IF v_reward.is_demo THEN RETURN jsonb_build_object('ok',false,'error','demo_reward_read_only'); END IF;
  IF v_reward.active AND p_stock_quantity = 0 THEN
    RETURN jsonb_build_object('ok',false,'error','deactivate_reward_before_zero_stock');
  END IF;

  v_before := jsonb_build_object('name',v_reward.name,'name_hi',v_reward.name_hi,
    'description',v_reward.description,'description_hi',v_reward.description_hi,
    'category',v_reward.category,'points_cost',v_reward.points_cost,
    'stock_quantity',v_reward.stock_quantity,'sort_order',v_reward.sort_order);
  IF v_reward.name IS NOT DISTINCT FROM v_name
     AND v_reward.name_hi IS NOT DISTINCT FROM v_name_hi
     AND v_reward.description IS NOT DISTINCT FROM v_description
     AND v_reward.description_hi IS NOT DISTINCT FROM v_description_hi
     AND v_reward.category IS NOT DISTINCT FROM v_category
     AND v_reward.points_cost IS NOT DISTINCT FROM p_points_cost
     AND v_reward.stock_quantity IS NOT DISTINCT FROM p_stock_quantity
     AND v_reward.sort_order IS NOT DISTINCT FROM p_sort_order THEN
    RETURN jsonb_build_object('ok',true,'unchanged',true,'reward_id',v_reward.id);
  END IF;

  UPDATE public.rewards SET name=v_name,name_hi=v_name_hi,description=v_description,
    description_hi=v_description_hi,category=v_category,points_cost=p_points_cost,
    stock_quantity=p_stock_quantity,sort_order=p_sort_order,updated_at=now()
   WHERE id=v_reward.id RETURNING * INTO v_reward;

  INSERT INTO public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,before_data,after_data)
  VALUES (p_tenant_id,p_actor_user_id,'reward_updated','reward',v_reward.id,v_before,
    jsonb_build_object('name',v_reward.name,'name_hi',v_reward.name_hi,
      'description',v_reward.description,'description_hi',v_reward.description_hi,
      'category',v_reward.category,'points_cost',v_reward.points_cost,
      'stock_quantity',v_reward.stock_quantity,'sort_order',v_reward.sort_order));

  RETURN jsonb_build_object('ok',true,'reward',jsonb_build_object(
    'id',v_reward.id,'slug',v_reward.slug,'name',v_reward.name,'name_hi',v_reward.name_hi,
    'description',v_reward.description,'description_hi',v_reward.description_hi,
    'category',v_reward.category,'points_cost',v_reward.points_cost,
    'stock_quantity',v_reward.stock_quantity,'active',v_reward.active,'is_demo',v_reward.is_demo,
    'sort_order',v_reward.sort_order));
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.update_rewardloop_reward(uuid,uuid,uuid,text,text,text,text,text,integer,integer,integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.update_rewardloop_reward(uuid,uuid,uuid,text,text,text,text,text,integer,integer,integer)
  TO service_role;

CREATE OR REPLACE FUNCTION public.rewardloop_update_reward_internal(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_reward_id uuid,
  p_name text,
  p_name_hi text,
  p_description text,
  p_description_hi text,
  p_category text,
  p_points_cost integer,
  p_stock_quantity integer,
  p_sort_order integer
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.update_rewardloop_reward(
    p_actor_user_id,p_tenant_id,p_reward_id,p_name,p_name_hi,p_description,p_description_hi,
    p_category,p_points_cost,p_stock_quantity,p_sort_order
  );
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_update_reward_internal(uuid,uuid,uuid,text,text,text,text,text,integer,integer,integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rewardloop_update_reward_internal(uuid,uuid,uuid,text,text,text,text,text,integer,integer,integer)
  TO service_role;

CREATE OR REPLACE FUNCTION private.set_rewardloop_reward_status(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_reward_id uuid,
  p_active boolean,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_reward public.rewards%rowtype;
  v_reason text := trim(coalesce(p_reason,''));
BEGIN
  IF p_actor_user_id IS NULL OR p_tenant_id IS NULL OR p_reward_id IS NULL
     OR p_active IS NULL OR (NOT p_active AND length(v_reason) < 5) THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_reward_status_request');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.tenant_memberships m
    WHERE m.tenant_id=p_tenant_id AND m.user_id=p_actor_user_id
      AND m.status='active' AND m.role IN ('brand_admin','super_admin')
  ) THEN
    RETURN jsonb_build_object('ok',false,'error','forbidden');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.tenants t WHERE t.id=p_tenant_id AND t.status='active') THEN
    RETURN jsonb_build_object('ok',false,'error','tenant_inactive');
  END IF;

  SELECT * INTO v_reward FROM public.rewards
   WHERE id=p_reward_id AND tenant_id=p_tenant_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','reward_not_found'); END IF;
  IF p_active AND v_reward.is_demo THEN RETURN jsonb_build_object('ok',false,'error','demo_reward_not_activatable'); END IF;
  IF p_active AND v_reward.stock_quantity = 0 THEN RETURN jsonb_build_object('ok',false,'error','reward_out_of_stock'); END IF;
  IF v_reward.active = p_active THEN
    RETURN jsonb_build_object('ok',true,'unchanged',true,'reward_id',v_reward.id,'active',v_reward.active);
  END IF;

  UPDATE public.rewards SET active=p_active,updated_at=now()
   WHERE id=v_reward.id RETURNING * INTO v_reward;
  INSERT INTO public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,reason,before_data,after_data)
  VALUES (p_tenant_id,p_actor_user_id,CASE WHEN p_active THEN 'reward_activated' ELSE 'reward_deactivated' END,
    'reward',v_reward.id,nullif(v_reason,''),jsonb_build_object('active',NOT p_active),jsonb_build_object('active',p_active));
  RETURN jsonb_build_object('ok',true,'reward_id',v_reward.id,'active',v_reward.active);
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.set_rewardloop_reward_status(uuid,uuid,uuid,boolean,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.set_rewardloop_reward_status(uuid,uuid,uuid,boolean,text) TO service_role;

CREATE OR REPLACE FUNCTION public.rewardloop_set_reward_status_internal(
  p_actor_user_id uuid,p_tenant_id uuid,p_reward_id uuid,p_active boolean,p_reason text
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.set_rewardloop_reward_status(p_actor_user_id,p_tenant_id,p_reward_id,p_active,p_reason);
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_set_reward_status_internal(uuid,uuid,uuid,boolean,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rewardloop_set_reward_status_internal(uuid,uuid,uuid,boolean,text) TO service_role;
