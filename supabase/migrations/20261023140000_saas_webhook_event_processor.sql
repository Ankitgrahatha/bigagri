-- Apply supported webhook effects and mark the inbox row in one transaction.
-- This RPC is internal-only. A scheduled/server-side worker must invoke it with
-- service_role credentials; never call it from an untrusted client.
CREATE OR REPLACE FUNCTION private.process_saas_payment_webhook_event(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_event private.saas_payment_webhook_events%rowtype;
  v_event_time timestamptz;
  v_event_type text;
  v_event_payload jsonb;
  v_subscription_entity jsonb;
  v_payment_entity jsonb;
  v_provider_subscription_id text;
  v_provider_payment_id text;
  v_provider_plan_id text;
  v_payment_status text;
  v_payment_currency text;
  v_payment_amount bigint;
  v_expected_amount bigint;
  v_expected_plan_id text;
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_subscription record;
  v_payment_attempt record;
  v_failure_code text;
BEGIN
  IF p_event_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_event_id');
  END IF;

  SELECT * INTO v_event
  FROM private.saas_payment_webhook_events
  WHERE id = p_event_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'event_not_found');
  END IF;

  IF v_event.status = 'processed' THEN
    RETURN jsonb_build_object(
      'ok', true, 'duplicate', true, 'result', v_event.processing_result
    );
  END IF;

  IF v_event.status = 'processing'
     AND v_event.processing_started_at > now() - interval '10 minutes' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_processing');
  END IF;

  IF v_event.status NOT IN ('received', 'failed', 'processing') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_event_state');
  END IF;

  UPDATE private.saas_payment_webhook_events
  SET status = 'processing',
      attempts = attempts + 1,
      processing_started_at = now(),
      last_error_code = NULL,
      processing_result = NULL,
      processed_at = NULL
  WHERE id = p_event_id;

  v_event_type := v_event.event_type;
  v_event_payload := v_event.payload;

  -- Unknown event types are durably acknowledged but never mutate billing state.
  IF v_event_type NOT IN (
    'subscription.charged',
    'subscription.cancelled',
    'subscription.completed',
    'subscription.halted',
    'subscription.paused',
    'payment.failed'
  ) THEN
    UPDATE private.saas_payment_webhook_events
    SET status = 'processed', processing_result = 'ignored',
        processed_at = now(), processing_started_at = NULL, last_error_code = NULL
    WHERE id = p_event_id;
    RETURN jsonb_build_object('ok', true, 'result', 'ignored');
  END IF;

  IF coalesce(v_event_payload->>'created_at', '') !~ '^[0-9]{9,10} THEN
    v_failure_code := 'invalid_event_timestamp';
    UPDATE private.saas_payment_webhook_events
    SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
        processing_result = NULL, processed_at = NULL
    WHERE id = p_event_id;
    RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
  END IF;
  v_event_time := to_timestamp((v_event_payload->>'created_at')::double precision);

  IF v_event_type IN (
    'subscription.charged',
    'subscription.cancelled',
    'subscription.completed',
    'subscription.halted',
    'subscription.paused'
  ) THEN
    v_subscription_entity := v_event_payload #> '{payload,subscription,entity}';
    v_provider_subscription_id := nullif(btrim(v_subscription_entity->>'id'), '');
  ELSE
    v_payment_entity := v_event_payload #> '{payload,payment,entity}';
    v_provider_subscription_id := nullif(btrim(v_payment_entity->>'subscription_id'), '');
  END IF;

  IF v_provider_subscription_id IS NULL
     OR length(v_provider_subscription_id) > 255 THEN
    v_failure_code := 'missing_subscription_reference';
    UPDATE private.saas_payment_webhook_events
    SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
        processing_result = NULL, processed_at = NULL
    WHERE id = p_event_id;
    RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
  END IF;

  SELECT
    s.id, s.tenant_id, s.plan_version_id, s.billing_interval, s.status,
    s.last_provider_event_created_at, s.last_provider_event_id,
    pv.monthly_amount_minor, pv.yearly_amount_minor, pv.currency,
    pv.monthly_provider_plan_id, pv.yearly_provider_plan_id
  INTO v_subscription
  FROM private.saas_tenant_subscriptions s
  JOIN private.saas_plan_versions pv ON pv.id = s.plan_version_id
  WHERE s.provider = 'razorpay'
    AND s.provider_subscription_id = v_provider_subscription_id
  FOR UPDATE OF s;

  IF NOT FOUND THEN
    v_failure_code := 'subscription_not_found';
    UPDATE private.saas_payment_webhook_events
    SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
        processing_result = NULL, processed_at = NULL
    WHERE id = p_event_id;
    RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
  END IF;

  IF v_subscription.last_provider_event_created_at IS NOT NULL
     AND (
       v_event_time < v_subscription.last_provider_event_created_at
       OR (
         v_event_time = v_subscription.last_provider_event_created_at
         AND v_event_type = 'subscription.charged'
       )
     ) THEN
    UPDATE private.saas_payment_webhook_events
    SET status = 'processed', processing_result = 'stale',
        processed_at = now(), processing_started_at = NULL, last_error_code = NULL
    WHERE id = p_event_id;
    RETURN jsonb_build_object('ok', true, 'result', 'stale');
  END IF;

  IF v_subscription.status IN ('canceled', 'expired')
     AND v_event_type NOT IN ('subscription.cancelled', 'subscription.completed') THEN
    UPDATE private.saas_payment_webhook_events
    SET status = 'processed', processing_result = 'stale',
        processed_at = now(), processing_started_at = NULL, last_error_code = NULL
    WHERE id = p_event_id;
    RETURN jsonb_build_object('ok', true, 'result', 'stale');
  END IF;

  IF v_event_type = 'subscription.charged' THEN
    IF v_subscription.status IN ('canceled', 'expired') THEN
      UPDATE private.saas_payment_webhook_events
      SET status = 'processed', processing_result = 'stale',
          processed_at = now(), processing_started_at = NULL, last_error_code = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', true, 'result', 'stale');
    END IF;

    v_payment_entity := v_event_payload #> '{payload,payment,entity}';
    v_provider_payment_id := nullif(btrim(v_payment_entity->>'id'), '');
    v_payment_status := lower(coalesce(v_payment_entity->>'status', ''));
    v_payment_currency := upper(coalesce(v_payment_entity->>'currency', ''));
    v_provider_plan_id := nullif(btrim(v_subscription_entity->>'plan_id'), '');
    v_expected_plan_id := CASE
      WHEN v_subscription.billing_interval = 'monthly' THEN v_subscription.monthly_provider_plan_id
      ELSE v_subscription.yearly_provider_plan_id
    END;
    v_expected_amount := CASE
      WHEN v_subscription.billing_interval = 'monthly' THEN v_subscription.monthly_amount_minor
      ELSE v_subscription.yearly_amount_minor
    END;

    IF v_provider_payment_id IS NULL OR length(v_provider_payment_id) > 255
       OR v_payment_status <> 'captured'
       OR coalesce(v_payment_entity->>'subscription_id', '') <> v_provider_subscription_id
       OR v_provider_plan_id IS NULL OR v_provider_plan_id <> v_expected_plan_id
       OR v_expected_amount <= 0
       OR coalesce(v_payment_entity->>'amount', '') !~ '^[0-9]{1,18}
       OR v_payment_currency !~ '^[A-Z]{3}$' THEN
      v_failure_code := 'payment_or_plan_validation_failed';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;

    v_payment_amount := (v_payment_entity->>'amount')::bigint;
    IF v_payment_amount <> v_expected_amount OR v_payment_currency <> v_subscription.currency THEN
      v_failure_code := 'payment_amount_currency_mismatch';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;

    IF coalesce(v_subscription_entity->>'current_start', '') !~ '^[0-9]{1,12}$'
       OR coalesce(v_subscription_entity->>'current_end', '') !~ '^[0-9]{1,12}$' THEN
      v_failure_code := 'invalid_billing_period';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;
    v_period_start := to_timestamp((v_subscription_entity->>'current_start')::double precision);
    v_period_end := to_timestamp((v_subscription_entity->>'current_end')::double precision);
    IF v_period_end <= v_period_start THEN
      v_failure_code := 'invalid_billing_period';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;

    INSERT INTO private.saas_payment_attempts (
      tenant_id, subscription_id, provider, idempotency_key, amount_minor, currency,
      provider_payment_id, status, captured_at
    )
    VALUES (
      v_subscription.tenant_id, v_subscription.id, 'razorpay',
      'razorpay-payment:' || v_provider_payment_id, v_payment_amount, v_payment_currency,
      v_provider_payment_id, 'captured', v_event_time
    )
    ON CONFLICT DO NOTHING;

    SELECT * INTO v_payment_attempt
    FROM private.saas_payment_attempts
    WHERE provider = 'razorpay' AND provider_payment_id = v_provider_payment_id;

    IF NOT FOUND THEN
      v_failure_code := 'payment_id_conflict';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;
    IF v_payment_attempt.tenant_id <> v_subscription.tenant_id
       OR v_payment_attempt.subscription_id IS DISTINCT FROM v_subscription.id
       OR v_payment_attempt.amount_minor <> v_payment_amount
       OR v_payment_attempt.currency <> v_payment_currency
       OR v_payment_attempt.status <> 'captured' THEN
      v_failure_code := 'payment_id_conflict';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;

    UPDATE private.saas_tenant_subscriptions
    SET status = 'active',
        current_period_start = v_period_start,
        current_period_end = v_period_end,
        last_provider_event_created_at = v_event_time,
        last_provider_event_id = v_event.provider_event_id,
        updated_at = now()
    WHERE id = v_subscription.id;

  ELSIF v_event_type = 'payment.failed' THEN
    IF v_subscription.status IN ('canceled', 'expired') THEN
      UPDATE private.saas_payment_webhook_events
      SET status = 'processed', processing_result = 'stale',
          processed_at = now(), processing_started_at = NULL, last_error_code = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', true, 'result', 'stale');
    END IF;

    v_provider_payment_id := nullif(btrim(v_payment_entity->>'id'), '');
    v_payment_currency := upper(coalesce(v_payment_entity->>'currency', ''));
    IF v_provider_payment_id IS NULL OR length(v_provider_payment_id) > 255
       OR coalesce(v_payment_entity->>'amount', '') !~ '^[0-9]{1,18}$'
       OR v_payment_currency !~ '^[A-Z]{3}$' THEN
      v_failure_code := 'invalid_failed_payment';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;
    v_payment_amount := (v_payment_entity->>'amount')::bigint;
    v_expected_amount := CASE
      WHEN v_subscription.billing_interval = 'monthly' THEN v_subscription.monthly_amount_minor
      ELSE v_subscription.yearly_amount_minor
    END;
    IF v_payment_amount <= 0 THEN
      v_failure_code := 'invalid_failed_payment';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;
    IF v_payment_amount <> v_expected_amount OR v_payment_currency <> v_subscription.currency THEN
      v_failure_code := 'payment_amount_currency_mismatch';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;

    INSERT INTO private.saas_payment_attempts (
      tenant_id, subscription_id, provider, idempotency_key, amount_minor, currency,
      provider_payment_id, status, failure_code
    )
    VALUES (
      v_subscription.tenant_id, v_subscription.id, 'razorpay',
      'razorpay-payment:' || v_provider_payment_id, v_payment_amount, v_payment_currency,
      v_provider_payment_id, 'failed', 'provider_payment_failed'
    )
    ON CONFLICT DO NOTHING;

    SELECT * INTO v_payment_attempt
    FROM private.saas_payment_attempts
    WHERE provider = 'razorpay' AND provider_payment_id = v_provider_payment_id;

    IF NOT FOUND THEN
      v_failure_code := 'payment_id_conflict';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;
    IF v_payment_attempt.tenant_id <> v_subscription.tenant_id
       OR v_payment_attempt.subscription_id IS DISTINCT FROM v_subscription.id
       OR v_payment_attempt.amount_minor <> v_payment_amount
       OR v_payment_attempt.currency <> v_payment_currency THEN
      v_failure_code := 'payment_id_conflict';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;

    IF v_payment_attempt.status = 'captured' THEN
      UPDATE private.saas_payment_webhook_events
      SET status = 'processed', processing_result = 'stale',
          processed_at = now(), processing_started_at = NULL, last_error_code = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', true, 'result', 'stale');
    END IF;

    UPDATE private.saas_tenant_subscriptions
    SET status = 'past_due',
        last_provider_event_created_at = v_event_time,
        last_provider_event_id = v_event.provider_event_id,
        updated_at = now()
    WHERE id = v_subscription.id;

  ELSE
    -- Cancellation/completion/pause/halt events are restrictive at equal timestamps:
    -- this prevents a same-second charge event from reactivating a canceled subscription.
    IF v_event_type = 'subscription.cancelled' THEN
      UPDATE private.saas_tenant_subscriptions
      SET status = 'canceled', canceled_at = v_event_time,
          cancel_at_period_end = false,
          last_provider_event_created_at = v_event_time,
          last_provider_event_id = v_event.provider_event_id,
          updated_at = now()
      WHERE id = v_subscription.id;
    ELSIF v_event_type = 'subscription.completed' THEN
      UPDATE private.saas_tenant_subscriptions
      SET status = 'expired', canceled_at = NULL,
          cancel_at_period_end = false,
          last_provider_event_created_at = v_event_time,
          last_provider_event_id = v_event.provider_event_id,
          updated_at = now()
      WHERE id = v_subscription.id;
    ELSIF v_event_type = 'subscription.halted' THEN
      UPDATE private.saas_tenant_subscriptions
      SET status = 'past_due', canceled_at = NULL,
          last_provider_event_created_at = v_event_time,
          last_provider_event_id = v_event.provider_event_id,
          updated_at = now()
      WHERE id = v_subscription.id;
    ELSIF v_event_type = 'subscription.paused' THEN
      UPDATE private.saas_tenant_subscriptions
      SET status = 'paused', canceled_at = NULL,
          last_provider_event_created_at = v_event_time,
          last_provider_event_id = v_event.provider_event_id,
          updated_at = now()
      WHERE id = v_subscription.id;
    END IF;
  END IF;

  UPDATE private.saas_payment_webhook_events
  SET status = 'processed', processing_result = 'applied',
      processed_at = now(), processing_started_at = NULL, last_error_code = NULL
  WHERE id = p_event_id;

  RETURN jsonb_build_object('ok', true, 'result', 'applied');
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.process_saas_payment_webhook_event(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.process_saas_payment_webhook_event(uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.process_saas_payment_webhook_event_internal(p_event_id uuid)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.process_saas_payment_webhook_event(p_event_id);
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.process_saas_payment_webhook_event_internal(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_saas_payment_webhook_event_internal(uuid)
  TO service_role;
 THEN
    v_failure_code := 'invalid_event_timestamp';
    UPDATE private.saas_payment_webhook_events
    SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
        processing_result = NULL, processed_at = NULL
    WHERE id = p_event_id;
    RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
  END IF;
  v_event_time := to_timestamp((v_event_payload->>'created_at')::double precision);

  IF v_event_type IN (
    'subscription.charged',
    'subscription.cancelled',
    'subscription.completed',
    'subscription.halted',
    'subscription.paused'
  ) THEN
    v_subscription_entity := v_event_payload #> '{payload,subscription,entity}';
    v_provider_subscription_id := nullif(btrim(v_subscription_entity->>'id'), '');
  ELSE
    v_payment_entity := v_event_payload #> '{payload,payment,entity}';
    v_provider_subscription_id := nullif(btrim(v_payment_entity->>'subscription_id'), '');
  END IF;

  IF v_provider_subscription_id IS NULL
     OR length(v_provider_subscription_id) > 255 THEN
    v_failure_code := 'missing_subscription_reference';
    UPDATE private.saas_payment_webhook_events
    SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
        processing_result = NULL, processed_at = NULL
    WHERE id = p_event_id;
    RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
  END IF;

  SELECT
    s.id, s.tenant_id, s.plan_version_id, s.billing_interval, s.status,
    s.last_provider_event_created_at, s.last_provider_event_id,
    pv.monthly_amount_minor, pv.yearly_amount_minor, pv.currency,
    pv.monthly_provider_plan_id, pv.yearly_provider_plan_id
  INTO v_subscription
  FROM private.saas_tenant_subscriptions s
  JOIN private.saas_plan_versions pv ON pv.id = s.plan_version_id
  WHERE s.provider = 'razorpay'
    AND s.provider_subscription_id = v_provider_subscription_id
  FOR UPDATE OF s;

  IF NOT FOUND THEN
    v_failure_code := 'subscription_not_found';
    UPDATE private.saas_payment_webhook_events
    SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
        processing_result = NULL, processed_at = NULL
    WHERE id = p_event_id;
    RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
  END IF;

  IF v_subscription.last_provider_event_created_at IS NOT NULL
     AND (
       v_event_time < v_subscription.last_provider_event_created_at
       OR (
         v_event_time = v_subscription.last_provider_event_created_at
         AND v_event_type = 'subscription.charged'
       )
     ) THEN
    UPDATE private.saas_payment_webhook_events
    SET status = 'processed', processing_result = 'stale',
        processed_at = now(), processing_started_at = NULL, last_error_code = NULL
    WHERE id = p_event_id;
    RETURN jsonb_build_object('ok', true, 'result', 'stale');
  END IF;

  IF v_event_type = 'subscription.charged' THEN
    IF v_subscription.status IN ('canceled', 'expired') THEN
      UPDATE private.saas_payment_webhook_events
      SET status = 'processed', processing_result = 'stale',
          processed_at = now(), processing_started_at = NULL, last_error_code = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', true, 'result', 'stale');
    END IF;

    v_payment_entity := v_event_payload #> '{payload,payment,entity}';
    v_provider_payment_id := nullif(btrim(v_payment_entity->>'id'), '');
    v_payment_status := lower(coalesce(v_payment_entity->>'status', ''));
    v_payment_currency := upper(coalesce(v_payment_entity->>'currency', ''));
    v_provider_plan_id := nullif(btrim(v_subscription_entity->>'plan_id'), '');
    v_expected_plan_id := CASE
      WHEN v_subscription.billing_interval = 'monthly' THEN v_subscription.monthly_provider_plan_id
      ELSE v_subscription.yearly_provider_plan_id
    END;
    v_expected_amount := CASE
      WHEN v_subscription.billing_interval = 'monthly' THEN v_subscription.monthly_amount_minor
      ELSE v_subscription.yearly_amount_minor
    END;

    IF v_provider_payment_id IS NULL OR length(v_provider_payment_id) > 255
       OR v_payment_status <> 'captured'
       OR v_provider_plan_id IS NULL OR v_provider_plan_id <> v_expected_plan_id
       OR coalesce(v_payment_entity->>'amount', '') !~ '^[0-9]{1,18}$'
       OR v_payment_currency !~ '^[A-Z]{3}$' THEN
      v_failure_code := 'payment_or_plan_validation_failed';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;

    v_payment_amount := (v_payment_entity->>'amount')::bigint;
    IF v_payment_amount <> v_expected_amount OR v_payment_currency <> v_subscription.currency THEN
      v_failure_code := 'payment_amount_currency_mismatch';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;

    IF coalesce(v_subscription_entity->>'current_start', '') !~ '^[0-9]{1,12}$'
       OR coalesce(v_subscription_entity->>'current_end', '') !~ '^[0-9]{1,12}$' THEN
      v_failure_code := 'invalid_billing_period';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;
    v_period_start := to_timestamp((v_subscription_entity->>'current_start')::double precision);
    v_period_end := to_timestamp((v_subscription_entity->>'current_end')::double precision);
    IF v_period_end <= v_period_start THEN
      v_failure_code := 'invalid_billing_period';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;

    INSERT INTO private.saas_payment_attempts (
      tenant_id, subscription_id, provider, idempotency_key, amount_minor, currency,
      provider_payment_id, status, captured_at
    )
    VALUES (
      v_subscription.tenant_id, v_subscription.id, 'razorpay',
      'razorpay-payment:' || v_provider_payment_id, v_payment_amount, v_payment_currency,
      v_provider_payment_id, 'captured', v_event_time
    )
    ON CONFLICT DO NOTHING;

    SELECT * INTO v_payment_attempt
    FROM private.saas_payment_attempts
    WHERE provider = 'razorpay' AND provider_payment_id = v_provider_payment_id;

    IF NOT FOUND
       OR v_payment_attempt.tenant_id <> v_subscription.tenant_id
       OR v_payment_attempt.subscription_id IS DISTINCT FROM v_subscription.id
       OR v_payment_attempt.amount_minor <> v_payment_amount
       OR v_payment_attempt.currency <> v_payment_currency
       OR v_payment_attempt.status <> 'captured' THEN
      v_failure_code := 'payment_id_conflict';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;

    UPDATE private.saas_tenant_subscriptions
    SET status = 'active',
        current_period_start = v_period_start,
        current_period_end = v_period_end,
        last_provider_event_created_at = v_event_time,
        last_provider_event_id = v_event.provider_event_id,
        updated_at = now()
    WHERE id = v_subscription.id;

  ELSIF v_event_type = 'payment.failed' THEN
    IF v_subscription.status IN ('canceled', 'expired') THEN
      UPDATE private.saas_payment_webhook_events
      SET status = 'processed', processing_result = 'stale',
          processed_at = now(), processing_started_at = NULL, last_error_code = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', true, 'result', 'stale');
    END IF;

    v_provider_payment_id := nullif(btrim(v_payment_entity->>'id'), '');
    v_payment_currency := upper(coalesce(v_payment_entity->>'currency', ''));
    IF v_provider_payment_id IS NULL OR length(v_provider_payment_id) > 255
       OR coalesce(v_payment_entity->>'amount', '') !~ '^[0-9]{1,18}$'
       OR v_payment_currency !~ '^[A-Z]{3}$' THEN
      v_failure_code := 'invalid_failed_payment';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;
    v_payment_amount := (v_payment_entity->>'amount')::bigint;
    IF v_payment_amount <= 0 THEN
      v_failure_code := 'invalid_failed_payment';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;

    INSERT INTO private.saas_payment_attempts (
      tenant_id, subscription_id, provider, idempotency_key, amount_minor, currency,
      provider_payment_id, status, failure_code
    )
    VALUES (
      v_subscription.tenant_id, v_subscription.id, 'razorpay',
      'razorpay-payment:' || v_provider_payment_id, v_payment_amount, v_payment_currency,
      v_provider_payment_id, 'failed', 'provider_payment_failed'
    )
    ON CONFLICT DO NOTHING;

    SELECT * INTO v_payment_attempt
    FROM private.saas_payment_attempts
    WHERE provider = 'razorpay' AND provider_payment_id = v_provider_payment_id;

    IF NOT FOUND
       OR v_payment_attempt.tenant_id <> v_subscription.tenant_id
       OR v_payment_attempt.subscription_id IS DISTINCT FROM v_subscription.id
       OR v_payment_attempt.amount_minor <> v_payment_amount
       OR v_payment_attempt.currency <> v_payment_currency THEN
      v_failure_code := 'payment_id_conflict';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;

    IF v_payment_attempt.status = 'captured' THEN
      UPDATE private.saas_payment_webhook_events
      SET status = 'processed', processing_result = 'stale',
          processed_at = now(), processing_started_at = NULL, last_error_code = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', true, 'result', 'stale');
    END IF;

    UPDATE private.saas_tenant_subscriptions
    SET status = 'past_due',
        last_provider_event_created_at = v_event_time,
        last_provider_event_id = v_event.provider_event_id,
        updated_at = now()
    WHERE id = v_subscription.id;

  ELSE
    -- Cancellation/completion/pause/halt events are restrictive at equal timestamps:
    -- this prevents a same-second charge event from reactivating a canceled subscription.
    IF v_event_type = 'subscription.cancelled' THEN
      UPDATE private.saas_tenant_subscriptions
      SET status = 'canceled', canceled_at = v_event_time,
          cancel_at_period_end = false,
          last_provider_event_created_at = v_event_time,
          last_provider_event_id = v_event.provider_event_id,
          updated_at = now()
      WHERE id = v_subscription.id;
    ELSIF v_event_type = 'subscription.completed' THEN
      UPDATE private.saas_tenant_subscriptions
      SET status = 'expired', canceled_at = NULL,
          cancel_at_period_end = false,
          last_provider_event_created_at = v_event_time,
          last_provider_event_id = v_event.provider_event_id,
          updated_at = now()
      WHERE id = v_subscription.id;
    ELSIF v_event_type = 'subscription.halted' THEN
      UPDATE private.saas_tenant_subscriptions
      SET status = 'past_due', canceled_at = NULL,
          last_provider_event_created_at = v_event_time,
          last_provider_event_id = v_event.provider_event_id,
          updated_at = now()
      WHERE id = v_subscription.id;
    ELSIF v_event_type = 'subscription.paused' THEN
      UPDATE private.saas_tenant_subscriptions
      SET status = 'paused', canceled_at = NULL,
          last_provider_event_created_at = v_event_time,
          last_provider_event_id = v_event.provider_event_id,
          updated_at = now()
      WHERE id = v_subscription.id;
    END IF;
  END IF;

  UPDATE private.saas_payment_webhook_events
  SET status = 'processed', processing_result = 'applied',
      processed_at = now(), processing_started_at = NULL, last_error_code = NULL
  WHERE id = p_event_id;

  RETURN jsonb_build_object('ok', true, 'result', 'applied');
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.process_saas_payment_webhook_event(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.process_saas_payment_webhook_event(uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.process_saas_payment_webhook_event_internal(p_event_id uuid)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.process_saas_payment_webhook_event(p_event_id);
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.process_saas_payment_webhook_event_internal(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_saas_payment_webhook_event_internal(uuid)
  TO service_role;

       OR v_payment_currency !~ '^[A-Z]{3}$' THEN
      v_failure_code := 'payment_or_plan_validation_failed';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;

    v_payment_amount := (v_payment_entity->>'amount')::bigint;
    IF v_payment_amount <> v_expected_amount OR v_payment_currency <> v_subscription.currency THEN
      v_failure_code := 'payment_amount_currency_mismatch';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;

    IF coalesce(v_subscription_entity->>'current_start', '') !~ '^[0-9]{1,12}$'
       OR coalesce(v_subscription_entity->>'current_end', '') !~ '^[0-9]{1,12}$' THEN
      v_failure_code := 'invalid_billing_period';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;
    v_period_start := to_timestamp((v_subscription_entity->>'current_start')::double precision);
    v_period_end := to_timestamp((v_subscription_entity->>'current_end')::double precision);
    IF v_period_end <= v_period_start THEN
      v_failure_code := 'invalid_billing_period';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;

    INSERT INTO private.saas_payment_attempts (
      tenant_id, subscription_id, provider, idempotency_key, amount_minor, currency,
      provider_payment_id, status, captured_at
    )
    VALUES (
      v_subscription.tenant_id, v_subscription.id, 'razorpay',
      'razorpay-payment:' || v_provider_payment_id, v_payment_amount, v_payment_currency,
      v_provider_payment_id, 'captured', v_event_time
    )
    ON CONFLICT DO NOTHING;

    SELECT * INTO v_payment_attempt
    FROM private.saas_payment_attempts
    WHERE provider = 'razorpay' AND provider_payment_id = v_provider_payment_id;

    IF NOT FOUND THEN
      v_failure_code := 'payment_id_conflict';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;
    IF v_payment_attempt.tenant_id <> v_subscription.tenant_id
       OR v_payment_attempt.subscription_id IS DISTINCT FROM v_subscription.id
       OR v_payment_attempt.amount_minor <> v_payment_amount
       OR v_payment_attempt.currency <> v_payment_currency
       OR v_payment_attempt.status <> 'captured' THEN
      v_failure_code := 'payment_id_conflict';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;

    UPDATE private.saas_tenant_subscriptions
    SET status = 'active',
        current_period_start = v_period_start,
        current_period_end = v_period_end,
        last_provider_event_created_at = v_event_time,
        last_provider_event_id = v_event.provider_event_id,
        updated_at = now()
    WHERE id = v_subscription.id;

  ELSIF v_event_type = 'payment.failed' THEN
    IF v_subscription.status IN ('canceled', 'expired') THEN
      UPDATE private.saas_payment_webhook_events
      SET status = 'processed', processing_result = 'stale',
          processed_at = now(), processing_started_at = NULL, last_error_code = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', true, 'result', 'stale');
    END IF;

    v_provider_payment_id := nullif(btrim(v_payment_entity->>'id'), '');
    v_payment_currency := upper(coalesce(v_payment_entity->>'currency', ''));
    IF v_provider_payment_id IS NULL OR length(v_provider_payment_id) > 255
       OR coalesce(v_payment_entity->>'amount', '') !~ '^[0-9]{1,18}$'
       OR v_payment_currency !~ '^[A-Z]{3}$' THEN
      v_failure_code := 'invalid_failed_payment';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;
    v_payment_amount := (v_payment_entity->>'amount')::bigint;
    v_expected_amount := CASE
      WHEN v_subscription.billing_interval = 'monthly' THEN v_subscription.monthly_amount_minor
      ELSE v_subscription.yearly_amount_minor
    END;
    IF v_payment_amount <= 0 THEN
      v_failure_code := 'invalid_failed_payment';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;
    IF v_payment_amount <> v_expected_amount OR v_payment_currency <> v_subscription.currency THEN
      v_failure_code := 'payment_amount_currency_mismatch';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;

    INSERT INTO private.saas_payment_attempts (
      tenant_id, subscription_id, provider, idempotency_key, amount_minor, currency,
      provider_payment_id, status, failure_code
    )
    VALUES (
      v_subscription.tenant_id, v_subscription.id, 'razorpay',
      'razorpay-payment:' || v_provider_payment_id, v_payment_amount, v_payment_currency,
      v_provider_payment_id, 'failed', 'provider_payment_failed'
    )
    ON CONFLICT DO NOTHING;

    SELECT * INTO v_payment_attempt
    FROM private.saas_payment_attempts
    WHERE provider = 'razorpay' AND provider_payment_id = v_provider_payment_id;

    IF NOT FOUND THEN
      v_failure_code := 'payment_id_conflict';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;
    IF v_payment_attempt.tenant_id <> v_subscription.tenant_id
       OR v_payment_attempt.subscription_id IS DISTINCT FROM v_subscription.id
       OR v_payment_attempt.amount_minor <> v_payment_amount
       OR v_payment_attempt.currency <> v_payment_currency THEN
      v_failure_code := 'payment_id_conflict';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;

    IF v_payment_attempt.status = 'captured' THEN
      UPDATE private.saas_payment_webhook_events
      SET status = 'processed', processing_result = 'stale',
          processed_at = now(), processing_started_at = NULL, last_error_code = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', true, 'result', 'stale');
    END IF;

    UPDATE private.saas_tenant_subscriptions
    SET status = 'past_due',
        last_provider_event_created_at = v_event_time,
        last_provider_event_id = v_event.provider_event_id,
        updated_at = now()
    WHERE id = v_subscription.id;

  ELSE
    -- Cancellation/completion/pause/halt events are restrictive at equal timestamps:
    -- this prevents a same-second charge event from reactivating a canceled subscription.
    IF v_event_type = 'subscription.cancelled' THEN
      UPDATE private.saas_tenant_subscriptions
      SET status = 'canceled', canceled_at = v_event_time,
          cancel_at_period_end = false,
          last_provider_event_created_at = v_event_time,
          last_provider_event_id = v_event.provider_event_id,
          updated_at = now()
      WHERE id = v_subscription.id;
    ELSIF v_event_type = 'subscription.completed' THEN
      UPDATE private.saas_tenant_subscriptions
      SET status = 'expired', canceled_at = NULL,
          cancel_at_period_end = false,
          last_provider_event_created_at = v_event_time,
          last_provider_event_id = v_event.provider_event_id,
          updated_at = now()
      WHERE id = v_subscription.id;
    ELSIF v_event_type = 'subscription.halted' THEN
      UPDATE private.saas_tenant_subscriptions
      SET status = 'past_due', canceled_at = NULL,
          last_provider_event_created_at = v_event_time,
          last_provider_event_id = v_event.provider_event_id,
          updated_at = now()
      WHERE id = v_subscription.id;
    ELSIF v_event_type = 'subscription.paused' THEN
      UPDATE private.saas_tenant_subscriptions
      SET status = 'paused', canceled_at = NULL,
          last_provider_event_created_at = v_event_time,
          last_provider_event_id = v_event.provider_event_id,
          updated_at = now()
      WHERE id = v_subscription.id;
    END IF;
  END IF;

  UPDATE private.saas_payment_webhook_events
  SET status = 'processed', processing_result = 'applied',
      processed_at = now(), processing_started_at = NULL, last_error_code = NULL
  WHERE id = p_event_id;

  RETURN jsonb_build_object('ok', true, 'result', 'applied');
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.process_saas_payment_webhook_event(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.process_saas_payment_webhook_event(uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.process_saas_payment_webhook_event_internal(p_event_id uuid)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.process_saas_payment_webhook_event(p_event_id);
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.process_saas_payment_webhook_event_internal(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_saas_payment_webhook_event_internal(uuid)
  TO service_role;
 THEN
    v_failure_code := 'invalid_event_timestamp';
    UPDATE private.saas_payment_webhook_events
    SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
        processing_result = NULL, processed_at = NULL
    WHERE id = p_event_id;
    RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
  END IF;
  v_event_time := to_timestamp((v_event_payload->>'created_at')::double precision);

  IF v_event_type IN (
    'subscription.charged',
    'subscription.cancelled',
    'subscription.completed',
    'subscription.halted',
    'subscription.paused'
  ) THEN
    v_subscription_entity := v_event_payload #> '{payload,subscription,entity}';
    v_provider_subscription_id := nullif(btrim(v_subscription_entity->>'id'), '');
  ELSE
    v_payment_entity := v_event_payload #> '{payload,payment,entity}';
    v_provider_subscription_id := nullif(btrim(v_payment_entity->>'subscription_id'), '');
  END IF;

  IF v_provider_subscription_id IS NULL
     OR length(v_provider_subscription_id) > 255 THEN
    v_failure_code := 'missing_subscription_reference';
    UPDATE private.saas_payment_webhook_events
    SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
        processing_result = NULL, processed_at = NULL
    WHERE id = p_event_id;
    RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
  END IF;

  SELECT
    s.id, s.tenant_id, s.plan_version_id, s.billing_interval, s.status,
    s.last_provider_event_created_at, s.last_provider_event_id,
    pv.monthly_amount_minor, pv.yearly_amount_minor, pv.currency,
    pv.monthly_provider_plan_id, pv.yearly_provider_plan_id
  INTO v_subscription
  FROM private.saas_tenant_subscriptions s
  JOIN private.saas_plan_versions pv ON pv.id = s.plan_version_id
  WHERE s.provider = 'razorpay'
    AND s.provider_subscription_id = v_provider_subscription_id
  FOR UPDATE OF s;

  IF NOT FOUND THEN
    v_failure_code := 'subscription_not_found';
    UPDATE private.saas_payment_webhook_events
    SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
        processing_result = NULL, processed_at = NULL
    WHERE id = p_event_id;
    RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
  END IF;

  IF v_subscription.last_provider_event_created_at IS NOT NULL
     AND (
       v_event_time < v_subscription.last_provider_event_created_at
       OR (
         v_event_time = v_subscription.last_provider_event_created_at
         AND v_event_type = 'subscription.charged'
       )
     ) THEN
    UPDATE private.saas_payment_webhook_events
    SET status = 'processed', processing_result = 'stale',
        processed_at = now(), processing_started_at = NULL, last_error_code = NULL
    WHERE id = p_event_id;
    RETURN jsonb_build_object('ok', true, 'result', 'stale');
  END IF;

  IF v_event_type = 'subscription.charged' THEN
    IF v_subscription.status IN ('canceled', 'expired') THEN
      UPDATE private.saas_payment_webhook_events
      SET status = 'processed', processing_result = 'stale',
          processed_at = now(), processing_started_at = NULL, last_error_code = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', true, 'result', 'stale');
    END IF;

    v_payment_entity := v_event_payload #> '{payload,payment,entity}';
    v_provider_payment_id := nullif(btrim(v_payment_entity->>'id'), '');
    v_payment_status := lower(coalesce(v_payment_entity->>'status', ''));
    v_payment_currency := upper(coalesce(v_payment_entity->>'currency', ''));
    v_provider_plan_id := nullif(btrim(v_subscription_entity->>'plan_id'), '');
    v_expected_plan_id := CASE
      WHEN v_subscription.billing_interval = 'monthly' THEN v_subscription.monthly_provider_plan_id
      ELSE v_subscription.yearly_provider_plan_id
    END;
    v_expected_amount := CASE
      WHEN v_subscription.billing_interval = 'monthly' THEN v_subscription.monthly_amount_minor
      ELSE v_subscription.yearly_amount_minor
    END;

    IF v_provider_payment_id IS NULL OR length(v_provider_payment_id) > 255
       OR v_payment_status <> 'captured'
       OR v_provider_plan_id IS NULL OR v_provider_plan_id <> v_expected_plan_id
       OR coalesce(v_payment_entity->>'amount', '') !~ '^[0-9]{1,18}$'
       OR v_payment_currency !~ '^[A-Z]{3}$' THEN
      v_failure_code := 'payment_or_plan_validation_failed';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;

    v_payment_amount := (v_payment_entity->>'amount')::bigint;
    IF v_payment_amount <> v_expected_amount OR v_payment_currency <> v_subscription.currency THEN
      v_failure_code := 'payment_amount_currency_mismatch';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;

    IF coalesce(v_subscription_entity->>'current_start', '') !~ '^[0-9]{1,12}$'
       OR coalesce(v_subscription_entity->>'current_end', '') !~ '^[0-9]{1,12}$' THEN
      v_failure_code := 'invalid_billing_period';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;
    v_period_start := to_timestamp((v_subscription_entity->>'current_start')::double precision);
    v_period_end := to_timestamp((v_subscription_entity->>'current_end')::double precision);
    IF v_period_end <= v_period_start THEN
      v_failure_code := 'invalid_billing_period';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;

    INSERT INTO private.saas_payment_attempts (
      tenant_id, subscription_id, provider, idempotency_key, amount_minor, currency,
      provider_payment_id, status, captured_at
    )
    VALUES (
      v_subscription.tenant_id, v_subscription.id, 'razorpay',
      'razorpay-payment:' || v_provider_payment_id, v_payment_amount, v_payment_currency,
      v_provider_payment_id, 'captured', v_event_time
    )
    ON CONFLICT DO NOTHING;

    SELECT * INTO v_payment_attempt
    FROM private.saas_payment_attempts
    WHERE provider = 'razorpay' AND provider_payment_id = v_provider_payment_id;

    IF NOT FOUND
       OR v_payment_attempt.tenant_id <> v_subscription.tenant_id
       OR v_payment_attempt.subscription_id IS DISTINCT FROM v_subscription.id
       OR v_payment_attempt.amount_minor <> v_payment_amount
       OR v_payment_attempt.currency <> v_payment_currency
       OR v_payment_attempt.status <> 'captured' THEN
      v_failure_code := 'payment_id_conflict';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;

    UPDATE private.saas_tenant_subscriptions
    SET status = 'active',
        current_period_start = v_period_start,
        current_period_end = v_period_end,
        last_provider_event_created_at = v_event_time,
        last_provider_event_id = v_event.provider_event_id,
        updated_at = now()
    WHERE id = v_subscription.id;

  ELSIF v_event_type = 'payment.failed' THEN
    IF v_subscription.status IN ('canceled', 'expired') THEN
      UPDATE private.saas_payment_webhook_events
      SET status = 'processed', processing_result = 'stale',
          processed_at = now(), processing_started_at = NULL, last_error_code = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', true, 'result', 'stale');
    END IF;

    v_provider_payment_id := nullif(btrim(v_payment_entity->>'id'), '');
    v_payment_currency := upper(coalesce(v_payment_entity->>'currency', ''));
    IF v_provider_payment_id IS NULL OR length(v_provider_payment_id) > 255
       OR coalesce(v_payment_entity->>'amount', '') !~ '^[0-9]{1,18}$'
       OR v_payment_currency !~ '^[A-Z]{3}$' THEN
      v_failure_code := 'invalid_failed_payment';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;
    v_payment_amount := (v_payment_entity->>'amount')::bigint;
    IF v_payment_amount <= 0 THEN
      v_failure_code := 'invalid_failed_payment';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;

    INSERT INTO private.saas_payment_attempts (
      tenant_id, subscription_id, provider, idempotency_key, amount_minor, currency,
      provider_payment_id, status, failure_code
    )
    VALUES (
      v_subscription.tenant_id, v_subscription.id, 'razorpay',
      'razorpay-payment:' || v_provider_payment_id, v_payment_amount, v_payment_currency,
      v_provider_payment_id, 'failed', 'provider_payment_failed'
    )
    ON CONFLICT DO NOTHING;

    SELECT * INTO v_payment_attempt
    FROM private.saas_payment_attempts
    WHERE provider = 'razorpay' AND provider_payment_id = v_provider_payment_id;

    IF NOT FOUND
       OR v_payment_attempt.tenant_id <> v_subscription.tenant_id
       OR v_payment_attempt.subscription_id IS DISTINCT FROM v_subscription.id
       OR v_payment_attempt.amount_minor <> v_payment_amount
       OR v_payment_attempt.currency <> v_payment_currency THEN
      v_failure_code := 'payment_id_conflict';
      UPDATE private.saas_payment_webhook_events
      SET status = 'failed', processing_started_at = NULL, last_error_code = v_failure_code,
          processing_result = NULL, processed_at = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', false, 'error', v_failure_code);
    END IF;

    IF v_payment_attempt.status = 'captured' THEN
      UPDATE private.saas_payment_webhook_events
      SET status = 'processed', processing_result = 'stale',
          processed_at = now(), processing_started_at = NULL, last_error_code = NULL
      WHERE id = p_event_id;
      RETURN jsonb_build_object('ok', true, 'result', 'stale');
    END IF;

    UPDATE private.saas_tenant_subscriptions
    SET status = 'past_due',
        last_provider_event_created_at = v_event_time,
        last_provider_event_id = v_event.provider_event_id,
        updated_at = now()
    WHERE id = v_subscription.id;

  ELSE
    -- Cancellation/completion/pause/halt events are restrictive at equal timestamps:
    -- this prevents a same-second charge event from reactivating a canceled subscription.
    IF v_event_type = 'subscription.cancelled' THEN
      UPDATE private.saas_tenant_subscriptions
      SET status = 'canceled', canceled_at = v_event_time,
          cancel_at_period_end = false,
          last_provider_event_created_at = v_event_time,
          last_provider_event_id = v_event.provider_event_id,
          updated_at = now()
      WHERE id = v_subscription.id;
    ELSIF v_event_type = 'subscription.completed' THEN
      UPDATE private.saas_tenant_subscriptions
      SET status = 'expired', canceled_at = NULL,
          cancel_at_period_end = false,
          last_provider_event_created_at = v_event_time,
          last_provider_event_id = v_event.provider_event_id,
          updated_at = now()
      WHERE id = v_subscription.id;
    ELSIF v_event_type = 'subscription.halted' THEN
      UPDATE private.saas_tenant_subscriptions
      SET status = 'past_due', canceled_at = NULL,
          last_provider_event_created_at = v_event_time,
          last_provider_event_id = v_event.provider_event_id,
          updated_at = now()
      WHERE id = v_subscription.id;
    ELSIF v_event_type = 'subscription.paused' THEN
      UPDATE private.saas_tenant_subscriptions
      SET status = 'paused', canceled_at = NULL,
          last_provider_event_created_at = v_event_time,
          last_provider_event_id = v_event.provider_event_id,
          updated_at = now()
      WHERE id = v_subscription.id;
    END IF;
  END IF;

  UPDATE private.saas_payment_webhook_events
  SET status = 'processed', processing_result = 'applied',
      processed_at = now(), processing_started_at = NULL, last_error_code = NULL
  WHERE id = p_event_id;

  RETURN jsonb_build_object('ok', true, 'result', 'applied');
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.process_saas_payment_webhook_event(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.process_saas_payment_webhook_event(uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.process_saas_payment_webhook_event_internal(p_event_id uuid)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.process_saas_payment_webhook_event(p_event_id);
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.process_saas_payment_webhook_event_internal(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_saas_payment_webhook_event_internal(uuid)
  TO service_role;
