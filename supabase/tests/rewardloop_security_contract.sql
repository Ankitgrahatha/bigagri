-- RewardLoop read-only security contract checks.
-- Safe to run against a project: this script only inspects catalog metadata and function source.
-- Run in Supabase SQL Editor or a disposable CI database after migrations are applied.

do $$
declare
  v_table text;
  v_oid oid;
  v_source text;
begin
  foreach v_table in array array[
    'tenants','tenant_memberships','partners','products','campaigns',
    'qr_codes','claims','points_ledger','redemptions','rewards',
    'rewardloop_admin_settings'
  ] loop
    if not exists (
      select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = v_table
        and c.relkind = 'r' and c.relrowsecurity
    ) then
      raise exception 'SECURITY CONTRACT FAILED: RLS missing or table missing: public.%', v_table;
    end if;
  end loop;

  foreach v_table in array array[
    'rewardloop_claim_qr_internal',
    'rewardloop_redeem_internal',
    'rewardloop_issue_qr_batch_internal',
    'rewardloop_revoke_qr_batch_internal',
    'rewardloop_verify_partner_internal',
    'rewardloop_resolve_redemption_internal',
    'rewardloop_create_campaign_internal',
    'rewardloop_set_campaign_status_internal'
  ] loop
    select p.oid into v_oid
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = v_table
    order by p.oid desc limit 1;

    if v_oid is null then
      raise exception 'SECURITY CONTRACT FAILED: missing RPC public.%', v_table;
    end if;

    if has_function_privilege('anon', v_oid, 'EXECUTE')
       or has_function_privilege('authenticated', v_oid, 'EXECUTE') then
      raise exception 'SECURITY CONTRACT FAILED: client role can execute public.%', v_table;
    end if;

    if not has_function_privilege('service_role', v_oid, 'EXECUTE') then
      raise exception 'SECURITY CONTRACT FAILED: service_role cannot execute public.%', v_table;
    end if;
  end loop;

  select pg_get_functiondef(p.oid) into v_source
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'set_rewardloop_campaign_status'
  order by p.oid desc limit 1;

  if v_source is null or position('demo_campaign_not_activatable' in v_source) = 0 then
    raise exception 'SECURITY CONTRACT FAILED: demo campaign activation guard is missing';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'qr_codes'
      and cmd = 'ALL' and 'anon'::name = any(roles) and 'authenticated'::name = any(roles)
      and coalesce(qual, '') = 'false'
      and coalesce(with_check, '') = 'false'
  ) then
    raise exception 'SECURITY CONTRACT FAILED: explicit client deny policy for QR codes missing';
  end if;

  raise notice 'RewardLoop security metadata contracts passed.';
end
$$;
