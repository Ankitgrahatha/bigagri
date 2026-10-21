-- Defense in depth: prevent activation of demo/test campaigns.
create or replace function private.set_rewardloop_campaign_status(
  p_actor_user_id uuid,p_tenant_id uuid,p_campaign_id uuid,p_new_status text,p_reason text
) returns jsonb language plpgsql security definer set search_path to 'pg_catalog','extensions','public','private'
as $function$
declare v_campaign public.campaigns%rowtype;
begin
  if p_actor_user_id is null or p_tenant_id is null or p_campaign_id is null or p_new_status not in ('active','paused','archived') or (p_new_status in ('paused','archived') and length(trim(coalesce(p_reason,'')))<5) then return jsonb_build_object('ok',false,'error','invalid_campaign_status_request'); end if;
  if not exists(select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active' and m.role in ('brand_admin','super_admin')) then return jsonb_build_object('ok',false,'error','forbidden'); end if;
  select * into v_campaign from public.campaigns where id=p_campaign_id and tenant_id=p_tenant_id for update;
  if not found then return jsonb_build_object('ok',false,'error','campaign_not_found'); end if;
  if v_campaign.status in ('ended','archived') then return jsonb_build_object('ok',false,'error','campaign_terminal_state'); end if;
  if p_new_status='active' then
    if v_campaign.rules->>'demo'='true' then return jsonb_build_object('ok',false,'error','demo_campaign_not_activatable'); end if;
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
