-- Archived legacy migration file. Its effective schema state is captured in
-- supabase/migrations/20261021083000_rewardloop_schema_baseline.sql.
-- Do not execute from this archive.


create or replace function private.resolve_redemption(
  p_actor_user_id uuid, p_tenant_id uuid, p_redemption_id uuid, p_new_status text, p_reason text
) returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'extensions', 'public', 'private'
as $function$
declare v_redemption public.redemptions%rowtype; v_reward public.rewards%rowtype; v_balance bigint;
begin
  if p_actor_user_id is null or p_tenant_id is null or p_redemption_id is null
     or p_new_status not in ('fulfilled','cancelled','rejected')
     or (p_new_status in ('cancelled','rejected') and length(trim(coalesce(p_reason,''))) < 5) then
    return jsonb_build_object('ok',false,'error','invalid_request');
  end if;
  if not exists (select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active' and m.role in ('brand_admin','super_admin')) then
    return jsonb_build_object('ok',false,'error','forbidden');
  end if;
  select * into v_redemption from public.redemptions where id=p_redemption_id and tenant_id=p_tenant_id for update;
  if not found then return jsonb_build_object('ok',false,'error','redemption_not_found'); end if;
  if v_redemption.status not in ('reserved','approved') then return jsonb_build_object('ok',false,'error','redemption_already_resolved','status',v_redemption.status); end if;
  if p_new_status='fulfilled' then
    update public.redemptions set status='fulfilled',fulfilled_at=now(),updated_at=now(),cancellation_reason=null where id=v_redemption.id;
  else
    update public.redemptions set status=p_new_status,updated_at=now(),cancellation_reason=trim(p_reason) where id=v_redemption.id;
    insert into public.points_ledger(tenant_id,partner_id,entry_type,points_delta,idempotency_key,reason_code,actor_user_id,metadata)
    values(p_tenant_id,v_redemption.partner_id,'redeem_refund',v_redemption.points_cost,'redemption-refund:'||v_redemption.id::text,
      case when p_new_status='rejected' then 'reward_redemption_rejected_refund' else 'reward_redemption_cancelled_refund' end,
      p_actor_user_id,jsonb_build_object('redemption_id',v_redemption.id,'reward_id',v_redemption.reward_id,'reason',trim(p_reason)));
    select * into v_reward from public.rewards where id=v_redemption.reward_id and tenant_id=p_tenant_id for update;
    if found and v_reward.stock_quantity is not null then update public.rewards set stock_quantity=stock_quantity+1,updated_at=now() where id=v_reward.id; end if;
  end if;
  select coalesce(sum(points_delta),0) into v_balance from public.points_ledger where tenant_id=p_tenant_id and partner_id=v_redemption.partner_id;
  insert into public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,reason,before_data,after_data)
  values(p_tenant_id,p_actor_user_id,
    case when p_new_status='fulfilled' then 'redemption_fulfilled' when p_new_status='rejected' then 'redemption_rejected_refunded' else 'redemption_cancelled_refunded' end,
    'redemption',v_redemption.id,nullif(trim(coalesce(p_reason,'')),''),
    jsonb_build_object('status',v_redemption.status),
    jsonb_build_object('status',p_new_status,'points_refunded',case when p_new_status='fulfilled' then 0 else v_redemption.points_cost end));
  return jsonb_build_object('ok',true,'redemption_id',v_redemption.id,'status',p_new_status,
    'points_refunded',case when p_new_status='fulfilled' then 0 else v_redemption.points_cost end,'balance_after',v_balance);
end
$function$;

create or replace function public.rewardloop_resolve_redemption_internal(
  p_actor_user_id uuid,p_tenant_id uuid,p_redemption_id uuid,p_new_status text,p_reason text
) returns jsonb language sql security definer
set search_path to 'pg_catalog','extensions','public','private'
as $function$ select private.resolve_redemption(p_actor_user_id,p_tenant_id,p_redemption_id,p_new_status,p_reason); $function$;

revoke all on function public.rewardloop_resolve_redemption_internal(uuid,uuid,uuid,text,text) from public, anon, authenticated;
grant execute on function public.rewardloop_resolve_redemption_internal(uuid,uuid,uuid,text,text) to service_role;
