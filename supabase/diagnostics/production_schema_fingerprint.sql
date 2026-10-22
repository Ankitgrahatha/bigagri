-- Read-only RewardLoop production schema fingerprint diagnostic.
-- Run only from a trusted SQL session with catalog visibility. This script returns
-- schema metadata, function hashes, ACL fingerprints, and migration history only.
-- It does not read business rows, mutate objects, repair migration history, or deploy code.

WITH fingerprints AS (
  SELECT 'columns' category, count(*)::integer object_count,
    encode(extensions.digest(convert_to(coalesce(string_agg(
      concat_ws('|',table_name,column_name,ordinal_position,udt_schema,udt_name,is_nullable,
        coalesce(column_default,''),coalesce(is_identity,''),coalesce(identity_generation,''),
        coalesce(is_generated,''),coalesce(generation_expression,'')),
      E'\n' ORDER BY table_name,ordinal_position),''),'UTF8'),'sha256'),'hex') fingerprint
  FROM information_schema.columns WHERE table_schema='public'
  UNION ALL
  SELECT 'constraints', count(*)::integer,
    encode(extensions.digest(convert_to(coalesce(string_agg(
      concat_ws('|',c.conrelid::regclass::text,c.conname,c.contype,pg_get_constraintdef(c.oid,true)),
      E'\n' ORDER BY c.conrelid::regclass::text,c.conname),''),'UTF8'),'sha256'),'hex')
  FROM pg_constraint c WHERE c.connamespace='public'::regnamespace
  UNION ALL
  SELECT 'enums', count(*)::integer,
    encode(extensions.digest(convert_to(coalesce(string_agg(
      concat_ws('|',n.nspname,t.typname,e.enumsortorder,e.enumlabel),
      E'\n' ORDER BY n.nspname,t.typname,e.enumsortorder),''),'UTF8'),'sha256'),'hex')
  FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
  JOIN pg_enum e ON e.enumtypid=t.oid WHERE n.nspname='public'
  UNION ALL
  SELECT 'indexes', count(*)::integer,
    encode(extensions.digest(convert_to(coalesce(string_agg(
      concat_ws('|',schemaname,tablename,indexname,indexdef),
      E'\n' ORDER BY schemaname,tablename,indexname),''),'UTF8'),'sha256'),'hex')
  FROM pg_indexes WHERE schemaname='public'
  UNION ALL
  SELECT 'policies', count(*)::integer,
    encode(extensions.digest(convert_to(coalesce(string_agg(
      concat_ws('|',schemaname,tablename,policyname,permissive,array_to_string(roles,','),
        cmd,coalesce(qual,''),coalesce(with_check,'')),
      E'\n' ORDER BY schemaname,tablename,policyname),''),'UTF8'),'sha256'),'hex')
  FROM pg_policies WHERE schemaname='public'
  UNION ALL
  SELECT 'rls', count(*)::integer,
    encode(extensions.digest(convert_to(coalesce(string_agg(
      concat_ws('|',n.nspname,c.relname,c.relrowsecurity,c.relforcerowsecurity),
      E'\n' ORDER BY n.nspname,c.relname),''),'UTF8'),'sha256'),'hex')
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p')
  UNION ALL
  SELECT 'triggers', count(*)::integer,
    encode(extensions.digest(convert_to(coalesce(string_agg(
      concat_ws('|',n.nspname,c.relname,t.tgname,pg_get_triggerdef(t.oid,true)),
      E'\n' ORDER BY n.nspname,c.relname,t.tgname),''),'UTF8'),'sha256'),'hex')
  FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE NOT t.tgisinternal AND n.nspname IN ('public','private')
)
SELECT category, object_count, fingerprint
FROM fingerprints
ORDER BY category;

SELECT n.nspname AS schema_name, p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS identity_arguments,
       md5(p.prosrc) AS body_md5, p.prosecdef AS security_definer,
       coalesce(array_to_string(p.proconfig, ','), '') AS config
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname IN ('public','private') AND p.prokind IN ('f','p')
ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid);

SELECT c.relname AS table_name,
       md5(coalesce(string_agg(
         concat_ws('|',gr.rolname,coalesce(ge.rolname,'PUBLIC'),x.privilege_type,x.is_grantable::text),';'
         ORDER BY gr.rolname,coalesce(ge.rolname,'PUBLIC'),x.privilege_type,x.is_grantable::text),'')) AS grants_md5
FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
LEFT JOIN LATERAL aclexplode(c.relacl) x ON true
LEFT JOIN pg_roles gr ON gr.oid=x.grantor
LEFT JOIN pg_roles ge ON ge.oid=x.grantee
WHERE n.nspname='public' AND c.relkind IN ('r','p','S')
GROUP BY c.relname
ORDER BY c.relname;

SELECT version::text AS version, name
FROM supabase_migrations.schema_migrations
ORDER BY version;
