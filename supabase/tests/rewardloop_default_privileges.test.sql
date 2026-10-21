-- Validate default grants on newly-created objects in an isolated disposable database.
BEGIN;

CREATE TABLE public.rewardloop_future_acl_table_test (id uuid PRIMARY KEY);
CREATE SEQUENCE public.rewardloop_future_acl_sequence_test;
CREATE FUNCTION public.rewardloop_future_acl_public_fn_test()
RETURNS integer LANGUAGE sql AS $fn$ SELECT 1 $fn$;
CREATE FUNCTION private.rewardloop_future_acl_private_fn_test()
RETURNS integer LANGUAGE sql AS $fn$ SELECT 1 $fn$;

DO $default_acl_test$
BEGIN
  IF has_table_privilege('anon', 'public.rewardloop_future_acl_table_test', 'SELECT')
     OR has_table_privilege('anon', 'public.rewardloop_future_acl_table_test', 'INSERT')
     OR has_table_privilege('anon', 'public.rewardloop_future_acl_table_test', 'UPDATE')
     OR has_table_privilege('anon', 'public.rewardloop_future_acl_table_test', 'DELETE')
     OR has_table_privilege('anon', 'public.rewardloop_future_acl_table_test', 'TRUNCATE')
     OR has_table_privilege('anon', 'public.rewardloop_future_acl_table_test', 'REFERENCES')
     OR has_table_privilege('anon', 'public.rewardloop_future_acl_table_test', 'TRIGGER')
     OR has_table_privilege('authenticated', 'public.rewardloop_future_acl_table_test', 'SELECT')
     OR has_table_privilege('authenticated', 'public.rewardloop_future_acl_table_test', 'INSERT')
     OR has_table_privilege('authenticated', 'public.rewardloop_future_acl_table_test', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.rewardloop_future_acl_table_test', 'DELETE')
     OR has_table_privilege('authenticated', 'public.rewardloop_future_acl_table_test', 'TRUNCATE')
     OR has_table_privilege('authenticated', 'public.rewardloop_future_acl_table_test', 'REFERENCES')
     OR has_table_privilege('authenticated', 'public.rewardloop_future_acl_table_test', 'TRIGGER') THEN
    RAISE EXCEPTION 'anon/authenticated received automatic table privileges on a newly-created public table';
  END IF;

  IF has_sequence_privilege('anon', 'public.rewardloop_future_acl_sequence_test', 'USAGE')
     OR has_sequence_privilege('anon', 'public.rewardloop_future_acl_sequence_test', 'SELECT')
     OR has_sequence_privilege('anon', 'public.rewardloop_future_acl_sequence_test', 'UPDATE')
     OR has_sequence_privilege('authenticated', 'public.rewardloop_future_acl_sequence_test', 'USAGE')
     OR has_sequence_privilege('authenticated', 'public.rewardloop_future_acl_sequence_test', 'SELECT')
     OR has_sequence_privilege('authenticated', 'public.rewardloop_future_acl_sequence_test', 'UPDATE') THEN
    RAISE EXCEPTION 'anon/authenticated received automatic sequence privileges';
  END IF;

  IF has_function_privilege('anon', 'public.rewardloop_future_acl_public_fn_test()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.rewardloop_future_acl_public_fn_test()', 'EXECUTE')
     OR has_function_privilege('anon', 'private.rewardloop_future_acl_private_fn_test()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.rewardloop_future_acl_private_fn_test()', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon/authenticated received EXECUTE on a newly-created function';
  END IF;

  IF NOT has_table_privilege('service_role', 'public.rewardloop_future_acl_table_test', 'INSERT')
     OR NOT has_sequence_privilege('service_role', 'public.rewardloop_future_acl_sequence_test', 'USAGE')
     OR NOT has_function_privilege('service_role', 'public.rewardloop_future_acl_public_fn_test()', 'EXECUTE') THEN
    RAISE EXCEPTION 'service_role lost the historical server-side default privileges';
  END IF;

  RAISE NOTICE 'PASS: new public/private objects default-deny client roles while retaining service_role public defaults';
END;
$default_acl_test$;

ROLLBACK;
