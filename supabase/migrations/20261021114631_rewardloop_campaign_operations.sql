-- Audited campaign creation and lifecycle controls for Growta RewardLoop.
-- All public wrappers are service-role-only; the private routines re-check tenant membership.

create or replace function private.create_rewardloop_campaign(
  p_actor_user_id uuid,p_tenant_id uuid,p_name text,p_starts_at timestamptz,p_ends_at timestamptz,p_budget_minor_units bigint
) returns jsonb language plpgsql security definer set search_path to 'pg_catalog','extensions','public','private'
as $function$
declare v_campaign_id uuid;
begin
  if p_actor_user_id is null or p_tenant_id is null or length(trim(coalesce(p_name,'')))<3 or length(trim(p_name))>120 or p_budget_minor_units is null or p_budget_minor_units<0 or (p_starts_at is not null and p_ends_at is not null and p_ends_at<=p_starts_at) or (p_ends_at is not null and p_ends_at<=now()) then return jsonb_build_object('ok',false,'error','invalid_campaign_details'); end if;
  if not exists(select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active' and m.role in ('brand_admin','super_admin')) then return jsonb_build_object('ok',false,'error','forbidden'); end if;
  if not exists(select 1 from public.tenants t where t.id=p_tenant_id and t.status='active') then return jsonb_build_object('ok',false,'error','tenant_inactive'); end if;
  insert into public.campaigns(tenant_id,name,status,starts_at,ends_at,budget_minor_units,currency,rules_version,rules,created_by,created_at,updated_at)
  values(p_tenant_id,trim(p_name),'draft',p_starts_at,p_ends_at,p_budget_minor_units,'INR',1,'{}'::jsonb,p_actor_user_id,now(),now()) returning id into v_campaign_id;
  insert into public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,after_data)
  values(p_tenant_id,p_actor_user_id,'campaign_created','campaign',v_campaign_id,jsonb_build_object('name',trim(p_name),'status','draft','starts_at',p_starts_at,'ends_at',p_ends_at,'budget_minor_units',p_budget_minor_units,'currency','INR'));
  return jsonb_build_object('ok',true,'campaign_id',v_campaign_id,'status','draft');
end $function$;

create or replace function private.set_rewardloop_campaign_status(p_actor_user_id uuid,p_tenant_id uuid,p_campaign_id uuid,p_new_status text,p_reason text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','extensions','public','private'
as $function$
declare v_campaign public.campaigns%rowtype;
begin
  if p_actor_user_id is null or p_tenant_id is null or p_campaign_id is null or p_new_status not in ('active','paused','archived') or (p_new_status in ('paused','archived') and length(trim(coalesce(p_reason,'')))<5) then return jsonb_build_object('ok',false,'error','invalid_campaign_status_request'); end if;
  if not exists(select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active' and m.role in ('brand_admin','super_admin')) then return jsonb_build_object('ok',false,'error','forbidden'); end if;
  select * into v_campaign from public.campaigns where id=p_campaign_id and tenant_id=p_tenant_id for update;
  if not found then return jsonb_build_object('ok',false,'error','campaign_not_found'); end if;
  if v_campaign.status in ('ended','archived') then return jsonb_build_object('ok',false,'error','campaign_terminal_state'); end if;
  if p_new_status='active' then
    if v_campaign.status not in ('draft','scheduled','paused') then return jsonb_build_object('ok',false,'error','invalid_campaign_transition'); end if;
    if v_campaign.starts_at is not null and v_campaign.starts_at>now() then return jsonb_build_object('ok',false,'error','campaign_not_started'); end if;
    if v_campaign.ends_at is not null and v_campaign.ends_at<=now() then return jsonb_build_object('ok',false,'error','campaign_expired'); end if;
    if not exists(select 1 from public.products p where p.tenant_id=p_tenant_id and p.active) then return jsonb_build_object('ok',false,'error','active_product_required'); end if;
  elsif p_new_status='paused' then
    if v_campaign.status not in ('active','scheduled','draft') then return jsonb_build_object('ok',false,'error','invalid_campaign_transition'); end if;
  elsif p_new_status='archived' then
    if v_campaign.status not in ('paused','draft','ended') then return jsonb_build_object('ok',false,'error','pause_campaign_before_archive'); end if;
  end if;
  update public.campaigns set status=p_new_status::public.campaign_status,updated_at=now() where id=v_campaign.id;
  insert into public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,reason,before_data,after_data)
  values(p_tenant_id,p_actor_user_id,'campaign_status_changed','campaign',v_campaign.id,nullif(trim(coalesce(p_reason,'')),''),jsonb_build_object('status',v_campaign.status),jsonb_build_object('status',p_new_status));
  return jsonb_build_object('ok',true,'campaign_id',v_campaign.id,'status',p_new_status);
end $function$;

create or replace function public.rewardloop_create_campaign_internal(p_actor_user_id uuid,p_tenant_id uuid,p_name text,p_starts_at timestamptz,p_ends_at timestamptz,p_budget_minor_units bigint)
returns jsonb language sql security definer set search_path to 'pg_catalog','extensions','public','private'
as $function$ select private.create_rewardloop_campaign(p_actor_user_id,p_tenant_id,p_name,p_starts_at,p_ends_at,p_budget_minor_units); $function$;
create or replace function public.rewardloop_set_campaign_status_internal(p_actor_user_id uuid,p_tenant_id uuid,p_campaign_id uuid,p_new_status text,p_reason text)
returns jsonb language sql security definer set search_path to 'pg_catalog','extensions','public','private'
as $function$ select private.set_rewardloop_campaign_status(p_actor_user_id,p_tenant_id,p_campaign_id,p_new_status,p_reason); $function$;

revoke all on function public.rewardloop_create_campaign_internal(uuid,uuid,text,timestamptz,timestamptz,bigint) from public,anon,authenticated;
grant execute on function public.rewardloop_create_campaign_internal(uuid,uuid,text,timestamptz,timestamptz,bigint) to service_role;
revoke all on function public.rewardloop_set_campaign_status_internal(uuid,uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.rewardloop_set_campaign_status_internal(uuid,uuid,uuid,text,text) to service_role;
