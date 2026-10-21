-- Database-level contract for actor-scoped claim replay.
-- Run only against a disposable local Supabase database rebuilt from migrations.
-- This inspects function source/grants only; it does not mutate business records.

begin;

do $$
declare
  v_oid oid;
  v_definition text;
begin
  select p.oid, pg_get_functiondef(p.oid)
    into v_oid, v_definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private'
    and p.proname = 'claim_qr'
    and pg_get_function_identity_arguments(p.oid) like 'p_actor_user_id uuid, p_token text, p_request_id uuid%';

  if v_oid is null then
    raise exception 'SECURITY CONTRACT FAILED: private.claim_qr definition missing';
  end if;

  if position('join public.partners p' in lower(v_definition)) = 0
     or position('p.user_id=p_actor_user_id' in lower(v_definition)) = 0
     or position('p.tenant_id=c.tenant_id' in lower(v_definition)) = 0 then
    raise exception 'SECURITY CONTRACT FAILED: claim replay is not scoped to the owning actor and tenant';
  end if;

  if has_function_privilege('anon', v_oid, 'EXECUTE')
     or has_function_privilege('authenticated', v_oid, 'EXECUTE') then
    raise exception 'SECURITY CONTRACT FAILED: private.claim_qr is directly executable by a client role';
  end if;
end
$$;

rollback;
