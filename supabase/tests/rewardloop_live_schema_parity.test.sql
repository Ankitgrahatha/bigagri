-- Fingerprint the clean baseline against a read-only catalog snapshot from the live project.
-- This test runs after the baseline + legacy timestamp markers and before any post-baseline migrations.
-- It performs no mutations to business tables and must only run in disposable CI PostgreSQL.
DO $schema_parity$
DECLARE
  v_actual record;
  v_expected record;
BEGIN
  FOR v_expected IN
    SELECT * FROM (VALUES
      ('columns',170,'557cf04098d8519f16d8cc1a9d145088734cb6ef9cefce7bf3dcc467098719a2'),
      ('constraints',92,'33c1dc63ba89a52e68e4d54ea54e2ee971269dfcd3821b339fcdbc499e09ebf2'),
      ('enums',28,'e42d1fab480c15e989b9c1ed6bb57176c1c2f3bf3440817df91e39bbe59a40a4'),
      ('functions',16,'22651a34d36fbdfcb05395ed57a02f79ffac0a0050ab974fd09709fcf2f746f3'),
      ('indexes',60,'9d67f1e13fcaca28de634af6810f33d0b478806b62b6c49b69d4a2469a7e8a1d'),
      ('policies',14,'55e32a204770348638ee3366e69ec6e77b590dfcaedd97a46e31cbe12e1b65dd'),
      ('rls',15,'ea231962c74cee2034e24221b023b7bcf79a01a0aa32550fc22eb6c413fd752a'),
      ('table_acl',15,'64a3c59af6a5583a528ec331353b4628ec978fa080b2a5d6189204b54e5d8d59'),
      ('triggers',0,'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
    ) AS e(category, object_count, fingerprint)
  LOOP
    CASE v_expected.category
      WHEN 'columns' THEN
        SELECT count(*)::integer n,
          encode(extensions.digest(convert_to(coalesce(string_agg(
            concat_ws('|',table_name,column_name,ordinal_position,udt_schema,udt_name,is_nullable,
              coalesce(column_default,''),coalesce(is_identity,''),coalesce(identity_generation,''),
              coalesce(is_generated,''),coalesce(generation_expression,'')),
            E'\n' ORDER BY table_name,ordinal_position),''),'UTF8'),'sha256'),'hex') fingerprint
          INTO v_actual FROM information_schema.columns WHERE table_schema='public';
      WHEN 'constraints' THEN
        SELECT count(*)::integer n,
          encode(extensions.digest(convert_to(coalesce(string_agg(
            concat_ws('|',c.conrelid::regclass::text,c.conname,c.contype,pg_get_constraintdef(c.oid,true)),
            E'\n' ORDER BY c.conrelid::regclass::text,c.conname),''),'UTF8'),'sha256'),'hex') fingerprint
          INTO v_actual FROM pg_constraint c WHERE c.connamespace='public'::regnamespace;
      WHEN 'enums' THEN
        SELECT count(*)::integer n,
          encode(extensions.digest(convert_to(coalesce(string_agg(
            concat_ws('|',n.nspname,t.typname,e.enumsortorder,e.enumlabel),
            E'\n' ORDER BY n.nspname,t.typname,e.enumsortorder),''),'UTF8'),'sha256'),'hex') fingerprint
          INTO v_actual
          FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
          JOIN pg_enum e ON e.enumtypid=t.oid WHERE n.nspname='public';
      WHEN 'functions' THEN
        SELECT count(*)::integer n,
          encode(extensions.digest(convert_to(coalesce(string_agg(
            concat_ws('|',n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),
              pg_get_functiondef(p.oid),p.prosecdef,coalesce(array_to_string(p.proconfig,','),''),
              coalesce((SELECT string_agg(concat_ws('|',gr.rolname,coalesce(ge.rolname,'PUBLIC'),
                x.privilege_type,x.is_grantable::text),';'
                ORDER BY gr.rolname,coalesce(ge.rolname,'PUBLIC'),x.privilege_type,x.is_grantable::text)
                FROM aclexplode(p.proacl) x JOIN pg_roles gr ON gr.oid=x.grantor
                LEFT JOIN pg_roles ge ON ge.oid=x.grantee),'')
            ),E'\\n' ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)),''),'UTF8'),'sha256'),'hex') fingerprint
          INTO v_actual FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname IN ('public','private') AND p.prokind IN ('f','p');
      WHEN 'indexes' THEN
        SELECT count(*)::integer n,
          encode(extensions.digest(convert_to(coalesce(string_agg(
            concat_ws('|',schemaname,tablename,indexname,indexdef),
            E'\n' ORDER BY schemaname,tablename,indexname),''),'UTF8'),'sha256'),'hex') fingerprint
          INTO v_actual FROM pg_indexes WHERE schemaname='public';
      WHEN 'policies' THEN
        SELECT count(*)::integer n,
          encode(extensions.digest(convert_to(coalesce(string_agg(
            concat_ws('|',schemaname,tablename,policyname,permissive,array_to_string(roles,','),
              cmd,coalesce(qual,''),coalesce(with_check,'')),
            E'\n' ORDER BY schemaname,tablename,policyname),''),'UTF8'),'sha256'),'hex') fingerprint
          INTO v_actual FROM pg_policies WHERE schemaname='public';
      WHEN 'rls' THEN
        SELECT count(*)::integer n,
          encode(extensions.digest(convert_to(coalesce(string_agg(
            concat_ws('|',n.nspname,c.relname,c.relrowsecurity,c.relforcerowsecurity),
            E'\n' ORDER BY n.nspname,c.relname),''),'UTF8'),'sha256'),'hex') fingerprint
          INTO v_actual FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
         WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p');
      WHEN 'table_acl' THEN
        SELECT
          (SELECT count(*)::integer FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='public' AND c.relkind IN ('r','p','S')) n,
          encode(extensions.digest(convert_to(coalesce((
            SELECT string_agg(concat_ws('|',n.nspname,c.relname,pg_get_userbyid(c.relowner),
              gr.rolname,coalesce(ge.rolname,'PUBLIC'),x.privilege_type,x.is_grantable::text),
              E'\\n' ORDER BY n.nspname,c.relname,pg_get_userbyid(c.relowner),
                gr.rolname,coalesce(ge.rolname,'PUBLIC'),x.privilege_type,x.is_grantable::text)
            FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            CROSS JOIN LATERAL aclexplode(c.relacl) x
            JOIN pg_roles gr ON gr.oid=x.grantor
            LEFT JOIN pg_roles ge ON ge.oid=x.grantee
            WHERE n.nspname='public' AND c.relkind IN ('r','p','S')
          ),''),'UTF8'),'sha256'),'hex') fingerprint
          INTO v_actual;
      WHEN 'triggers' THEN
        SELECT count(*)::integer n,
          encode(extensions.digest(convert_to(coalesce(string_agg(
            concat_ws('|',n.nspname,c.relname,t.tgname,pg_get_triggerdef(t.oid,true)),
            E'\n' ORDER BY n.nspname,c.relname,t.tgname),''),'UTF8'),'sha256'),'hex') fingerprint
          INTO v_actual FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
          JOIN pg_namespace n ON n.oid=c.relnamespace
         WHERE NOT t.tgisinternal AND n.nspname IN ('public','private');
    END CASE;

    IF v_actual.n <> v_expected.object_count OR v_actual.fingerprint <> v_expected.fingerprint THEN
      RAISE EXCEPTION 'schema baseline parity mismatch for %: count expected %, actual %; fingerprint expected %, actual %',
        v_expected.category,v_expected.object_count,v_actual.n,v_expected.fingerprint,v_actual.fingerprint;
    END IF;
  END LOOP;
  -- Default ACLs are compared behaviorally because PostgreSQL versions may serialize ACL arrays differently.
  CREATE TABLE public.rewardloop_schema_parity_acl_probe (id integer);
  CREATE SEQUENCE public.rewardloop_schema_parity_sequence_probe;
  CREATE FUNCTION public.rewardloop_schema_parity_function_probe()
    RETURNS integer LANGUAGE sql AS $fn$ SELECT 1 $fn$;

  IF NOT has_table_privilege('anon','public.rewardloop_schema_parity_acl_probe','SELECT')
     OR NOT has_table_privilege('anon','public.rewardloop_schema_parity_acl_probe','INSERT')
     OR NOT has_table_privilege('anon','public.rewardloop_schema_parity_acl_probe','TRUNCATE')
     OR NOT has_table_privilege('authenticated','public.rewardloop_schema_parity_acl_probe','SELECT')
     OR NOT has_table_privilege('authenticated','public.rewardloop_schema_parity_acl_probe','INSERT')
     OR NOT has_table_privilege('authenticated','public.rewardloop_schema_parity_acl_probe','TRUNCATE')
     OR NOT has_sequence_privilege('anon','public.rewardloop_schema_parity_sequence_probe','USAGE')
     OR NOT has_sequence_privilege('authenticated','public.rewardloop_schema_parity_sequence_probe','USAGE')
     OR NOT has_function_privilege('anon','public.rewardloop_schema_parity_function_probe()','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.rewardloop_schema_parity_function_probe()','EXECUTE')
     OR NOT has_table_privilege('service_role','public.rewardloop_schema_parity_acl_probe','INSERT')
     OR NOT has_sequence_privilege('service_role','public.rewardloop_schema_parity_sequence_probe','USAGE')
     OR NOT has_function_privilege('service_role','public.rewardloop_schema_parity_function_probe()','EXECUTE') THEN
    RAISE EXCEPTION 'schema baseline default-privilege behavior differs from the captured live project';
  END IF;

  DROP FUNCTION public.rewardloop_schema_parity_function_probe();
  DROP SEQUENCE public.rewardloop_schema_parity_sequence_probe;
  DROP TABLE public.rewardloop_schema_parity_acl_probe;

  RAISE NOTICE 'PASS: clean baseline matches live catalog fingerprints and default ACL behavior';
END
$schema_parity$;
