-- Idempotent checkout reservation before calling the external Razorpay API.
-- If the provider call succeeds but persisting its response fails, the reservation
-- remains incomplete and blocks a second provider subscription until reconciled.
ALTER TABLE private.saas_tenant_subscriptions
  ADD COLUMN checkout_idempotency_key text
    CHECK (checkout_idempotency_key IS NULL OR length(btrim(checkout_idempotency_key)) BETWEEN 16 AND 128),
  ADD COLUMN checkout_url text
    CHECK (checkout_url IS NULL OR checkout_url ~ '^https://(rzp\.io|razorpay\.com)/'),
  ADD COLUMN checkout_provider_created_at timestamptz;

CREATE UNIQUE INDEX saas_tenant_subscription_checkout_idempotency_idx
  ON private.saas_tenant_subscriptions (tenant_id, checkout_idempotency_key)
  WHERE checkout_idempotency_key IS NOT NULL;

CREATE UNIQUE INDEX saas_tenant_one_incomplete_checkout_idx
  ON private.saas_tenant_subscriptions (tenant_id)
  WHERE status = 'incomplete' AND checkout_idempotency_key IS NOT NULL;

CREATE OR REPLACE FUNCTION private.reserve_saas_checkout(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_plan_version_id uuid,
  p_billing_interval text,
  p_idempotency_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_existing record;
  v_plan record;
  v_subscription_id uuid;
  v_attempt_id uuid;
  v_amount bigint;
  v_provider_plan_id text;
BEGIN
  IF p_actor_user_id IS NULL OR p_tenant_id IS NULL OR p_plan_version_id IS NULL
     OR p_billing_interval IS NULL OR p_billing_interval NOT IN ('monthly', 'yearly')
     OR p_idempotency_key IS NULL
     OR p_idempotency_key !~ '^[A-Za-z0-9._:-]{16,128}$' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_request');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.tenant_memberships m
    WHERE m.tenant_id = p_tenant_id
      AND m.user_id = p_actor_user_id
      AND m.status = 'active'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  -- Serialize checkout creation per tenant so concurrent requests cannot reserve
  -- multiple incomplete subscriptions for the same tenant.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_tenant_id::text, 0));

  SELECT s.id, s.status, s.checkout_idempotency_key, s.provider_subscription_id,
         s.checkout_url, s.plan_version_id, s.billing_interval, a.id AS attempt_id,
         a.idempotency_key
  INTO v_existing
  FROM private.saas_tenant_subscriptions s
  LEFT JOIN private.saas_payment_attempts a ON a.subscription_id = s.id
  WHERE s.tenant_id = p_tenant_id
    AND (
      s.checkout_idempotency_key = p_idempotency_key
      OR (s.status = 'incomplete' AND s.checkout_idempotency_key IS NOT NULL)
    )
  ORDER BY (s.checkout_idempotency_key = p_idempotency_key) DESC, s.created_at DESC
  LIMIT 1
  FOR UPDATE OF s;

  IF FOUND THEN
    IF v_existing.checkout_idempotency_key <> p_idempotency_key THEN
      RETURN jsonb_build_object('ok', false, 'error', 'pending_checkout_exists');
    END IF;
    IF v_existing.plan_version_id <> p_plan_version_id
       OR v_existing.billing_interval <> p_billing_interval THEN
      RETURN jsonb_build_object('ok', false, 'error', 'idempotency_key_conflict');
    END IF;
    IF v_existing.provider_subscription_id IS NOT NULL AND v_existing.checkout_url IS NOT NULL THEN
      RETURN jsonb_build_object(
        'ok', true, 'reused', true,
        'subscription_id', v_existing.id,
        'provider_subscription_id', v_existing.provider_subscription_id,
        'checkout_url', v_existing.checkout_url
      );
    END IF;
    RETURN jsonb_build_object(
      'ok', false, 'error', 'checkout_reconciliation_required',
      'subscription_id', v_existing.id
    );
  END IF;

  IF EXISTS (
    SELECT 1 FROM private.saas_tenant_subscriptions s
    WHERE s.tenant_id = p_tenant_id
      AND s.status IN ('trialing', 'active', 'past_due', 'paused')
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'subscription_already_exists');
  END IF;

  SELECT pv.id, pv.currency, pv.monthly_amount_minor, pv.yearly_amount_minor,
         pv.monthly_provider_plan_id, pv.yearly_provider_plan_id, pv.published_at,
         p.status AS plan_status
  INTO v_plan
  FROM private.saas_plan_versions pv
  JOIN private.saas_plans p ON p.id = pv.plan_id
  WHERE pv.id = p_plan_version_id
  FOR SHARE OF pv, p;

  IF NOT FOUND OR v_plan.published_at IS NULL OR v_plan.plan_status <> 'published' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'plan_unavailable');
  END IF;

  IF p_billing_interval = 'monthly' THEN
    v_amount := v_plan.monthly_amount_minor;
    v_provider_plan_id := v_plan.monthly_provider_plan_id;
  ELSE
    v_amount := v_plan.yearly_amount_minor;
    v_provider_plan_id := v_plan.yearly_provider_plan_id;
  END IF;

  IF v_amount IS NULL OR v_amount <= 0 OR v_provider_plan_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'plan_not_configured');
  END IF;

  INSERT INTO private.saas_tenant_subscriptions (
    tenant_id, plan_version_id, billing_interval, status, checkout_idempotency_key
  ) VALUES (
    p_tenant_id, p_plan_version_id, p_billing_interval, 'incomplete', p_idempotency_key
  ) RETURNING id INTO v_subscription_id;

  INSERT INTO private.saas_payment_attempts (
    tenant_id, subscription_id, idempotency_key, amount_minor, currency, status
  ) VALUES (
    p_tenant_id, v_subscription_id, p_idempotency_key, v_amount, v_plan.currency, 'initiated'
  ) RETURNING id INTO v_attempt_id;

  RETURN jsonb_build_object(
    'ok', true, 'created', true,
    'subscription_id', v_subscription_id,
    'payment_attempt_id', v_attempt_id,
    'provider_plan_id', v_provider_plan_id,
    'amount_minor', v_amount,
    'currency', v_plan.currency,
    'billing_interval', p_billing_interval
  );
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pending_checkout_exists');
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.reserve_saas_checkout(uuid,uuid,uuid,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.reserve_saas_checkout(uuid,uuid,uuid,text,text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.reserve_saas_checkout_internal(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_plan_version_id uuid,
  p_billing_interval text,
  p_idempotency_key text
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.reserve_saas_checkout(
    p_actor_user_id, p_tenant_id, p_plan_version_id, p_billing_interval, p_idempotency_key
  );
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.reserve_saas_checkout_internal(uuid,uuid,uuid,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_saas_checkout_internal(uuid,uuid,uuid,text,text)
  TO service_role;

CREATE OR REPLACE FUNCTION private.finalize_saas_checkout(
  p_subscription_id uuid,
  p_provider_subscription_id text,
  p_checkout_url text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_subscription private.saas_tenant_subscriptions%rowtype;
BEGIN
  IF p_subscription_id IS NULL
     OR p_provider_subscription_id IS NULL
     OR length(btrim(p_provider_subscription_id)) NOT BETWEEN 1 AND 255
     OR p_checkout_url IS NULL
     OR p_checkout_url !~ '^https://(rzp\.io|razorpay\.com)/' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_provider_response');
  END IF;

  SELECT * INTO v_subscription
  FROM private.saas_tenant_subscriptions
  WHERE id = p_subscription_id
  FOR UPDATE;

  IF NOT FOUND OR v_subscription.status <> 'incomplete'
     OR v_subscription.checkout_idempotency_key IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'checkout_not_found');
  END IF;

  IF v_subscription.provider_subscription_id IS NOT NULL THEN
    IF v_subscription.provider_subscription_id = p_provider_subscription_id
       AND v_subscription.checkout_url = p_checkout_url THEN
      RETURN jsonb_build_object('ok', true, 'reused', true);
    END IF;
    RETURN jsonb_build_object('ok', false, 'error', 'provider_subscription_conflict');
  END IF;

  UPDATE private.saas_tenant_subscriptions
  SET provider_subscription_id = p_provider_subscription_id,
      checkout_url = p_checkout_url,
      checkout_provider_created_at = now(),
      updated_at = now()
  WHERE id = p_subscription_id;

  RETURN jsonb_build_object('ok', true, 'reused', false);
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false, 'error', 'provider_subscription_conflict');
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.finalize_saas_checkout(uuid,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.finalize_saas_checkout(uuid,text,text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.finalize_saas_checkout_internal(
  p_subscription_id uuid,
  p_provider_subscription_id text,
  p_checkout_url text
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.finalize_saas_checkout(
    p_subscription_id, p_provider_subscription_id, p_checkout_url
  );
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.finalize_saas_checkout_internal(uuid,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_saas_checkout_internal(uuid,text,text)
  TO service_role;

CREATE OR REPLACE FUNCTION private.fail_saas_checkout_reservation(
  p_subscription_id uuid,
  p_provider_http_status integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_subscription private.saas_tenant_subscriptions%rowtype;
BEGIN
  IF p_subscription_id IS NULL OR p_provider_http_status NOT BETWEEN 400 AND 499 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_provider_failure');
  END IF;

  SELECT * INTO v_subscription
  FROM private.saas_tenant_subscriptions
  WHERE id = p_subscription_id
  FOR UPDATE;

  IF NOT FOUND OR v_subscription.status <> 'incomplete'
     OR v_subscription.provider_subscription_id IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'checkout_not_rejectable');
  END IF;

  UPDATE private.saas_payment_attempts
  SET status = 'failed',
      failure_code = 'provider_rejected_' || p_provider_http_status::text,
      updated_at = now()
  WHERE subscription_id = p_subscription_id AND status = 'initiated';

  UPDATE private.saas_tenant_subscriptions
  SET status = 'expired', updated_at = now()
  WHERE id = p_subscription_id;

  RETURN jsonb_build_object('ok', true);
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.fail_saas_checkout_reservation(uuid,integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.fail_saas_checkout_reservation(uuid,integer)
  TO service_role;

CREATE OR REPLACE FUNCTION public.fail_saas_checkout_reservation_internal(
  p_subscription_id uuid,
  p_provider_http_status integer
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.fail_saas_checkout_reservation(p_subscription_id, p_provider_http_status);
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.fail_saas_checkout_reservation_internal(uuid,integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fail_saas_checkout_reservation_internal(uuid,integer)
  TO service_role;

