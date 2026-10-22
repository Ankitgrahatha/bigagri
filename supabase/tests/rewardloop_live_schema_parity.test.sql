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
  -- Compare function bodies by name so any baseline drift identifies the exact function.
  IF EXISTS (
    WITH expected(schema_name,function_name,body_md5,is_security_definer,config) AS (
      VALUES
      ('private','claim_qr','f6a67d7974fe5da73b2a973c8b206f4c',true,'search_path=pg_catalog, extensions, public, private'),
      ('private','create_rewardloop_campaign','918c691ed084fa161290ff0b163f9b4a',true,'search_path=pg_catalog, extensions, public, private'),
      ('private','issue_qr_batch','5bb83cd3b2d4ebd905aaef1bde3bec25',true,'search_path=pg_catalog, extensions, public, private'),
      ('private','redeem_reward','0e4f87419e83975efdc8ac478c136ce8',true,'search_path=pg_catalog, extensions, public, private'),
      ('private','resolve_redemption','202080e0c8ea5c1d978063c5410d8de9',true,'search_path=pg_catalog, extensions, public, private'),
      ('private','revoke_qr_batch','0db0c8e10fb27f4208f599a4878ca594',true,'search_path=pg_catalog, extensions, public, private'),
      ('private','set_rewardloop_campaign_status','ead75432d9a4f03d917346d9721ead90',true,'search_path=pg_catalog, extensions, public, private'),
      ('private','verify_partner','5b8c45f972003e9327c76261d92b9997',true,'search_path=pg_catalog, extensions, public, private'),
      ('public','rewardloop_claim_qr_internal','c49ead7a91a57126905ea9c0c5234993',false,'search_path=pg_catalog, extensions, public, private'),
      ('public','rewardloop_create_campaign_internal','7536904b9391f87c0ccabb1d54b67957',true,'search_path=pg_catalog, extensions, public, private'),
      ('public','rewardloop_issue_qr_batch_internal','d49267006831ec38efe7dd31848dc89b',false,'search_path=pg_catalog, extensions, public, private'),
      ('public','rewardloop_redeem_internal','11abc0cb80825d0296726765b0b7360c',false,'search_path=pg_catalog, extensions, public, private'),
      ('public','rewardloop_resolve_redemption_internal','8946c7c4992af47872e40dc3fc4ee60f',true,'search_path=pg_catalog, extensions, public, private'),
      ('public','rewardloop_revoke_qr_batch_internal','5bee22a66d052403231df626c6ae4e33',false,'search_path=pg_catalog, extensions, public, private'),
      ('public','rewardloop_set_campaign_status_internal','9bf11777ff2af089fb72618e5fce6c13',true,'search_path=pg_catalog, extensions, public, private'),
      ('public','rewardloop_verify_partner_internal','68a505d1495a26cdd414352fe1fdea6a',false,'search_path=pg_catalog, extensions, public, private')
    )
    SELECT 1 FROM expected e
    LEFT JOIN pg_namespace n ON n.nspname=e.schema_name
    LEFT JOIN pg_proc p ON p.pronamespace=n.oid AND p.proname=e.function_name AND p.prokind IN ('f','p')
    WHERE p.oid IS NULL OR md5(p.prosrc)<>e.body_md5 OR p.prosecdef<>e.is_security_definer
       OR coalesce(array_to_string(p.proconfig,','),'')<>e.config
  ) THEN
    RAISE EXCEPTION 'baseline function body/security configuration differs from captured live function snapshot';
  END IF;

  -- Compare effective function execution grants at the historical baseline. The private schema
  -- itself must remain inaccessible to client roles; later hardening migrations narrow function ACLs.
  IF has_schema_privilege('anon','private','USAGE')
     OR has_schema_privilege('authenticated','private','USAGE') THEN
    RAISE EXCEPTION 'private schema unexpectedly grants client USAGE';
  END IF;

  IF has_function_privilege('anon','private.claim_qr(uuid,text,uuid,text,text)','EXECUTE')
     OR has_function_privilege('authenticated','private.claim_qr(uuid,text,uuid,text,text)','EXECUTE')
     OR NOT has_function_privilege('service_role','private.claim_qr(uuid,text,uuid,text,text)','EXECUTE')
     OR NOT has_function_privilege('anon','private.create_rewardloop_campaign(uuid,uuid,text,timestamptz,timestamptz,bigint)','EXECUTE')
     OR NOT has_function_privilege('authenticated','private.create_rewardloop_campaign(uuid,uuid,text,timestamptz,timestamptz,bigint)','EXECUTE')
     OR NOT has_function_privilege('service_role','private.create_rewardloop_campaign(uuid,uuid,text,timestamptz,timestamptz,bigint)','EXECUTE')
     OR has_function_privilege('anon','private.issue_qr_batch(uuid,uuid,uuid,uuid,integer,integer,text)','EXECUTE')
     OR has_function_privilege('authenticated','private.issue_qr_batch(uuid,uuid,uuid,uuid,integer,integer,text)','EXECUTE')
     OR NOT has_function_privilege('service_role','private.issue_qr_batch(uuid,uuid,uuid,uuid,integer,integer,text)','EXECUTE')
     OR has_function_privilege('anon','private.redeem_reward(uuid,uuid,text)','EXECUTE')
     OR has_function_privilege('authenticated','private.redeem_reward(uuid,uuid,text)','EXECUTE')
     OR NOT has_function_privilege('service_role','private.redeem_reward(uuid,uuid,text)','EXECUTE')
     OR NOT has_function_privilege('anon','private.resolve_redemption(uuid,uuid,uuid,text,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','private.resolve_redemption(uuid,uuid,uuid,text,text)','EXECUTE')
     OR NOT has_function_privilege('service_role','private.resolve_redemption(uuid,uuid,uuid,text,text)','EXECUTE')
     OR has_function_privilege('anon','private.revoke_qr_batch(uuid,uuid,uuid,text)','EXECUTE')
     OR has_function_privilege('authenticated','private.revoke_qr_batch(uuid,uuid,uuid,text)','EXECUTE')
     OR NOT has_function_privilege('service_role','private.revoke_qr_batch(uuid,uuid,uuid,text)','EXECUTE')
     OR NOT has_function_privilege('anon','private.set_rewardloop_campaign_status(uuid,uuid,uuid,text,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','private.set_rewardloop_campaign_status(uuid,uuid,uuid,text,text)','EXECUTE')
     OR NOT has_function_privilege('service_role','private.set_rewardloop_campaign_status(uuid,uuid,uuid,text,text)','EXECUTE')
     OR has_function_privilege('anon','private.verify_partner(uuid,uuid,uuid,text,text)','EXECUTE')
     OR has_function_privilege('authenticated','private.verify_partner(uuid,uuid,uuid,text,text)','EXECUTE')
     OR NOT has_function_privilege('service_role','private.verify_partner(uuid,uuid,uuid,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'effective private function grants differ from the captured live baseline';
  END IF;

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

  RAISE NOTICE 'PASS: clean baseline matches live catalog fingerprints, function definitions/security settings, and default ACL behavior';
END
$schema_parity$;
