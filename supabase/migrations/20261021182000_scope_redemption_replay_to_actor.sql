-- Prevent cross-actor redemption idempotency replay from leaking another partner's redemption.
-- Also serialize tenant-scoped idempotency keys and per-actor balance checks.
-- This migration does not rewrite existing redemptions, ledger rows, or reward stock.

CREATE OR REPLACE FUNCTION private.redeem_reward(
  p_actor_user_id uuid,
  p_reward_id uuid,
  p_request_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'extensions', 'public', 'private'
AS $function$
DECLARE
  v_partner public.partners%rowtype;
  v_reward public.rewards%rowtype;
  v_existing public.redemptions%rowtype;
  v_balance bigint;
  v_redemption_id uuid;
  v_request_tenant_id uuid;
BEGIN
  IF p_actor_user_id IS NULL
     OR p_reward_id IS NULL
     OR p_request_key IS NULL
     OR length(trim(p_request_key)) < 8
     OR length(p_request_key) > 160
     OR p_request_key <> btrim(p_request_key) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_request');
  END IF;

  SELECT rw.tenant_id
    INTO v_request_tenant_id
    FROM public.rewards rw
   WHERE rw.id = p_reward_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'reward_unavailable');
  END IF;

  -- Idempotency keys are unique within a tenant. Serialize identical keys
  -- across all actors so a collision is returned safely, not as a raw DB error.
  PERFORM pg_advisory_xact_lock(
    hashtextextended(v_request_tenant_id::text || ':reward-redemption:' || p_request_key, 0)
  );

  SELECT r.*
    INTO v_existing
    FROM public.redemptions r
   WHERE r.tenant_id = v_request_tenant_id
     AND r.request_key = p_request_key
   LIMIT 1;

  IF FOUND THEN
    IF v_existing.reward_id = p_reward_id
       AND EXISTS (
         SELECT 1
           FROM public.partners p
          WHERE p.id = v_existing.partner_id
            AND p.tenant_id = v_existing.tenant_id
            AND p.user_id = p_actor_user_id
       ) THEN
      RETURN jsonb_build_object(
        'ok', v_existing.status NOT IN ('cancelled', 'rejected'),
        'redemption_id', v_existing.id,
        'status', v_existing.status,
        'replayed', true
      );
    END IF;

    -- Do not return IDs, status, or point amounts for a key owned by another
    -- actor or reused for a different reward.
    RETURN jsonb_build_object('ok', false, 'error', 'request_key_conflict');
  END IF;

  -- A user may try different request keys concurrently. Serialize account
  -- balance checks to prevent two individually-valid debits overspending.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_actor_user_id::text, 0));

  SELECT p.*
    INTO v_partner
    FROM public.partners p
   WHERE p.tenant_id = v_request_tenant_id
     AND p.user_id = p_actor_user_id
     AND p.verification_status = 'verified'
     AND p.role = 'farmer'
   ORDER BY p.created_at
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'partner_not_verified');
  END IF;

  SELECT rw.*
    INTO v_reward
    FROM public.rewards rw
   WHERE rw.id = p_reward_id
     AND rw.tenant_id = v_partner.tenant_id
     AND rw.active
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'reward_unavailable');
  END IF;

  IF v_reward.is_demo THEN
    RETURN jsonb_build_object('ok', false, 'error', 'demo_reward_not_redeemable');
  END IF;

  IF v_reward.stock_quantity IS NOT NULL AND v_reward.stock_quantity < 1 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'out_of_stock');
  END IF;

  SELECT COALESCE(sum(l.points_delta), 0)
    INTO v_balance
    FROM public.points_ledger l
   WHERE l.tenant_id = v_partner.tenant_id
     AND l.partner_id = v_partner.id;

  IF v_balance < v_reward.points_cost THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'insufficient_points',
      'balance', v_balance,
      'required', v_reward.points_cost
    );
  END IF;

  INSERT INTO public.redemptions(
    tenant_id, partner_id, reward_id, points_cost, status, request_key
  )
  VALUES (
    v_partner.tenant_id, v_partner.id, v_reward.id,
    v_reward.points_cost, 'reserved', p_request_key
  )
  RETURNING id INTO v_redemption_id;

  INSERT INTO public.points_ledger(
    tenant_id, partner_id, entry_type, points_delta, idempotency_key,
    reason_code, actor_user_id, metadata
  )
  VALUES (
    v_partner.tenant_id, v_partner.id, 'redeem_reserve', -v_reward.points_cost,
    'redeem:' || v_redemption_id::text, 'reward_redemption_reserved',
    p_actor_user_id,
    jsonb_build_object('redemption_id', v_redemption_id, 'reward_id', v_reward.id)
  );

  IF v_reward.stock_quantity IS NOT NULL THEN
    UPDATE public.rewards
       SET stock_quantity = stock_quantity - 1, updated_at = now()
     WHERE id = v_reward.id;
  END IF;

  INSERT INTO public.audit_logs(
    tenant_id, actor_user_id, action, entity_type, entity_id, after_data
  )
  VALUES (
    v_partner.tenant_id, p_actor_user_id, 'reward_redemption_reserved',
    'redemption', v_redemption_id,
    jsonb_build_object('reward_id', v_reward.id, 'points_cost', v_reward.points_cost)
  );

  RETURN jsonb_build_object(
    'ok', true,
    'redemption_id', v_redemption_id,
    'status', 'reserved',
    'points_cost', v_reward.points_cost,
    'balance_after', v_balance - v_reward.points_cost,
    'replayed', false
  );
END
$function$;
