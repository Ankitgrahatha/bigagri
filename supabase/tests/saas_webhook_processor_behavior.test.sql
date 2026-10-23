-- Transactional integration regression for the SaaS billing processor.
-- Runs only in the disposable PostgreSQL CI database and rolls back all fixtures.
BEGIN;

DO $saas_webhook_behavior$
DECLARE
  v_tenant_id uuid := 'c5f1e3b4-2c72-4e1f-9c24-1a8d5d710001';
  v_user_id uuid := 'c5f1e3b4-2c72-4e1f-9c24-1a8d5d710002';
  v_plan_id uuid := 'c5f1e3b4-2c72-4e1f-9c24-1a8d5d710003';
  v_plan_version_id uuid := 'c5f1e3b4-2c72-4e1f-9c24-1a8d5d710004';
  v_subscription_id uuid := 'c5f1e3b4-2c72-4e1f-9c24-1a8d5d710005';
  v_event_id uuid;
  v_event_epoch bigint := extract(epoch FROM clock_timestamp())::bigint;
  v_period_start bigint := extract(epoch FROM (clock_timestamp() - interval '1 minute'))::bigint;
  v_period_end bigint := extract(epoch FROM (clock_timestamp() + interval '1 day'))::bigint;
  v_result jsonb;
  v_health jsonb;
  v_status text;
  v_active boolean;
BEGIN
  INSERT INTO auth.users (id, email)
  VALUES (v_user_id, 'billing-regression@example.invalid');

  INSERT INTO public.tenants (id, name, slug, status)
  VALUES (v_tenant_id, 'Billing regression tenant', 'billing-regression-tenant', 'active');

  INSERT INTO public.tenant_memberships (tenant_id, user_id, role, status)
  VALUES (v_tenant_id, v_user_id, 'super_admin', 'active');

  INSERT INTO private.saas_plans (id, plan_key, display_name, status)
  VALUES (v_plan_id, 'billing_test', 'Billing Test', 'published');

  INSERT INTO private.saas_plan_versions (
    id, plan_id, version_no, currency, monthly_amount_minor, yearly_amount_minor,
    monthly_provider_plan_id, yearly_provider_plan_id, published_at
  )
  VALUES (
    v_plan_version_id, v_plan_id, 1, 'INR', 10000, 100000,
    'plan_monthly_test', 'plan_yearly_test', now()
  );

  INSERT INTO private.saas_tenant_subscriptions (
    id, tenant_id, plan_version_id, billing_interval, provider_subscription_id, status
  )
  VALUES (
    v_subscription_id, v_tenant_id, v_plan_version_id, 'monthly', 'sub_billing_regression', 'incomplete'
  );

  INSERT INTO private.saas_payment_webhook_events (
    provider_event_id, event_type, payload, signature_verified_at
  )
  VALUES (
    'evt_billing_charge_ok',
    'subscription.charged',
    jsonb_build_object(
      'event', 'subscription.charged',
      'created_at', v_event_epoch,
      'payload', jsonb_build_object(
        'subscription', jsonb_build_object('entity', jsonb_build_object(
          'id', 'sub_billing_regression',
          'plan_id', 'plan_monthly_test',
          'current_start', v_period_start,
          'current_end', v_period_end
        )),
        'payment', jsonb_build_object('entity', jsonb_build_object(
          'id', 'pay_billing_charge_ok',
          'subscription_id', 'sub_billing_regression',
          'status', 'captured',
          'amount', 10000,
          'currency', 'INR'
        ))
      )
    ),
    now()
  )
  RETURNING id INTO v_event_id;

  v_result := public.process_saas_payment_webhook_event_internal(v_event_id);
  IF v_result->>'ok' <> 'true' OR v_result->>'result' <> 'applied' THEN
    RAISE EXCEPTION 'valid captured charge was not applied: %', v_result;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM private.saas_tenant_subscriptions
    WHERE id = v_subscription_id AND status = 'active'
      AND current_period_end = to_timestamp(v_period_end::double precision)
  ) THEN
    RAISE EXCEPTION 'valid charge did not activate the matching subscription period';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM private.saas_payment_attempts
    WHERE provider_payment_id = 'pay_billing_charge_ok'
      AND tenant_id = v_tenant_id AND subscription_id = v_subscription_id
      AND amount_minor = 10000 AND currency = 'INR' AND status = 'captured'
  ) THEN
    RAISE EXCEPTION 'captured payment attempt was not recorded';
  END IF;

  v_result := public.process_saas_payment_webhook_event_internal(v_event_id);
  IF v_result->>'ok' <> 'true' OR v_result->>'duplicate' <> 'true' THEN
    RAISE EXCEPTION 'duplicate processor call was not idempotent: %', v_result;
  END IF;

  v_result := public.resolve_saas_tenant_entitlements_internal(v_user_id, v_tenant_id);
  IF v_result->>'active' <> 'true' OR v_result->>'plan_key' <> 'billing_test' THEN
    RAISE EXCEPTION 'valid subscription did not resolve active entitlements: %', v_result;
  END IF;

  INSERT INTO private.saas_payment_webhook_events (
    provider_event_id, event_type, payload, signature_verified_at
  )
  VALUES (
    'evt_billing_charge_wrong_amount',
    'subscription.charged',
    jsonb_build_object(
      'event', 'subscription.charged',
      'created_at', v_event_epoch + 10,
      'payload', jsonb_build_object(
        'subscription', jsonb_build_object('entity', jsonb_build_object(
          'id', 'sub_billing_regression',
          'plan_id', 'plan_monthly_test',
          'current_start', v_period_start,
          'current_end', v_period_end
        )),
        'payment', jsonb_build_object('entity', jsonb_build_object(
          'id', 'pay_billing_wrong_amount',
          'subscription_id', 'sub_billing_regression',
          'status', 'captured',
          'amount', 9999,
          'currency', 'INR'
        ))
      )
    ),
    now()
  )
  RETURNING id INTO v_event_id;

  v_result := public.process_saas_payment_webhook_event_internal(v_event_id);
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'payment_amount_currency_mismatch' THEN
    RAISE EXCEPTION 'amount mismatch was not rejected: %', v_result;
  END IF;
  IF EXISTS (SELECT 1 FROM private.saas_payment_attempts WHERE provider_payment_id = 'pay_billing_wrong_amount') THEN
    RAISE EXCEPTION 'mismatched amount created a payment attempt';
  END IF;

  v_health := public.get_saas_payment_webhook_health_internal();
  IF v_health->>'ok' <> 'true'
     OR (v_health->>'retryable_failed')::integer < 1
     OR (v_health->>'oldest_unprocessed_age_seconds')::bigint < 0 THEN
    RAISE EXCEPTION 'webhook health metrics did not report retryable failed event and age: %', v_health;
  END IF;

  INSERT INTO private.saas_payment_webhook_events (
    provider_event_id, event_type, payload, signature_verified_at
  )
  VALUES (
    'evt_billing_stale_charge',
    'subscription.charged',
    jsonb_build_object(
      'event', 'subscription.charged',
      'created_at', v_event_epoch - 20,
      'payload', jsonb_build_object(
        'subscription', jsonb_build_object('entity', jsonb_build_object(
          'id', 'sub_billing_regression',
          'plan_id', 'plan_monthly_test',
          'current_start', v_period_start,
          'current_end', v_period_end
        )),
        'payment', jsonb_build_object('entity', jsonb_build_object(
          'id', 'pay_billing_stale_charge',
          'subscription_id', 'sub_billing_regression',
          'status', 'captured',
          'amount', 10000,
          'currency', 'INR'
        ))
      )
    ),
    now()
  )
  RETURNING id INTO v_event_id;

  v_result := public.process_saas_payment_webhook_event_internal(v_event_id);
  IF v_result->>'ok' <> 'true' OR v_result->>'result' <> 'stale' THEN
    RAISE EXCEPTION 'out-of-order charge was not marked stale: %', v_result;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM private.saas_payment_attempts
    WHERE provider_payment_id = 'pay_billing_stale_charge' AND status = 'captured'
  ) THEN
    RAISE EXCEPTION 'stale captured charge was not retained in the payment ledger';
  END IF;

  INSERT INTO private.saas_payment_webhook_events (
    provider_event_id, event_type, payload, signature_verified_at
  )
  VALUES (
    'evt_billing_cancel',
    'subscription.cancelled',
    jsonb_build_object(
      'event', 'subscription.cancelled',
      'created_at', v_event_epoch + 20,
      'payload', jsonb_build_object(
        'subscription', jsonb_build_object('entity', jsonb_build_object(
          'id', 'sub_billing_regression'
        ))
      )
    ),
    now()
  )
  RETURNING id INTO v_event_id;

  v_result := public.process_saas_payment_webhook_event_internal(v_event_id);
  IF v_result->>'ok' <> 'true' OR v_result->>'result' <> 'applied' THEN
    RAISE EXCEPTION 'cancellation event was not applied: %', v_result;
  END IF;

  INSERT INTO private.saas_payment_webhook_events (
    provider_event_id, event_type, payload, signature_verified_at
  )
  VALUES (
    'evt_billing_late_charge_after_cancel',
    'subscription.charged',
    jsonb_build_object(
      'event', 'subscription.charged',
      'created_at', v_event_epoch + 10,
      'payload', jsonb_build_object(
        'subscription', jsonb_build_object('entity', jsonb_build_object(
          'id', 'sub_billing_regression',
          'plan_id', 'plan_monthly_test',
          'current_start', v_period_start,
          'current_end', v_period_end
        )),
        'payment', jsonb_build_object('entity', jsonb_build_object(
          'id', 'pay_billing_late_charge',
          'subscription_id', 'sub_billing_regression',
          'status', 'captured',
          'amount', 10000,
          'currency', 'INR'
        ))
      )
    ),
    now()
  )
  RETURNING id INTO v_event_id;

  v_result := public.process_saas_payment_webhook_event_internal(v_event_id);
  IF v_result->>'ok' <> 'true' OR v_result->>'result' <> 'stale' THEN
    RAISE EXCEPTION 'late charge after cancellation was not made stale: %', v_result;
  END IF;

  SELECT status INTO v_status
  FROM private.saas_tenant_subscriptions
  WHERE id = v_subscription_id;
  IF v_status <> 'canceled' THEN
    RAISE EXCEPTION 'late charge reopened a canceled subscription';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM private.saas_payment_attempts
    WHERE provider_payment_id = 'pay_billing_late_charge' AND status = 'captured'
  ) THEN
    RAISE EXCEPTION 'late captured payment was dropped from payment history';
  END IF;

  v_result := public.resolve_saas_tenant_entitlements_internal(v_user_id, v_tenant_id);
  IF v_result->>'active' <> 'false' OR v_result->>'status' <> 'canceled' THEN
    RAISE EXCEPTION 'canceled subscription still resolves active entitlements: %', v_result;
  END IF;

  RAISE NOTICE 'PASS: SaaS webhook processing is idempotent, amount-bound, stale-safe, and preserves captured payment records';
END
$saas_webhook_behavior$;

ROLLBACK;
