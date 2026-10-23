-- Read-only live schema baseline gate for the protected production release workflow.
-- Returns exactly one row; it never changes schema, data, grants, or migration history.
WITH live_categories AS (
  SELECT 'columns' AS category, count(*)::int AS object_count,
    encode(extensions.digest(convert_to(coalesce(string_agg(concat_ws('|',table_name,column_name,ordinal_position,udt_schema,udt_name,is_nullable,coalesce(column_default,''),coalesce(is_identity,''),coalesce(identity_generation,''),coalesce(is_generated,''),coalesce(generation_expression,'')), E'\n' ORDER BY table_name,ordinal_position),''),'UTF8'),'sha256'),'hex') AS fingerprint
  FROM information_schema.columns WHERE table_schema='public'
  UNION ALL
  SELECT 'constraints', count(*)::int,
    encode(extensions.digest(convert_to(coalesce(string_agg(concat_ws('|',c.conrelid::regclass::text,c.conname,c.contype,pg_get_constraintdef(c.oid,true)),E'\n' ORDER BY c.conrelid::regclass::text,c.conname),''),'UTF8'),'sha256'),'hex')
  FROM pg_constraint c WHERE c.connamespace='public'::regnamespace
  UNION ALL
  SELECT 'enums', count(*)::int,
    encode(extensions.digest(convert_to(coalesce(string_agg(concat_ws('|',n.nspname,t.typname,e.enumsortorder,e.enumlabel),E'\n' ORDER BY n.nspname,t.typname,e.enumsortorder),''),'UTF8'),'sha256'),'hex')
  FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace JOIN pg_enum e ON e.enumtypid=t.oid WHERE n.nspname='public'
  UNION ALL
  SELECT 'indexes', count(*)::int,
    encode(extensions.digest(convert_to(coalesce(string_agg(concat_ws('|',schemaname,tablename,indexname,indexdef),E'\n' ORDER BY schemaname,tablename,indexname),''),'UTF8'),'sha256'),'hex')
  FROM pg_indexes WHERE schemaname='public'
  UNION ALL
  SELECT 'policies', count(*)::int,
    encode(extensions.digest(convert_to(coalesce(string_agg(concat_ws('|',schemaname,tablename,policyname,permissive,array_to_string(roles,','),cmd,coalesce(qual,''),coalesce(with_check,'')),E'\n' ORDER BY schemaname,tablename,policyname),''),'UTF8'),'sha256'),'hex')
  FROM pg_policies WHERE schemaname='public'
  UNION ALL
  SELECT 'rls', count(*)::int,
    encode(extensions.digest(convert_to(coalesce(string_agg(concat_ws('|',n.nspname,c.relname,c.relrowsecurity,c.relforcerowsecurity),E'\n' ORDER BY n.nspname,c.relname),''),'UTF8'),'sha256'),'hex')
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p')
  UNION ALL
  SELECT 'triggers', count(*)::int,
    encode(extensions.digest(convert_to(coalesce(string_agg(concat_ws('|',n.nspname,c.relname,t.tgname,pg_get_triggerdef(t.oid,true)),E'\n' ORDER BY n.nspname,c.relname,t.tgname),''),'UTF8'),'sha256'),'hex')
  FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE NOT t.tgisinternal AND n.nspname IN ('public','private')
),
expected_categories(category, object_count, fingerprint) AS (
  VALUES
    ('columns',170,'557cf04098d8519f16d8cc1a9d145088734cb6ef9cefce7bf3dcc467098719a2'),
    ('constraints',92,'33c1dc63ba89a52e68e4d54ea54e2ee971269dfcd3821b339fcdbc499e09ebf2'),
    ('enums',28,'e42d1fab480c15e989b9c1ed6bb57176c1c2f3bf3440817df91e39bbe59a40a4'),
    ('indexes',60,'9d67f1e13fcaca28de634af6810f33d0b478806b62b6c49b69d4a2469a7e8a1d'),
    ('policies',14,'55e32a204770348638ee3366e69ec6e77b590dfcaedd97a46e31cbe12e1b65dd'),
    ('rls',15,'ea231962c74cee2034e24221b023b7bcf79a01a0aa32550fc22eb6c413fd752a'),
    ('triggers',0,'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
),
expected_functions(schema_name,function_name,body_md5,is_security_definer,config) AS (
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
),
expected_table_grants(table_name, grants_md5) AS (
  VALUES
    ('audit_logs','e1fb0cbab82059804326b753e16d4557'),
    ('campaigns','e52514b32371c5f424fe9b730d67ae5b'),
    ('claims','d4daba63fc0f1e39d138b6f1b5ad2b6e'),
    ('partners','d4daba63fc0f1e39d138b6f1b5ad2b6e'),
    ('points_ledger','d4daba63fc0f1e39d138b6f1b5ad2b6e'),
    ('production_batches','e1fb0cbab82059804326b753e16d4557'),
    ('products','e52514b32371c5f424fe9b730d67ae5b'),
    ('qr_codes','e1fb0cbab82059804326b753e16d4557'),
    ('qr_issuance_batches','e1fb0cbab82059804326b753e16d4557'),
    ('redemptions','b2899319147ae8beb8b63ba3ad8f9156'),
    ('rewardloop_admin_settings','e1fb0cbab82059804326b753e16d4557'),
    ('rewards','b2899319147ae8beb8b63ba3ad8f9156'),
    ('scan_events','e1fb0cbab82059804326b753e16d4557'),
    ('tenant_memberships','d4daba63fc0f1e39d138b6f1b5ad2b6e'),
    ('tenants','e52514b32371c5f424fe9b730d67ae5b')
),
live_table_grants AS (
  SELECT c.relname AS table_name,
    md5(coalesce(string_agg(concat_ws('|',gr.rolname,coalesce(ge.rolname,'PUBLIC'),x.privilege_type,x.is_grantable::text),';'
      ORDER BY gr.rolname,coalesce(ge.rolname,'PUBLIC'),x.privilege_type,x.is_grantable::text),'')) AS grants_md5
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  LEFT JOIN LATERAL aclexplode(c.relacl) x ON true
  LEFT JOIN pg_roles gr ON gr.oid=x.grantor LEFT JOIN pg_roles ge ON ge.oid=x.grantee
  WHERE n.nspname='public' AND c.relkind IN ('r','p','S')
  GROUP BY c.relname
),
checks AS (
  SELECT
    NOT EXISTS (
      SELECT 1 FROM expected_categories e LEFT JOIN live_categories a USING(category)
      WHERE a.category IS NULL OR a.object_count<>e.object_count OR a.fingerprint<>e.fingerprint
    ) AS categories_match,
    NOT EXISTS (
      SELECT 1 FROM expected_functions e
      LEFT JOIN pg_namespace n ON n.nspname=e.schema_name
      LEFT JOIN pg_proc p ON p.pronamespace=n.oid AND p.proname=e.function_name AND p.prokind IN ('f','p')
      WHERE p.oid IS NULL OR md5(p.prosrc)<>e.body_md5 OR p.prosecdef<>e.is_security_definer
        OR coalesce(array_to_string(p.proconfig,','),'')<>e.config
    ) AS functions_match,
    NOT EXISTS (
      SELECT 1 FROM expected_table_grants e LEFT JOIN live_table_grants a USING(table_name)
      WHERE a.table_name IS NULL OR a.grants_md5<>e.grants_md5
    ) AS table_acl_match,
    (
      SELECT count(*) = 24
        AND encode(extensions.digest(convert_to(coalesce(string_agg(
          concat_ws('|',COALESCE(r.rolname,'PUBLIC'),COALESCE(n.nspname,'ALL_SCHEMAS'),d.defaclobjtype,d.defaclacl::text),
          E'\n' ORDER BY COALESCE(r.rolname,'PUBLIC'),COALESCE(n.nspname,'ALL_SCHEMAS'),d.defaclobjtype),''),'UTF8'),'sha256'),'hex')
          = '642e160f2667b54bde03a979af4eb14bb818281cb3f628f4910ab24426bb1792'
      FROM pg_default_acl d
      LEFT JOIN pg_roles r ON r.oid=d.defaclrole
      LEFT JOIN pg_namespace n ON n.oid=d.defaclnamespace
    ) AS default_acl_match,
    NOT has_schema_privilege('anon','private','USAGE')
      AND NOT has_schema_privilege('authenticated','private','USAGE')
      AND NOT has_function_privilege('anon','private.claim_qr(uuid,text,uuid,text,text)','EXECUTE')
      AND NOT has_function_privilege('authenticated','private.claim_qr(uuid,text,uuid,text,text)','EXECUTE')
      AND has_function_privilege('service_role','private.claim_qr(uuid,text,uuid,text,text)','EXECUTE')
      AND has_function_privilege('anon','private.create_rewardloop_campaign(uuid,uuid,text,timestamptz,timestamptz,bigint)','EXECUTE')
      AND has_function_privilege('authenticated','private.create_rewardloop_campaign(uuid,uuid,text,timestamptz,timestamptz,bigint)','EXECUTE')
      AND has_function_privilege('service_role','private.create_rewardloop_campaign(uuid,uuid,text,timestamptz,timestamptz,bigint)','EXECUTE')
      AND NOT has_function_privilege('anon','private.issue_qr_batch(uuid,uuid,uuid,uuid,integer,integer,text)','EXECUTE')
      AND NOT has_function_privilege('authenticated','private.issue_qr_batch(uuid,uuid,uuid,uuid,integer,integer,text)','EXECUTE')
      AND has_function_privilege('service_role','private.issue_qr_batch(uuid,uuid,uuid,uuid,integer,integer,text)','EXECUTE')
      AND NOT has_function_privilege('anon','private.redeem_reward(uuid,uuid,text)','EXECUTE')
      AND NOT has_function_privilege('authenticated','private.redeem_reward(uuid,uuid,text)','EXECUTE')
      AND has_function_privilege('service_role','private.redeem_reward(uuid,uuid,text)','EXECUTE')
      AND has_function_privilege('anon','private.resolve_redemption(uuid,uuid,uuid,text,text)','EXECUTE')
      AND has_function_privilege('authenticated','private.resolve_redemption(uuid,uuid,uuid,text,text)','EXECUTE')
      AND has_function_privilege('service_role','private.resolve_redemption(uuid,uuid,uuid,text,text)','EXECUTE')
      AND NOT has_function_privilege('anon','private.revoke_qr_batch(uuid,uuid,uuid,text)','EXECUTE')
      AND NOT has_function_privilege('authenticated','private.revoke_qr_batch(uuid,uuid,uuid,text)','EXECUTE')
      AND has_function_privilege('service_role','private.revoke_qr_batch(uuid,uuid,uuid,text)','EXECUTE')
      AND has_function_privilege('anon','private.set_rewardloop_campaign_status(uuid,uuid,uuid,text,text)','EXECUTE')
      AND has_function_privilege('authenticated','private.set_rewardloop_campaign_status(uuid,uuid,uuid,text,text)','EXECUTE')
      AND has_function_privilege('service_role','private.set_rewardloop_campaign_status(uuid,uuid,uuid,text,text)','EXECUTE')
      AND NOT has_function_privilege('anon','private.verify_partner(uuid,uuid,uuid,text,text)','EXECUTE')
      AND NOT has_function_privilege('authenticated','private.verify_partner(uuid,uuid,uuid,text,text)','EXECUTE')
      AND has_function_privilege('service_role','private.verify_partner(uuid,uuid,uuid,text,text)','EXECUTE')
      AS function_acl_match
)
SELECT categories_match, functions_match, table_acl_match, default_acl_match, function_acl_match,
  (categories_match AND functions_match AND table_acl_match AND default_acl_match AND function_acl_match) AS baseline_matches
FROM checks;
