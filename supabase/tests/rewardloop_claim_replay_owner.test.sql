-- Claim replay authorization must be bound to the user who owns the credited partner.
-- Executed only in disposable PostgreSQL CI.
BEGIN;

DO $claim_replay_owner_test$
DECLARE
  v_tenant constant uuid := '00000000-0000-4000-8000-00000000b101';
  v_user_a constant uuid := '00000000-0000-4000-8000-00000000b201';
  v_user_b constant uuid := '00000000-0000-4000-8000-00000000b202';
  v_partner_a constant uuid := '00000000-0000-4000-8000-00000000b301';
  v_partner_b constant uuid := '00000000-0000-4000-8000-00000000b302';
  v_product constant uuid := '00000000-0000-4000-8000-00000000b401';
  v_campaign constant uuid := '00000000-0000-4000-8000-00000000b501';
  v_qr_a constant uuid := '00000000-0000-4000-8000-00000000b601';
  v_qr_b constant uuid := '00000000-0000-4000-8000-00000000b602';
  v_request constant uuid := '00000000-0000-4000-8000-00000000b701';
  v_result_a jsonb;
  v_result_b jsonb;
  v_claim_id uuid;
  v_ledger_count integer;
  v_balance_a bigint;
  v_balance_b bigint;
BEGIN
  INSERT INTO auth.users(id) VALUES(v_user_a),(v_user_b);
  INSERT INTO public.tenants(id,name,slug,status,default_locale)
  VALUES(v_tenant,'Replay Owner Test','replay-owner-test','active','en-IN');
  INSERT INTO public.partners(id,tenant_id,user_id,role,display_name,verification_status)
  VALUES
    (v_partner_a,v_tenant,v_user_a,'farmer','Owner A','verified'),
    (v_partner_b,v_tenant,v_user_b,'farmer','Owner B','verified');
  INSERT INTO public.products(id,tenant_id,sku,name,active,metadata)
  VALUES(v_product,v_tenant,'REPLAY-OWNER-TEST','Replay Owner Test Product',true,'{}'::jsonb);
  INSERT INTO public.campaigns(id,tenant_id,name,status,starts_at,ends_at,budget_minor_units,currency,rules_version,rules)
  VALUES(v_campaign,v_tenant,'Replay Owner Test Campaign','active',now()-interval '1 hour',now()+interval '1 day',100000,'INR',1,'{}'::jsonb);
  INSERT INTO public.qr_codes(id,tenant_id,product_id,campaign_id,token_hash,status,entitlement_role,points_value,activated_at)
  VALUES
    (v_qr_a,v_tenant,v_product,v_campaign,encode(extensions.digest(convert_to('replay-owner-token-a','UTF8'),'sha256'),'hex'),'active','farmer',10,now()),
    (v_qr_b,v_tenant,v_product,v_campaign,encode(extensions.digest(convert_to('replay-owner-token-b','UTF8'),'sha256'),'hex'),'active','farmer',10,now());

  v_result_a := private.claim_qr(v_user_a,'replay-owner-token-a',v_request,'test','device-a');
  IF v_result_a->>'outcome'<>'accepted' OR v_result_a->>'points_awarded'<>'10' THEN
    RAISE EXCEPTION 'first owner claim failed: %',v_result_a;
  END IF;
  v_claim_id := (v_result_a->>'claim_id')::uuid;

  -- Another user reuses the same request UUID with a different QR in the same tenant.
  -- Must not receive the first owner's claim ID, points or replay result.
  v_result_b := private.claim_qr(v_user_b,'replay-owner-token-b',v_request,'test','device-b');
  IF v_result_b->>'claim_id' IS NOT NULL
     OR v_result_b->>'points_awarded'<>'0'
     OR v_result_b->>'replayed'='true'
     OR v_result_b->>'outcome' <> 'request_id_conflict' THEN
    RAISE EXCEPTION 'claim replay data leaked across actors: %',v_result_b;
  END IF;

  SELECT count(*) INTO v_ledger_count FROM public.points_ledger WHERE tenant_id=v_tenant;
  SELECT COALESCE(sum(points_delta),0) INTO v_balance_a FROM public.points_ledger WHERE tenant_id=v_tenant AND partner_id=v_partner_a;
  SELECT COALESCE(sum(points_delta),0) INTO v_balance_b FROM public.points_ledger WHERE tenant_id=v_tenant AND partner_id=v_partner_b;
  IF v_ledger_count<>1 OR v_balance_a<>10 OR v_balance_b<>0 THEN
    RAISE EXCEPTION 'actor replay isolation accounting mismatch: ledger=%, balanceA=%, balanceB=%',v_ledger_count,v_balance_a,v_balance_b;
  END IF;
END;
$claim_replay_owner_test$;

ROLLBACK;
