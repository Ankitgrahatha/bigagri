-- Bind a tenant-scoped claim request ID to both its owning actor and QR resource.
-- A tenant/request key cannot be replayed across actors or across different QRs.
-- Advisory lock serializes the tenant/request key before QR row locking.
-- This migration changes no existing claims, ledger entries, QR status, or balances.

-- Scope claim idempotency replay to the authenticated actor's own partner.
-- Previously a replay key was looked up only by tenant + request UUID and could
-- return another partner's claim ID/points if the same request UUID was reused.
-- This migration changes no existing claim, ledger, QR, or balance rows.

create or replace function private.claim_qr(
  p_actor_user_id uuid,
  p_token text,
  p_request_id uuid,
  p_app_version text default null,
  p_device_ref_hash text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'extensions', 'public', 'private'
as $function$
declare
  v_qr public.qr_codes%rowtype;
  v_partner public.partners%rowtype;
  v_campaign public.campaigns%rowtype;
  v_claim_id uuid;
  v_existing public.claims%rowtype;
begin
  if p_actor_user_id is null or p_request_id is null then
    return jsonb_build_object('ok',false,'outcome','invalid_request','points_awarded',0);
  end if;
  if p_token is null or length(p_token)<16 or length(p_token)>512 then
    return jsonb_build_object('ok',false,'outcome','invalid_code','points_awarded',0);
  end if;

  select q.* into v_qr
  from public.qr_codes q
  where q.token_hash=encode(digest(convert_to(p_token,'UTF8'),'sha256'),'hex')
  limit 1;
  if not found then
    return jsonb_build_object('ok',false,'outcome','invalid_code','points_awarded',0);
  end if;

  -- A client request ID is tenant-scoped. Serialize it before locking the QR row
  -- so concurrent re-use against different QRs cannot race into a unique-key error.
  perform pg_advisory_xact_lock(
    hashtextextended(v_qr.tenant_id::text || ':claim:' || p_request_id::text, 0)
  );

  select q.* into v_qr
    from public.qr_codes q
   where q.id = v_qr.id
   for update;
  if not found then
    return jsonb_build_object('ok',false,'outcome','invalid_code','points_awarded',0);
  end if;

  -- Replays must match BOTH the owner and the QR. A reused request UUID for a
  -- different QR or actor must fail without disclosing any prior claim details.
  select c.* into v_existing
    from public.claims c
   where c.tenant_id = v_qr.tenant_id
     and c.idempotency_key = ('claim:' || p_request_id::text)
   limit 1;

  if found then
    if v_existing.qr_code_id = v_qr.id
       and exists (
         select 1 from public.partners p
          where p.id = v_existing.partner_id
            and p.tenant_id = v_existing.tenant_id
            and p.user_id = p_actor_user_id
       ) then
      return jsonb_build_object(
        'ok',v_existing.status='accepted',
        'outcome',case when v_existing.status='accepted' then 'accepted' else 'rejected' end,
        'claim_id',v_existing.id,
        'points_awarded',v_existing.points_awarded,
        'replayed',true
      );
    end if;

    return jsonb_build_object(
      'ok',false,
      'outcome','request_id_conflict',
      'points_awarded',0
    );
  end if;

  select p.* into v_partner
  from public.partners p
  where p.tenant_id=v_qr.tenant_id
    and p.user_id=p_actor_user_id
    and p.verification_status='verified'
    and p.role=v_qr.entitlement_role
  limit 1;
  if not found then
    insert into public.scan_events(tenant_id,qr_code_id,actor_user_id,outcome,request_id,app_version,device_ref_hash)
    values(v_qr.tenant_id,v_qr.id,p_actor_user_id,'ineligible',p_request_id,p_app_version,p_device_ref_hash)
    on conflict(tenant_id,request_id) do nothing;
    return jsonb_build_object('ok',false,'outcome','ineligible','points_awarded',0);
  end if;

  if v_qr.status='claimed' then
    insert into public.scan_events(tenant_id,qr_code_id,actor_user_id,outcome,request_id,app_version,device_ref_hash)
    values(v_qr.tenant_id,v_qr.id,p_actor_user_id,'duplicate',p_request_id,p_app_version,p_device_ref_hash)
    on conflict(tenant_id,request_id) do nothing;
    return jsonb_build_object('ok',false,'outcome','already_claimed','points_awarded',0);
  elsif v_qr.status='revoked' then
    insert into public.scan_events(tenant_id,qr_code_id,actor_user_id,outcome,request_id,app_version,device_ref_hash)
    values(v_qr.tenant_id,v_qr.id,p_actor_user_id,'revoked',p_request_id,p_app_version,p_device_ref_hash)
    on conflict(tenant_id,request_id) do nothing;
    return jsonb_build_object('ok',false,'outcome','revoked','points_awarded',0);
  elsif v_qr.status='expired' or (v_qr.expires_at is not null and v_qr.expires_at<=now()) then
    insert into public.scan_events(tenant_id,qr_code_id,actor_user_id,outcome,request_id,app_version,device_ref_hash)
    values(v_qr.tenant_id,v_qr.id,p_actor_user_id,'expired',p_request_id,p_app_version,p_device_ref_hash)
    on conflict(tenant_id,request_id) do nothing;
    return jsonb_build_object('ok',false,'outcome','expired','points_awarded',0);
  elsif v_qr.status<>'active' then
    insert into public.scan_events(tenant_id,qr_code_id,actor_user_id,outcome,request_id,app_version,device_ref_hash)
    values(v_qr.tenant_id,v_qr.id,p_actor_user_id,'invalid',p_request_id,p_app_version,p_device_ref_hash)
    on conflict(tenant_id,request_id) do nothing;
    return jsonb_build_object('ok',false,'outcome','not_activated','points_awarded',0);
  end if;

  if v_qr.campaign_id is null then
    return jsonb_build_object('ok',false,'outcome','campaign_missing','points_awarded',0);
  end if;

  select c.* into v_campaign
  from public.campaigns c
  where c.id=v_qr.campaign_id and c.tenant_id=v_qr.tenant_id;
  if not found or v_campaign.status<>'active'
     or (v_campaign.starts_at is not null and v_campaign.starts_at>now())
     or (v_campaign.ends_at is not null and v_campaign.ends_at<=now()) then
    insert into public.scan_events(tenant_id,qr_code_id,actor_user_id,outcome,request_id,app_version,device_ref_hash)
    values(v_qr.tenant_id,v_qr.id,p_actor_user_id,'ineligible',p_request_id,p_app_version,p_device_ref_hash)
    on conflict(tenant_id,request_id) do nothing;
    return jsonb_build_object('ok',false,'outcome','campaign_inactive','points_awarded',0);
  end if;

  if v_qr.points_value<=0 then
    return jsonb_build_object('ok',false,'outcome','no_reward_value','points_awarded',0);
  end if;

  update public.qr_codes set status='claimed',claimed_at=now()
  where id=v_qr.id and status='active';
  if not found then
    insert into public.scan_events(tenant_id,qr_code_id,actor_user_id,outcome,request_id,app_version,device_ref_hash)
    values(v_qr.tenant_id,v_qr.id,p_actor_user_id,'duplicate',p_request_id,p_app_version,p_device_ref_hash)
    on conflict(tenant_id,request_id) do nothing;
    return jsonb_build_object('ok',false,'outcome','already_claimed','points_awarded',0);
  end if;

  insert into public.claims(tenant_id,qr_code_id,partner_id,campaign_id,status,points_awarded,rule_version,idempotency_key)
  values(v_qr.tenant_id,v_qr.id,v_partner.id,v_qr.campaign_id,'accepted',v_qr.points_value,v_campaign.rules_version,'claim:'||p_request_id::text)
  returning id into v_claim_id;

  insert into public.points_ledger(tenant_id,partner_id,claim_id,entry_type,points_delta,idempotency_key,reason_code,actor_user_id)
  values(v_qr.tenant_id,v_partner.id,v_claim_id,'earn',v_qr.points_value,'earn:'||v_claim_id::text,'verified_qr_claim',p_actor_user_id);

  insert into public.scan_events(tenant_id,qr_code_id,actor_user_id,outcome,request_id,app_version,device_ref_hash)
  values(v_qr.tenant_id,v_qr.id,p_actor_user_id,'accepted',p_request_id,p_app_version,p_device_ref_hash)
  on conflict(tenant_id,request_id) do nothing;

  insert into public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,request_id,after_data)
  values(v_qr.tenant_id,p_actor_user_id,'qr_claim_accepted','claim',v_claim_id,p_request_id,jsonb_build_object('points_awarded',v_qr.points_value,'campaign_id',v_qr.campaign_id));

  return jsonb_build_object('ok',true,'outcome','accepted','claim_id',v_claim_id,'points_awarded',v_qr.points_value,'replayed',false);
end
$function$;
