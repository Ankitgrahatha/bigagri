-- Runs only against an isolated disposable PostgreSQL database.
-- Every test row is inside a transaction and rolled back; never run against production.
BEGIN;

DO $claim_replay_test$
DECLARE
  v_tenant_id constant uuid := '00000000-0000-4000-8000-000000000101';
  v_user_a constant uuid := '00000000-0000-4000-8000-000000000201';
  v_user_b constant uuid := '00000000-0000-4000-8000-000000000202';
  v_partner_a constant uuid := '00000000-0000-4000-8000-000000000301';
  v_partner_b constant uuid := '00000000-0000-4000-8000-000000000302';
  v_product constant uuid := '00000000-0000-4000-8000-000000000401';
  v_campaign constant uuid := '00000000-0000-4000-8000-000000000501';
  v_qr constant uuid := '00000000-0000-4000-8000-000000000601';
  v_request constant uuid := '00000000-0000-4000-8000-000000000701';
  v_token constant text := 'growta-replay-test-token-very-long';
  v_first jsonb;
  v_retry jsonb;
  v_other_actor jsonb;
  v_ledger_count integer;
  v_ledger_points bigint;
BEGIN
  INSERT INTO auth.users(id) VALUES (v_user_a), (v_user_b);

  INSERT INTO public.tenants(id, name, slug, status, default_locale)
  VALUES (v_tenant_id, 'Replay Test Tenant', 'replay-test-tenant', 'active', 'en-IN');

  INSERT INTO public.partners(id, tenant_id, user_id, role, display_name, verification_status)
  VALUES
    (v_partner_a, v_tenant_id, v_user_a, 'farmer', 'Replay Actor A', 'verified'),
    (v_partner_b, v_tenant_id, v_user_b, 'farmer', 'Replay Actor B', 'verified');

  INSERT INTO public.products(id, tenant_id, sku, name, active, metadata)
  VALUES (v_product, v_tenant_id, 'TEST-REPLAY-001', 'Replay Test Product', true, '{}'::jsonb);

  INSERT INTO public.campaigns(
    id, tenant_id, name, status, starts_at, ends_at, budget_minor_units, currency, rules_version, rules
  )
  VALUES (
    v_campaign, v_tenant_id, 'Replay Test Campaign', 'active',
    now() - interval '1 hour', now() + interval '1 day', 100000, 'INR', 1, '{}'::jsonb
  );

  INSERT INTO public.qr_codes(
    id, tenant_id, product_id, campaign_id, token_hash, status, entitlement_role, points_value, activated_at
  )
  VALUES (
    v_qr, v_tenant_id, v_product, v_campaign,
    encode(digest(convert_to(v_token, 'UTF8'), 'sha256'), 'hex'),
    'active', 'farmer', 10, now()
  );

  v_first := private.claim_qr(v_user_a, v_token, v_request, 'db-test', 'device-hash-a');
  IF v_first->>'ok' <> 'true'
     OR v_first->>'outcome' <> 'accepted'
     OR v_first->>'points_awarded' <> '10'
     OR v_first->>'replayed' <> 'false' THEN
    RAISE EXCEPTION 'first claim did not succeed as expected: %', v_first;
  END IF;

  v_retry := private.claim_qr(v_user_a, v_token, v_request, 'db-test', 'device-hash-a');
  IF v_retry->>'ok' <> 'true'
     OR v_retry->>'outcome' <> 'accepted'
     OR v_retry->>'points_awarded' <> '10'
     OR v_retry->>'replayed' <> 'true'
     OR v_retry->>'claim_id' IS DISTINCT FROM v_first->>'claim_id' THEN
    RAISE EXCEPTION 'same-actor retry was not idempotent: first=%, retry=%', v_first, v_retry;
  END IF;

  v_other_actor := private.claim_qr(v_user_b, v_token, v_request, 'db-test', 'device-hash-b');
  IF v_other_actor->>'outcome' <> 'already_claimed'
     OR v_other_actor->>'points_awarded' <> '0'
     OR COALESCE(v_other_actor->>'replayed', 'false') <> 'false'
     OR v_other_actor ? 'claim_id' THEN
    RAISE EXCEPTION 'other actor received another actor''s replay result: %', v_other_actor;
  END IF;

  SELECT count(*), COALESCE(sum(points_delta), 0)
    INTO v_ledger_count, v_ledger_points
    FROM public.points_ledger
   WHERE tenant_id = v_tenant_id;

  IF v_ledger_count <> 1 OR v_ledger_points <> 10 THEN
    RAISE EXCEPTION 'claim retry credited points more than once: count=%, points=%', v_ledger_count, v_ledger_points;
  END IF;

  IF has_function_privilege('anon', 'private.claim_qr(uuid,text,uuid,text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon unexpectedly has EXECUTE on private.claim_qr';
  END IF;
  IF has_function_privilege('authenticated', 'private.claim_qr(uuid,text,uuid,text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated unexpectedly has EXECUTE on private.claim_qr';
  END IF;
  IF NOT has_function_privilege('service_role', 'private.claim_qr(uuid,text,uuid,text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'service_role is missing EXECUTE on private.claim_qr';
  END IF;

  RAISE NOTICE 'PASS: first claim, same-actor replay, cross-actor replay isolation, one ledger credit, and RPC grants';
END;
$claim_replay_test$;

ROLLBACK;
