-- Checkout reservation and idempotency regression. Disposable CI database only.
BEGIN;

DO $saas_checkout_behavior$
DECLARE
  v_tenant_id uuid := 'd6a2f7d1-4e22-4b2a-8f1a-5a7100010001';
  v_user_id uuid := 'd6a2f7d1-4e22-4b2a-8f1a-5a7100010002';
  v_plan_id uuid := 'd6a2f7d1-4e22-4b2a-8f1a-5a7100010003';
  v_version_id uuid := 'd6a2f7d1-4e22-4b2a-8f1a-5a7100010004';
  v_result jsonb;
  v_subscription_id uuid;
  v_count integer;
  v_event_id uuid;
  v_event_epoch bigint := extract(epoch FROM clock_timestamp())::bigint;
  v_period_start bigint := extract(epoch FROM (clock_timestamp() - interval '1 minute'))::bigint;
  v_period_end bigint := extract(epoch FROM (clock_timestamp() + interval '1 day'))::bigint;
BEGIN
  INSERT INTO auth.users (id, email)
  VALUES (v_user_id, 'checkout-regression@example.invalid');

  INSERT INTO public.tenants (id, name, slug, status)
  VALUES (v_tenant_id, 'Checkout regression tenant', 'checkout-regression-tenant', 'active');

  INSERT INTO public.tenant_memberships (tenant_id, user_id, role, status)
  VALUES (v_tenant_id, v_user_id, 'super_admin', 'active');

  INSERT INTO private.saas_plans (id, plan_key, display_name, status)
  VALUES (v_plan_id, 'checkout_test', 'Checkout Test', 'published');

  INSERT INTO private.saas_plan_versions (
    id, plan_id, version_no, currency, monthly_amount_minor, yearly_amount_minor,
    monthly_provider_plan_id, yearly_provider_plan_id, published_at
  ) VALUES (
    v_version_id, v_plan_id, 1, 'INR', 10000, 100000,
    'plan_checkout_monthly', 'plan_checkout_yearly', now()
  );

  v_result := public.reserve_saas_checkout_internal(
    v_user_id, v_tenant_id, v_version_id, 'monthly', 'checkout-idem-key-0001'
  );
  IF v_result->>'ok' <> 'true' OR v_result->>'created' <> 'true' THEN
    RAISE EXCEPTION 'initial checkout reservation failed: %', v_result;
  END IF;
  v_subscription_id := (v_result->>'subscription_id')::uuid;

  IF v_result->>'provider_plan_id' <> 'plan_checkout_monthly'
     OR (v_result->>'amount_minor')::bigint <> 10000
     OR v_result->>'currency' <> 'INR' THEN
    RAISE EXCEPTION 'reservation did not return expected published plan values: %', v_result;
  END IF;

  v_result := public.reserve_saas_checkout_internal(
    v_user_id, v_tenant_id, v_version_id, 'monthly', 'checkout-idem-key-0001'
  );
  IF v_result->>'ok' <> 'false'
     OR v_result->>'error' <> 'checkout_reconciliation_required' THEN
    RAISE EXCEPTION 'same-key pending reservation must not create a second provider subscription: %', v_result;
  END IF;

  UPDATE private.saas_tenant_subscriptions
  SET created_at = now() - interval '11 minutes'
  WHERE id = v_subscription_id;

  v_result := public.list_saas_checkout_reconciliation_internal(v_user_id, v_tenant_id, 10);
  IF v_result->>'ok' <> 'true'
     OR jsonb_array_length(v_result->'checkouts') <> 1
     OR v_result->'checkouts'->0->>'needs_provider_reconciliation' <> 'true'
     OR v_result->'checkouts'->0->>'provider_subscription_id' IS NOT NULL THEN
    RAISE EXCEPTION 'ambiguous checkout was not surfaced in reconciliation queue: %', v_result;
  END IF;

  v_result := public.list_saas_checkout_reconciliation_internal(
    'd6a2f7d1-4e22-4b2a-8f1a-5a7100010099'::uuid, v_tenant_id, 10
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'forbidden' THEN
    RAISE EXCEPTION 'non-admin was allowed to view reconciliation queue: %', v_result;
  END IF;

  v_result := public.get_saas_checkout_recovery_target_internal(v_user_id, v_tenant_id, v_subscription_id);
  IF v_result->>'ok' <> 'true'
     OR v_result->>'expected_provider_plan_id' <> 'plan_checkout_monthly'
     OR v_result->>'idempotency_key' <> 'checkout-idem-key-0001' THEN
    RAISE EXCEPTION 'authorized checkout recovery target was not returned: %', v_result;
  END IF;

  v_result := public.get_saas_checkout_recovery_target_internal(
    'd6a2f7d1-4e22-4b2a-8f1a-5a7100010099'::uuid, v_tenant_id, v_subscription_id
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'forbidden' THEN
    RAISE EXCEPTION 'non-admin was allowed to inspect checkout recovery target: %', v_result;
  END IF;

  v_result := public.finalize_saas_checkout_internal(
    v_subscription_id, 'sub_checkout_regression', 'https://rzp.io/i/checkout-regression'
  );
  IF v_result->>'ok' <> 'true' THEN
    RAISE EXCEPTION 'checkout finalization failed: %', v_result;
  END IF;

  v_result := public.list_saas_checkout_reconciliation_internal(v_user_id, v_tenant_id, 10);
  IF v_result->>'ok' <> 'true'
     OR v_result->'checkouts'->0->>'needs_provider_reconciliation' <> 'false'
     OR v_result->'checkouts'->0->>'provider_subscription_id' <> 'sub_checkout_regression'
     OR v_result->'checkouts'->0->>'checkout_url' <> 'https://rzp.io/i/checkout-regression' THEN
    RAISE EXCEPTION 'finalized checkout was not reported with provider correlation: %', v_result;
  END IF;

  INSERT INTO private.saas_payment_webhook_events (
    provider_event_id, event_type, payload, signature_verified_at
  ) VALUES (
    'evt_checkout_charge',
    'subscription.charged',
    jsonb_build_object(
      'event', 'subscription.charged',
      'created_at', v_event_epoch,
      'payload', jsonb_build_object(
        'subscription', jsonb_build_object('entity', jsonb_build_object(
          'id', 'sub_checkout_regression',
          'plan_id', 'plan_checkout_monthly',
          'current_start', v_period_start,
          'current_end', v_period_end
        )),
        'payment', jsonb_build_object('entity', jsonb_build_object(
          'id', 'pay_checkout_regression',
          'subscription_id', 'sub_checkout_regression',
          'status', 'captured',
          'amount', 10000,
          'currency', 'INR'
        ))
      )
    ),
    now()
  ) RETURNING id INTO v_event_id;

  v_result := public.process_saas_payment_webhook_event_internal(v_event_id);
  IF v_result->>'ok' <> 'true' OR v_result->>'result' <> 'applied' THEN
    RAISE EXCEPTION 'checkout payment webhook did not activate subscription: %', v_result;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM private.saas_payment_attempts
    WHERE tenant_id = v_tenant_id AND subscription_id = v_subscription_id
      AND idempotency_key = 'checkout-idem-key-0001'
      AND provider_payment_id = 'pay_checkout_regression'
      AND status = 'captured' AND captured_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'captured webhook was not reconciled into the reserved checkout attempt';
  END IF;

  v_result := public.reserve_saas_checkout_internal(
    v_user_id, v_tenant_id, v_version_id, 'monthly', 'checkout-idem-key-0001'
  );
  IF v_result->>'ok' <> 'true'
     OR v_result->>'reused' <> 'true'
     OR v_result->>'checkout_url' <> 'https://rzp.io/i/checkout-regression' THEN
    RAISE EXCEPTION 'completed reservation retry was not idempotent: %', v_result;
  END IF;

  SELECT count(*) INTO v_count
  FROM private.saas_tenant_subscriptions
  WHERE tenant_id = v_tenant_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'idempotent retry created duplicate local subscriptions: %', v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM private.saas_payment_attempts
  WHERE tenant_id = v_tenant_id AND idempotency_key = 'checkout-idem-key-0001';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'idempotent retry created duplicate payment attempts: %', v_count;
  END IF;

  v_result := public.reserve_saas_checkout_internal(
    'd6a2f7d1-4e22-4b2a-8f1a-5a7100010099'::uuid,
    v_tenant_id, v_version_id, 'monthly', 'checkout-idem-key-0002'
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'forbidden' THEN
    RAISE EXCEPTION 'non-member was allowed to reserve checkout: %', v_result;
  END IF;

  v_result := public.reserve_saas_checkout_internal(
    v_user_id, v_tenant_id, v_version_id, NULL, 'checkout-idem-key-0003'
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'invalid_request' THEN
    RAISE EXCEPTION 'null billing interval was not rejected: %', v_result;
  END IF;

  RAISE NOTICE 'PASS: checkout reservation is membership-checked, idempotent, and blocks duplicate provider creation';
END
$saas_checkout_behavior$;

ROLLBACK;
