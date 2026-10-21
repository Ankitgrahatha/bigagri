-- Run only in the disposable PostgreSQL CI service; no production data is touched.
BEGIN;

DO $privilege_hardening_test$
DECLARE
  v_name text;
  v_signature text;
BEGIN
  IF NOT has_table_privilege('anon', 'public.rewards', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.rewards', 'SELECT')
     OR NOT has_table_privilege('anon', 'public.redemptions', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.redemptions', 'SELECT') THEN
    RAISE EXCEPTION 'client roles lost required read access to rewards/redemptions';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM (VALUES ('anon'), ('authenticated')) AS roles(role_name)
     WHERE has_table_privilege(role_name, 'public.rewards', 'INSERT')
        OR has_table_privilege(role_name, 'public.rewards', 'UPDATE')
        OR has_table_privilege(role_name, 'public.rewards', 'DELETE')
        OR has_table_privilege(role_name, 'public.rewards', 'TRUNCATE')
        OR has_table_privilege(role_name, 'public.rewards', 'REFERENCES')
        OR has_table_privilege(role_name, 'public.rewards', 'TRIGGER')
        OR has_table_privilege(role_name, 'public.redemptions', 'INSERT')
        OR has_table_privilege(role_name, 'public.redemptions', 'UPDATE')
        OR has_table_privilege(role_name, 'public.redemptions', 'DELETE')
        OR has_table_privilege(role_name, 'public.redemptions', 'TRUNCATE')
        OR has_table_privilege(role_name, 'public.redemptions', 'REFERENCES')
        OR has_table_privilege(role_name, 'public.redemptions', 'TRIGGER')
  ) THEN
    RAISE EXCEPTION 'anon/authenticated retains non-SELECT privileges on reward-bearing tables';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE (n.nspname = 'private' AND p.proname IN (
       'claim_qr','create_rewardloop_campaign','issue_qr_batch','redeem_reward',
       'resolve_redemption','revoke_qr_batch','set_rewardloop_campaign_status','verify_partner'
     ))
        OR (n.nspname = 'public' AND p.proname LIKE 'rewardloop\_%\_internal')
       AND (
         has_function_privilege('anon', p.oid, 'EXECUTE')
         OR has_function_privilege('authenticated', p.oid, 'EXECUTE')
       )
  ) THEN
    RAISE EXCEPTION 'client role still has EXECUTE on a privileged internal function';
  END IF;

  IF NOT has_function_privilege('service_role', 'private.create_rewardloop_campaign(uuid,uuid,text,timestamptz,timestamptz,bigint)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.rewardloop_create_campaign_internal(uuid,uuid,text,timestamptz,timestamptz,bigint)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'private.resolve_redemption(uuid,uuid,uuid,text,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.rewardloop_resolve_redemption_internal(uuid,uuid,uuid,text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'service_role lost a required internal RPC grant';
  END IF;

  RAISE NOTICE 'PASS: read-only reward table grants, client RPC denial, service-role internal RPC access';
END;
$privilege_hardening_test$;

ROLLBACK;
