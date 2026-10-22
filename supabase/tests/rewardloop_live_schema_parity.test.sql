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
      ('default_acl_postgres',3,'22b6455fc66b7493530b32ae5b6c884685dcbbbe8e430d686e82c989a42949c4'),
      ('enums',28,'e42d1fab480c15e989b9c1ed6bb57176c1c2f3bf3440817df91e39bbe59a40a4'),
      ('functions',16,'91eb2351ce145e8313d7b0db461200b916dd229dc7c367ff16f1fddd71bb484e'),
      ('indexes',60,'9d67f1e13fcaca28de634af6810f33d0b478806b62b6c49b69d4a2469a7e8a1d'),
      ('policies',14,'55e32a204770348638ee3366e69ec6e77b590dfcaedd97a46e31cbe12e1b65dd'),
      ('rls',15,'ea231962c74cee2034e24221b023b7bcf79a01a0aa32550fc22eb6c413fd752a'),
      ('table_acl',15,'7307bd5015e41b8209d48e8a309ee1c4c2b0a315a9c365b40d38244281b5ab84'),
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
      WHEN 'default_acl_postgres' THEN
        SELECT count(*)::integer n,
          encode(extensions.digest(convert_to(coalesce(string_agg(
            concat_ws('|',r.rolname,coalesce(n.nspname,''),d.defaclobjtype,d.defaclacl::text),
            E'\n' ORDER BY r.rolname,coalesce(n.nspname,''),d.defaclobjtype),''),'UTF8'),'sha256'),'hex') fingerprint
          INTO v_actual
          FROM pg_default_acl d JOIN pg_roles r ON r.oid=d.defaclrole
          LEFT JOIN pg_namespace n ON n.oid=d.defaclnamespace
         WHERE r.rolname='postgres' AND (n.nspname='public' OR n.nspname IS NULL);
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
              coalesce(p.proacl::text,'')),
            E'\n' ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)),''),'UTF8'),'sha256'),'hex') fingerprint
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
        SELECT count(*)::integer n,
          encode(extensions.digest(convert_to(coalesce(string_agg(
            concat_ws('|',n.nspname,c.relname,pg_get_userbyid(c.relowner),coalesce(c.relacl::text,'')),
            E'\n' ORDER BY n.nspname,c.relname),''),'UTF8'),'sha256'),'hex') fingerprint
          INTO v_actual FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
         WHERE n.nspname='public' AND c.relkind IN ('r','p','S');
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
  RAISE NOTICE 'PASS: clean baseline matches live schema fingerprints for columns, constraints, default ACLs, enums, functions, indexes, policies, RLS, table ACLs and triggers';
END
$schema_parity$;
